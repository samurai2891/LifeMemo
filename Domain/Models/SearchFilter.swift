import Foundation

struct SearchFilter: Equatable {
    var query: String = ""
    var dateFrom: Date?
    var dateTo: Date?
    var highlightsOnly: Bool = false
    var languageMode: String?
    var hasAudio: Bool?
    var sortOrder: SortOrder = .newest

    enum SortOrder: String, CaseIterable, Identifiable {
        case newest = "newest"
        case oldest = "oldest"
        case relevance = "relevance"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .newest: return "Newest First"
            case .oldest: return "Oldest First"
            case .relevance: return "Most Relevant"
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
    }

    var hasActiveFilters: Bool {
        dateFrom != nil || dateTo != nil || highlightsOnly || languageMode != nil || hasAudio != nil
    }
}
