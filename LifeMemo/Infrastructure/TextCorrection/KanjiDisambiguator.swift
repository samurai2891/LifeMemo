import Foundation
import NaturalLanguage

/// Stage 5: N-gram + NLEmbedding context-based kanji selection.
///
/// For each word matching a known homophone group, computes a weighted score
/// from three signals:
/// - N-gram frequency (40%): Bigram co-occurrence with neighboring words
/// - NLEmbedding similarity (35%): Cosine distance to surrounding context
/// - Rule confidence (25%): Static context patterns from homophone rules
///
/// Only corrects when the best candidate score exceeds 0.6 and differs
/// from the current word.
struct KanjiDisambiguator: TextCorrectionStage {
    let name = "KanjiDisambiguator"

    private static let minimumConfidence: Double = 0.6
    private static let ngramWeight: Double = 0.40
    private static let embeddingWeight: Double = 0.35
    private static let ruleWeight: Double = 0.25

    func apply(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let words = tokenizeWords(text)
        guard words.count > 1 else { return text }
        return disambiguate(text: text, words: words)
    }

    // MARK: - Word token

    private struct WordToken {
        let text: String
        let range: Range<String.Index>
    }

    // MARK: - Tokenization

    private func tokenizeWords(_ text: String) -> [WordToken] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(.japanese)

        var tokens: [WordToken] = []
        tokenizer.enumerateTokens(
            in: text.startIndex..<text.endIndex
        ) { range, _ in
            tokens.append(WordToken(text: String(text[range]), range: range))
            return true
        }
        return tokens
    }

    // MARK: - Disambiguation

    private func disambiguate(text: String, words: [WordToken]) -> String {
        var result = text
        let wordTexts = words.map(\.text)

        // Process in reverse so earlier ranges stay valid after replacement
        for i in stride(from: words.count - 1, through: 0, by: -1) {
            let word = words[i]
            guard let group = JapaneseHomophoneRules.group(containing: word.text) else {
                continue
            }
            guard group.candidates.count > 1 else { continue }

            let prevWord = i > 0 ? wordTexts[i - 1] : nil
            let nextWord = i < wordTexts.count - 1 ? wordTexts[i + 1] : nil

            if let best = bestCandidate(
                current: word.text,
                group: group,
                prevWord: prevWord,
                nextWord: nextWord,
                allWords: wordTexts
            ), best.word != word.text {
                var mutable = result
                mutable.replaceSubrange(word.range, with: best.word)
                result = mutable
            }
        }
        return result
    }

    // MARK: - Candidate scoring

    private struct ScoredCandidate {
        let word: String
        let score: Double
    }

    private func bestCandidate(
        current: String,
        group: HomophoneGroup,
        prevWord: String?,
        nextWord: String?,
        allWords: [String]
    ) -> ScoredCandidate? {
        let scored = group.candidates.map { candidate -> ScoredCandidate in
            let ngram = computeNgramScore(
                candidate: candidate.word,
                prevWord: prevWord,
                nextWord: nextWord
            )
            let embedding = computeEmbeddingScore(
                candidate: candidate.word,
                context: allWords
            )
            let rule = computeRuleScore(
                candidate: candidate,
                prevWord: prevWord,
                nextWord: nextWord
            )

            let total =
                ngram * Self.ngramWeight
                + embedding * Self.embeddingWeight
                + rule * Self.ruleWeight

            return ScoredCandidate(word: candidate.word, score: total)
        }

        guard let best = scored.max(by: { $0.score < $1.score }),
              best.score > Self.minimumConfidence
        else {
            return nil
        }
        return best
    }

    // MARK: - Signal 1: N-gram score

    private func computeNgramScore(
        candidate: String, prevWord: String?, nextWord: String?
    ) -> Double {
        var score: Double = 0.0
        var count: Double = 0.0

        if let prev = prevWord {
            let s = JapaneseNGramTable.bigramScore(first: prev, second: candidate)
            if s > 0 { score += s; count += 1 }
        }
        if let next = nextWord {
            let s = JapaneseNGramTable.bigramScore(first: candidate, second: next)
            if s > 0 { score += s; count += 1 }
        }
        return count > 0 ? score / count : 0.0
    }

    // MARK: - Signal 2: NLEmbedding score

    private func computeEmbeddingScore(
        candidate: String, context: [String]
    ) -> Double {
        guard let embedding = NLEmbedding.wordEmbedding(for: .japanese) else {
            return 0.0
        }
        // Only compute if the candidate word has a vector
        guard embedding.vector(for: candidate) != nil else { return 0.0 }

        var totalSimilarity: Double = 0.0
        var count: Double = 0.0

        for contextWord in context where contextWord != candidate {
            guard embedding.vector(for: contextWord) != nil else { continue }
            let distance = embedding.distance(
                between: candidate, and: contextWord
            )
            // NLEmbedding distance is typically 0–2 (cosine); normalize to 0–1
            let similarity = max(0, 1.0 - distance / 2.0)
            totalSimilarity += similarity
            count += 1
        }
        return count > 0 ? totalSimilarity / count : 0.0
    }

    // MARK: - Signal 3: Rule confidence

    private func computeRuleScore(
        candidate: HomophoneCandidate,
        prevWord: String?,
        nextWord: String?
    ) -> Double {
        var maxScore = candidate.baseFrequency

        for pattern in candidate.contextPatterns {
            var matches = false
            if let prev = prevWord, !pattern.precedingWords.isEmpty {
                if pattern.precedingWords.contains(prev) {
                    matches = true
                }
            }
            if let next = nextWord, !pattern.followingWords.isEmpty {
                if pattern.followingWords.contains(next) {
                    matches = true
                }
            }
            if matches {
                maxScore = max(maxScore, pattern.confidence)
            }
        }
        return maxScore
    }
}
