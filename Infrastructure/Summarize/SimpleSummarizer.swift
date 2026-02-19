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
        // Use speaker-attributed text if available for better summarization
        let speakerText = repository.getSpeakerAttributedTranscript(sessionId: sessionId)
        let fullText = speakerText.isEmpty
            ? repository.getFullTranscriptText(sessionId: sessionId)
            : speakerText
        guard !fullText.isEmpty else {
            return "# Summary\n\nNo transcript available yet."
        }

        let highlights = repository.getHighlights(sessionId: sessionId)
        // Summarize using raw text (without speaker labels) for cleaner extraction
        let rawText = repository.getFullTranscriptText(sessionId: sessionId)
        let result = summarize(text: rawText.isEmpty ? fullText : rawText, algorithm: algorithm)
        let topics = topicExtractor.extract(from: rawText.isEmpty ? fullText : rawText)

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

        // Speaker Participation
        let speakerStats = computeSpeakerParticipation(sessionId: sessionId)
        if !speakerStats.isEmpty {
            md += "\n## Speaker Participation\n"
            for stat in speakerStats {
                md += "- **\(stat.name)**: \(stat.wordCount) words (\(stat.percentage)%)\n"
            }
            md += "\n"
        }

        return md
    }

    // MARK: - Speaker Statistics

    private struct SpeakerStat {
        let name: String
        let wordCount: Int
        let percentage: Int
    }

    private func computeSpeakerParticipation(sessionId: UUID) -> [SpeakerStat] {
        let segments = repository.getSpeakerSegments(sessionId: sessionId)
        guard !segments.isEmpty else { return [] }

        // Check for actual diarization (not all -1)
        let hasDiarization = segments.contains { $0.speakerIndex >= 0 }
        guard hasDiarization else { return [] }

        // Count words per speaker
        var wordCounts: [Int: Int] = [:]
        var speakerNames: [Int: String] = [:]

        for segment in segments where segment.speakerIndex >= 0 {
            let words = segment.text.split(separator: " ").count
            wordCounts[segment.speakerIndex, default: 0] += words
            if let name = segment.speakerName {
                speakerNames[segment.speakerIndex] = name
            }
        }

        let totalWords = wordCounts.values.reduce(0, +)
        guard totalWords > 0 else { return [] }

        return wordCounts
            .sorted { $0.key < $1.key }
            .map { idx, count in
                let name = speakerNames[idx] ?? "Speaker \(idx + 1)"
                let pct = Int(round(Double(count) / Double(totalWords) * 100))
                return SpeakerStat(name: name, wordCount: count, percentage: pct)
            }
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
