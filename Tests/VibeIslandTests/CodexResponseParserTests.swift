import Foundation
import XCTest
@testable import VibeIsland
@testable import VibeIslandShared

final class CodexResponseParserTests: XCTestCase {
    func testWidgetTreatsDecodedSnapshotAsRunningAppEvenWhenCodexIsDisconnected() throws {
        let snapshot = WidgetStatusSnapshot(
            updatedAt: Date(timeIntervalSince1970: 1_000),
            remainingPercent: 68,
            resetsAt: nil,
            weeklyRemainingPercent: 82,
            weeklyResetsAt: Date(timeIntervalSince1970: 9_000),
            planName: "plus",
            isConnected: false,
            activeTaskCount: 0,
            completedTaskCount: 7
        )

        let load = WidgetStatusLoad.resolve(responseData: try JSONEncoder().encode(snapshot))

        XCTAssertTrue(load.isAppAvailable)
        XCTAssertEqual(load.snapshot, snapshot)
    }

    func testWidgetPromptsToOpenAppWhenNoSnapshotResponseArrives() {
        let load = WidgetStatusLoad.resolve(responseData: nil)

        XCTAssertFalse(load.isAppAvailable)
        XCTAssertEqual(load.snapshot, .placeholder)
    }

    func testWidgetSnapshotRoundTripsWithoutCredentialsOrPaths() throws {
        let snapshot = WidgetStatusSnapshot(
            updatedAt: Date(timeIntervalSince1970: 1_000),
            remainingPercent: 68,
            resetsAt: Date(timeIntervalSince1970: 2_000),
            weeklyRemainingPercent: 82,
            weeklyResetsAt: Date(timeIntervalSince1970: 9_000),
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

    func testWidgetSnapshotWithMissingWeeklyFieldsDefaultsToChinese() throws {
        let data = Data(
            """
            {
              "updatedAt": 1000,
              "remainingPercent": 68,
              "resetsAt": null,
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
        XCTAssertNil(snapshot.weeklyRemainingPercent)
        XCTAssertNil(snapshot.weeklyResetsAt)
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
        {"id":1,"result":{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":24,"windowDurationMins":300,"resetsAt":1800000000},"secondary":{"usedPercent":10,"windowDurationMins":10080,"resetsAt":1800500000},"credits":{"balance":"0"},"planType":"plus"}}}}
        """

        let snapshot = try CodexResponseParser.parse(Data(payload.utf8))
        XCTAssertEqual(snapshot.quota.remainingPercent, 76)
        XCTAssertEqual(snapshot.quota.windowMinutes, 300)
        XCTAssertEqual(snapshot.quota.weeklyRemainingPercent, 90)
        XCTAssertEqual(snapshot.quota.weeklyWindowMinutes, 10_080)
        XCTAssertEqual(snapshot.quota.weeklyResetsAt, Date(timeIntervalSince1970: 1_800_500_000))
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
            weeklyRemainingPercent: 82,
            weeklyResetsAt: now.addingTimeInterval(4 * 86_400 + 7_200),
            weeklyWindowMinutes: 10_080,
            creditsBalance: nil,
            planName: nil
        )
        XCTAssertEqual(quota.resetCountdown(relativeTo: now), "1天 1小时")
        XCTAssertEqual(quota.compactResetCountdown(relativeTo: now), "1天 1小时")
        XCTAssertEqual(quota.resetCountdown(relativeTo: now, language: .english), "1d 1h")
        XCTAssertEqual(quota.compactResetCountdown(relativeTo: now, language: .english), "1d 1h")
        XCTAssertEqual(quota.weeklyResetCountdown(relativeTo: now), "4天 2小时")
        XCTAssertEqual(quota.weeklyResetCountdown(relativeTo: now, language: .english), "4d 2h")
    }

    func testWeeklyDailyUsageTargetSpreadsRemainingQuotaUntilReset() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let quota = QuotaSnapshot(
            remainingPercent: 50,
            resetsAt: nil,
            windowMinutes: nil,
            weeklyRemainingPercent: 83,
            weeklyResetsAt: now.addingTimeInterval(6 * 86_400 + 11 * 3_600),
            weeklyWindowMinutes: 10_080,
            creditsBalance: nil,
            planName: nil
        )

        XCTAssertEqual(
            try XCTUnwrap(quota.weeklyDailyUsageTarget(relativeTo: now)),
            12.8516129032,
            accuracy: 0.000_000_1
        )
    }

    func testWeeklyDailyUsageTargetIsUnavailableWithoutAFutureReset() {
        let now = Date(timeIntervalSince1970: 1_000)
        var quota = QuotaSnapshot(
            remainingPercent: 50,
            resetsAt: nil,
            windowMinutes: nil,
            weeklyRemainingPercent: 83,
            weeklyResetsAt: nil,
            weeklyWindowMinutes: 10_080,
            creditsBalance: nil,
            planName: nil
        )

        XCTAssertNil(quota.weeklyDailyUsageTarget(relativeTo: now))
        quota.weeklyResetsAt = now
        XCTAssertNil(quota.weeklyDailyUsageTarget(relativeTo: now))
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
