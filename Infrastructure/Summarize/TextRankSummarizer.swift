import Foundation
import NaturalLanguage

/// Graph-based extractive summarizer using TextRank algorithm.
/// Builds a similarity graph between sentences and ranks by PageRank-style iteration.
@MainActor
final class TextRankSummarizer {

    struct Config {
        var maxSentences: Int = 5
        var maxKeywords: Int = 15
        var dampingFactor: Double = 0.85
        var convergenceThreshold: Double = 0.0001
        var maxIterations: Int = 100

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
                algorithm: .textRank,
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
                algorithm: .textRank,
                sentences: single.map { [$0] } ?? [],
                keywords: extractKeywords(text),
                detectedLanguage: detectedLang,
                processingTime: elapsed,
                inputWordCount: wordCount
            )
        }

        // Build word vectors for each sentence
        let sentenceVectors = sentences.map { wordVector($0) }

        // Build similarity matrix
        let n = sentences.count
        var similarity = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                let sim = cosineSimilarity(sentenceVectors[i], sentenceVectors[j])
                similarity[i][j] = sim
                similarity[j][i] = sim
            }
        }

        // Normalize similarity matrix (row-wise)
        var normalized = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        for i in 0..<n {
            let rowSum = similarity[i].reduce(0, +)
            guard rowSum > 0 else { continue }
            for j in 0..<n {
                normalized[i][j] = similarity[i][j] / rowSum
            }
        }

        // PageRank iteration
        var scores = Array(repeating: 1.0 / Double(n), count: n)
        let d = config.dampingFactor

        for _ in 0..<config.maxIterations {
            var newScores = Array(repeating: 0.0, count: n)
            for i in 0..<n {
                var incomingSum = 0.0
                for j in 0..<n {
                    if i != j {
                        incomingSum += normalized[j][i] * scores[j]
                    }
                }
                newScores[i] = (1.0 - d) / Double(n) + d * incomingSum
            }

            // Check convergence
            let diff = zip(scores, newScores).map { abs($0 - $1) }.reduce(0, +)
            scores = newScores
            if diff < config.convergenceThreshold { break }
        }

        // Rank sentences
        let ranked = sentences.enumerated().map { index, sentence in
            SummarizationResult.RankedSentence(
                id: UUID(),
                text: sentence.trimmingCharacters(in: .whitespacesAndNewlines),
                score: scores[index],
                positionIndex: index
            )
        }

        let topSentences = Array(
            ranked.sorted { $0.score > $1.score }.prefix(config.maxSentences)
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        return SummarizationResult(
            algorithm: .textRank,
            sentences: topSentences,
            keywords: extractKeywords(text),
            detectedLanguage: detectedLang,
            processingTime: elapsed,
            inputWordCount: wordCount
        )
    }

    // MARK: - Similarity

    private func wordVector(_ text: String) -> [String: Double] {
        let words = tokenizeWords(text)
        var freq: [String: Double] = [:]
        for w in words { freq[w, default: 0] += 1 }
        return freq
    }

    private func cosineSimilarity(_ a: [String: Double], _ b: [String: Double]) -> Double {
        let allKeys = Set(a.keys).union(b.keys)
        guard !allKeys.isEmpty else { return 0 }

        var dotProduct = 0.0
        var normA = 0.0
        var normB = 0.0

        for key in allKeys {
            let va = a[key, default: 0]
            let vb = b[key, default: 0]
            dotProduct += va * vb
            normA += va * va
            normB += vb * vb
        }

        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 0 }
        return dotProduct / denom
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
