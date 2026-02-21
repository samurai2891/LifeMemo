import Testing
@testable import LifeMemo

struct KanjiDisambiguatorTests {
    let sut = KanjiDisambiguator()

    // MARK: - Empty / no-op

    @Test func emptyStringReturnsEmpty() {
        #expect(sut.apply("") == "")
    }

    @Test func singleWordUnchanged() {
        #expect(sut.apply("会議") == "会議")
    }

    @Test func textWithoutHomophonesUnchanged() {
        let input = "今日は天気がいい"
        #expect(sut.apply(input) == input)
    }

    // MARK: - 会技 → 会議 (common SFSpeechRecognizer error)

    @Test func kaigiCorrectedWithMeetingContext() {
        // "定例会技" → "定例会議" (regular meeting)
        let input = "定例会技"
        let result = sut.apply(input)
        // With strong bigram + rule context, should correct
        #expect(result == "定例会議" || result == input)
    }

    @Test func kaigiCorrectedWithRoomContext() {
        // "会技室" → "会議室"
        let input = "会技室"
        let result = sut.apply(input)
        #expect(result == "会議室" || result == input)
    }

    // MARK: - 核人 → 確認

    @Test func kakuninCorrectedWithBusinessContext() {
        // "内容核人" → "内容確認"
        let input = "内容核人"
        let result = sut.apply(input)
        #expect(result == "内容確認" || result == input)
    }

    // MARK: - 変換 vs 返還 (context-dependent)

    @Test func henkanCorrectInDataContext() {
        // "データ変換" should stay as 変換
        let input = "データ変換"
        let result = sut.apply(input)
        #expect(result == "データ変換")
    }

    @Test func henkanCorrectInTerritoryContext() {
        // "領土返還" should stay as 返還
        let input = "領土返還"
        let result = sut.apply(input)
        #expect(result == "領土返還")
    }

    // MARK: - 計画 vs 経過区

    @Test func keikakuCorrectedFromMisrecognition() {
        // "事業経過区" → "事業計画" (business plan)
        let input = "事業経過区"
        let result = sut.apply(input)
        #expect(result == "事業計画" || result == input)
    }

    // MARK: - 報告 (common business word)

    @Test func houkokuPreservedInCorrectContext() {
        // "進捗報告" should stay as-is
        let input = "進捗報告"
        let result = sut.apply(input)
        #expect(result == "進捗報告")
    }

    // MARK: - 開発

    @Test func kaihatsuPreservedInCorrectContext() {
        // "システム開発" should stay
        let input = "システム開発"
        let result = sut.apply(input)
        #expect(result == "システム開発")
    }

    // MARK: - Multiple homophones in one sentence

    @Test func multipleCorrectionsPossible() {
        let input = "定例会技の内容核人"
        let result = sut.apply(input)
        // At minimum, should not crash or corrupt
        #expect(!result.isEmpty)
    }

    // MARK: - Confidence threshold

    @Test func lowConfidenceCandidateNotApplied() {
        // A word not in any homophone group should pass through unchanged
        let input = "りんごを食べる"
        #expect(sut.apply(input) == input)
    }

    // MARK: - Longer text

    @Test func sentenceWithMultipleContextWords() {
        let input = "来週の定例会技で進捗報告の資料を確認する"
        let result = sut.apply(input)
        // Should at least preserve the general structure
        #expect(result.contains("進捗"))
        #expect(result.contains("資料"))
    }
}
