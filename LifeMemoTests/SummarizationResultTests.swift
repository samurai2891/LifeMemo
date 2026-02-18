import XCTest
@testable import LifeMemo

final class SummarizationResultTests: XCTestCase {

    func testEmptyResult() {
        let result = SummarizationResult(
            sentences: [],
            keywords: [],
            detectedLanguage: nil,
            processingTime: 0,
            inputWordCount: 0
        )
        XCTAssertTrue(result.topSentencesText.isEmpty)
        XCTAssertEqual(result.inputWordCount, 0)
    }

    func testTopSentencesTextPreservesOriginalOrder() {
        let s1 = SummarizationResult.RankedSentence(id: UUID(), text: "First.", score: 0.5, positionIndex: 0)
        let s2 = SummarizationResult.RankedSentence(id: UUID(), text: "Second.", score: 0.9, positionIndex: 1)
        let s3 = SummarizationResult.RankedSentence(id: UUID(), text: "Third.", score: 0.7, positionIndex: 2)

        // Even though s2 has highest score, topSentencesText should order by positionIndex
        let result = SummarizationResult(
            sentences: [s2, s3, s1], // score-ordered input
            keywords: ["test"],
            detectedLanguage: "en",
            processingTime: 0.1,
            inputWordCount: 10
        )

        XCTAssertEqual(result.topSentencesText, "First. Second. Third.")
    }

    func testEquatable() {
        let s1 = SummarizationResult.RankedSentence(id: UUID(), text: "A", score: 1.0, positionIndex: 0)
        let r1 = SummarizationResult(sentences: [s1], keywords: ["k"], detectedLanguage: "en", processingTime: 0.1, inputWordCount: 5)
        let r2 = SummarizationResult(sentences: [s1], keywords: ["k"], detectedLanguage: "en", processingTime: 0.1, inputWordCount: 5)
        XCTAssertEqual(r1, r2)
    }
}
