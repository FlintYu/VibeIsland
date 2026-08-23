import Foundation

public enum VibeIslandWidgetConstants {
    public static let kind = "VibeIslandStatusWidget"
    public static let loopbackPort: UInt16 = 47_831
}

public struct WidgetStatusSnapshot: Codable, Equatable, Sendable {
    public let updatedAt: Date
    public let remainingPercent: Int
    public let resetsAt: Date?
    public let dailyAllowancePercent: Int?
    public let planName: String?
    public let isConnected: Bool
    public let activeTaskCount: Int
    public let completedTaskCount: Int

    public init(
        updatedAt: Date,
        remainingPercent: Int,
        resetsAt: Date?,
        dailyAllowancePercent: Int?,
        planName: String?,
        isConnected: Bool,
        activeTaskCount: Int,
        completedTaskCount: Int
    ) {
        self.updatedAt = updatedAt
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.dailyAllowancePercent = dailyAllowancePercent
        self.planName = planName
        self.isConnected = isConnected
        self.activeTaskCount = activeTaskCount
        self.completedTaskCount = completedTaskCount
    }

    public static let placeholder = WidgetStatusSnapshot(
        updatedAt: .now,
        remainingPercent: 0,
        resetsAt: nil,
        dailyAllowancePercent: nil,
        planName: nil,
        isConnected: false,
        activeTaskCount: 0,
        completedTaskCount: 0
    )
}
