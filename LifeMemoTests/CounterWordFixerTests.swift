import Testing
@testable import LifeMemo

struct CounterWordFixerTests {
    let sut = CounterWordFixer()

    // MARK: - Empty / no-op

    @Test func emptyStringReturnsEmpty() {
        #expect(sut.apply("") == "")
    }

    // MARK: - People counters

    @Test func hiraganaPeopleCountersConverted() {
        #expect(sut.apply("ひとり") == "一人")
        #expect(sut.apply("ふたり") == "二人")
        #expect(sut.apply("さんにん") == "三人")
    }

    // MARK: - General counters

    @Test func hiraganaGeneralCountersConverted() {
        #expect(sut.apply("いっこ") == "一個")
        #expect(sut.apply("にこ") == "二個")
    }

    // MARK: - Sheet counters

    @Test func hiraganaSheetCountersConverted() {
        #expect(sut.apply("いちまい") == "一枚")
        #expect(sut.apply("さんまい") == "三枚")
    }

    // MARK: - Time counters

    @Test func hiraganaTimeCountersConverted() {
        #expect(sut.apply("いちじ") == "一時")
        #expect(sut.apply("ごじ") == "五時")
    }

    // MARK: - Month counters

    @Test func hiraganaMonthCountersConverted() {
        #expect(sut.apply("いちがつ") == "一月")
        #expect(sut.apply("じゅうにがつ") == "十二月")
    }

    // MARK: - Archaic numerals

    @Test func archaicNumeralsNormalized() {
        #expect(sut.apply("壱") == "一")
        #expect(sut.apply("弐") == "二")
        #expect(sut.apply("参") == "三")
        #expect(sut.apply("萬") == "万")
    }

    @Test func archaicNumeralsInContext() {
        #expect(sut.apply("金壱萬円") == "金一万円")
    }

    // MARK: - Mixed / no-op

    @Test func kanjiCountersUnchanged() {
        let input = "三人で会議"
        #expect(sut.apply(input) == input)
    }

    @Test func regularTextUnchanged() {
        let input = "今日の会議は順調です"
        #expect(sut.apply(input) == input)
    }

    // MARK: - In-context

    @Test func counterWordsFixedInSentence() {
        let input = "ひとりでさんまいの資料を確認した"
        let result = sut.apply(input)
        #expect(result.contains("一人"))
        #expect(result.contains("三枚"))
    }
}
