import Foundation
import NaturalLanguage

/// On-device extractive summarizer using Apple's NaturalLanguage framework.
/// Scores sentences by TF-IDF relevance, position, length, and named entity density.
@MainActor
final class NLExtractiveSummarizer {

    // MARK: - Configuration

    struct Config {
        var maxSentences: Int = 5
        var maxKeywords: Int = 15
        var positionBias: Double = 0.3
        var lengthPenaltyMin: Int = 5
        var lengthPenaltyMax: Int = 80

        static let `default` = Config()
        static let brief = Config(maxSentences: 3, maxKeywords: 8)
        static let detailed = Config(maxSentences: 8, maxKeywords: 20)
    }

    private let config: Config

    init(config: Config = .default) {
        self.config = config
    }

    // MARK: - Public API

    func summarize(text: String) -> SummarizationResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard !text.isEmpty else {
            return SummarizationResult(
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
                sentences: single.map { [$0] } ?? [],
                keywords: extractKeywords(text),
                detectedLanguage: detectedLang,
                processingTime: elapsed,
                inputWordCount: wordCount
            )
        }

        let tfidfScores = computeTFIDF(sentences: sentences)
        let ranked = sentences.enumerated().map { index, sentence in
            let score = tfidfScores[index] * 0.4
                + positionScore(index: index, total: sentences.count) * config.positionBias
                + lengthScore(sentence: sentence) * 0.15
                + namedEntityDensity(sentence: sentence) * 0.15
            return SummarizationResult.RankedSentence(
                id: UUID(),
                text: sentence.trimmingCharacters(in: .whitespacesAndNewlines),
                score: score,
                positionIndex: index
            )
        }

        let topSentences = Array(
            ranked.sorted { $0.score > $1.score }.prefix(config.maxSentences)
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        return SummarizationResult(
            sentences: topSentences,
            keywords: extractKeywords(text),
            detectedLanguage: detectedLang,
            processingTime: elapsed,
            inputWordCount: wordCount
        )
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

    private func tokenizeWords(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var words: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            words.append(String(text[range]).lowercased())
            return true
        }
        return words
    }

    private func tokenizeSentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if countWords(sentence) >= config.lengthPenaltyMin {
                sentences.append(sentence)
            }
            return true
        }
        return sentences
    }

    // MARK: - TF-IDF

    private func computeTFIDF(sentences: [String]) -> [Double] {
        let total = Double(sentences.count)
        let tokenized = sentences.map { tokenizeWords($0) }

        // Document frequency: how many sentences contain each term
        var df: [String: Int] = [:]
        for words in tokenized {
            for term in Set(words) {
                df[term, default: 0] += 1
            }
        }

        // Per-sentence TF-IDF score
        let scores = tokenized.map { words -> Double in
            guard !words.isEmpty else { return 0.0 }
            var tf: [String: Int] = [:]
            for w in words { tf[w, default: 0] += 1 }
            let len = Double(words.count)
            return tf.reduce(0.0) { acc, pair in
                let idf = log(total / Double(df[pair.key, default: 1]))
                return acc + (Double(pair.value) / len) * idf
            }
        }

        // Normalize to 0..1
        let maxScore = scores.max() ?? 1.0
        guard maxScore > 0 else { return scores }
        return scores.map { $0 / maxScore }
    }

    // MARK: - Scoring Signals

    private func positionScore(index: Int, total: Int) -> Double {
        guard total > 1 else { return 1.0 }
        if index == 0 { return 1.0 }
        if index == total - 1 { return 0.8 }
        return 1.0 - (Double(index) / Double(total)) * 0.5
    }

    private func lengthScore(sentence: String) -> Double {
        let words = countWords(sentence)
        if words >= 10, words <= 40 { return 1.0 }
        if words < config.lengthPenaltyMin {
            return Double(words) / Double(config.lengthPenaltyMin)
        }
        if words > config.lengthPenaltyMax {
            return Double(config.lengthPenaltyMax) / Double(words)
        }
        if words < 10 {
            return 0.6 + 0.4 * Double(words - config.lengthPenaltyMin)
                / Double(10 - config.lengthPenaltyMin)
        }
        return 0.6 + 0.4 * (1.0 - Double(words - 40)
            / Double(config.lengthPenaltyMax - 40))
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

    // MARK: - Keyword Extraction

    private func extractKeywords(_ text: String) -> [String] {
        var counts: [String: Int] = [:]
        let opts: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]

        // Nouns via lexical class
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

        // Named entities with boosted weight
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
