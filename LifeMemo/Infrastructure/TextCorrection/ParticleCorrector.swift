import Foundation
import NaturalLanguage

/// Stage 3: NLTagger-based Japanese particle correction.
///
/// Corrects commonly mis-transcribed particles:
/// - わ → は (topic marker, when preceded by noun and followed by verb/adjective)
/// - お → を (object marker, when preceded by noun and followed by verb)
/// - え → へ (direction marker, when preceded by noun and followed by verb)
struct ParticleCorrector: TextCorrectionStage {
    let name = "ParticleCorrector"

    func apply(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let tokens = tokenize(text)
        guard tokens.count > 1 else { return text }
        return correctParticles(in: text, tokens: tokens)
    }

    // MARK: - Token type

    private struct Token {
        let text: String
        let range: Range<String.Index>
        let tag: NLTag?
    }

    // MARK: - Tokenization

    private func tokenize(_ text: String) -> [Token] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        tagger.setLanguage(.japanese, range: text.startIndex..<text.endIndex)

        var tokens: [Token] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass
        ) { tag, range in
            tokens.append(Token(
                text: String(text[range]),
                range: range,
                tag: tag
            ))
            return true
        }
        return tokens
    }

    // MARK: - Correction logic

    private func correctParticles(in text: String, tokens: [Token]) -> String {
        // Build corrections in reverse order to preserve string indices
        var corrections: [(range: Range<String.Index>, replacement: String)] = []

        for i in 0..<tokens.count {
            let token = tokens[i]
            let prev: Token? = i > 0 ? tokens[i - 1] : nil
            let next: Token? = i < tokens.count - 1 ? tokens[i + 1] : nil

            if let replacement = particleReplacement(
                token: token, prev: prev, next: next
            ) {
                corrections.append((range: token.range, replacement: replacement))
            }
        }

        guard !corrections.isEmpty else { return text }

        // Apply in reverse order
        var result = text
        for correction in corrections.reversed() {
            result = result.replacingCharacters(
                in: correction.range,
                with: correction.replacement
            )
        }
        return result
    }

    private func particleReplacement(
        token: Token, prev: Token?, next: Token?
    ) -> String? {
        // Only consider single-character particles
        guard token.text.count == 1 else { return nil }

        switch token.text {
        case "わ":
            // わ → は: topic marker after noun, before verb/adjective
            if isNounLike(prev?.tag) && isPredicateLike(next?.tag) {
                return "は"
            }
        case "お":
            // お → を: object marker after noun, before verb
            if isNounLike(prev?.tag) && isVerb(next?.tag) {
                return "を"
            }
        case "え":
            // え → へ: direction marker after noun, before verb
            if isNounLike(prev?.tag) && isVerb(next?.tag) {
                return "へ"
            }
        default:
            break
        }
        return nil
    }

    // MARK: - POS helpers

    private func isNounLike(_ tag: NLTag?) -> Bool {
        guard let tag else { return false }
        return [
            .noun, .pronoun, .personalName, .placeName, .organizationName,
        ].contains(tag)
    }

    private func isPredicateLike(_ tag: NLTag?) -> Bool {
        guard let tag else { return false }
        return tag == .verb || tag == .adjective
    }

    private func isVerb(_ tag: NLTag?) -> Bool {
        tag == .verb
    }
}

// MARK: - String helpers

private extension String {
    func replacingCharacters(
        in range: Range<String.Index>,
        with replacement: String
    ) -> String {
        String(self[..<range.lowerBound])
            + replacement
            + String(self[range.upperBound...])
    }
}
