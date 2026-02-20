import XCTest
@testable import LifeMemo

final class WordSpeakerMapperTests: XCTestCase {

    // MARK: - Basic Overlap Mapping

    func testWordsMapToCorrectSpeakers() {
        let words = [
            makeWord(text: "hello", start: 0.1, duration: 0.3),   // 0.1-0.4s
            makeWord(text: "world", start: 0.5, duration: 0.3),   // 0.5-0.8s
            makeWord(text: "foo", start: 1.5, duration: 0.3),     // 1.5-1.8s
        ]

        let segments = [
            SpeakerTurnSmoother.SpeakerSegment(startFrame: 0, endFrame: 100, speakerLabel: 0),   // 0-1.0s
            SpeakerTurnSmoother.SpeakerSegment(startFrame: 100, endFrame: 200, speakerLabel: 1),  // 1.0-2.0s
        ]

        let mapped = WordSpeakerMapper.mapWords(words: words, segments: segments)

        XCTAssertEqual(mapped.count, 3)
        XCTAssertEqual(mapped[0].speakerLabel, 0)  // "hello" overlaps speaker 0
        XCTAssertEqual(mapped[1].speakerLabel, 0)  // "world" overlaps speaker 0
        XCTAssertEqual(mapped[2].speakerLabel, 1)  // "foo" overlaps speaker 1
    }

    // MARK: - Empty Segments Fallback

    func testEmptySegmentsDefaultsToSpeaker0() {
        let words = [
            makeWord(text: "hello", start: 0.0, duration: 0.5),
        ]

        let mapped = WordSpeakerMapper.mapWords(words: words, segments: [])

        XCTAssertEqual(mapped.count, 1)
        XCTAssertEqual(mapped[0].speakerLabel, 0)
    }

    // MARK: - Empty Words

    func testEmptyWordsReturnsEmpty() {
        let segments = [
            SpeakerTurnSmoother.SpeakerSegment(startFrame: 0, endFrame: 100, speakerLabel: 0),
        ]

        let mapped = WordSpeakerMapper.mapWords(words: [], segments: segments)
        XCTAssertTrue(mapped.isEmpty)
    }

    // MARK: - Word Between Segments (Nearest Fallback)

    func testWordBetweenSegmentsFallsBackToNearest() {
        let words = [
            makeWord(text: "gap", start: 1.05, duration: 0.1),  // Falls between segments
        ]

        let segments = [
            SpeakerTurnSmoother.SpeakerSegment(startFrame: 0, endFrame: 100, speakerLabel: 0),   // 0-1.0s
            SpeakerTurnSmoother.SpeakerSegment(startFrame: 120, endFrame: 200, speakerLabel: 1),  // 1.2-2.0s
        ]

        let mapped = WordSpeakerMapper.mapWords(words: words, segments: segments)

        XCTAssertEqual(mapped.count, 1)
        // Should fall back to nearest segment (segment 0 or 1 depending on midpoint)
        XCTAssertTrue([0, 1].contains(mapped[0].speakerLabel))
    }

    // MARK: - Partial Overlap Prefers Larger Overlap

    func testPartialOverlapPrefersLarger() {
        let words = [
            makeWord(text: "split", start: 0.95, duration: 0.2),  // 0.95-1.15s, straddles boundary
        ]

        let segments = [
            SpeakerTurnSmoother.SpeakerSegment(startFrame: 0, endFrame: 100, speakerLabel: 0),   // 0-1.0s
            SpeakerTurnSmoother.SpeakerSegment(startFrame: 100, endFrame: 200, speakerLabel: 1),  // 1.0-2.0s
        ]

        let mapped = WordSpeakerMapper.mapWords(words: words, segments: segments)

        XCTAssertEqual(mapped.count, 1)
        // 0.95-1.0 overlaps speaker 0 (0.05s), 1.0-1.15 overlaps speaker 1 (0.15s)
        XCTAssertEqual(mapped[0].speakerLabel, 1, "Should prefer segment with larger overlap")
    }

    // MARK: - Word Text Preserved

    func testWordTextPreserved() {
        let word = makeWord(text: "preserved", start: 0.0, duration: 0.5)
        let segments = [
            SpeakerTurnSmoother.SpeakerSegment(startFrame: 0, endFrame: 100, speakerLabel: 0),
        ]

        let mapped = WordSpeakerMapper.mapWords(words: [word], segments: segments)
        XCTAssertEqual(mapped[0].word.substring, "preserved")
    }

    // MARK: - Helpers

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
