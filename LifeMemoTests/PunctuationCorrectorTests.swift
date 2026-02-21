import Testing
@testable import LifeMemo

struct PunctuationCorrectorTests {
    let sut = PunctuationCorrector()

    // MARK: - Empty / no-op

    @Test func emptyStringReturnsEmpty() {
        #expect(sut.apply("") == "")
    }

    @Test func pureEnglishUnchanged() {
        let input = "Hello, world."
        #expect(sut.apply(input) == input)
    }

    // MARK: - Comma conversion

    @Test func asciiCommaBecomesJapaneseInJapaneseContext() {
        #expect(sut.apply("東京,大阪") == "東京、大阪")
    }

    @Test func asciiCommaInPureEnglishUnchanged() {
        #expect(sut.apply("a,b") == "a,b")
    }

    // MARK: - Period conversion

    @Test func asciiPeriodBecomesJapanesePeriod() {
        #expect(sut.apply("終了.次") == "終了。次")
    }

    @Test func decimalPointPreserved() {
        // 3.14 should not become 3。14
        #expect(sut.apply("3.14") == "3.14")
    }

    // MARK: - Question and exclamation marks

    @Test func asciiQuestionMarkBecomesFullWidth() {
        #expect(sut.apply("本当?") == "本当？")
    }

    @Test func asciiExclamationBecomesFullWidth() {
        #expect(sut.apply("すごい!") == "すごい！")
    }

    // MARK: - Space removal

    @Test func spaceBeforeJapanesePunctuationRemoved() {
        #expect(sut.apply("東京 。") == "東京。")
        #expect(sut.apply("東京 、大阪") == "東京、大阪")
    }

    @Test func spaceAfterOpeningBracketRemoved() {
        #expect(sut.apply("「 東京」") == "「東京」")
    }

    // MARK: - Deduplication

    @Test func repeatedPeriodsDeduped() {
        #expect(sut.apply("終了。。次") == "終了。次")
    }

    @Test func repeatedCommasDeduped() {
        #expect(sut.apply("東京、、大阪") == "東京、大阪")
    }

    @Test func repeatedQuestionMarksNotDeduped() {
        // Question marks can repeat for emphasis in Japanese
        #expect(sut.apply("本当？？") == "本当？？")
    }

    // MARK: - Combined scenarios

    @Test func mixedPunctuationInJapaneseText() {
        let input = "会議は,明日です.よろしく!"
        let expected = "会議は、明日です。よろしく！"
        #expect(sut.apply(input) == expected)
    }
}
