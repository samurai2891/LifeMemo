import XCTest
@testable import LifeMemo

@MainActor
final class AudioMeterCollectorTests: XCTestCase {

    func testInitialState() {
        let collector = AudioMeterCollector()
        XCTAssertEqual(collector.currentLevel, 0)
        XCTAssertTrue(collector.recentLevels.isEmpty)
    }

    func testUpdateNormalizesValues() {
        let collector = AudioMeterCollector()
        collector.update(averagePower: 0, peakPower: 0) // 0 dB = maximum
        XCTAssertGreaterThan(collector.currentLevel, 0.9) // Should be near 1.0
    }

    func testSilenceProducesLowLevel() {
        let collector = AudioMeterCollector()
        collector.update(averagePower: -160, peakPower: -160) // Silence
        XCTAssertLessThan(collector.currentLevel, 0.01)
    }

    func testResetClearsState() {
        let collector = AudioMeterCollector()
        collector.update(averagePower: -10, peakPower: -5)
        collector.update(averagePower: -20, peakPower: -15)

        collector.reset()

        XCTAssertEqual(collector.currentLevel, 0)
        XCTAssertTrue(collector.recentLevels.isEmpty)
    }

    func testRecentLevelsPaddedToDisplayCount() {
        let collector = AudioMeterCollector()
        for _ in 0..<5 {
            collector.update(averagePower: -20, peakPower: -10)
        }
        // recentLevels is always padded to 30 for display
        XCTAssertEqual(collector.recentLevels.count, 30)
    }

    func testNormalSpeechProducesVisibleLevel() {
        let collector = AudioMeterCollector()
        collector.update(averagePower: -20, peakPower: -15)
        // Normal speech should produce bars at roughly 40-50% height
        XCTAssertGreaterThan(collector.currentLevel, 0.3)
    }

    func testQuietSpeechStillVisible() {
        let collector = AudioMeterCollector()
        collector.update(averagePower: -40, peakPower: -35)
        // Quiet speech should still be clearly visible
        XCTAssertGreaterThan(collector.currentLevel, 0.1)
    }
}
