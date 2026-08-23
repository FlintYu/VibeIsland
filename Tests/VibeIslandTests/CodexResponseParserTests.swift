import Foundation
import XCTest
@testable import VibeIsland
@testable import VibeIslandShared

final class CodexResponseParserTests: XCTestCase {
    func testWidgetSnapshotRoundTripsWithoutCredentialsOrPaths() throws {
        let snapshot = WidgetStatusSnapshot(
            updatedAt: Date(timeIntervalSince1970: 1_000),
            remainingPercent: 68,
            resetsAt: Date(timeIntervalSince1970: 2_000),
            dailyAllowancePercent: 21,
            planName: "plus",
            isConnected: true,
            activeTaskCount: 2,
            completedTaskCount: 7,
            language: .english
        )

        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(WidgetStatusSnapshot.self, from: data), snapshot)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("auth"))
        XCTAssertFalse(text.contains("/Users/"))
        XCTAssertFalse(text.contains("Build"))
    }

    func testLegacyWidgetSnapshotDefaultsToChinese() throws {
        let data = Data(
            """
            {
              "updatedAt": 1000,
              "remainingPercent": 68,
              "resetsAt": null,
              "dailyAllowancePercent": 21,
              "planName": "plus",
              "isConnected": true,
              "activeTaskCount": 2,
              "completedTaskCount": 7
            }
            """.utf8
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(WidgetStatusSnapshot.self, from: data)
        XCTAssertEqual(snapshot.language, .chinese)
    }

    @MainActor
    func testLanguagePreferencePersists() throws {
        let suiteName = "VibeIslandTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = IslandSettingsModel(defaults: defaults)
        XCTAssertEqual(settings.language, .chinese)
        settings.setLanguage(.english)

        XCTAssertEqual(IslandSettingsModel(defaults: defaults).language, .english)
    }

    func testExecutableOverrideDoesNotDependOnUserHomePath() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibe-island-codex-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data().write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )

        XCTAssertEqual(
            CodexInstallation.executablePath(override: url.path),
            url.path
        )
    }

    func testInitializedNotificationOmitsParamsForCurrentProtocol() {
        let initialized = CodexAppServerClient.requestMessages()[1]
        XCTAssertEqual(initialized["method"] as? String, "initialized")
        XCTAssertNil(initialized["params"])
    }

    func testParsesQuotaAndThreads() throws {
        let payload = """
        {"id":0,"result":{"userAgent":"test"}}
        {"id":2,"result":{"data":[{"id":"thread-1","name":"Build the island","preview":"fallback","updatedAt":1700000000,"status":{"type":"active","activeFlags":[]},"path":null}]}}
        {"id":1,"result":{"rateLimits":{"primary":{"usedPercent":24,"windowDurationMins":10080,"resetsAt":1800000000},"credits":{"balance":"0"},"planType":"plus"}}}
        """

        let snapshot = try CodexResponseParser.parse(Data(payload.utf8))
        XCTAssertEqual(snapshot.quota.remainingPercent, 76)
        XCTAssertEqual(snapshot.quota.windowMinutes, 10_080)
        XCTAssertEqual(snapshot.quota.planName, "plus")
        XCTAssertEqual(snapshot.tasks.first?.title, "Build the island")
        XCTAssertEqual(snapshot.tasks.first?.state, .running)
    }

    func testWaitingStatusAndCountdown() {
        XCTAssertEqual(
            CodexResponseParser.state(from: ["type": "active", "activeFlags": ["waitingOnUserInput"]]),
            .waiting
        )

        let now = Date(timeIntervalSince1970: 1_000)
        let quota = QuotaSnapshot(
            remainingPercent: 50,
            resetsAt: now.addingTimeInterval(90_060),
            windowMinutes: nil,
            creditsBalance: nil,
            planName: nil
        )
        XCTAssertEqual(quota.resetCountdown(relativeTo: now), "1天 1小时")
        XCTAssertEqual(quota.compactResetCountdown(relativeTo: now), "1天 1小时")
        XCTAssertEqual(quota.resetCountdown(relativeTo: now, language: .english), "1d 1h")
        XCTAssertEqual(quota.compactResetCountdown(relativeTo: now, language: .english), "1d 1h")
        XCTAssertEqual(quota.averageDailyAllowance(relativeTo: now), 47)
    }

    func testRecentRolloutWithoutTerminalEventIsRunning() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibe-island-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        {"type":"event_msg","payload":{"type":"item_completed"}}
        """.write(to: url, atomically: true, encoding: .utf8)

        XCTAssertEqual(RolloutStatusDetector.state(at: url.path), .running)
    }

    func testOrdinaryConversationTurnIsRunningUntilTaskCompletes() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibe-island-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }

        try """
        {"type":"event_msg","payload":{"type":"task_started"}}
        {"type":"event_msg","payload":{"type":"item_completed"}}
        """.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(RolloutStatusDetector.state(at: url.path), .running)
        XCTAssertEqual(
            RolloutStatusDetector.snapshot(at: url.path)?.isOrdinaryConversation,
            true
        )

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}\n".utf8))
        try handle.close()
        XCTAssertEqual(RolloutStatusDetector.state(at: url.path), .completed)
    }

    func testToolWorkIsNotClassifiedAsOrdinaryConversation() {
        let text = """
        {"type":"event_msg","payload":{"type":"task_started"}}
        {"type":"event_msg","payload":{"type":"item_completed","item":{"type":"CommandExecution"}}}
        {"type":"event_msg","payload":{"type":"task_complete"}}
        """

        let snapshot = RolloutStatusDetector.snapshot(from: text)
        XCTAssertEqual(snapshot?.state, .completed)
        XCTAssertEqual(snapshot?.isOrdinaryConversation, false)
    }

    func testCompletionTransitionOnlyFiresAfterRunningTaskCompletes() {
        let now = Date()
        func task(_ state: CodexTaskState) -> CodexTaskSnapshot {
            CodexTaskSnapshot(
                id: "task-1",
                title: "Build",
                state: state,
                updatedAt: now,
                rolloutPath: nil
            )
        }

        var tracker = TaskCompletionTransitionTracker()
        XCTAssertTrue(tracker.consume([task(.running)]).isEmpty)
        XCTAssertTrue(tracker.consume([task(.running)]).isEmpty)
        XCTAssertEqual(tracker.consume([task(.completed)]), ["task-1"])
        XCTAssertTrue(tracker.consume([task(.completed)]).isEmpty)
    }
}
