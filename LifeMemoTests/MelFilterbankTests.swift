import XCTest
@testable import LifeMemo

final class MelFilterbankTests: XCTestCase {

    // MARK: - Mel/Hz Conversion

    func testHzToMelMonotonic() {
        let hz: [Float] = [0, 100, 500, 1000, 4000, 8000]
        let mels = hz.map { MelFilterbank.hzToMel($0) }

        for i in 1..<mels.count {
            XCTAssertGreaterThan(mels[i], mels[i - 1], "Mel should increase with Hz")
        }
    }

    func testMelToHzRoundTrip() {
        let original: Float = 1000
        let mel = MelFilterbank.hzToMel(original)
        let backToHz = MelFilterbank.melToHz(mel)
        XCTAssertEqual(backToHz, original, accuracy: 0.1)
    }

    func testHzToMelAtZero() {
        XCTAssertEqual(MelFilterbank.hzToMel(0), 0, accuracy: 0.01)
    }

    // MARK: - Filterbank Shape

    func testFilterbankDimensions() {
        let bank = MelFilterbank.createFilterbank(sampleRate: 16000)
        XCTAssertEqual(bank.count, MelFilterbank.numMelFilters)
        for filter in bank {
            XCTAssertEqual(filter.count, MelFilterbank.fftSize / 2 + 1)
        }
    }

    func testFilterbankNonNegative() {
        let bank = MelFilterbank.createFilterbank(sampleRate: 16000)
        for filter in bank {
            for value in filter {
                XCTAssertGreaterThanOrEqual(value, 0, "Filter values must be non-negative")
            }
        }
    }

    func testFilterbankPeakAtMostOne() {
        let bank = MelFilterbank.createFilterbank(sampleRate: 16000)
        for filter in bank {
            let maxVal = filter.max() ?? 0
            XCTAssertLessThanOrEqual(maxVal, 1.01, "Triangular filter peak should be ~1.0")
        }
    }

    // MARK: - MFCC Extraction

    func testMFCCExtractionFromSineWave() {
        // Generate a 440Hz sine wave at 16kHz, 1 second
        let sampleRate: Float = 16000
        let duration: Float = 1.0
        let numSamples = Int(sampleRate * duration)
        let frequency: Float = 440

        var samples = [Float](repeating: 0, count: numSamples)
        for i in 0..<numSamples {
            samples[i] = sinf(2 * .pi * frequency * Float(i) / sampleRate) * 0.5
        }

        let result = MelFilterbank.extractMFCCs(samples: samples, sampleRate: sampleRate)

        // Should produce frames
        let expectedFrames = (numSamples - MelFilterbank.frameLength) / MelFilterbank.frameHop + 1
        XCTAssertEqual(result.mfccs.count, expectedFrames)
        XCTAssertEqual(result.deltas.count, expectedFrames)
        XCTAssertEqual(result.deltaDeltas.count, expectedFrames)
        XCTAssertEqual(result.rmsEnergies.count, expectedFrames)
        XCTAssertEqual(result.frameTimestamps.count, expectedFrames)

        // Each MFCC frame should have 13 coefficients
        for mfcc in result.mfccs {
            XCTAssertEqual(mfcc.count, MelFilterbank.numMFCCs)
        }
    }

    func testMFCCExtractionTooShort() {
        // Fewer samples than frameLength
        let samples = [Float](repeating: 0, count: 100)
        let result = MelFilterbank.extractMFCCs(samples: samples, sampleRate: 16000)
        XCTAssertTrue(result.mfccs.isEmpty)
    }

    func testMFCCExtractionEmpty() {
        let result = MelFilterbank.extractMFCCs(samples: [], sampleRate: 16000)
        XCTAssertTrue(result.mfccs.isEmpty)
    }

    // MARK: - Delta Computation

    func testDeltaOutputDimensions() {
        let features: [[Float]] = (0..<10).map { _ in
            [Float](repeating: 1.0, count: 13)
        }
        let deltas = MelFilterbank.computeDeltas(features: features, width: 2)
        XCTAssertEqual(deltas.count, features.count)
        for delta in deltas {
            XCTAssertEqual(delta.count, 13)
        }
    }

    func testDeltaOfConstantIsZero() {
        // Constant features should yield zero deltas
        let features: [[Float]] = (0..<20).map { _ in
            [Float](repeating: 5.0, count: 13)
        }
        let deltas = MelFilterbank.computeDeltas(features: features, width: 2)
        for delta in deltas {
            for val in delta {
                XCTAssertEqual(val, 0, accuracy: 1e-5)
            }
        }
    }

    func testDeltaOfLinearRamp() {
        // Linearly increasing features should yield constant positive deltas
        let features: [[Float]] = (0..<20).map { i in
            [Float(i)]
        }
        let deltas = MelFilterbank.computeDeltas(features: features, width: 2)

        // Interior frames (not affected by boundary padding) should be ~1.0
        for t in 3..<17 {
            XCTAssertEqual(deltas[t][0], 1.0, accuracy: 0.01)
        }
    }

    // MARK: - Pre-Emphasis

    func testPreEmphasis() {
        let samples: [Float] = [1.0, 1.0, 1.0, 1.0]
        let result = MelFilterbank.applyPreEmphasis(samples: samples)
        XCTAssertEqual(result[0], 1.0, accuracy: 1e-5)
        XCTAssertEqual(result[1], 1.0 - 0.97, accuracy: 1e-5)
    }

    // MARK: - RMS Energy

    func testRMSEnergyPositive() {
        let sampleRate: Float = 16000
        let numSamples = Int(sampleRate * 0.5)
        let samples = (0..<numSamples).map { i in
            sinf(2 * .pi * 440 * Float(i) / sampleRate) * 0.3
        }

        let result = MelFilterbank.extractMFCCs(samples: samples, sampleRate: sampleRate)
        for energy in result.rmsEnergies {
            XCTAssertGreaterThan(energy, 0)
        }
    }
}
