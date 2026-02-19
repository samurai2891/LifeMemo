import Foundation

struct SearchFilter: Equatable {
    var query: String = ""
    var dateFrom: Date?
    var dateTo: Date?
    var highlightsOnly: Bool = false
    var languageMode: String?
    var hasAudio: Bool?
    var sortOrder: SortOrder = .newest
    var tagName: String?
    var folderName: String?

    enum SortOrder: String, CaseIterable, Identifiable {
        case newest = "newest"
        case oldest = "oldest"
        case relevance = "relevance"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .newest: return String(localized: "Newest First")
            case .oldest: return String(localized: "Oldest First")
            case .relevance: return String(localized: "Most Relevant")
            }
        }
    }

    var isEmpty: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && dateFrom == nil
            && dateTo == nil
            && !highlightsOnly
            && languageMode == nil
            && hasAudio == nil
            && tagName == nil
            && folderName == nil
    }

    var hasActiveFilters: Bool {
        dateFrom != nil || dateTo != nil || highlightsOnly || languageMode != nil || hasAudio != nil
            || tagName != nil || folderName != nil
    }
}
