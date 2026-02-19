import Foundation

/// Available on-device summarization algorithms.
enum SummarizationAlgorithm: String, CaseIterable, Identifiable, Codable {
    case tfidf = "tfidf"
    case textRank = "textrank"
    case leadBased = "lead"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tfidf: return String(localized: "TF-IDF")
        case .textRank: return String(localized: "TextRank")
        case .leadBased: return String(localized: "Lead-Based")
        }
    }

    var description: String {
        switch self {
        case .tfidf:
            return String(localized: "Term Frequency-Inverse Document Frequency scoring with position, length, and entity density signals.")
        case .textRank:
            return String(localized: "Graph-based ranking using sentence similarity, inspired by Google's PageRank algorithm.")
        case .leadBased:
            return String(localized: "Prioritizes sentences by position, weighting early sentences as most important.")
        }
    }
}
