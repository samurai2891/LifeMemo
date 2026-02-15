import Foundation
import NaturalLanguage

@MainActor
final class SimpleSummarizer: SummarizerProtocol {

    // MARK: - Dependencies

    private let repository: SessionRepository

    // MARK: - Init

    init(repository: SessionRepository) {
        self.repository = repository
    }

    // MARK: - SummarizerProtocol

    func buildSummaryMarkdown(sessionId: UUID) -> String {
        let fullText = repository.getFullTranscriptText(sessionId: sessionId)
        guard !fullText.isEmpty else {
            return "# Summary\n\nNo transcript available yet."
        }

        let highlights = repository.getHighlights(sessionId: sessionId)
        let head = String(fullText.prefix(600))
        let keywords = extractKeywords(text: fullText)
            .prefix(12)
            .map { "- \($0)" }
            .joined(separator: "\n")

        var md = "# Summary\n\n"

        if !highlights.isEmpty {
            md += "## Highlights\n"
            for h in highlights.prefix(5) {
                let sec = h.atMs / 1000
                let min = sec / 60
                let remSec = sec % 60
                let label = h.label.map { " - \($0)" } ?? ""
                md += "- [\(String(format: "%02d:%02d", min, remSec))]\(label)\n"
            }
            md += "\n"
        }

        md += "## Overview\n\(head)\n\n"

        if !keywords.isEmpty {
            md += "## Keywords\n\(keywords)\n"
        }

        return md
    }

    // MARK: - Private

    private func extractKeywords(text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        var counts: [String: Int] = [:]
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: options
        ) { tag, range in
            guard tag == .noun else { return true }
            let token = String(text[range]).lowercased()
            if token.count >= 2 {
                counts[token, default: 0] += 1
            }
            return true
        }

        return counts
            .sorted { $0.value > $1.value }
            .map { $0.key }
    }
}
