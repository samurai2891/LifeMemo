import Foundation
import Testing
@testable import LifeMemo

struct AudioPreprocessorTests {
    private func makeSUT(hangoverLimit: Int = 3) -> AudioPreprocessor {
        AudioPreprocessor(
            noiseReducer: NoiseReducer(),
            gainController: AutomaticGainController(),
            voiceDetector: VoiceActivityDetector(),
            levelMonitor: AudioLevelMonitor(),
            hangoverLimit: hangoverLimit
        )
    }

    @Test func emptyInputReturnsSilence() {
        let sut = makeSUT()
        let result = sut.process([], sampleRate: 16000)
        #expect(result.samples.isEmpty)
        #expect(result.level == .silence)
        #expect(!result.isSpeech)
    }

    @Test func silenceProducesNoSpeech() {
        let sut = makeSUT()
        let silence = [Float](repeating: 0, count: 1024)
        let result = sut.process(silence, sampleRate: 16000)
        #expect(!result.isSpeech)
    }

    @Test func outputSameLengthAsInput() {
        let sut = makeSUT()
        let samples = [Float](repeating: 0.1, count: 500)
        let result = sut.process(samples, sampleRate: 16000)
        #expect(result.samples.count == 500)
    }

    @Test func resetClearsHangover() {
        let sut = makeSUT(hangoverLimit: 5)

        // Process a speech-like signal to activate hangover
        let speechSignal = (0..<1024).map { i in
            Float(0.2) * sin(2 * .pi * 300 * Float(i) / 16000)
        }
        _ = sut.process(speechSignal, sampleRate: 16000)

        // Reset
        sut.reset()

        // Process silence — should not carry over hangover
        let silence = [Float](repeating: 0, count: 1024)
        let result = sut.process(silence, sampleRate: 16000)
        #expect(!result.isSpeech)
    }

    @Test func levelIsAlwaysProvided() {
        let sut = makeSUT()
        let samples = (0..<512).map { i in
            Float(0.15) * sin(2 * .pi * 440 * Float(i) / 16000)
        }
        let result = sut.process(samples, sampleRate: 16000)
        #expect(result.level.rms >= 0)
        #expect(result.level.peak >= 0)
    }

    @Test func hangoverKeepsSpeechAlive() {
        let sut = makeSUT(hangoverLimit: 3)

        // First: speech-like signal to set hangover counter
        let speech = (0..<1024).map { i in
            Float(0.3) * sin(2 * .pi * 250 * Float(i) / 16000)
        }
        let speechResult = sut.process(speech, sampleRate: 16000)

        // If speech was detected, hangover should keep next few frames as speech
        if speechResult.isSpeech {
            let quietFrame = [Float](repeating: 0.001, count: 512)
            let hangoverResult = sut.process(quietFrame, sampleRate: 16000)
            #expect(hangoverResult.isSpeech)
        }
    }

    // MARK: - New tests for far-field fix

    @Test func nonSpeechSamplesAreNotZeroed() {
        // Key fix: samples should NEVER be zeroed, even when isSpeech is false
        let sut = makeSUT()
        let quietSignal = (0..<1024).map { i in
            Float(0.001) * sin(2 * .pi * 440 * Float(i) / 16000)
        }
        let result = sut.process(quietSignal, sampleRate: 16000)

        // Even if VAD says non-speech, samples should not be zeroed
        let hasNonZero = result.samples.contains { $0 != 0 }
        #expect(hasNonZero)
    }

    @Test func farFieldSignalIsPreserved() {
        // Verify that a far-field signal (~0.003 RMS) survives the full pipeline
        let sut = makeSUT()
        let sampleRate: Double = 16000
        let farFieldSignal = (0..<1024).map { i in
            Float(0.003) * sin(2 * .pi * 300 * Float(i) / Float(sampleRate))
        }
        let result = sut.process(farFieldSignal, sampleRate: sampleRate)

        // Signal should survive — not zeroed, not destroyed
        let hasNonZero = result.samples.contains { abs($0) > 0.0001 }
        #expect(hasNonZero)

        // Level should reflect the (amplified) signal
        #expect(result.level.rms > 0)
    }
}
