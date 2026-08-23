import Foundation

enum CodexResponseParser {
    static func parse(_ data: Data, now: Date = Date()) throws -> CodexSnapshot {
        guard let text = String(data: data, encoding: .utf8) else {
            throw VibeIslandError.invalidResponse(
                L10n.current(chinese: "响应不是 UTF-8 文本", english: "Response is not UTF-8 text")
            )
        }

        var rateLimitResult: [String: Any]?
        var threadResult: [String: Any]?

        for line in text.split(whereSeparator: \Character.isNewline) {
            guard
                let lineData = String(line).data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                let id = object["id"] as? Int,
                let result = object["result"] as? [String: Any]
            else { continue }

            if id == 1 { rateLimitResult = result }
            if id == 2 { threadResult = result }
        }

        guard let rateLimitResult else {
            throw VibeIslandError.invalidResponse(
                L10n.current(chinese: "缺少额度响应", english: "Quota response is missing")
            )
        }
        guard let threadResult else {
            throw VibeIslandError.invalidResponse(
                L10n.current(chinese: "缺少任务响应", english: "Task response is missing")
            )
        }

        let quota = parseQuota(rateLimitResult)
        let tasks = parseTasks(threadResult, now: now)
        return CodexSnapshot(quota: quota, tasks: tasks)
    }

    static func parseQuota(_ result: [String: Any]) -> QuotaSnapshot {
        let bucket = (result["rateLimitsByLimitId"] as? [String: Any])?["codex"] as? [String: Any]
            ?? result["rateLimits"] as? [String: Any]
            ?? [:]
        let primary = bucket["primary"] as? [String: Any]
        let used = primary?["usedPercent"] as? Int ?? 100
        let resetsAt = (primary?["resetsAt"] as? NSNumber).map {
            Date(timeIntervalSince1970: $0.doubleValue)
        }
        let duration = (primary?["windowDurationMins"] as? NSNumber)?.intValue
        let credits = bucket["credits"] as? [String: Any]

        return QuotaSnapshot(
            remainingPercent: max(0, min(100, 100 - used)),
            resetsAt: resetsAt,
            windowMinutes: duration,
            creditsBalance: credits?["balance"] as? String,
            planName: bucket["planType"] as? String
        )
    }

    static func parseTasks(_ result: [String: Any], now: Date) -> [CodexTaskSnapshot] {
        let rows = result["data"] as? [[String: Any]] ?? []
        return rows.prefix(20).compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let preview = (row["preview"] as? String) ?? L10n.current(
                chinese: "未命名任务",
                english: "Untitled task"
            )
            let rawTitle = (row["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (rawTitle?.isEmpty == false ? rawTitle! : preview)
                .replacingOccurrences(of: "\n", with: " ")
            let updated = (row["updatedAt"] as? NSNumber)?.doubleValue ?? 0
            let path = row["path"] as? String
            let status = row["status"] as? [String: Any] ?? [:]

            let rolloutSnapshot = RolloutStatusDetector.snapshot(at: path, now: now)
            var state = state(from: status)
            if state == .unknown || state == .idle {
                state = rolloutSnapshot?.state ?? state
            }

            return CodexTaskSnapshot(
                id: id,
                title: title,
                state: state,
                updatedAt: Date(timeIntervalSince1970: updated),
                rolloutPath: path,
                isOrdinaryConversation: rolloutSnapshot?.isOrdinaryConversation ?? false
            )
        }
    }

    static func state(from status: [String: Any]) -> CodexTaskState {
        switch status["type"] as? String {
        case "active":
            let flags = status["activeFlags"] as? [String] ?? []
            return flags.isEmpty ? .running : .waiting
        case "idle": return .idle
        case "systemError": return .failed
        case "notLoaded": return .unknown
        default: return .unknown
        }
    }
}

enum RolloutStatusDetector {
    struct Snapshot: Equatable {
        let state: CodexTaskState
        let isOrdinaryConversation: Bool
    }

    private struct CacheEntry {
        let modifiedAt: Date
        let fileSize: UInt64
        let snapshot: Snapshot?
        let expiresAt: Date
    }

    private static let cacheLock = NSLock()
    private static var cache: [String: CacheEntry] = [:]

    static func state(at path: String?, now: Date = Date()) -> CodexTaskState? {
        snapshot(at: path, now: now)?.state
    }

    static func snapshot(at path: String?, now: Date = Date()) -> Snapshot? {
        guard let path, !path.isEmpty else { return nil }
        guard let metadata = fileMetadata(at: path) else { return nil }

        cacheLock.lock()
        let cached = cache[path]
        cacheLock.unlock()
        if let cached,
           cached.modifiedAt == metadata.modifiedAt,
           cached.fileSize == metadata.fileSize,
           now < cached.expiresAt {
            return cached.snapshot
        }

        let url = URL(fileURLWithPath: path)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let end = (try? handle.seekToEnd()) ?? 0
        let sampleSize: UInt64 = 192 * 1024
        try? handle.seek(toOffset: end > sampleSize ? end - sampleSize : 0)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }

        let result = snapshot(from: text, modifiedAt: metadata.modifiedAt, now: now)
        let cacheLifetime: TimeInterval
        switch result?.state {
        case .completed, .interrupted, .failed:
            // Terminal results cannot change while the file is unchanged.
            cacheLifetime = 3_600
        case .running, .waiting:
            // Active files normally invalidate through their modification date.
            // A short expiry still lets inactivity thresholds advance correctly.
            cacheLifetime = 5
        default:
            cacheLifetime = 2
        }

        cacheLock.lock()
        cache[path] = CacheEntry(
            modifiedAt: metadata.modifiedAt,
            fileSize: metadata.fileSize,
            snapshot: result,
            expiresAt: now.addingTimeInterval(cacheLifetime)
        )
        if cache.count > 100 {
            cache = cache.filter { now < $0.value.expiresAt }
        }
        cacheLock.unlock()
        return result
    }

    static func snapshot(
        from text: String,
        modifiedAt: Date? = nil,
        now: Date = Date()
    ) -> Snapshot? {
        var detectedState: CodexTaskState?
        var hasTaskWork = false

        for line in text.split(whereSeparator: \Character.isNewline).reversed() {
            guard
                let lineData = String(line).data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                object["type"] as? String == "event_msg",
                let payload = object["payload"] as? [String: Any],
                let type = payload["type"] as? String
            else { continue }

            switch type {
            case "task_complete":
                detectedState = detectedState ?? .completed
            case "turn_aborted":
                detectedState = detectedState ?? .interrupted
            case "task_started":
                if detectedState == nil {
                    let modified = modifiedAt ?? now
                    detectedState = now.timeIntervalSince(modified) < 900 ? .running : .interrupted
                }
                return Snapshot(
                    state: detectedState ?? .unknown,
                    isOrdinaryConversation: !hasTaskWork
                )
            case "item_completed":
                let item = payload["item"] as? [String: Any]
                hasTaskWork = hasTaskWork || isTaskWorkItem(item?["type"] as? String)
            default: continue
            }
        }

        // A long-running turn can push its task_started event outside the tail sample.
        // Recent writes without a terminal event still indicate active work.
        if let detectedState {
            return Snapshot(state: detectedState, isOrdinaryConversation: !hasTaskWork)
        }
        if let modifiedAt, now.timeIntervalSince(modifiedAt) < 120 {
            return Snapshot(state: .running, isOrdinaryConversation: !hasTaskWork)
        }
        return nil
    }

    private static func isTaskWorkItem(_ type: String?) -> Bool {
        switch type {
        case "CommandExecution", "FileChange", "McpToolCall", "DynamicToolCall", "ImageView", "Extension":
            return true
        default:
            return false
        }
    }

    private static func fileMetadata(at path: String) -> (modifiedAt: Date, fileSize: UInt64)? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        guard let modifiedAt = attributes?[.modificationDate] as? Date else { return nil }
        let fileSize = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        return (modifiedAt, fileSize)
    }
}
