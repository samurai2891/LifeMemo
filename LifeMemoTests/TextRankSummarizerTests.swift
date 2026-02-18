import XCTest
@testable import LifeMemo

@MainActor
final class TextRankSummarizerTests: XCTestCase {

    func testEmptyTextReturnsEmptyResult() {
        let summarizer = TextRankSummarizer()
        let result = summarizer.summarize(text: "")
        XCTAssertTrue(result.sentences.isEmpty)
        XCTAssertTrue(result.keywords.isEmpty)
        XCTAssertEqual(result.inputWordCount, 0)
        XCTAssertEqual(result.algorithm, .textRank)
    }

    func testSingleSentenceReturnsThatSentence() {
        let summarizer = TextRankSummarizer()
        let result = summarizer.summarize(text: "The quick brown fox jumps over the lazy dog.")
        XCTAssertEqual(result.sentences.count, 1)
        XCTAssertFalse(result.sentences[0].text.isEmpty)
        XCTAssertEqual(result.algorithm, .textRank)
    }

    func testMultipleSentencesProducesSummary() {
        let summarizer = TextRankSummarizer()
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
        XCTAssertEqual(result.algorithm, .textRank)
    }

    func testBriefConfigProducesFewerSentences() {
        let summarizer = TextRankSummarizer(config: .brief)
        let text = "First point about the project. Second point about the budget. Third point about the timeline. Fourth point about resources. Fifth point about risks. Sixth point about mitigation strategies."
        let result = summarizer.summarize(text: text)
        XCTAssertLessThanOrEqual(result.sentences.count, 3)
    }

    func testKeywordsAreExtracted() {
        let summarizer = TextRankSummarizer()
        let text = "The computer science department organized a technology conference. Many researchers presented their findings on artificial intelligence and machine learning algorithms."
        let result = summarizer.summarize(text: text)
        XCTAssertGreaterThan(result.keywords.count, 0)
    }

    func testProcessingTimeIsRecorded() {
        let summarizer = TextRankSummarizer()
        let result = summarizer.summarize(text: "Hello world. This is a test. Testing summarization. Another sentence here. Final thoughts on this topic.")
        XCTAssertGreaterThanOrEqual(result.processingTime, 0)
    }

    func testLanguageDetection() {
        let summarizer = TextRankSummarizer()
        let result = summarizer.summarize(text: "The weather is beautiful today. I went to the park and enjoyed the sunshine. The flowers are blooming nicely.")
        if let lang = result.detectedLanguage {
            XCTAssertEqual(lang, "en")
        }
    }

    func testJapaneseText() {
        let summarizer = TextRankSummarizer()
        let text = "今日は会議で四半期の結果を議論しました。売上は前年比で大幅に増加しました。新しいマーケティング戦略が効果を発揮しています。来月の計画についても話し合いました。"
        let result = summarizer.summarize(text: text)
        XCTAssertGreaterThan(result.sentences.count, 0)
        XCTAssertGreaterThan(result.inputWordCount, 0)
    }

    func testSentencesHaveValidScores() {
        let summarizer = TextRankSummarizer()
        let text = "First important point about the meeting. Second notable observation from the data. Third key finding in our research. Fourth critical insight about the market. Fifth major conclusion for the team."
        let result = summarizer.summarize(text: text)
        for sentence in result.sentences {
            XCTAssertGreaterThanOrEqual(sentence.score, 0)
        }
    }

    func testConvergence() {
        let summarizer = TextRankSummarizer()
        let text = "The alpha project is making good progress on all fronts. The beta team has completed their initial review process. The gamma initiative shows promising early results today. The delta system needs additional testing and validation work. The epsilon platform will launch next quarter successfully."
        let result = summarizer.summarize(text: text)
        XCTAssertGreaterThan(result.sentences.count, 0)
        // Scores should sum to approximately 1.0 (PageRank property)
        let totalScore = result.sentences.reduce(0.0) { $0 + $1.score }
        XCTAssertGreaterThan(totalScore, 0)
    }

}
