import XCTest
@testable import LifeMemo

@MainActor
final class LeadSummarizerTests: XCTestCase {

    func testEmptyTextReturnsEmptyResult() {
        let summarizer = LeadSummarizer()
        let result = summarizer.summarize(text: "")
        XCTAssertTrue(result.sentences.isEmpty)
        XCTAssertTrue(result.keywords.isEmpty)
        XCTAssertEqual(result.inputWordCount, 0)
        XCTAssertEqual(result.algorithm, .leadBased)
    }

    func testSingleSentenceReturnsThatSentence() {
        let summarizer = LeadSummarizer()
        let result = summarizer.summarize(text: "The quick brown fox jumps over the lazy dog.")
        XCTAssertEqual(result.sentences.count, 1)
        XCTAssertFalse(result.sentences[0].text.isEmpty)
        XCTAssertEqual(result.algorithm, .leadBased)
    }

    func testMultipleSentencesProducesSummary() {
        let summarizer = LeadSummarizer()
        let text = """
        The quarterly report shows strong growth in all departments. Revenue increased by twenty percent compared to last year. \
        The marketing team launched a successful digital campaign. Customer satisfaction reached an all-time high this quarter. \
        The engineering team delivered three major product updates. Employee retention improved significantly with new benefits. \
        International expansion plans are proceeding on schedule. The board approved the new strategic initiative unanimously.
        """
        let result = summarizer.summarize(text: text)
        XCTAssertGreaterThan(result.sentences.count, 0)
        XCTAssertLessThanOrEqual(result.sentences.count, 5)
        XCTAssertGreaterThan(result.inputWordCount, 50)
        XCTAssertEqual(result.algorithm, .leadBased)
    }

    func testLeadBiasSelectsEarlySentences() {
        let summarizer = LeadSummarizer(config: .brief) // 3 sentences max
        let text = "First important point about the project. Second key observation from the data. Third notable finding in research. Fourth insight about the market today. Fifth conclusion for the entire team. Sixth recommendation for future work. Seventh final thought about everything."
        let result = summarizer.summarize(text: text)

        // Lead-based should strongly prefer early sentences
        let maxPosition = result.sentences.map(\.positionIndex).max() ?? 0
        XCTAssertLessThanOrEqual(maxPosition, 4, "Lead-based should prefer early sentences")
    }

    func testFirstSentenceHasHighestScore() {
        let summarizer = LeadSummarizer()
        let text = "First point about the quarterly project results. Second point about the annual budget planning. Third point about the implementation timeline schedule. Fourth point about resource allocation needs. Fifth point about identified risk factors."
        let result = summarizer.summarize(text: text)

        guard let firstSentence = result.sentences.first(where: { $0.positionIndex == 0 }) else {
            XCTFail("First sentence should be in results")
            return
        }

        for sentence in result.sentences where sentence.positionIndex != 0 {
            XCTAssertGreaterThanOrEqual(
                firstSentence.score, sentence.score,
                "First sentence should have highest or equal score in lead-based"
            )
        }
    }

    func testBriefConfigProducesFewerSentences() {
        let summarizer = LeadSummarizer(config: .brief)
        let text = "First point about the project. Second point about the budget. Third point about the timeline. Fourth point about resources. Fifth point about risks. Sixth point about mitigation strategies."
        let result = summarizer.summarize(text: text)
        XCTAssertLessThanOrEqual(result.sentences.count, 3)
    }

    func testKeywordsAreExtracted() {
        let summarizer = LeadSummarizer()
        let text = "The computer science department organized a technology conference. Many researchers presented their findings on artificial intelligence and machine learning algorithms."
        let result = summarizer.summarize(text: text)
        XCTAssertGreaterThan(result.keywords.count, 0)
    }

    func testProcessingTimeIsRecorded() {
        let summarizer = LeadSummarizer()
        let result = summarizer.summarize(text: "Hello world. This is a test. Testing summarization. Another sentence here. Final thoughts on topic.")
        XCTAssertGreaterThanOrEqual(result.processingTime, 0)
    }

    func testJapaneseText() {
        let summarizer = LeadSummarizer()
        let text = "今日は会議で四半期の結果を議論しました。売上は前年比で大幅に増加しました。新しいマーケティング戦略が効果を発揮しています。来月の計画についても話し合いました。"
        let result = summarizer.summarize(text: text)
        XCTAssertGreaterThan(result.sentences.count, 0)
        XCTAssertGreaterThan(result.inputWordCount, 0)
    }

    func testSentencesHaveValidScores() {
        let summarizer = LeadSummarizer()
        let text = "First important point from the meeting today. Second notable observation from data analysis. Third key finding in our ongoing research. Fourth critical insight about market trends. Fifth major conclusion for the whole team."
        let result = summarizer.summarize(text: text)
        for sentence in result.sentences {
            XCTAssertGreaterThanOrEqual(sentence.score, 0)
        }
    }

}
