import Foundation

/// A single long-lived app-server process. Starting a new process for every
/// one-second poll caused recurring CPU spikes that were visible in UI animations.
private final class CodexAppServerConnection: @unchecked Sendable {
    private let requestLock = NSLock()
    private let responseCondition = NSCondition()

    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var readBuffer = Data()
    private var responses: [Int: [String: Any]] = [:]
    private var serverStopped = false
    private var connectionGeneration = 0
    private var nextRequestID = 10

    deinit {
        stop()
    }

    func fetch(executable: String) throws -> CodexSnapshot {
        requestLock.lock()
        defer { requestLock.unlock() }

        do {
            try ensureStarted(executable: executable)
            let rateLimitID = nextRequestID
            let threadListID = nextRequestID + 1
            nextRequestID += 2
            try write([
                ["id": rateLimitID, "method": "account/rateLimits/read", "params": [:]],
                [
                    "id": threadListID,
                    "method": "thread/list",
                    "params": [
                        "limit": 20,
                        "sortKey": "updated_at",
                        "sortDirection": "desc",
                        "useStateDbOnly": true
                    ]
                ]
            ])
            let result = try waitForResponses(ids: [rateLimitID, threadListID])
            return try parseSnapshot(
                result,
                rateLimitID: rateLimitID,
                threadListID: threadListID
            )
        } catch {
            stop()
            throw error
        }
    }

    private func ensureStarted(executable: String) throws {
        if process?.isRunning == true { return }
        stop()

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let outputHandle = outputPipe.fileHandleForReading

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        responseCondition.lock()
        connectionGeneration &+= 1
        let generation = connectionGeneration
        readBuffer.removeAll(keepingCapacity: true)
        responses.removeAll(keepingCapacity: true)
        serverStopped = false
        responseCondition.unlock()

        outputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                self?.markServerStopped(generation: generation)
                return
            }
            self?.receive(data, generation: generation)
        }
        process.terminationHandler = { [weak self] _ in
            self?.markServerStopped(generation: generation)
        }

        try process.run()
        self.process = process
        inputHandle = inputPipe.fileHandleForWriting
        self.outputHandle = outputHandle

        try write([
            [
                "id": 0,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "vibe-island",
                        "title": "Vibe Island",
                        "version": AppMetadata.version
                    ],
                    "capabilities": ["experimentalApi": true]
                ]
            ],
            ["method": "initialized"]
        ])
    }

    private func write(_ messages: [[String: Any]]) throws {
        guard let inputHandle else {
            throw VibeIslandError.serverFailed(
                L10n.current(chinese: "连接尚未建立", english: "Connection has not been established")
            )
        }
        var data = Data()
        for message in messages {
            data.append(try JSONSerialization.data(withJSONObject: message))
            data.append(0x0A)
        }
        try inputHandle.write(contentsOf: data)
    }

    private func receive(_ data: Data, generation: Int) {
        responseCondition.lock()
        guard generation == connectionGeneration else {
            responseCondition.unlock()
            return
        }
        readBuffer.append(data)
        while let newlineIndex = readBuffer.firstIndex(of: 0x0A) {
            let line = Data(readBuffer[..<newlineIndex])
            readBuffer.removeSubrange(...newlineIndex)
            guard
                let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                let id = object["id"] as? Int
            else { continue }
            responses[id] = object
        }
        responseCondition.broadcast()
        responseCondition.unlock()
    }

    private func waitForResponses(ids: Set<Int>) throws -> [Int: [String: Any]] {
        let deadline = Date().addingTimeInterval(4)
        responseCondition.lock()
        defer { responseCondition.unlock() }

        while !ids.allSatisfy({ responses[$0] != nil }) && !serverStopped {
            if !responseCondition.wait(until: deadline) { break }
        }
        guard ids.allSatisfy({ responses[$0] != nil }) else {
            throw VibeIslandError.serverFailed(
                serverStopped
                    ? L10n.current(chinese: "连接已中断", english: "Connection was interrupted")
                    : L10n.current(chinese: "请求超时", english: "Request timed out")
            )
        }

        var result: [Int: [String: Any]] = [:]
        for id in ids {
            result[id] = responses.removeValue(forKey: id)
        }
        return result
    }

    private func parseSnapshot(
        _ responseObjects: [Int: [String: Any]],
        rateLimitID: Int,
        threadListID: Int
    ) throws -> CodexSnapshot {
        guard var rateLimits = responseObjects[rateLimitID],
              var threadList = responseObjects[threadListID] else {
            throw VibeIslandError.invalidResponse(
                L10n.current(
                    chinese: "缺少任务或额度响应",
                    english: "Task or quota response is missing"
                )
            )
        }
        // Normalize dynamic request IDs for the existing parser.
        rateLimits["id"] = 1
        threadList["id"] = 2
        var data = try JSONSerialization.data(withJSONObject: rateLimits)
        data.append(0x0A)
        data.append(try JSONSerialization.data(withJSONObject: threadList))
        data.append(0x0A)
        return try CodexResponseParser.parse(data)
    }

    private func markServerStopped(generation: Int) {
        responseCondition.lock()
        guard generation == connectionGeneration else {
            responseCondition.unlock()
            return
        }
        serverStopped = true
        responseCondition.broadcast()
        responseCondition.unlock()
    }

    private func stop() {
        responseCondition.lock()
        connectionGeneration &+= 1
        serverStopped = true
        responseCondition.broadcast()
        responseCondition.unlock()

        outputHandle?.readabilityHandler = nil
        try? inputHandle?.close()
        if process?.isRunning == true {
            process?.terminationHandler = nil
            process?.terminate()
        }
        process = nil
        inputHandle = nil
        outputHandle = nil
    }
}

struct CodexAppServerClient {
    var codexExecutableOverride: String?
    private let connection = CodexAppServerConnection()

    static func requestMessages() -> [[String: Any]] {
        [
            [
                "id": 0,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "vibe-island",
                        "title": "Vibe Island",
                        "version": AppMetadata.version
                    ],
                    "capabilities": ["experimentalApi": true]
                ]
            ],
            // The initialized notification has no params in the current app-server protocol.
            // Sending an empty params object makes newer servers ignore subsequent requests.
            ["method": "initialized"],
            ["id": 1, "method": "account/rateLimits/read", "params": [:]],
            [
                "id": 2,
                "method": "thread/list",
                "params": [
                    "limit": 20,
                    "sortKey": "updated_at",
                    "sortDirection": "desc",
                    "useStateDbOnly": true
                ]
            ]
        ]
    }

    func fetch() async throws -> CodexSnapshot {
        let executable = try locateCodex()
        let connection = connection
        return try await Task.detached(priority: .utility) {
            try connection.fetch(executable: executable)
        }.value
    }

    private func locateCodex() throws -> String {
        guard let path = CodexInstallation.executablePath(override: codexExecutableOverride) else {
            throw VibeIslandError.codexNotFound
        }
        return path
    }
}
