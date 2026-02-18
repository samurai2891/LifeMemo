import Foundation
import NaturalLanguage

/// Position-based extractive summarizer that prioritizes early sentences.
/// Combines strong position bias with length and entity density signals.
@MainActor
final class LeadSummarizer {

    struct Config {
        var maxSentences: Int = 5
        var maxKeywords: Int = 15
        var positionDecay: Double = 0.15

        static let `default` = Config()
        static let brief = Config(maxSentences: 3, maxKeywords: 8)
        static let detailed = Config(maxSentences: 8, maxKeywords: 20)
    }

    private let config: Config

    init(config: Config = .default) {
        self.config = config
    }

    func summarize(text: String) -> SummarizationResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard !text.isEmpty else {
            return SummarizationResult(
                algorithm: .leadBased,
                sentences: [], keywords: [], detectedLanguage: nil,
                processingTime: 0, inputWordCount: 0
            )
        }

        let detectedLang = detectLanguage(text)
        let wordCount = countWords(text)
        let sentences = tokenizeSentences(text)

        guard sentences.count > 1 else {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let single = sentences.first.map {
                SummarizationResult.RankedSentence(
                    id: UUID(), text: $0, score: 1.0, positionIndex: 0
                )
            }
            return SummarizationResult(
                algorithm: .leadBased,
                sentences: single.map { [$0] } ?? [],
                keywords: extractKeywords(text),
                detectedLanguage: detectedLang,
                processingTime: elapsed,
                inputWordCount: wordCount
            )
        }

        // Score primarily by position with mild length/entity adjustments
        let ranked = sentences.enumerated().map { index, sentence in
            let posScore = max(0, 1.0 - Double(index) * config.positionDecay)
            let lenScore = lengthScore(sentence: sentence) * 0.1
            let entityScore = namedEntityDensity(sentence: sentence) * 0.1
            let total = posScore * 0.8 + lenScore + entityScore

            return SummarizationResult.RankedSentence(
                id: UUID(),
                text: sentence.trimmingCharacters(in: .whitespacesAndNewlines),
                score: total,
                positionIndex: index
            )
        }

        let topSentences = Array(
            ranked.sorted { $0.score > $1.score }.prefix(config.maxSentences)
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        return SummarizationResult(
            algorithm: .leadBased,
            sentences: topSentences,
            keywords: extractKeywords(text),
            detectedLanguage: detectedLang,
            processingTime: elapsed,
            inputWordCount: wordCount
        )
    }

    // MARK: - Scoring

    private func lengthScore(sentence: String) -> Double {
        let words = countWords(sentence)
        if words >= 10, words <= 40 { return 1.0 }
        if words < 5 { return Double(words) / 5.0 }
        if words > 80 { return 80.0 / Double(words) }
        if words < 10 { return 0.6 + 0.4 * Double(words - 5) / 5.0 }
        return 0.6 + 0.4 * (1.0 - Double(words - 40) / 40.0)
    }

    private func namedEntityDensity(sentence: String) -> Double {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = sentence
        let opts: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        var entityCount = 0
        tagger.enumerateTags(
            in: sentence.startIndex..<sentence.endIndex,
            unit: .word, scheme: .nameType, options: opts
        ) { tag, _ in
            if let tag, [.personalName, .placeName, .organizationName].contains(tag) {
                entityCount += 1
            }
            return true
        }
        let words = countWords(sentence)
        guard words > 0 else { return 0.0 }
        return min(Double(entityCount) / Double(words), 1.0)
    }

    // MARK: - Language & Tokenization

    private func detectLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    private func countWords(_ text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

    private func tokenizeSentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if countWords(sentence) >= 5 {
                sentences.append(sentence)
            }
            return true
        }
        return sentences
    }

    // MARK: - Keyword Extraction

    private func extractKeywords(_ text: String) -> [String] {
        var counts: [String: Int] = [:]
        let opts: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]

        let lexTagger = NLTagger(tagSchemes: [.lexicalClass])
        lexTagger.string = text
        lexTagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word, scheme: .lexicalClass, options: opts
        ) { tag, range in
            guard tag == .noun else { return true }
            let token = String(text[range]).lowercased()
            if token.count >= 2 { counts[token, default: 0] += 1 }
            return true
        }

        let entTagger = NLTagger(tagSchemes: [.nameType])
        entTagger.string = text
        entTagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word, scheme: .nameType, options: opts
        ) { tag, range in
            if let tag, [.personalName, .placeName, .organizationName].contains(tag) {
                let entity = String(text[range])
                if entity.count >= 2 { counts[entity, default: 0] += 2 }
            }
            return true
        }

        return counts
            .sorted { $0.value > $1.value }
            .prefix(config.maxKeywords)
            .map(\.key)
    }
}
