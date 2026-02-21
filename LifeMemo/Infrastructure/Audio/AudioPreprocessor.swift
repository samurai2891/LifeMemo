import Foundation

/// Result of preprocessing an audio buffer.
struct PreprocessedAudio: Sendable {
    let samples: [Float]
    let level: AudioLevel
    let isSpeech: Bool
}

/// Orchestrates the audio preprocessing chain: noise reduction → gain control → VAD.
///
/// Holds a hangover counter to avoid cutting off speech between short pauses.
/// Thread-safe for use from the audio render thread.
final class AudioPreprocessor: @unchecked Sendable {
    nonisolated var name: String { "AudioPreprocessor" }

    private let noiseReducer: NoiseReducer
    private let gainController: AutomaticGainController
    private let voiceDetector: VoiceActivityDetector
    private let levelMonitor: AudioLevelMonitor

    /// Number of consecutive non-speech frames before zeroing audio.
    private let hangoverLimit: Int
    private let lock = NSLock()
    private var hangoverCounter: Int = 0

    init(
        noiseReducer: NoiseReducer = NoiseReducer(),
        gainController: AutomaticGainController = AutomaticGainController(),
        voiceDetector: VoiceActivityDetector = VoiceActivityDetector(),
        levelMonitor: AudioLevelMonitor = AudioLevelMonitor(),
        hangoverLimit: Int = 15
    ) {
        self.noiseReducer = noiseReducer
        self.gainController = gainController
        self.voiceDetector = voiceDetector
        self.levelMonitor = levelMonitor
        self.hangoverLimit = hangoverLimit
    }

    /// Process a buffer of raw PCM samples through the full chain.
    ///
    /// Called from the audio render thread — must not block.
    nonisolated func process(
        _ samples: [Float], sampleRate: Double
    ) -> PreprocessedAudio {
        guard !samples.isEmpty else {
            return PreprocessedAudio(
                samples: [], level: .silence, isSpeech: false
            )
        }

        // 1. Noise reduction (high-pass + noise gate)
        let denoised = noiseReducer.process(samples, sampleRate: sampleRate)

        // 2. Automatic gain control
        let amplified = gainController.process(denoised, sampleRate: sampleRate)

        // 3. Voice activity detection
        let rawSpeech = voiceDetector.detectSpeech(
            amplified, sampleRate: sampleRate
        )
        let isSpeech = applyHangover(rawSpeech)

        // 4. If not speech (after hangover), zero out the buffer
        let finalSamples: [Float]
        if isSpeech {
            finalSamples = amplified
        } else {
            finalSamples = [Float](repeating: 0, count: amplified.count)
        }

        // 5. Calculate audio level for UI
        let level = levelMonitor.calculateLevel(
            from: amplified, isSpeech: isSpeech
        )

        return PreprocessedAudio(
            samples: finalSamples, level: level, isSpeech: isSpeech
        )
    }

    /// Reset hangover state (e.g., when starting a new recording).
    nonisolated func reset() {
        lock.lock()
        hangoverCounter = 0
        lock.unlock()
    }

    // MARK: - Hangover

    /// Keeps speech "alive" for a few frames after the VAD says non-speech,
    /// preventing words from being cut off during brief pauses.
    nonisolated private func applyHangover(_ isSpeechDetected: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if isSpeechDetected {
            hangoverCounter = hangoverLimit
            return true
        }

        if hangoverCounter > 0 {
            hangoverCounter -= 1
            return true
        }

        return false
    }
}
