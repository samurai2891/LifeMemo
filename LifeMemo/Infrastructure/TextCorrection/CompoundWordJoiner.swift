import Foundation

/// Stage 4: Re-join compound words split by speech recognition.
///
/// SFSpeechRecognizer sometimes inserts spaces within compound words
/// (e.g., "東京 都" → "東京都"). This stage uses a known compounds dictionary,
/// suffix rules, and prefix rules to rejoin them.
struct CompoundWordJoiner: TextCorrectionStage {
    let name = "CompoundWordJoiner"

    func apply(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = joinKnownCompounds(text)
        result = joinSuffixes(result)
        result = joinPrefixes(result)
        return result
    }

    // MARK: - Known compound words

    private static let compoundWords: [String] = [
        // Administrative regions
        "東京都", "大阪府", "京都府", "北海道",
        // Stations
        "東京駅", "新宿駅", "渋谷駅", "品川駅", "大阪駅", "名古屋駅",
        // Corporate forms
        "株式会社", "有限会社", "合同会社", "合資会社",
        // Titles
        "代表取締役", "取締役",
        // Departments
        "営業部", "開発部", "総務部", "人事部", "経理部", "企画部",
        "法務部", "広報部", "情報システム部",
        // Rooms
        "会議室", "応接室", "休憩室",
        // Financial
        "売上高", "経常利益", "営業利益", "純利益",
        "前年比", "前月比", "前期比", "前年同期比",
        "年度末", "四半期", "半期", "通期",
        // Common compound verbs / nouns
        "取り組み", "打ち合わせ", "引き続き",
        "問い合わせ", "申し込み", "切り替え",
        "受け入れ", "追い込み", "振り返り",
        "見積もり", "立ち上げ", "巻き込み",
        // Time expressions
        "今日中", "明日中", "今週中", "今月中",
        // Business
        "決算書", "貸借対照表", "損益計算書",
    ]

    /// Pre-computed split variants for efficient lookup.
    /// Each compound generates (compound.count - 1) split patterns.
    private static let splitPatterns: [(split: String, compound: String)] = {
        var patterns: [(String, String)] = []
        for compound in compoundWords {
            let chars = Array(compound)
            for splitAt in 1..<chars.count {
                let first = String(chars[0..<splitAt])
                let second = String(chars[splitAt...])
                patterns.append(("\(first) \(second)", compound))
            }
        }
        // Sort by split length descending so longer patterns match first
        return patterns.sorted { $0.0.count > $1.0.count }
    }()

    // MARK: - Suffix / prefix lists

    private static let suffixes: [String] = [
        // Geography
        "都", "府", "県", "市", "区", "町", "村",
        "駅", "線", "港", "空港",
        // Organization
        "部", "課", "室", "係", "局", "所",
        "会社", "法人", "機構",
        // Honorifics
        "さん", "様", "殿", "先生",
        // Positional
        "中", "内", "外", "間", "後", "前", "上", "下",
        // Derivational
        "的", "性", "化", "型", "式", "用",
    ]

    private static let prefixes: [String] = [
        "全", "各", "毎", "約", "新", "旧", "大", "小",
        "再", "未", "非", "不", "無", "超", "準",
        "前", "後", "上", "下", "副", "総",
    ]

    /// Regex pattern matching any CJK / kana character.
    private static let cjkClass = "[\\p{Han}\\p{Hiragana}\\p{Katakana}]"

    /// Pre-compiled suffix regexes to avoid recompilation on each call.
    private static let suffixRegexes: [NSRegularExpression] = {
        suffixes.compactMap { suffix in
            let escaped = NSRegularExpression.escapedPattern(for: suffix)
            return try? NSRegularExpression(
                pattern: "(\(cjkClass)) (\(escaped))"
            )
        }
    }()

    /// Pre-compiled prefix regexes to avoid recompilation on each call.
    private static let prefixRegexes: [NSRegularExpression] = {
        prefixes.compactMap { prefix in
            let escaped = NSRegularExpression.escapedPattern(for: prefix)
            return try? NSRegularExpression(
                pattern: "(\(escaped)) (\(cjkClass))"
            )
        }
    }()

    // MARK: - Joining logic

    private func joinKnownCompounds(_ text: String) -> String {
        var result = text
        for (split, compound) in Self.splitPatterns {
            result = result.replacingOccurrences(of: split, with: compound)
        }
        return result
    }

    private func joinSuffixes(_ text: String) -> String {
        var result = text
        for regex in Self.suffixRegexes {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: range, withTemplate: "$1$2"
            )
        }
        return result
    }

    private func joinPrefixes(_ text: String) -> String {
        var result = text
        for regex in Self.prefixRegexes {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: range, withTemplate: "$1$2"
            )
        }
        return result
    }
}
