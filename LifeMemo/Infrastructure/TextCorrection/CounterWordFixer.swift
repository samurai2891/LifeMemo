import Foundation

/// Stage 6: Counter word normalization and archaic numeral conversion.
///
/// Fixes hiragana counter words that should be kanji (e.g. "ひとり" → "一人")
/// and normalizes archaic/formal numerals to modern forms (e.g. "壱" → "一").
struct CounterWordFixer: TextCorrectionStage {
    let name = "CounterWordFixer"

    func apply(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = fixCounterWords(text)
        result = normalizeArchaicNumerals(result)
        return result
    }

    // MARK: - Counter word corrections

    /// Hiragana counter words that should be written in kanji.
    private static let counterCorrections: [(pattern: String, replacement: String)] = [
        // People
        ("ひとり", "一人"),
        ("ふたり", "二人"),
        ("さんにん", "三人"),
        ("よにん", "四人"),
        ("ごにん", "五人"),
        // General counter
        ("いっこ", "一個"),
        ("にこ", "二個"),
        ("さんこ", "三個"),
        ("よんこ", "四個"),
        ("ごこ", "五個"),
        // Flat objects (sheets, tickets)
        ("いちまい", "一枚"),
        ("にまい", "二枚"),
        ("さんまい", "三枚"),
        // Long objects (pens, bottles)
        ("いっぽん", "一本"),
        ("にほん", "二本"),
        ("さんぼん", "三本"),
        // Small animals / insects
        ("いっぴき", "一匹"),
        ("にひき", "二匹"),
        ("さんびき", "三匹"),
        // Bound objects (books)
        ("いっさつ", "一冊"),
        ("にさつ", "二冊"),
        ("さんさつ", "三冊"),
        // Machines / vehicles
        ("いちだい", "一台"),
        ("にだい", "二台"),
        ("さんだい", "三台"),
        // Times / occurrences
        ("いっかい", "一回"),
        ("にかい", "二回"),
        ("さんかい", "三回"),
        // Hours (o'clock)
        ("いちじ", "一時"),
        ("にじ", "二時"),
        ("さんじ", "三時"),
        ("よじ", "四時"),
        ("ごじ", "五時"),
        ("ろくじ", "六時"),
        ("しちじ", "七時"),
        ("はちじ", "八時"),
        ("くじ", "九時"),
        ("じゅうじ", "十時"),
        // Months
        ("いちがつ", "一月"),
        ("にがつ", "二月"),
        ("さんがつ", "三月"),
        ("しがつ", "四月"),
        ("ごがつ", "五月"),
        ("ろくがつ", "六月"),
        ("しちがつ", "七月"),
        ("はちがつ", "八月"),
        ("くがつ", "九月"),
        ("じゅうがつ", "十月"),
        ("じゅういちがつ", "十一月"),
        ("じゅうにがつ", "十二月"),
    ]

    // MARK: - Archaic numerals

    /// Old-form / formal kanji numerals to their modern equivalents.
    private static let archaicNumerals: [(old: String, modern: String)] = [
        ("壱", "一"),
        ("弐", "二"),
        ("参", "三"),
        ("肆", "四"),
        ("伍", "五"),
        ("陸", "六"),
        ("漆", "七"),
        ("捌", "八"),
        ("玖", "九"),
        ("拾", "十"),
        ("佰", "百"),
        ("仟", "千"),
        ("萬", "万"),
    ]

    // MARK: - Application

    /// Sorted by pattern length descending so longer patterns match first.
    /// Prevents "にがつ" from matching inside "じゅうにがつ".
    private static let sortedCounterCorrections: [(pattern: String, replacement: String)] = {
        counterCorrections.sorted { $0.pattern.count > $1.pattern.count }
    }()

    private func fixCounterWords(_ text: String) -> String {
        var result = text
        for correction in Self.sortedCounterCorrections {
            result = result.replacingOccurrences(
                of: correction.pattern, with: correction.replacement
            )
        }
        return result
    }

    private func normalizeArchaicNumerals(_ text: String) -> String {
        var result = text
        for numeral in Self.archaicNumerals {
            result = result.replacingOccurrences(
                of: numeral.old, with: numeral.modern
            )
        }
        return result
    }
}
