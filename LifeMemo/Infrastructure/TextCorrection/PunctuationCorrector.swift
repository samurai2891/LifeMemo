import Foundation

/// Stage 2: Japanese punctuation repair.
///
/// Converts ASCII punctuation to Japanese equivalents when surrounded
/// by Japanese characters. Removes extraneous spaces around punctuation
/// and deduplicates non-repeatable marks.
struct PunctuationCorrector: TextCorrectionStage {
    let name = "PunctuationCorrector"

    func apply(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = convertASCIPunctuationInJapaneseContext(text)
        result = removeSpacesAroundJapanesePunctuation(result)
        result = deduplicateNonRepeatablePunctuation(result)
        return result
    }

    // MARK: - ASCII → Japanese punctuation

    private func convertASCIPunctuationInJapaneseContext(_ text: String) -> String {
        let chars = Array(text)
        var result = ""
        result.reserveCapacity(chars.count)

        for i in 0..<chars.count {
            let char = chars[i]
            let prev: Character? = i > 0 ? chars[i - 1] : nil
            let next: Character? = i < chars.count - 1 ? chars[i + 1] : nil

            guard isJapaneseContext(prev: prev, next: next) else {
                result.append(char)
                continue
            }

            switch char {
            case ",":
                result.append("、")
            case ".":
                if isDecimalPoint(prev: prev, next: next) {
                    result.append(char)
                } else {
                    result.append("。")
                }
            case "?":
                result.append("？")
            case "!":
                result.append("！")
            default:
                result.append(char)
            }
        }
        return result
    }

    private func isDecimalPoint(prev: Character?, next: Character?) -> Bool {
        guard let p = prev, let n = next else { return false }
        return p.isNumber && n.isNumber
    }

    private func isJapaneseContext(prev: Character?, next: Character?) -> Bool {
        let neighbors = [prev, next].compactMap { $0 }
        return neighbors.contains(where: isJapaneseCharacter)
    }

    // MARK: - Space removal around punctuation

    private static let closingPunctuation: Set<Character> = [
        "。", "、", "？", "！", "）", "」", "』", "】", "〕", "〉", "》",
    ]

    private static let openingPunctuation: Set<Character> = [
        "（", "「", "『", "【", "〔", "〈", "《",
    ]

    private func removeSpacesAroundJapanesePunctuation(_ text: String) -> String {
        var result = text

        // Remove space before closing punctuation
        for punct in Self.closingPunctuation {
            result = result.replacingOccurrences(of: " \(punct)", with: String(punct))
        }
        // Remove space after opening punctuation
        for punct in Self.openingPunctuation {
            result = result.replacingOccurrences(of: "\(punct) ", with: String(punct))
        }
        return result
    }

    // MARK: - Deduplication

    private static let nonRepeatable: Set<Character> = ["。", "、"]

    private func deduplicateNonRepeatablePunctuation(_ text: String) -> String {
        var result = ""
        var lastChar: Character?
        for char in text {
            if let last = lastChar, Self.nonRepeatable.contains(char), char == last {
                continue
            }
            result.append(char)
            lastChar = char
        }
        return result
    }

    // MARK: - Japanese character detection

    private func isJapaneseCharacter(_ char: Character) -> Bool {
        for scalar in char.unicodeScalars {
            let v = scalar.value
            if (0x3040...0x309F).contains(v)   // Hiragana
                || (0x30A0...0x30FF).contains(v) // Katakana
                || (0x4E00...0x9FFF).contains(v) // CJK Unified Ideographs
                || (0x3400...0x4DBF).contains(v) // CJK Extension A
                || (0x3000...0x303F).contains(v) // CJK Symbols and Punctuation
            {
                return true
            }
        }
        return false
    }
}
