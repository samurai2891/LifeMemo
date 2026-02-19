import XCTest
import AVFoundation
@testable import LifeMemo

final class AudioFeatureExtractorTests: XCTestCase {

    // MARK: - Empty Input Tests

    func testExtractFeaturesWithInvalidURL() {
        let url = URL(fileURLWithPath: "/nonexistent/audio.m4a")
        let results = AudioFeatureExtractor.extractFeatures(url: url, windows: [
            (startSec: 0, durationSec: 1.0)
        ])

        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results[0].meanPitch)
        XCTAssertNil(results[0].meanEnergy)
        XCTAssertNil(results[0].meanSpectralCentroid)
        XCTAssertNil(results[0].jitter)
        XCTAssertNil(results[0].shimmer)
    }

    func testExtractFeaturesWithEmptyWindows() {
        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        let results = AudioFeatureExtractor.extractFeatures(url: url, windows: [])
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - WindowFeatures Completeness

    func testWindowFeaturesHasAllFields() {
        let features = AudioFeatureExtractor.WindowFeatures(
            meanPitch: 150.0,
            pitchStdDev: 20.0,
            meanEnergy: 0.5,
            meanSpectralCentroid: 800.0,
            jitter: 0.02,
            shimmer: 0.04
        )

        XCTAssertEqual(features.meanPitch, 150.0)
        XCTAssertEqual(features.pitchStdDev, 20.0)
        XCTAssertEqual(features.meanEnergy, 0.5)
        XCTAssertEqual(features.meanSpectralCentroid, 800.0)
        XCTAssertEqual(features.jitter, 0.02)
        XCTAssertEqual(features.shimmer, 0.04)
    }

    func testWindowFeaturesAllNil() {
        let features = AudioFeatureExtractor.WindowFeatures(
            meanPitch: nil,
            pitchStdDev: nil,
            meanEnergy: nil,
            meanSpectralCentroid: nil,
            jitter: nil,
            shimmer: nil
        )

        XCTAssertNil(features.meanPitch)
        XCTAssertNil(features.pitchStdDev)
        XCTAssertNil(features.meanEnergy)
        XCTAssertNil(features.meanSpectralCentroid)
        XCTAssertNil(features.jitter)
        XCTAssertNil(features.shimmer)
    }

    // MARK: - Multiple Windows

    func testMultipleWindowsReturnParallelResults() {
        let url = URL(fileURLWithPath: "/nonexistent/audio.m4a")
        let windows: [(startSec: TimeInterval, durationSec: TimeInterval)] = [
            (startSec: 0, durationSec: 0.5),
            (startSec: 0.5, durationSec: 0.5),
            (startSec: 1.0, durationSec: 0.5),
        ]
        let results = AudioFeatureExtractor.extractFeatures(url: url, windows: windows)
        XCTAssertEqual(results.count, windows.count)
    }
}
