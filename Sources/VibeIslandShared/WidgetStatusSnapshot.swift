import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case chinese
    case english

    public static let defaultsKey = "appLanguage"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .chinese: return "Chinese"
        case .english: return "English"
        }
    }

    public static func stored(in defaults: UserDefaults = .standard) -> AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .chinese
    }
}

public enum VibeIslandWidgetConstants {
    public static let kind = "VibeIslandStatusWidget"
    public static let loopbackPort: UInt16 = 47_831
}

public struct WidgetStatusSnapshot: Codable, Equatable, Sendable {
    public let updatedAt: Date
    public let remainingPercent: Int
    public let resetsAt: Date?
    public let weeklyRemainingPercent: Int?
    public let weeklyResetsAt: Date?
    public let planName: String?
    public let isConnected: Bool
    public let activeTaskCount: Int
    public let completedTaskCount: Int
    public let language: AppLanguage

    public init(
        updatedAt: Date,
        remainingPercent: Int,
        resetsAt: Date?,
        weeklyRemainingPercent: Int?,
        weeklyResetsAt: Date?,
        planName: String?,
        isConnected: Bool,
        activeTaskCount: Int,
        completedTaskCount: Int,
        language: AppLanguage = .chinese
    ) {
        self.updatedAt = updatedAt
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.weeklyRemainingPercent = weeklyRemainingPercent
        self.weeklyResetsAt = weeklyResetsAt
        self.planName = planName
        self.isConnected = isConnected
        self.activeTaskCount = activeTaskCount
        self.completedTaskCount = completedTaskCount
        self.language = language
    }

    public static let placeholder = WidgetStatusSnapshot(
        updatedAt: .now,
        remainingPercent: 0,
        resetsAt: nil,
        weeklyRemainingPercent: nil,
        weeklyResetsAt: nil,
        planName: nil,
        isConnected: false,
        activeTaskCount: 0,
        completedTaskCount: 0,
        language: .chinese
    )

    private enum CodingKeys: String, CodingKey {
        case updatedAt
        case remainingPercent
        case resetsAt
        case weeklyRemainingPercent
        case weeklyResetsAt
        case planName
        case isConnected
        case activeTaskCount
        case completedTaskCount
        case language
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        remainingPercent = try container.decode(Int.self, forKey: .remainingPercent)
        resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
        weeklyRemainingPercent = try container.decodeIfPresent(Int.self, forKey: .weeklyRemainingPercent)
        weeklyResetsAt = try container.decodeIfPresent(Date.self, forKey: .weeklyResetsAt)
        planName = try container.decodeIfPresent(String.self, forKey: .planName)
        isConnected = try container.decode(Bool.self, forKey: .isConnected)
        activeTaskCount = try container.decode(Int.self, forKey: .activeTaskCount)
        completedTaskCount = try container.decode(Int.self, forKey: .completedTaskCount)
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .chinese
    }
}

public struct WidgetStatusLoad: Equatable, Sendable {
    public let snapshot: WidgetStatusSnapshot
    public let isAppAvailable: Bool

    public static func resolve(responseData: Data?) -> WidgetStatusLoad {
        guard let responseData,
              let snapshot = try? JSONDecoder().decode(
                  WidgetStatusSnapshot.self,
                  from: responseData
              ) else {
            return WidgetStatusLoad(snapshot: .placeholder, isAppAvailable: false)
        }
        return WidgetStatusLoad(snapshot: snapshot, isAppAvailable: true)
    }
}
