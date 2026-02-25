import Accelerate
import Foundation

/// Stage 3: Voice Activity Detection based on energy and zero-crossing rate.
///
/// Classifies audio frames as speech or non-speech. Used **advisory only** —
/// the result drives the UI speech indicator but does NOT gate the recognizer.
/// Uses a combination of RMS energy and zero-crossing rate (ZCR) for
/// robust detection even in noisy environments.
struct VoiceActivityDetector: AudioProcessingStage {
    nonisolated var name: String { "VoiceActivityDetector" }

    /// RMS energy threshold for speech detection (linear).
    /// Lowered to 0.002 for far-field sensitivity.
    let energyThreshold: Float
    /// Zero-crossing rate threshold (normalized 0.0–1.0).
    let zcrLowThreshold: Float
    /// Upper ZCR threshold — very high ZCR often indicates noise, not speech.
    let zcrHighThreshold: Float
    /// Frame size for analysis (samples per frame).
    let frameSize: Int

    init(
        energyThreshold: Float = 0.002,
        zcrLowThreshold: Float = 0.02,
        zcrHighThreshold: Float = 0.5,
        frameSize: Int = 512
    ) {
        self.energyThreshold = energyThreshold
        self.zcrLowThreshold = zcrLowThreshold
        self.zcrHighThreshold = zcrHighThreshold
        self.frameSize = frameSize
    }

    /// Pass-through — VAD is advisory only. Samples are never modified.
    /// Use `detectSpeech(_:sampleRate:)` to check for speech presence.
    nonisolated func process(_ samples: [Float], sampleRate: Double) -> [Float] {
        samples
    }

    /// Detect whether a buffer contains speech (advisory only).
    nonisolated func detectSpeech(_ samples: [Float], sampleRate: Double) -> Bool {
        guard !samples.isEmpty else { return false }
        return detectSpeechInFrame(samples)
    }

    // MARK: - Frame analysis

    nonisolated private func detectSpeechInFrame(_ frame: [Float]) -> Bool {
        let energy = rmsEnergy(of: frame)
        let zcr = zeroCrossingRate(of: frame)

        // Speech: sufficient energy AND ZCR within speech-like range
        let hasEnergy = energy > energyThreshold
        let hasTypicalZCR = zcr > zcrLowThreshold && zcr < zcrHighThreshold

        return hasEnergy && hasTypicalZCR
    }

    // MARK: - Metrics

    nonisolated private func rmsEnergy(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var rms: Float = 0
        samples.withContiguousStorageIfAvailable { buffer in
            vDSP_rmsqv(buffer.baseAddress!, 1, &rms, vDSP_Length(samples.count))
        }
        return rms
    }

    /// Normalized zero-crossing rate (0.0–1.0).
    nonisolated private func zeroCrossingRate(of samples: [Float]) -> Float {
        guard samples.count > 1 else { return 0 }
        var crossings: Int = 0
        for i in 1..<samples.count {
            if (samples[i] >= 0 && samples[i - 1] < 0)
                || (samples[i] < 0 && samples[i - 1] >= 0)
            {
                crossings += 1
            }
        }
        return Float(crossings) / Float(samples.count - 1)
    }
}
