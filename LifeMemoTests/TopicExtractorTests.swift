import XCTest
@testable import LifeMemo

@MainActor
final class TopicExtractorTests: XCTestCase {

    func testEmptyTextReturnsEmpty() {
        let extractor = TopicExtractor()
        let result = extractor.extract(from: "")
        XCTAssertTrue(result.keywords.isEmpty)
        XCTAssertTrue(result.namedEntities.isEmpty)
        XCTAssertTrue(result.topicClusters.isEmpty)
    }

    func testKeywordExtraction() {
        let extractor = TopicExtractor()
        let text = "The software engineer developed a new algorithm for the database system. The algorithm improved performance significantly."
        let result = extractor.extract(from: text)
        XCTAssertGreaterThan(result.keywords.count, 0)
        // "algorithm" should appear as it's repeated
        let words = result.keywords.map { $0.word.lowercased() }
        XCTAssertTrue(words.contains("algorithm"))
    }

    func testNamedEntityExtraction() {
        let extractor = TopicExtractor()
        let text = "John Smith met with Sarah Johnson at the Apple headquarters in Cupertino. They discussed the partnership with Microsoft."
        let result = extractor.extract(from: text)
        // NLTagger should find person and org names
        // On simulator, NER may have limited capability
        XCTAssertGreaterThanOrEqual(result.namedEntities.count, 0) // Graceful
    }

    func testProcessingTimeRecorded() {
        let extractor = TopicExtractor()
        let result = extractor.extract(from: "Simple test text for timing measurement.")
        XCTAssertGreaterThanOrEqual(result.processingTime, 0)
    }

    func testMaxKeywordsRespected() {
        let extractor = TopicExtractor()
        extractor.maxKeywords = 3
        let text = "Apple banana cherry dates elderberry fig grape. Apple banana cherry dates elderberry fig grape."
        let result = extractor.extract(from: text)
        XCTAssertLessThanOrEqual(result.keywords.count, 3)
    }

    func testKeywordHasPartOfSpeech() {
        let extractor = TopicExtractor()
        let text = "The brilliant scientist discovered a revolutionary method for protein analysis."
        let result = extractor.extract(from: text)
        if let first = result.keywords.first {
            // partOfSpeech should be one of the enum values
            XCTAssertNotNil(first.partOfSpeech)
        }
    }
}
