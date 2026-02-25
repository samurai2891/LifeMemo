import Accelerate
import Foundation

/// Stage 1: High-pass filtering to remove low-frequency rumble.
///
/// Removes frequencies below the cutoff (e.g., HVAC hum, traffic rumble).
/// Apple's voice processing already handles noise suppression, so this stage
/// only applies a high-pass filter — no noise gate is needed.
struct NoiseReducer: AudioProcessingStage {
    nonisolated var name: String { "NoiseReducer" }

    /// Frequency below which audio is attenuated (Hz).
    let highPassCutoff: Float

    init(highPassCutoff: Float = 80) {
        self.highPassCutoff = highPassCutoff
    }

    nonisolated func process(_ samples: [Float], sampleRate: Double) -> [Float] {
        guard !samples.isEmpty else { return samples }
        return applyHighPassFilter(samples, sampleRate: sampleRate)
    }

    // MARK: - High-pass filter

    /// Simple first-order IIR high-pass filter.
    nonisolated private func applyHighPassFilter(
        _ samples: [Float], sampleRate: Double
    ) -> [Float] {
        guard samples.count > 1 else { return samples }
        let rc = 1.0 / (2.0 * Float.pi * highPassCutoff)
        let dt = 1.0 / Float(sampleRate)
        let alpha = rc / (rc + dt)

        var output = [Float](repeating: 0, count: samples.count)
        output[0] = samples[0]

        for i in 1..<samples.count {
            output[i] = alpha * (output[i - 1] + samples[i] - samples[i - 1])
        }
        return output
    }

    // MARK: - Utility

    /// Calculate RMS energy of an audio buffer.
    nonisolated func rmsEnergy(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var rms: Float = 0
        samples.withContiguousStorageIfAvailable { buffer in
            vDSP_rmsqv(buffer.baseAddress!, 1, &rms, vDSP_Length(samples.count))
        }
        return rms
    }
}
