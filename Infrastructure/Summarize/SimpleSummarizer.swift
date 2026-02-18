import Foundation
import NaturalLanguage

@MainActor
final class SimpleSummarizer: SummarizerProtocol {

    // MARK: - Dependencies

    private let repository: SessionRepository
    private let extractiveSummarizer: NLExtractiveSummarizer
    private let textRankSummarizer: TextRankSummarizer
    private let leadSummarizer: LeadSummarizer
    private let topicExtractor: TopicExtractor

    // MARK: - Init

    init(repository: SessionRepository,
         extractiveSummarizer: NLExtractiveSummarizer,
         textRankSummarizer: TextRankSummarizer,
         leadSummarizer: LeadSummarizer,
         topicExtractor: TopicExtractor) {
        self.repository = repository
        self.extractiveSummarizer = extractiveSummarizer
        self.textRankSummarizer = textRankSummarizer
        self.leadSummarizer = leadSummarizer
        self.topicExtractor = topicExtractor
    }

    // MARK: - SummarizerProtocol

    func buildSummaryMarkdown(sessionId: UUID, algorithm: SummarizationAlgorithm) -> String {
        let fullText = repository.getFullTranscriptText(sessionId: sessionId)
        guard !fullText.isEmpty else {
            return "# Summary\n\nNo transcript available yet."
        }

        let highlights = repository.getHighlights(sessionId: sessionId)
        let result = summarize(text: fullText, algorithm: algorithm)
        let topics = topicExtractor.extract(from: fullText)

        var md = "# Summary\n\n"

        // Stats + algorithm badge
        md += "*\(result.inputWordCount) words"
        if let lang = result.detectedLanguage {
            md += " \u{2022} \(lang)"
        }
        md += " \u{2022} \(algorithm.displayName)"
        md += " \u{2022} generated in \(String(format: "%.1f", result.processingTime * 1000))ms*\n\n"

        // Highlights
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

        // Key Points (extractive summary)
        if !result.sentences.isEmpty {
            md += "## Key Points\n"
            for sentence in result.sentences.sorted(by: { $0.positionIndex < $1.positionIndex }) {
                md += "- \(sentence.text)\n"
            }
            md += "\n"
        }

        // Topics
        if !topics.topicClusters.isEmpty {
            md += "## Topics\n"
            for topic in topics.topicClusters {
                let related = topic.keywords.prefix(4).joined(separator: ", ")
                md += "- **\(topic.label)** (\(related))\n"
            }
            md += "\n"
        }

        // Keywords
        if !result.keywords.isEmpty {
            md += "## Keywords\n"
            md += result.keywords.prefix(12).map { "- \($0)" }.joined(separator: "\n")
            md += "\n"
        }

        return md
    }

    // MARK: - Algorithm Dispatch

    func summarize(text: String, algorithm: SummarizationAlgorithm) -> SummarizationResult {
        switch algorithm {
        case .tfidf:
            return extractiveSummarizer.summarize(text: text)
        case .textRank:
            return textRankSummarizer.summarize(text: text)
        case .leadBased:
            return leadSummarizer.summarize(text: text)
        }
    }
}
