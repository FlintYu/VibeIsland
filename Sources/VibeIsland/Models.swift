import Foundation
import SwiftUI
import VibeIslandShared

struct QuotaSnapshot: Equatable {
    var remainingPercent: Int
    var resetsAt: Date?
    var windowMinutes: Int?
    var weeklyRemainingPercent: Int? = nil
    var weeklyResetsAt: Date? = nil
    var weeklyWindowMinutes: Int? = nil
    var creditsBalance: String?
    var planName: String?

    static let placeholder = QuotaSnapshot(
        remainingPercent: 0,
        resetsAt: nil,
        windowMinutes: nil,
        creditsBalance: nil,
        planName: nil
    )

    func resetCountdown(relativeTo now: Date, language: AppLanguage = .chinese) -> String {
        guard let resetsAt else {
            return L10n.text(language, chinese: "等待同步", english: "Waiting to sync")
        }
        let seconds = max(0, Int(resetsAt.timeIntervalSince(now)))
        if seconds == 0 {
            return L10n.text(language, chinese: "即将刷新", english: "Refreshing soon")
        }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if language == .english {
            if days > 0 { return "\(days)d \(hours)h" }
            if hours > 0 { return "\(hours)h \(minutes)m" }
            return "\(max(1, minutes))m"
        }
        if days > 0 { return "\(days)天 \(hours)小时" }
        if hours > 0 { return "\(hours)小时 \(minutes)分" }
        return "\(max(1, minutes))分钟"
    }

    func compactResetCountdown(relativeTo now: Date, language: AppLanguage = .chinese) -> String {
        compactCountdown(to: resetsAt, relativeTo: now, language: language)
    }

    func weeklyResetCountdown(relativeTo now: Date, language: AppLanguage = .chinese) -> String {
        compactCountdown(to: weeklyResetsAt, relativeTo: now, language: language)
    }

    /// The average percentage of the full weekly quota that can still be used
    /// per day if the remaining allowance is spread evenly until the reset.
    func weeklyDailyUsageTarget(relativeTo now: Date) -> Double? {
        guard
            let weeklyRemainingPercent,
            let weeklyResetsAt
        else { return nil }

        let secondsUntilReset = weeklyResetsAt.timeIntervalSince(now)
        guard secondsUntilReset > 0 else { return nil }

        let daysUntilReset = secondsUntilReset / 86_400
        return Double(weeklyRemainingPercent) / daysUntilReset
    }

    private func compactCountdown(
        to resetDate: Date?,
        relativeTo now: Date,
        language: AppLanguage
    ) -> String {
        guard let resetDate else { return "--" }
        let seconds = max(0, Int(resetDate.timeIntervalSince(now)))
        if seconds == 0 {
            return L10n.text(language, chinese: "即将刷新", english: "Refreshing soon")
        }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if language == .english {
            if days > 0 { return "\(days)d \(hours)h" }
            if hours > 0 { return "\(hours)h \(minutes)m" }
            return "\(max(1, minutes))m"
        }
        if days > 0 { return "\(days)天 \(hours)小时" }
        if hours > 0 { return "\(hours)小时 \(minutes)分钟" }
        return "\(max(1, minutes))分钟"
    }
}

enum CodexTaskState: String, Equatable {
    case running
    case waiting
    case completed
    case interrupted
    case failed
    case idle
    case unknown

    var label: String {
        label(in: .chinese)
    }

    func label(in language: AppLanguage) -> String {
        if language == .english {
            switch self {
            case .running: return "Running"
            case .waiting: return "Waiting for input"
            case .completed: return "Completed"
            case .interrupted: return "Interrupted"
            case .failed: return "Failed"
            case .idle: return "Idle"
            case .unknown: return "Unknown"
            }
        }
        switch self {
        case .running: return "执行中"
        case .waiting: return "等待输入"
        case .completed: return "已完成"
        case .interrupted: return "已中断"
        case .failed: return "出错"
        case .idle: return "空闲"
        case .unknown: return "未知"
        }
    }

    var color: Color {
        switch self {
        case .running:
            return Color(red: 0.24, green: 0.62, blue: 1.0)
        case .waiting:
            return Color(red: 1.0, green: 0.76, blue: 0.20)
        case .completed:
            return Color(red: 0.24, green: 0.96, blue: 0.58)
        case .interrupted:
            return Color(red: 1.0, green: 0.47, blue: 0.20)
        case .failed:
            return Color(red: 1.0, green: 0.25, blue: 0.32)
        case .idle:
            return Color.white.opacity(0.42)
        case .unknown:
            return Color(red: 0.67, green: 0.48, blue: 1.0)
        }
    }

    var matrixLabel: String {
        matrixLabel(in: .chinese)
    }

    func matrixLabel(in language: AppLanguage) -> String {
        switch self {
        case .running: return "RUN"
        case .waiting: return "WAIT"
        case .completed: return "DONE"
        case .interrupted: return "STOP"
        case .failed: return "ERROR"
        case .idle: return "IDLE"
        case .unknown: return "UNKNOWN"
        }
    }
}

struct CodexTaskSnapshot: Identifiable, Equatable {
    let id: String
    let title: String
    var state: CodexTaskState
    let updatedAt: Date
    let rolloutPath: String?
    var isOrdinaryConversation = false

    var isActive: Bool {
        state == .running || state == .waiting
    }
}

struct CodexSnapshot {
    let quota: QuotaSnapshot
    let tasks: [CodexTaskSnapshot]
}

struct TaskCompletionTransitionTracker {
    private(set) var hasSnapshot = false
    private(set) var runningTaskIDs = Set<String>()

    mutating func consume(_ tasks: [CodexTaskSnapshot]) -> Set<String> {
        let newRunningIDs = Set(
            tasks
                .filter { $0.state == .running || $0.state == .waiting }
                .map(\.id)
        )

        guard hasSnapshot else {
            hasSnapshot = true
            runningTaskIDs = newRunningIDs
            return []
        }

        let completedIDs = Set(
            tasks
                .filter { $0.state == .completed }
                .map(\.id)
        )
        let newlyCompletedIDs = runningTaskIDs.intersection(completedIDs)
        runningTaskIDs = newRunningIDs
        return newlyCompletedIDs
    }
}

enum VibeIslandError: LocalizedError {
    case codexNotFound
    case serverFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return L10n.current(chinese: "未找到 Codex CLI", english: "Codex CLI was not found")
        case .serverFailed(let message):
            return L10n.current(
                chinese: "Codex 数据服务不可用：\(message)",
                english: "Codex data service unavailable: \(message)"
            )
        case .invalidResponse(let reason):
            return L10n.current(
                chinese: "Codex 返回了无法识别的数据：\(reason)",
                english: "Codex returned unrecognized data: \(reason)"
            )
        }
    }
}
