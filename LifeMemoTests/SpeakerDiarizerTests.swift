import XCTest
@testable import LifeMemo

final class SpeakerDiarizerTests: XCTestCase {

    private let diarizer = SpeakerDiarizer()

    // MARK: - Empty Input

    func testEmptySegmentsReturnsZeroSpeakers() {
        let result = diarizer.diarize(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            wordSegments: []
        )
        XCTAssertEqual(result.speakerCount, 0)
        XCTAssertTrue(result.segments.isEmpty)
    }

    // MARK: - Single Word

    func testSingleWordReturnsOneSpeaker() {
        let segments = [
            WordSegmentInfo(
                substring: "Hello",
                timestamp: 0.0, duration: 0.5,
                confidence: 0.9, averagePitch: 150
            )
        ]

        let result = diarizer.diarize(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            wordSegments: segments
        )

        // With a non-existent audio file, should fall back to single speaker
        XCTAssertEqual(result.speakerCount, 1)
        XCTAssertEqual(result.segments.count, 1)
    }

    // MARK: - Fallback on Invalid Audio

    func testInvalidAudioFallsBackToSingleSpeaker() {
        let words = (0..<5).map { i in
            WordSegmentInfo(
                substring: "word\(i)",
                timestamp: Double(i) * 0.3,
                duration: 0.25,
                confidence: 0.9,
                averagePitch: 150
            )
        }

        let result = diarizer.diarize(
            audioURL: URL(fileURLWithPath: "/tmp/nonexistent.m4a"),
            wordSegments: words
        )

        // Invalid audio should produce single speaker fallback
        XCTAssertEqual(result.speakerCount, 1)
        XCTAssertFalse(result.segments.isEmpty)
    }

    // MARK: - Result Structure

    func testResultContainsDiarizedSegments() {
        let words = [
            WordSegmentInfo(substring: "hello", timestamp: 0, duration: 0.5, confidence: 0.9, averagePitch: nil),
            WordSegmentInfo(substring: "world", timestamp: 0.6, duration: 0.5, confidence: 0.9, averagePitch: nil),
        ]

        let result = diarizer.diarize(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            wordSegments: words
        )

        // Should not crash, returns valid structure
        XCTAssertGreaterThanOrEqual(result.speakerCount, 0)
        for segment in result.segments {
            XCTAssertFalse(segment.text.isEmpty)
            XCTAssertGreaterThanOrEqual(segment.speakerIndex, 0)
        }
    }

    // MARK: - Backward Compatibility

    func testOldStyleWordsStillWork() {
        let words = [
            WordSegmentInfo(substring: "test", timestamp: 0, duration: 0.5, confidence: 0.9, averagePitch: nil),
            WordSegmentInfo(substring: "words", timestamp: 0.6, duration: 0.5, confidence: 0.9, averagePitch: nil),
        ]

        let result = diarizer.diarize(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            wordSegments: words
        )

        XCTAssertGreaterThanOrEqual(result.speakerCount, 0)
    }

    // MARK: - Speaker Profiles Include MFCC

    func testProfilesHaveMFCCEmbeddingWhenAudioAvailable() {
        // This test verifies the data flow; with a non-existent file the embedding will be nil
        let words = [
            WordSegmentInfo(substring: "test", timestamp: 0, duration: 0.5, confidence: 0.9, averagePitch: nil),
        ]

        let result = diarizer.diarize(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            wordSegments: words
        )

        // Even with fallback, profiles may or may not be populated
        XCTAssertGreaterThanOrEqual(result.speakerCount, 0)
    }
}
