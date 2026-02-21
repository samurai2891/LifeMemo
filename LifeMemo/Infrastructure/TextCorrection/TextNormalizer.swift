import Foundation

/// Stage 1: Full-width / half-width normalization and whitespace cleanup.
///
/// Converts full-width ASCII characters (letters, digits, basic symbols) to
/// half-width equivalents while preserving full-width katakana, hiragana, and kanji.
/// Collapses redundant whitespace.
struct TextNormalizer: TextCorrectionStage {
    let name = "TextNormalizer"

    func apply(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let widthNormalized = normalizeFullWidthASCII(text)
        let cleaned = normalizeWhitespace(widthNormalized)
        return cleaned
    }

    // MARK: - Width normalization

    /// Convert full-width ASCII (U+FF01–U+FF5E) and ideographic space (U+3000)
    /// to their half-width equivalents. Full-width kana are left untouched.
    private func normalizeFullWidthASCII(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.unicodeScalars.count)

        for scalar in text.unicodeScalars {
            let value = scalar.value
            switch value {
            case 0xFF01...0xFF5E:
                // Full-width ASCII → half-width (offset: 0xFEE0)
                let halfWidth = value - 0xFEE0
                result.unicodeScalars.append(Unicode.Scalar(halfWidth)!)
            case 0x3000:
                // Ideographic space → ASCII space
                result.append(" ")
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    // MARK: - Whitespace normalization

    /// Collapse runs of spaces/tabs into a single space.
    /// Preserves newlines. Trims leading/trailing whitespace per line.
    private func normalizeWhitespace(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let cleaned = lines.map { line -> String in
            var result = ""
            var lastWasSpace = false
            for char in line {
                if char == " " || char == "\t" {
                    if !lastWasSpace {
                        result.append(" ")
                        lastWasSpace = true
                    }
                } else {
                    result.append(char)
                    lastWasSpace = false
                }
            }
            return result.trimmingCharacters(in: .whitespaces)
        }
        return cleaned.joined(separator: "\n")
    }
}
