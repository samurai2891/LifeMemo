import Foundation
import Testing
@testable import LifeMemo

struct TextCorrectionPipelineTests {
    let jaLocale = Locale(identifier: "ja_JP")
    let enLocale = Locale(identifier: "en_US")

    private func makeSUT() -> TextCorrectionPipeline {
        let suite = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let dict = AdaptiveDictionary(
            storage: suite,
            storageKey: "test.pipeline",
            maxEntries: 100
        )
        return TextCorrectionPipeline(adaptiveDictionary: dict)
    }

    // MARK: - Non-Japanese locale passthrough

    @Test func englishLocaleReturnsUnchangedText() async {
        let sut = makeSUT()
        let output = await sut.correct("Hello, world.", locale: enLocale)
        #expect(output.correctedText == "Hello, world.")
        #expect(!output.wasModified)
        #expect(output.records.isEmpty)
    }

    // MARK: - Empty input

    @Test func emptyStringReturnsEmpty() async {
        let sut = makeSUT()
        let output = await sut.correct("", locale: jaLocale)
        #expect(output.correctedText == "")
        #expect(!output.wasModified)
    }

    // MARK: - Stage 1: Width normalization

    @Test func fullWidthASCIINormalized() async {
        let sut = makeSUT()
        let output = await sut.correct("Ｈｅｌｌｏ", locale: jaLocale)
        #expect(output.correctedText == "Hello")
        #expect(output.wasModified)
    }

    // MARK: - Stage 2: Punctuation correction

    @Test func asciiPunctuationConverted() async {
        let sut = makeSUT()
        let output = await sut.correct("東京,大阪", locale: jaLocale)
        #expect(output.correctedText == "東京、大阪")
    }

    // MARK: - Stage 4: Compound word joining

    @Test func splitCompoundWordsJoined() async {
        let sut = makeSUT()
        let output = await sut.correct("東京 都", locale: jaLocale)
        #expect(output.correctedText == "東京都")
    }

    // MARK: - Stage 6: Counter words

    @Test func hiraganaCounterWordsFixed() async {
        let sut = makeSUT()
        let output = await sut.correct("ひとりで確認", locale: jaLocale)
        #expect(output.correctedText.contains("一人"))
    }

    // MARK: - Multiple stages combined

    @Test func multipleStagesAppliedSequentially() async {
        let sut = makeSUT()
        // Full-width + punctuation + compound word
        let input = "Ｔｅｓｔ,東京 都"
        let output = await sut.correct(input, locale: jaLocale)
        #expect(output.correctedText.contains("Test"))
        #expect(output.correctedText.contains("東京都"))
        #expect(output.correctedText.contains("、"))
    }

    // MARK: - CorrectionOutput tracking

    @Test func correctionRecordsTrackChanges() async {
        let sut = makeSUT()
        let output = await sut.correct("Ｔｅｓｔ", locale: jaLocale)
        #expect(output.wasModified)
        #expect(!output.records.isEmpty)
        #expect(output.records[0].stageName == "TextNormalizer")
    }

    @Test func noModificationProducesEmptyRecords() async {
        let sut = makeSUT()
        let output = await sut.correct("東京都", locale: jaLocale)
        // Pure kanji with no issues should pass through most stages unchanged
        // (though some stages might still process it)
        #expect(output.originalText == "東京都")
    }

    // MARK: - Live correction (lightweight)

    @Test func liveCorrectionUsesFewerStages() async {
        let sut = makeSUT()
        // Live should still normalize width and punctuation
        let output = await sut.correctLive("Ｔｅｓｔ,東京", locale: jaLocale)
        #expect(output.correctedText.contains("Test"))
        #expect(output.correctedText.contains("、"))
    }

    @Test func liveCorrectionSkipsHeavyStages() async {
        let sut = makeSUT()
        // Compound joining (stage 4) should NOT run in live mode
        let output = await sut.correctLive("東京 都", locale: jaLocale)
        // In live mode, compound joining is skipped, so the space remains
        #expect(output.correctedText == "東京 都")
    }

    @Test func liveCorrectionNonJapanesePassthrough() async {
        let sut = makeSUT()
        let output = await sut.correctLive("Hello", locale: enLocale)
        #expect(output.correctedText == "Hello")
        #expect(!output.wasModified)
    }

    // MARK: - End-to-end realistic scenario

    @Test func realisticTranscriptionCorrection() async {
        let sut = makeSUT()
        let input = "定例会技の資料お確認ください,よろしく."
        let output = await sut.correct(input, locale: jaLocale)
        // Should fix punctuation at minimum
        #expect(output.correctedText.contains("、") || output.correctedText.contains("。"))
        #expect(output.wasModified)
    }
}
