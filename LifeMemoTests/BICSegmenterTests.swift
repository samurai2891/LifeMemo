import XCTest
@testable import LifeMemo

final class BICSegmenterTests: XCTestCase {

    // MARK: - Homogeneous Signal (No Split Expected)

    func testHomogeneousSignalNoSplit() {
        // Frames from a single Gaussian (same speaker) should yield no boundaries
        let frames = generateGaussianFrames(
            numFrames: 300,
            mean: [Float](repeating: 0, count: 13),
            stdDev: 1.0,
            seed: 42
        )

        let region = EnergyVAD.SpeechRegion(startFrame: 0, endFrame: 300)
        let boundaries = BICSegmenter.segment(mfccFrames: frames, speechRegions: [region])

        // With homogeneous data, BIC should find no significant change point
        // (may find 0 or very few spurious ones)
        XCTAssertLessThanOrEqual(boundaries.count, 1,
            "Homogeneous signal should produce at most 1 spurious boundary")
    }

    // MARK: - Clear Change Point

    func testClearChangePointDetected() {
        // Two distinct Gaussians concatenated
        let framesA = generateGaussianFrames(
            numFrames: 200,
            mean: [Float](repeating: -3, count: 13),
            stdDev: 0.5,
            seed: 1
        )
        let framesB = generateGaussianFrames(
            numFrames: 200,
            mean: [Float](repeating: 3, count: 13),
            stdDev: 0.5,
            seed: 2
        )

        let frames = framesA + framesB
        let region = EnergyVAD.SpeechRegion(startFrame: 0, endFrame: frames.count)
        let boundaries = BICSegmenter.segment(mfccFrames: frames, speechRegions: [region])

        XCTAssertGreaterThanOrEqual(boundaries.count, 1,
            "Should detect at least one change point between distinct distributions")

        // The detected boundary should be near the actual change at frame 200
        if let firstBoundary = boundaries.first {
            XCTAssertGreaterThan(firstBoundary.frameIndex, 100,
                "Boundary should be after first segment start")
            XCTAssertLessThan(firstBoundary.frameIndex, 300,
                "Boundary should be before second segment end")
            XCTAssertGreaterThan(firstBoundary.bicDelta, 0,
                "ΔBIC should be positive at a true change point")
        }
    }

    // MARK: - Short Input

    func testShortInputNoCrash() {
        let frames = generateGaussianFrames(numFrames: 50, mean: [Float](repeating: 0, count: 13), stdDev: 1.0, seed: 3)
        let region = EnergyVAD.SpeechRegion(startFrame: 0, endFrame: 50)
        let boundaries = BICSegmenter.segment(mfccFrames: frames, speechRegions: [region])

        // Too short for minWindowFrames (100), so no boundaries
        XCTAssertTrue(boundaries.isEmpty)
    }

    // MARK: - Empty Input

    func testEmptyFramesNoCrash() {
        let boundaries = BICSegmenter.segment(mfccFrames: [], speechRegions: [])
        XCTAssertTrue(boundaries.isEmpty)
    }

    // MARK: - Multiple Speech Regions

    func testMultipleSpeechRegions() {
        let framesA = generateGaussianFrames(numFrames: 200, mean: [Float](repeating: -2, count: 13), stdDev: 0.5, seed: 10)
        let framesB = generateGaussianFrames(numFrames: 200, mean: [Float](repeating: 2, count: 13), stdDev: 0.5, seed: 11)
        let silence = [[Float]](repeating: [Float](repeating: 0, count: 13), count: 50)

        let allFrames = framesA + silence + framesB

        let regions = [
            EnergyVAD.SpeechRegion(startFrame: 0, endFrame: 200),
            EnergyVAD.SpeechRegion(startFrame: 250, endFrame: 450),
        ]

        let boundaries = BICSegmenter.segment(mfccFrames: allFrames, speechRegions: regions)
        // Should process each region independently, no crash
        XCTAssertNotNil(boundaries)
    }

    // MARK: - findBestSplit

    func testFindBestSplitReturnsZeroBICForHomogeneous() {
        let frames = generateGaussianFrames(numFrames: 200, mean: [Float](repeating: 0, count: 13), stdDev: 1.0, seed: 99)
        let (_, bic) = BICSegmenter.findBestSplit(frames: frames)
        XCTAssertEqual(bic, 0, accuracy: 0.01, "Homogeneous data should yield ΔBIC ≈ 0")
    }

    // MARK: - Helpers

    /// Generates pseudo-Gaussian frames using a simple deterministic approach.
    private func generateGaussianFrames(
        numFrames: Int,
        mean: [Float],
        stdDev: Float,
        seed: Int
    ) -> [[Float]] {
        let dim = mean.count
        var frames: [[Float]] = []
        frames.reserveCapacity(numFrames)

        // Simple deterministic pseudo-random using linear congruential generator
        var state = UInt64(seed &* 6364136223846793005 &+ 1442695040888963407)

        for _ in 0..<numFrames {
            var frame = [Float](repeating: 0, count: dim)
            for d in 0..<dim {
                // Box-Muller-like transform using LCG
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let u1 = Float(state >> 33) / Float(1 << 31)
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let u2 = Float(state >> 33) / Float(1 << 31)

                let u1Safe = max(u1, 1e-10)
                let z = sqrtf(-2 * logf(u1Safe)) * cosf(2 * .pi * u2)
                frame[d] = mean[d] + stdDev * z
            }
            frames.append(frame)
        }

        return frames
    }
}
