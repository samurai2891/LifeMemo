import XCTest
@testable import LifeMemo

final class WordSegmentInfoTests: XCTestCase {

    // MARK: - Backward-Compatible Initializer

    func testFiveArgInitializerSetsNilsForNewFields() {
        let word = WordSegmentInfo(
            substring: "Hello",
            timestamp: 1.0,
            duration: 0.5,
            confidence: 0.95,
            averagePitch: 150.0
        )

        XCTAssertEqual(word.substring, "Hello")
        XCTAssertEqual(word.timestamp, 1.0)
        XCTAssertEqual(word.duration, 0.5)
        XCTAssertEqual(word.confidence, 0.95)
        XCTAssertEqual(word.averagePitch, 150.0)
        XCTAssertNil(word.pitchStdDev)
        XCTAssertNil(word.averageEnergy)
        XCTAssertNil(word.averageSpectralCentroid)
        XCTAssertNil(word.averageJitter)
        XCTAssertNil(word.averageShimmer)
    }

    func testFiveArgInitializerWithNilPitch() {
        let word = WordSegmentInfo(
            substring: "Test",
            timestamp: 0.0,
            duration: 0.3,
            confidence: 0.8,
            averagePitch: nil
        )

        XCTAssertNil(word.averagePitch)
        XCTAssertNil(word.pitchStdDev)
    }

    // MARK: - Full Initializer

    func testTenFieldInitializer() {
        let word = WordSegmentInfo(
            substring: "World",
            timestamp: 2.0,
            duration: 0.4,
            confidence: 0.92,
            averagePitch: 180.0,
            pitchStdDev: 25.0,
            averageEnergy: 0.6,
            averageSpectralCentroid: 900.0,
            averageJitter: 0.015,
            averageShimmer: 0.035
        )

        XCTAssertEqual(word.substring, "World")
        XCTAssertEqual(word.timestamp, 2.0)
        XCTAssertEqual(word.duration, 0.4)
        XCTAssertEqual(word.confidence, 0.92)
        XCTAssertEqual(word.averagePitch, 180.0)
        XCTAssertEqual(word.pitchStdDev, 25.0)
        XCTAssertEqual(word.averageEnergy, 0.6)
        XCTAssertEqual(word.averageSpectralCentroid, 900.0)
        XCTAssertEqual(word.averageJitter, 0.015)
        XCTAssertEqual(word.averageShimmer, 0.035)
    }

    func testTenFieldInitializerWithSomeNils() {
        let word = WordSegmentInfo(
            substring: "Mixed",
            timestamp: 1.5,
            duration: 0.35,
            confidence: 0.88,
            averagePitch: 160.0,
            pitchStdDev: nil,
            averageEnergy: 0.5,
            averageSpectralCentroid: nil,
            averageJitter: 0.02,
            averageShimmer: nil
        )

        XCTAssertEqual(word.averagePitch, 160.0)
        XCTAssertNil(word.pitchStdDev)
        XCTAssertEqual(word.averageEnergy, 0.5)
        XCTAssertNil(word.averageSpectralCentroid)
        XCTAssertEqual(word.averageJitter, 0.02)
        XCTAssertNil(word.averageShimmer)
    }
}
