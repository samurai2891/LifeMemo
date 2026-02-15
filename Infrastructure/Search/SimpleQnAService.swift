import Foundation

@MainActor
final class SimpleQnAService: QnAServiceProtocol {

    // MARK: - Dependencies

    private let repository: SessionRepository

    // MARK: - Init

    init(repository: SessionRepository) {
        self.repository = repository
    }

    // MARK: - QnAServiceProtocol

    func answer(question: String, in sessionId: UUID?) -> AnswerResult {
        let keywords = extractKeywords(from: question)
        guard !keywords.isEmpty else {
            return AnswerResult(segments: [], isEmpty: true)
        }

        var allResults: [SearchResult] = []
        for keyword in keywords {
            let results = repository.searchSegments(query: keyword, sessionId: sessionId)
            allResults.append(contentsOf: results)
        }

        // Deduplicate by segment id and take top results
        var seen = Set<UUID>()
        let unique = allResults.filter { result in
            guard !seen.contains(result.id) else { return false }
            seen.insert(result.id)
            return true
        }

        let top = Array(unique.prefix(10))
        return AnswerResult(segments: top, isEmpty: top.isEmpty)
    }

    // MARK: - Private

    private static let stopWords: Set<String> = [
        // English
        "the", "a", "an", "is", "are", "was", "were",
        "what", "where", "when", "who", "how", "why",
        "do", "does", "did",
        // Japanese particles / auxiliaries
        "\u{3092}", "\u{304C}", "\u{306F}", "\u{306E}", "\u{306B}",
        "\u{3067}", "\u{3068}", "\u{3082}", "\u{304B}",
        "\u{304B}\u{3089}", "\u{307E}\u{3067}", "\u{3078}",
        "\u{3088}\u{308A}", "\u{3063}\u{3066}",
        "\u{3067}\u{3059}", "\u{307E}\u{3059}",
        "\u{3057}\u{305F}", "\u{3059}\u{308B}",
        "\u{306A}\u{3044}", "\u{3042}\u{308B}",
        "\u{3053}\u{306E}", "\u{305D}\u{306E}",
        "\u{3042}\u{306E}", "\u{3069}\u{306E}"
    ]

    private func extractKeywords(from question: String) -> [String] {
        question
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 2 && !Self.stopWords.contains($0) }
    }
}
