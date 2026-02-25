import Foundation
import Testing
@testable import LifeMemo

struct AutomaticGainControllerTests {
    private func makeSUT(
        targetRMS: Float = 0.08,
        maxGain: Float = 40.0,
        minGain: Float = 1.0,
        silenceThreshold: Float = 0.00001
    ) -> AutomaticGainController {
        AutomaticGainController(
            targetRMS: targetRMS,
            maxGain: maxGain,
            minGain: minGain,
            silenceThreshold: silenceThreshold
        )
    }

    @Test func emptyInputReturnsEmpty() {
        let sut = makeSUT()
        let result = sut.process([], sampleRate: 16000)
        #expect(result.isEmpty)
    }

    @Test func silenceRemainsUnchanged() {
        let sut = makeSUT()
        let silence = [Float](repeating: 0, count: 512)
        let result = sut.process(silence, sampleRate: 16000)
        #expect(result.allSatisfy { $0 == 0 })
    }

    @Test func quietSignalIsBoosted() {
        let sut = makeSUT(targetRMS: 0.1, maxGain: 10.0)
        let samples = (0..<1024).map { i in
            Float(0.005) * sin(2 * .pi * 440 * Float(i) / 16000)
        }
        let result = sut.process(samples, sampleRate: 16000)

        var inputRMS: Float = 0
        var outputRMS: Float = 0
        for s in samples { inputRMS += s * s }
        for s in result { outputRMS += s * s }
        inputRMS = sqrt(inputRMS / Float(samples.count))
        outputRMS = sqrt(outputRMS / Float(result.count))

        #expect(outputRMS > inputRMS)
    }

    @Test func outputIsClipped() {
        let sut = makeSUT(targetRMS: 0.5, maxGain: 100.0, minGain: 1.0)
        let samples = [Float](repeating: 0.8, count: 256)
        let result = sut.process(samples, sampleRate: 16000)
        #expect(result.allSatisfy { $0 >= -1.0 && $0 <= 1.0 })
    }

    @Test func outputSameLength() {
        let sut = makeSUT()
        let samples = [Float](repeating: 0.05, count: 1000)
        let result = sut.process(samples, sampleRate: 16000)
        #expect(result.count == samples.count)
    }

    @Test func gainDoesNotExceedMax() {
        let sut = makeSUT(targetRMS: 1.0, maxGain: 2.0, minGain: 1.0)
        let samples = [Float](repeating: 0.01, count: 512)
        let result = sut.process(samples, sampleRate: 16000)
        // Max gain = 2x, so max output should be ~0.02
        #expect(result.allSatisfy { abs($0) <= 0.021 })
    }

    @Test func farFieldSignalIsBoosted() {
        // Far-field signal (~0.003 RMS) should be boosted significantly with maxGain=40
        let sut = makeSUT(targetRMS: 0.08, maxGain: 40.0, silenceThreshold: 0.00001)
        let sampleRate: Float = 16000
        let samples = (0..<1024).map { i in
            Float(0.003) * sin(2 * .pi * 300 * Float(i) / sampleRate)
        }
        let result = sut.process(samples, sampleRate: Double(sampleRate))

        var outputRMS: Float = 0
        for s in result { outputRMS += s * s }
        outputRMS = sqrt(outputRMS / Float(result.count))

        // Should be boosted well above the original ~0.002 RMS
        #expect(outputRMS > 0.01)
    }
}
