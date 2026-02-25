import XCTest
@testable import LifeMemo

final class TranscriptionCompletenessEvaluatorTests: XCTestCase {

    func testEmptyFullTextDoesNotFallback() {
        let evaluation = TranscriptionCompletenessEvaluator.evaluate(
            fullText: "   ",
            wordSegments: [],
            diarizedSegments: [],
            chunkDurationSec: 60
        )

        XCTAssertFalse(evaluation.shouldFallbackToFullText)
        XCTAssertFalse(evaluation.isSuspectTruncation)
    }

    func testEmptyDiarizedTextFallsBack() {
        let evaluation = TranscriptionCompletenessEvaluator.evaluate(
            fullText: "This is a sufficiently long transcript sentence.",
            wordSegments: makeWordSegments(
                starts: [0, 1, 2, 3, 4],
                duration: 0.4
            ),
            diarizedSegments: [],
            chunkDurationSec: 60
        )

        XCTAssertTrue(evaluation.shouldFallbackToFullText)
        XCTAssertEqual(evaluation.reason, "diarized_text_empty")
    }

    func testMuchShorterDiarizedTextFallsBack() {
        let fullText = "This is the full text that should be preserved when diarization is too short."
        let diarizedSegments = [
            DiarizedSegment(
                id: UUID(),
                speakerIndex: 0,
                text: "too short",
                startOffsetMs: 56_000,
                endOffsetMs: 59_000
            )
        ]

        let evaluation = TranscriptionCompletenessEvaluator.evaluate(
            fullText: fullText,
            wordSegments: makeWordSegments(
                starts: [0, 2, 4, 6, 8, 10, 12, 14],
                duration: 0.5
            ),
            diarizedSegments: diarizedSegments,
            chunkDurationSec: 60
        )

        XCTAssertTrue(evaluation.shouldFallbackToFullText)
        XCTAssertEqual(evaluation.reason, "diarized_text_much_shorter_than_full_text")
    }

    func testTemporalCoverageTooSmallFallsBack() {
        let fullText = String(repeating: "a", count: 40)
        let diarizedText = String(repeating: "b", count: 35)
        let diarizedSegments = [
            DiarizedSegment(
                id: UUID(),
                speakerIndex: 0,
                text: diarizedText,
                startOffsetMs: 28_000,
                endOffsetMs: 30_000
            )
        ]

        let words = [
            makeWord(text: "a", start: 0, duration: 0.3),
            makeWord(text: "b", start: 6, duration: 0.3),
            makeWord(text: "c", start: 12, duration: 0.3),
            makeWord(text: "d", start: 18, duration: 0.3),
            makeWord(text: "e", start: 24, duration: 0.3),
            makeWord(text: "f", start: 30, duration: 0.3),
        ]

        let evaluation = TranscriptionCompletenessEvaluator.evaluate(
            fullText: fullText,
            wordSegments: words,
            diarizedSegments: diarizedSegments,
            chunkDurationSec: 30
        )

        XCTAssertTrue(evaluation.shouldFallbackToFullText)
        XCTAssertEqual(evaluation.reason, "diarized_time_coverage_too_small")
    }

    func testComparableOutputsDoNotFallback() {
        let fullText = "Hello there how are you today"
        let diarizedSegments = [
            DiarizedSegment(
                id: UUID(),
                speakerIndex: 0,
                text: "Hello there",
                startOffsetMs: 0,
                endOffsetMs: 4_000
            ),
            DiarizedSegment(
                id: UUID(),
                speakerIndex: 1,
                text: "how are you today",
                startOffsetMs: 4_000,
                endOffsetMs: 8_000
            ),
        ]

        let evaluation = TranscriptionCompletenessEvaluator.evaluate(
            fullText: fullText,
            wordSegments: makeWordSegments(
                starts: [0, 1, 2, 3, 4, 5, 6],
                duration: 0.4
            ),
            diarizedSegments: diarizedSegments,
            chunkDurationSec: 10
        )

        XCTAssertFalse(evaluation.shouldFallbackToFullText)
        XCTAssertFalse(evaluation.isSuspectTruncation)
    }

    private func makeWordSegments(starts: [Double], duration: Double) -> [WordSegmentInfo] {
        starts.enumerated().map { index, start in
            makeWord(text: "w\(index)", start: start, duration: duration)
        }
    }

    private func makeWord(text: String, start: Double, duration: Double) -> WordSegmentInfo {
        WordSegmentInfo(
            substring: text,
            timestamp: start,
            duration: duration,
            confidence: 0.9,
            averagePitch: nil
        )
    }
}
