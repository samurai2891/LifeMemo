import XCTest
@testable import LifeMemo

final class SummarizationAlgorithmTests: XCTestCase {

    func testAllCasesCount() {
        XCTAssertEqual(SummarizationAlgorithm.allCases.count, 3)
    }

    func testRawValues() {
        XCTAssertEqual(SummarizationAlgorithm.tfidf.rawValue, "tfidf")
        XCTAssertEqual(SummarizationAlgorithm.textRank.rawValue, "textrank")
        XCTAssertEqual(SummarizationAlgorithm.leadBased.rawValue, "lead")
    }

    func testDisplayNames() {
        XCTAssertEqual(SummarizationAlgorithm.tfidf.displayName, "TF-IDF")
        XCTAssertEqual(SummarizationAlgorithm.textRank.displayName, "TextRank")
        XCTAssertEqual(SummarizationAlgorithm.leadBased.displayName, String(localized: "Lead-Based"))
    }

    func testDescriptionsAreNotEmpty() {
        for algo in SummarizationAlgorithm.allCases {
            XCTAssertFalse(algo.description.isEmpty, "\(algo) should have a description")
        }
    }

    func testIdentifiable() {
        for algo in SummarizationAlgorithm.allCases {
            XCTAssertEqual(algo.id, algo.rawValue)
        }
    }

    func testCodableRoundTrip() throws {
        for algo in SummarizationAlgorithm.allCases {
            let data = try JSONEncoder().encode(algo)
            let decoded = try JSONDecoder().decode(SummarizationAlgorithm.self, from: data)
            XCTAssertEqual(decoded, algo)
        }
    }

    func testPreferenceDefaultAlgorithm() {
        // Default should be .tfidf
        UserDefaults.standard.removeObject(forKey: "lifememo.summarization.algorithm")
        XCTAssertEqual(SummarizationPreference.preferredAlgorithm, .tfidf)
    }

    func testPreferenceSetAndGet() {
        SummarizationPreference.preferredAlgorithm = .textRank
        XCTAssertEqual(SummarizationPreference.preferredAlgorithm, .textRank)

        SummarizationPreference.preferredAlgorithm = .leadBased
        XCTAssertEqual(SummarizationPreference.preferredAlgorithm, .leadBased)

        // Cleanup
        SummarizationPreference.preferredAlgorithm = .tfidf
    }

    func testAutoSummarizeDefault() {
        UserDefaults.standard.removeObject(forKey: "lifememo.summarization.auto")
        XCTAssertFalse(SummarizationPreference.autoSummarize)
    }

    func testAutoSummarizeToggle() {
        SummarizationPreference.autoSummarize = true
        XCTAssertTrue(SummarizationPreference.autoSummarize)

        SummarizationPreference.autoSummarize = false
        XCTAssertFalse(SummarizationPreference.autoSummarize)
    }
}
