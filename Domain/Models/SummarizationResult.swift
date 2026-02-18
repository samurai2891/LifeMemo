import Foundation

/// Result of on-device extractive summarization.
struct SummarizationResult: Equatable {
    /// Top extracted sentences ranked by importance.
    let sentences: [RankedSentence]
    /// Extracted keywords (nouns + named entities) sorted by frequency.
    let keywords: [String]
    /// Detected dominant language.
    let detectedLanguage: String?
    /// Processing time in seconds.
    let processingTime: TimeInterval
    /// Approximate word count of input.
    let inputWordCount: Int

    struct RankedSentence: Equatable, Identifiable {
        let id: UUID
        let text: String
        let score: Double
        let positionIndex: Int  // original position in text
    }

    var topSentencesText: String {
        sentences
            .sorted { $0.positionIndex < $1.positionIndex }
            .map(\.text)
            .joined(separator: " ")
    }
}
