import Foundation
import Testing
@testable import LifeMemo

struct VoiceActivityDetectorTests {
    private func makeSUT(
        energyThreshold: Float = 0.008,
        zcrLowThreshold: Float = 0.02,
        zcrHighThreshold: Float = 0.5
    ) -> VoiceActivityDetector {
        VoiceActivityDetector(
            energyThreshold: energyThreshold,
            zcrLowThreshold: zcrLowThreshold,
            zcrHighThreshold: zcrHighThreshold
        )
    }

    @Test func emptyInputReturnsEmpty() {
        let sut = makeSUT()
        let result = sut.process([], sampleRate: 16000)
        #expect(result.isEmpty)
    }

    @Test func silenceIsZeroed() {
        let sut = makeSUT(energyThreshold: 0.01)
        let silence = [Float](repeating: 0.0001, count: 512)
        let result = sut.process(silence, sampleRate: 16000)
        #expect(result.allSatisfy { $0 == 0 })
    }

    @Test func speechLikeSignalPassesThrough() {
        let sut = makeSUT(energyThreshold: 0.005, zcrLowThreshold: 0.01, zcrHighThreshold: 0.8)
        // Generate a moderate sine wave (speech-like energy + ZCR)
        let sampleRate: Float = 16000
        let samples = (0..<512).map { i in
            0.1 * sin(2 * .pi * 300 * Float(i) / sampleRate)
        }
        let result = sut.process(samples, sampleRate: Double(sampleRate))
        // At least some samples should be non-zero
        #expect(result.contains { $0 != 0 })
    }

    @Test func detectSpeechReturnsFalseForSilence() {
        let sut = makeSUT()
        let silence = [Float](repeating: 0, count: 256)
        #expect(!sut.detectSpeech(silence, sampleRate: 16000))
    }

    @Test func detectSpeechReturnsFalseForEmpty() {
        let sut = makeSUT()
        #expect(!sut.detectSpeech([], sampleRate: 16000))
    }

    @Test func detectSpeechReturnsTrueForLoudSignal() {
        let sut = makeSUT(energyThreshold: 0.005, zcrLowThreshold: 0.01, zcrHighThreshold: 0.8)
        let sampleRate: Float = 16000
        let samples = (0..<1024).map { i in
            0.2 * sin(2 * .pi * 250 * Float(i) / sampleRate)
        }
        #expect(sut.detectSpeech(samples, sampleRate: Double(sampleRate)))
    }

    @Test func outputSameLength() {
        let sut = makeSUT()
        let samples = [Float](repeating: 0.1, count: 1000)
        let result = sut.process(samples, sampleRate: 16000)
        #expect(result.count == samples.count)
    }

    @Test func pureNoiseIsFiltered() {
        // Very high ZCR (random noise) should be filtered as non-speech
        let sut = makeSUT(energyThreshold: 0.001, zcrHighThreshold: 0.3)
        // Alternating positive/negative = very high ZCR
        let noise = (0..<512).map { i in
            Float(i % 2 == 0 ? 0.05 : -0.05)
        }
        let detected = sut.detectSpeech(noise, sampleRate: 16000)
        // High ZCR should exceed zcrHighThreshold, filtering it
        #expect(!detected)
    }
}
