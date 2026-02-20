import XCTest
@testable import LifeMemo

final class SpeakerTurnSmootherTests: XCTestCase {

    // MARK: - Empty / Single

    func testEmptySegments() {
        let result = SpeakerTurnSmoother.smooth(segments: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testSingleSegmentUnchanged() {
        let seg = makeSeg(start: 0, end: 100, speaker: 0)
        let result = SpeakerTurnSmoother.smooth(segments: [seg])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], seg)
    }

    // MARK: - Minimum Duration Enforcement

    func testShortSegmentMergedIntoPrevious() {
        let segments = [
            makeSeg(start: 0, end: 100, speaker: 0),    // 1000ms (OK)
            makeSeg(start: 100, end: 120, speaker: 1),   // 200ms (too short)
            makeSeg(start: 120, end: 250, speaker: 0),   // 1300ms (OK)
        ]

        let result = SpeakerTurnSmoother.smooth(segments: segments, minDurationMs: 500)

        // Short segment should be absorbed
        XCTAssertLessThan(result.count, 3)
    }

    // MARK: - Collar Merge

    func testCollarMergesSameSpeakerWithSmallGap() {
        let segments = [
            makeSeg(start: 0, end: 100, speaker: 0),
            makeSeg(start: 120, end: 250, speaker: 0),  // gap = 20 frames = 200ms
        ]

        let result = SpeakerTurnSmoother.collarMerge(
            segments: segments,
            collarMs: 300,
            frameHopMs: 10
        )

        XCTAssertEqual(result.count, 1, "Same speaker with small gap should be merged")
        XCTAssertEqual(result[0].startFrame, 0)
        XCTAssertEqual(result[0].endFrame, 250)
    }

    func testCollarDoesNotMergeDifferentSpeakers() {
        let segments = [
            makeSeg(start: 0, end: 100, speaker: 0),
            makeSeg(start: 120, end: 250, speaker: 1),  // gap = 20 frames, different speaker
        ]

        let result = SpeakerTurnSmoother.collarMerge(
            segments: segments,
            collarMs: 300,
            frameHopMs: 10
        )

        XCTAssertEqual(result.count, 2, "Different speakers should not be merged")
    }

    // MARK: - Isolated Turn Removal

    func testIsolatedTurnRemovedWhenSurrounded() {
        let segments = [
            makeSeg(start: 0, end: 200, speaker: 0),    // 2000ms
            makeSeg(start: 200, end: 250, speaker: 1),   // 500ms (< 1000ms, isolated)
            makeSeg(start: 250, end: 500, speaker: 0),   // 2500ms
        ]

        let result = SpeakerTurnSmoother.removeIsolatedTurns(
            segments: segments,
            maxIsolatedMs: 1000,
            frameHopMs: 10
        )

        // Isolated turn should be absorbed into surrounding speaker 0
        XCTAssertLessThan(result.count, 3)
    }

    func testIsolatedTurnKeptWhenSurroundingDifferent() {
        let segments = [
            makeSeg(start: 0, end: 200, speaker: 0),
            makeSeg(start: 200, end: 250, speaker: 1),
            makeSeg(start: 250, end: 500, speaker: 2),   // Different from speaker 0
        ]

        let result = SpeakerTurnSmoother.removeIsolatedTurns(
            segments: segments,
            maxIsolatedMs: 1000,
            frameHopMs: 10
        )

        XCTAssertEqual(result.count, 3, "Isolated turn between different speakers should be kept")
    }

    // MARK: - Consecutive Same-Speaker Merge

    func testConsecutiveSameSpeakerMerged() {
        let segments = [
            makeSeg(start: 0, end: 100, speaker: 0),
            makeSeg(start: 100, end: 200, speaker: 0),
            makeSeg(start: 200, end: 300, speaker: 1),
        ]

        let result = SpeakerTurnSmoother.mergeConsecutive(segments: segments)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].startFrame, 0)
        XCTAssertEqual(result[0].endFrame, 200)
        XCTAssertEqual(result[0].speakerLabel, 0)
        XCTAssertEqual(result[1].speakerLabel, 1)
    }

    // MARK: - Full Pipeline

    func testFullSmoothPipeline() {
        let segments = [
            makeSeg(start: 0, end: 200, speaker: 0),     // Long
            makeSeg(start: 200, end: 220, speaker: 1),    // Short (200ms)
            makeSeg(start: 220, end: 500, speaker: 0),    // Long
        ]

        let result = SpeakerTurnSmoother.smooth(segments: segments)

        // The short segment should be smoothed away
        XCTAssertLessThanOrEqual(result.count, 2)
    }

    // MARK: - Helpers

    private func makeSeg(start: Int, end: Int, speaker: Int) -> SpeakerTurnSmoother.SpeakerSegment {
        SpeakerTurnSmoother.SpeakerSegment(
            startFrame: start,
            endFrame: end,
            speakerLabel: speaker
        )
    }
}
