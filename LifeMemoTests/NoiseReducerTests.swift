import Foundation
import Testing
@testable import LifeMemo

struct NoiseReducerTests {
    private func makeSUT(
        highPassCutoff: Float = 80
    ) -> NoiseReducer {
        NoiseReducer(highPassCutoff: highPassCutoff)
    }

    @Test func emptyInputReturnsEmpty() {
        let sut = makeSUT()
        let result = sut.process([], sampleRate: 16000)
        #expect(result.isEmpty)
    }

    @Test func singleSampleReturnsUnchanged() {
        let sut = makeSUT()
        let result = sut.process([0.5], sampleRate: 16000)
        #expect(result.count == 1)
    }

    @Test func loudSignalPassesThrough() {
        let sut = makeSUT()
        // Generate a sine wave at moderate amplitude above cutoff frequency
        let sampleCount = 1024
        let frequency: Float = 440
        let sampleRate: Float = 16000
        let samples = (0..<sampleCount).map { i in
            0.3 * sin(2 * .pi * frequency * Float(i) / sampleRate)
        }
        let result = sut.process(samples, sampleRate: Double(sampleRate))
        let outputEnergy = sut.rmsEnergy(of: result)
        // Signal above cutoff should retain significant energy
        #expect(outputEnergy > 0.05)
    }

    @Test func highPassRemovesLowFrequency() {
        let sut = makeSUT(highPassCutoff: 200)
        // Low frequency signal (50Hz) should be attenuated
        let sampleRate: Float = 16000
        let sampleCount = 4096
        let lowFreqSamples = (0..<sampleCount).map { i in
            0.3 * sin(2 * .pi * 50 * Float(i) / sampleRate)
        }
        let result = sut.process(lowFreqSamples, sampleRate: Double(sampleRate))
        let outputEnergy = sut.rmsEnergy(of: result)
        let inputEnergy = sut.rmsEnergy(of: lowFreqSamples)
        // Low-frequency energy should be reduced
        #expect(outputEnergy < inputEnergy * 0.8)
    }

    @Test func rmsEnergyOfSilenceIsZero() {
        let sut = makeSUT()
        let silence = [Float](repeating: 0, count: 256)
        #expect(sut.rmsEnergy(of: silence) == 0)
    }

    @Test func rmsEnergyOfEmptyIsZero() {
        let sut = makeSUT()
        #expect(sut.rmsEnergy(of: []) == 0)
    }

    @Test func outputSameLength() {
        let sut = makeSUT()
        let samples = [Float](repeating: 0.1, count: 1000)
        let result = sut.process(samples, sampleRate: 16000)
        #expect(result.count == samples.count)
    }

    @Test func quietSignalIsNotAttenuated() {
        // Without noise gate, quiet signals should pass through unchanged
        // (only high-pass filtering applies)
        let sut = makeSUT(highPassCutoff: 20) // Very low cutoff
        let sampleRate: Float = 16000
        let quietSignal = (0..<1024).map { i in
            Float(0.003) * sin(2 * .pi * 300 * Float(i) / sampleRate)
        }
        let result = sut.process(quietSignal, sampleRate: Double(sampleRate))
        let outputEnergy = sut.rmsEnergy(of: result)
        let inputEnergy = sut.rmsEnergy(of: quietSignal)
        // Without noise gate, quiet signal should retain most energy
        #expect(outputEnergy > inputEnergy * 0.8)
    }
}
