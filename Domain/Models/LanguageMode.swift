import Foundation

enum LanguageMode: String, CaseIterable, Identifiable, Codable {
    case auto = "auto"
    case japanese = "ja-JP"
    case english = "en-US"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .japanese: return "Japanese"
        case .english: return "English"
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
