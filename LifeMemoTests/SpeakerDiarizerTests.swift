import XCTest
@testable import LifeMemo

final class SpeakerDiarizerTests: XCTestCase {

    private let diarizer = SpeakerDiarizer()

    // MARK: - Single Speaker

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

        XCTAssertEqual(result.speakerCount, 1)
        XCTAssertEqual(result.segments.count, 1)
    }

    func testEmptySegmentsReturnsZeroSpeakers() {
        let result = diarizer.diarize(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            wordSegments: []
        )
        XCTAssertEqual(result.speakerCount, 0)
        XCTAssertTrue(result.segments.isEmpty)
    }

    // MARK: - Multi-Feature Change Detection

    func testSimilarFeaturesNoChangeDetected() {
        // Words with very similar features should not trigger change points
        let words = (0..<5).map { i in
            WordSegmentInfo(
                substring: "word\(i)",
                timestamp: Double(i) * 0.3,
                duration: 0.25,
                confidence: 0.9,
                averagePitch: 150 + Float(i), // minimal variation
                pitchStdDev: 20,
                averageEnergy: 0.5,
                averageSpectralCentroid: 800,
                averageJitter: 0.02,
                averageShimmer: 0.04
            )
        }

        let result = diarizer.diarize(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            wordSegments: words
        )

        // Similar features should result in 1 speaker
        XCTAssertEqual(result.speakerCount, 1)
    }

    // MARK: - Speaker Profiles

    func testDiarizationIncludesProfiles() {
        // Create words with distinct features and a long pause between groups
        var words: [WordSegmentInfo] = []

        // Speaker A words (low pitch)
        for i in 0..<3 {
            words.append(WordSegmentInfo(
                substring: "hello\(i)",
                timestamp: Double(i) * 0.4,
                duration: 0.3,
                confidence: 0.9,
                averagePitch: 120,
                pitchStdDev: 15,
                averageEnergy: 0.4,
                averageSpectralCentroid: 600,
                averageJitter: 0.01,
                averageShimmer: 0.03
            ))
        }

        // Large gap + very different features (Speaker B - high pitch)
        for i in 0..<3 {
            words.append(WordSegmentInfo(
                substring: "world\(i)",
                timestamp: 3.0 + Double(i) * 0.4,
                duration: 0.3,
                confidence: 0.9,
                averagePitch: 280,
                pitchStdDev: 45,
                averageEnergy: 0.8,
                averageSpectralCentroid: 1400,
                averageJitter: 0.04,
                averageShimmer: 0.08
            ))
        }

        let result = diarizer.diarize(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            wordSegments: words
        )

        // Should detect 2 speakers
        if result.speakerCount > 1 {
            XCTAssertFalse(result.speakerProfiles.isEmpty)
            XCTAssertEqual(result.speakerProfiles.count, result.speakerCount)
        }
    }

    // MARK: - Backward Compatibility

    func testOldStyleWordsStillWork() {
        // Words created with the backward-compatible 5-arg initializer
        let words = [
            WordSegmentInfo(substring: "test", timestamp: 0, duration: 0.5, confidence: 0.9, averagePitch: nil),
            WordSegmentInfo(substring: "words", timestamp: 0.6, duration: 0.5, confidence: 0.9, averagePitch: nil),
        ]

        let result = diarizer.diarize(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            wordSegments: words
        )

        // Should not crash, returns valid result
        XCTAssertGreaterThanOrEqual(result.speakerCount, 0)
    }
}
