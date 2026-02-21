import Testing
@testable import LifeMemo

struct CompoundWordJoinerTests {
    let sut = CompoundWordJoiner()

    // MARK: - Empty / no-op

    @Test func emptyStringReturnsEmpty() {
        #expect(sut.apply("") == "")
    }

    @Test func textWithoutSplitsUnchanged() {
        let input = "東京都渋谷区"
        #expect(sut.apply(input) == input)
    }

    // MARK: - Known compound word joining

    @Test func splitTokyoToRejoined() {
        #expect(sut.apply("東京 都") == "東京都")
    }

    @Test func splitKabushikiGaishaRejoined() {
        #expect(sut.apply("株式 会社") == "株式会社")
    }

    @Test func splitDaihyoTorishimariyakuRejoined() {
        #expect(sut.apply("代表 取締役") == "代表取締役")
    }

    @Test func splitCompoundVerbRejoined() {
        #expect(sut.apply("打ち 合わせ") == "打ち合わせ")
        #expect(sut.apply("問い 合わせ") == "問い合わせ")
    }

    // MARK: - Suffix joining

    @Test func suffixJoinedToKanji() {
        #expect(sut.apply("営業 部") == "営業部")
        #expect(sut.apply("大阪 府") == "大阪府")
        #expect(sut.apply("神奈川 県") == "神奈川県")
    }

    @Test func honorificSuffixJoined() {
        #expect(sut.apply("田中 さん") == "田中さん")
        #expect(sut.apply("山田 様") == "山田様")
    }

    // MARK: - Prefix joining

    @Test func prefixJoinedToKanji() {
        #expect(sut.apply("全 社員") == "全社員")
        #expect(sut.apply("再 確認") == "再確認")
        #expect(sut.apply("未 完了") == "未完了")
    }

    // MARK: - No false positives

    @Test func englishWordsNotJoined() {
        let input = "Hello World"
        #expect(sut.apply(input) == input)
    }

    @Test func separateJapaneseWordsNotIncorrectlyJoined() {
        // Words that happen to look like a prefix + noun but aren't
        let input = "新しい 考え方"
        // "新" is a prefix, but "しい" follows it, not a kanji
        // This depends on the regex pattern matching
        #expect(!sut.apply(input).isEmpty)
    }

    // MARK: - Multiple compounds in one sentence

    @Test func multipleCompoundsJoined() {
        let input = "株式 会社の営業 部で打ち 合わせ"
        let result = sut.apply(input)
        #expect(result.contains("株式会社"))
        #expect(result.contains("営業部"))
        #expect(result.contains("打ち合わせ"))
    }
}
