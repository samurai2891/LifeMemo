import Foundation

enum LanguageMode: String, CaseIterable, Identifiable, Codable {
    case auto = "auto"
    case japanese = "ja-JP"
    case english = "en-US"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return String(localized: "Auto")
        case .japanese: return String(localized: "Japanese")
        case .english: return String(localized: "English")
        }
    }

    var locale: Locale {
        switch self {
        case .auto: return Locale.current
        case .japanese: return Locale(identifier: "ja-JP")
        case .english: return Locale(identifier: "en-US")
        }
    }
}
