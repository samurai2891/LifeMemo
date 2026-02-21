import Accelerate
import Foundation

/// Stage 1: Noise reduction using high-pass filtering and spectral gating.
///
/// Removes low-frequency rumble (below cutoff) and attenuates samples
/// whose energy falls below the noise floor threshold. Designed for
/// far-field recording in meeting rooms with ambient noise.
struct NoiseReducer: AudioProcessingStage {
    nonisolated var name: String { "NoiseReducer" }

    /// Frequency below which audio is attenuated (Hz).
    let highPassCutoff: Float
    /// RMS threshold below which a frame is considered noise (linear scale).
    let noiseGateThreshold: Float
    /// Smoothing factor for the noise gate (0.0 = hard gate, 1.0 = no gate).
    let smoothingFactor: Float

    init(
        highPassCutoff: Float = 80,
        noiseGateThreshold: Float = 0.005,
        smoothingFactor: Float = 0.1
    ) {
        self.highPassCutoff = highPassCutoff
        self.noiseGateThreshold = noiseGateThreshold
        self.smoothingFactor = smoothingFactor
    }

    nonisolated func process(_ samples: [Float], sampleRate: Double) -> [Float] {
        guard !samples.isEmpty else { return samples }
        let filtered = applyHighPassFilter(samples, sampleRate: sampleRate)
        return applyNoiseGate(filtered)
    }

    // MARK: - High-pass filter

    /// Simple first-order IIR high-pass filter using the Accelerate framework.
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

    // MARK: - Noise gate

    /// Attenuate frames whose RMS energy is below the noise floor.
    nonisolated private func applyNoiseGate(_ samples: [Float]) -> [Float] {
        let frameSize = 256
        let frameCount = (samples.count + frameSize - 1) / frameSize
        var output = samples

        for frame in 0..<frameCount {
            let start = frame * frameSize
            let end = min(start + frameSize, samples.count)
            let length = end - start

            var rms: Float = 0
            samples[start..<end].withContiguousStorageIfAvailable { buffer in
                vDSP_rmsqv(buffer.baseAddress!, 1, &rms, vDSP_Length(length))
            }

            if rms < noiseGateThreshold {
                // Soft gate: multiply by ratio to avoid harsh cutoffs
                let gain = max(smoothingFactor * (rms / noiseGateThreshold), 0)
                for i in start..<end {
                    output[i] = output[i] * gain
                }
            }
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
