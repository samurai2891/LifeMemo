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

final class OnDeviceTranscriberFinalSelectionTests: XCTestCase {

    func testConflictHeavyConsensusDoesNotOverridePrimary() {
        let primary = "今日は会議を開始します"
        let primarySegments = [
            makeWord(text: "今日は", start: 0.0),
            makeWord(text: "会議を", start: 0.4),
            makeWord(text: "開始します", start: 0.8),
        ]
        let consensus = "今日は 今日 会議を 景気 開始します"
        let consensusSegments = [
            makeWord(text: "今日は", start: 0.0),
            makeWord(text: "今日", start: 0.0),
            makeWord(text: "会議を", start: 0.4),
            makeWord(text: "景気", start: 0.4),
            makeWord(text: "開始します", start: 0.8),
        ]

        let resolved = OnDeviceTranscriber.resolveFinalResultForTesting(
            primaryText: primary,
            primaryWordSegments: primarySegments,
            consensusText: consensus,
            consensusWordSegments: consensusSegments,
            conflictWordRate: 0.40
        )

        XCTAssertEqual(resolved.source, .primaryFinal)
        XCTAssertEqual(resolved.text, primary)
        XCTAssertEqual(resolved.segments.map(\.substring), primarySegments.map(\.substring))
    }

    func testPrimaryEmptyUsesConsensusFallback() {
        let consensus = "議事録を作成します"
        let consensusSegments = [
            makeWord(text: "議事録を", start: 0.0),
            makeWord(text: "作成します", start: 0.5),
        ]

        let resolved = OnDeviceTranscriber.resolveFinalResultForTesting(
            primaryText: "",
            primaryWordSegments: [],
            consensusText: consensus,
            consensusWordSegments: consensusSegments,
            conflictWordRate: 0.0
        )

        XCTAssertEqual(resolved.source, .consensusFallback)
        XCTAssertEqual(resolved.text, consensus)
        XCTAssertEqual(resolved.segments.map(\.substring), consensusSegments.map(\.substring))
    }

    func testLowCoverageConsensusStillKeepsPrimaryWhenAlignmentIsInsufficient() {
        let primary = "本日の議題"
        let primarySegments = [
            makeWord(text: "本日の", start: 0.0),
            makeWord(text: "議題を", start: 0.4),
        ]
        let consensus = "本日の議題を確認します では進めます 次の項目です"
        let consensusSegments = [
            makeWord(text: "本日の", start: 0.0),
            makeWord(text: "議題を", start: 0.4),
            makeWord(text: "確認します", start: 0.8),
            makeWord(text: "では", start: 1.2),
            makeWord(text: "進めます", start: 1.5),
            makeWord(text: "次の", start: 1.9),
            makeWord(text: "項目です", start: 2.2),
        ]

        let resolved = OnDeviceTranscriber.resolveFinalResultForTesting(
            primaryText: primary,
            primaryWordSegments: primarySegments,
            consensusText: consensus,
            consensusWordSegments: consensusSegments,
            conflictWordRate: 0.0
        )

        XCTAssertEqual(resolved.source, .primaryFinal)
        XCTAssertEqual(resolved.text, primary)
    }

    private func makeWord(text: String, start: Double) -> WordSegmentInfo {
        WordSegmentInfo(
            substring: text,
            timestamp: start,
            duration: 0.3,
            confidence: 0.95,
            averagePitch: nil
        )
    }
}
