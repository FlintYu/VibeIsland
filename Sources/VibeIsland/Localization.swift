import Foundation
import VibeIslandShared

enum L10n {
    static func text(_ language: AppLanguage, chinese: String, english: String) -> String {
        language == .chinese ? chinese : english
    }

    static func current(chinese: String, english: String) -> String {
        text(AppLanguage.stored(), chinese: chinese, english: english)
    }
}
