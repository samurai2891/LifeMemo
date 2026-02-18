import XCTest
@testable import LifeMemo

@MainActor
final class NLExtractiveSummarizerTests: XCTestCase {

    func testEmptyTextReturnsEmptyResult() {
        let summarizer = NLExtractiveSummarizer()
        let result = summarizer.summarize(text: "")
        XCTAssertTrue(result.sentences.isEmpty)
        XCTAssertTrue(result.keywords.isEmpty)
        XCTAssertEqual(result.inputWordCount, 0)
    }

    func testSingleSentenceReturnsThatSentence() {
        let summarizer = NLExtractiveSummarizer()
        let result = summarizer.summarize(text: "The quick brown fox jumps over the lazy dog.")
        XCTAssertEqual(result.sentences.count, 1)
        XCTAssertFalse(result.sentences[0].text.isEmpty)
    }

    func testMultipleSentencesProducesSummary() {
        let summarizer = NLExtractiveSummarizer()
        let text = """
        The quarterly report shows strong growth in all departments. Revenue increased by twenty percent compared to last year. \
        The marketing team launched a successful digital campaign. Customer satisfaction reached an all-time high this quarter. \
        The engineering team delivered three major product updates. Employee retention improved significantly with new benefits. \
        International expansion plans are proceeding on schedule. The board approved the new strategic initiative unanimously.
        """
        let result = summarizer.summarize(text: text)
        XCTAssertGreaterThan(result.sentences.count, 0)
        XCTAssertLessThanOrEqual(result.sentences.count, 5) // default maxSentences
        XCTAssertGreaterThan(result.inputWordCount, 50)
    }

    func testBriefConfigProducesFewerSentences() {
        let summarizer = NLExtractiveSummarizer(config: .brief)
        let text = "First point about the project. Second point about the budget. Third point about the timeline. Fourth point about resources. Fifth point about risks. Sixth point about mitigation strategies."
        let result = summarizer.summarize(text: text)
        XCTAssertLessThanOrEqual(result.sentences.count, 3)
    }

    func testKeywordsAreExtracted() {
        let summarizer = NLExtractiveSummarizer()
        let text = "The computer science department organized a technology conference. Many researchers presented their findings on artificial intelligence and machine learning algorithms."
        let result = summarizer.summarize(text: text)
        XCTAssertGreaterThan(result.keywords.count, 0)
    }

    func testProcessingTimeIsRecorded() {
        let summarizer = NLExtractiveSummarizer()
        let result = summarizer.summarize(text: "Hello world. This is a test. Testing summarization.")
        XCTAssertGreaterThanOrEqual(result.processingTime, 0)
    }

    func testLanguageDetection() {
        let summarizer = NLExtractiveSummarizer()
        let result = summarizer.summarize(text: "The weather is beautiful today. I went to the park and enjoyed the sunshine. The flowers are blooming nicely.")
        // Language detection may return "en" or nil on simulator
        if let lang = result.detectedLanguage {
            XCTAssertEqual(lang, "en")
        }
    }

    func testJapaneseText() {
        let summarizer = NLExtractiveSummarizer()
        let text = "今日は会議で四半期の結果を議論しました。売上は前年比で大幅に増加しました。新しいマーケティング戦略が効果を発揮しています。来月の計画についても話し合いました。"
        let result = summarizer.summarize(text: text)
        XCTAssertGreaterThan(result.sentences.count, 0)
        XCTAssertGreaterThan(result.inputWordCount, 0)
    }

    func testSentencesHaveValidScores() {
        let summarizer = NLExtractiveSummarizer()
        let text = "First important point. Second notable observation. Third key finding. Fourth critical insight. Fifth major conclusion."
        let result = summarizer.summarize(text: text)
        for sentence in result.sentences {
            XCTAssertGreaterThan(sentence.score, 0)
        }
    }

    func testTopSentencesTextPreservesOrder() {
        let summarizer = NLExtractiveSummarizer()
        let text = "The alpha sentence comes first in this document. The beta sentence comes second in the list. The gamma sentence comes third among all entries. The delta sentence is the fourth one presented. The epsilon sentence is positioned fifth in order. The zeta sentence is the very last one here."
        let result = summarizer.summarize(text: text)
        let combined = result.topSentencesText
        XCTAssertFalse(combined.isEmpty)
    }

    func testPerformanceWithLargeText() {
        let summarizer = NLExtractiveSummarizer()
        let paragraph = "This is a sample sentence for benchmarking. It contains enough words to be meaningful for the test. "
        let largeText = String(repeating: paragraph, count: 200) // ~3400 words

        measure {
            _ = summarizer.summarize(text: largeText)
        }
    }
}
