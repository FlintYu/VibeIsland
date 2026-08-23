import Foundation
import SwiftUI

struct QuotaSnapshot: Equatable {
    var remainingPercent: Int
    var resetsAt: Date?
    var windowMinutes: Int?
    var creditsBalance: String?
    var planName: String?

    static let placeholder = QuotaSnapshot(
        remainingPercent: 0,
        resetsAt: nil,
        windowMinutes: nil,
        creditsBalance: nil,
        planName: nil
    )

    func resetCountdown(relativeTo now: Date) -> String {
        guard let resetsAt else { return "等待同步" }
        let seconds = max(0, Int(resetsAt.timeIntervalSince(now)))
        if seconds == 0 { return "即将刷新" }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)天 \(hours)小时" }
        if hours > 0 { return "\(hours)小时 \(minutes)分" }
        return "\(max(1, minutes))分钟"
    }

    func compactResetCountdown(relativeTo now: Date) -> String {
        guard let resetsAt else { return "--" }
        let seconds = max(0, Int(resetsAt.timeIntervalSince(now)))
        if seconds == 0 { return "即将刷新" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)天 \(hours)小时" }
        if hours > 0 { return "\(hours)小时 \(minutes)分钟" }
        return "\(max(1, minutes))分钟"
    }

    func averageDailyAllowance(relativeTo now: Date) -> Int? {
        guard let resetsAt else { return nil }
        let secondsRemaining = max(0, resetsAt.timeIntervalSince(now))
        guard secondsRemaining > 0 else { return remainingPercent }
        let daysRemaining = max(1, secondsRemaining / 86_400)
        let dailyAllowance = Double(remainingPercent) / daysRemaining
        return max(0, min(100, Int(dailyAllowance.rounded(.down))))
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
            return "未找到 Codex CLI"
        case .serverFailed(let message):
            return "Codex 数据服务不可用：\(message)"
        case .invalidResponse(let reason):
            return "Codex 返回了无法识别的数据：\(reason)"
        }
    }
}
