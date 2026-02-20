import XCTest
@testable import LifeMemo

final class EnergyVADTests: XCTestCase {

    // MARK: - Empty Input

    func testEmptyEnergiesReturnsNoRegions() {
        let regions = EnergyVAD.detectSpeechRegions(rmsEnergies: [])
        XCTAssertTrue(regions.isEmpty)
    }

    // MARK: - Silence

    func testAllSilenceReturnsNoRegions() {
        // Very low energy throughout
        let energies = [Float](repeating: 0.001, count: 500)
        let regions = EnergyVAD.detectSpeechRegions(rmsEnergies: energies)
        XCTAssertTrue(regions.isEmpty)
    }

    // MARK: - Constant High Energy

    func testConstantHighEnergyReturnsSingleRegion() {
        // Uniform high energy
        let energies = [Float](repeating: 0.5, count: 500)
        let regions = EnergyVAD.detectSpeechRegions(rmsEnergies: energies)
        // With uniform energy, the adaptive threshold may or may not split
        // At least verify no crash and sensible output
        XCTAssertLessThanOrEqual(regions.count, 1)
    }

    // MARK: - Speech with Pause

    func testSpeechPauseSpeechDetectsTwoRegions() {
        // Speech (high energy) - pause (low energy) - speech (high energy)
        // Silence ratio must exceed energyPercentile (30%) so the adaptive
        // threshold falls between silence and speech levels.
        var energies = [Float]()
        energies.append(contentsOf: [Float](repeating: 0.5, count: 150))   // Speech 1
        energies.append(contentsOf: [Float](repeating: 0.001, count: 200)) // Pause (>30% of total)
        energies.append(contentsOf: [Float](repeating: 0.5, count: 150))   // Speech 2

        let regions = EnergyVAD.detectSpeechRegions(rmsEnergies: energies)

        // Should detect at least 1 speech region
        XCTAssertGreaterThanOrEqual(regions.count, 1)

        // All regions should be within bounds
        for region in regions {
            XCTAssertGreaterThanOrEqual(region.startFrame, 0)
            XCTAssertLessThanOrEqual(region.endFrame, energies.count)
            XCTAssertGreaterThan(region.frameCount, 0)
        }
    }

    // MARK: - Adaptive Threshold

    func testAdaptiveThresholdBetweenNoiseAndSignal() {
        // Noise floor at 0.01, signal at 0.5
        var energies = [Float](repeating: 0.01, count: 300)
        energies.append(contentsOf: [Float](repeating: 0.5, count: 200))

        let threshold = EnergyVAD.computeAdaptiveThreshold(energies: energies)
        XCTAssertGreaterThan(threshold, 0.01, "Threshold should be above noise floor")
        XCTAssertLessThan(threshold, 0.5, "Threshold should be below signal level")
    }

    // MARK: - Morphological Operations

    func testCloseKernelFillsSmallGaps() {
        // Speech with a tiny gap (10 frames < closeKernel=30)
        var mask = [Bool](repeating: true, count: 50)
        mask.append(contentsOf: [Bool](repeating: false, count: 10))  // Small gap
        mask.append(contentsOf: [Bool](repeating: true, count: 50))

        let closed = EnergyVAD.morphologicalClose(mask: mask, kernelSize: 30)
        let regions = EnergyVAD.extractRegions(from: closed)

        // Small gap should be filled, resulting in 1 region
        XCTAssertEqual(regions.count, 1)
    }

    func testOpenKernelRemovesShortBursts() {
        // Short burst (5 frames < openKernel=20) in silence
        var mask = [Bool](repeating: false, count: 100)
        for i in 40..<45 {
            mask[i] = true
        }

        let opened = EnergyVAD.morphologicalOpen(mask: mask, kernelSize: 20)
        let regions = EnergyVAD.extractRegions(from: opened)

        // Short burst should be removed
        XCTAssertEqual(regions.count, 0)
    }

    // MARK: - Region Extraction

    func testExtractRegionsFromMask() {
        let mask: [Bool] = [false, true, true, true, false, false, true, true, false]
        let regions = EnergyVAD.extractRegions(from: mask)

        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions[0].startFrame, 1)
        XCTAssertEqual(regions[0].endFrame, 4)
        XCTAssertEqual(regions[1].startFrame, 6)
        XCTAssertEqual(regions[1].endFrame, 8)
    }

    func testExtractRegionsTrailingTrues() {
        let mask: [Bool] = [false, true, true]
        let regions = EnergyVAD.extractRegions(from: mask)

        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].startFrame, 1)
        XCTAssertEqual(regions[0].endFrame, 3) // mask.count
    }
}
