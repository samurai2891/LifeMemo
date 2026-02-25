import Accelerate
import Foundation

/// Stage 2: Automatic Gain Control for boosting distant speakers.
///
/// Normalizes audio volume to a target RMS level so that speakers
/// far from the microphone produce adequate UI level meter readings.
/// Uses per-buffer RMS calculation with gain limiting to prevent clipping.
struct AutomaticGainController: AudioProcessingStage {
    nonisolated var name: String { "AutomaticGainController" }

    /// Target RMS level (linear scale, 0.0–1.0).
    let targetRMS: Float
    /// Maximum allowable gain multiplier (40x for far-field sensitivity).
    let maxGain: Float
    /// Minimum gain (prevents over-attenuation of already-quiet signals).
    let minGain: Float
    /// RMS below this threshold is treated as silence (no gain applied).
    let silenceThreshold: Float

    init(
        targetRMS: Float = 0.08,
        maxGain: Float = 40.0,
        minGain: Float = 1.0,
        silenceThreshold: Float = 0.00001
    ) {
        self.targetRMS = targetRMS
        self.maxGain = maxGain
        self.minGain = minGain
        self.silenceThreshold = silenceThreshold
    }

    nonisolated func process(_ samples: [Float], sampleRate: Double) -> [Float] {
        guard !samples.isEmpty else { return samples }

        // Calculate overall RMS
        var overallRMS: Float = 0
        samples.withContiguousStorageIfAvailable { buffer in
            vDSP_rmsqv(buffer.baseAddress!, 1, &overallRMS, vDSP_Length(samples.count))
        }

        // Skip if signal is essentially silence
        guard overallRMS > silenceThreshold else { return samples }

        // Calculate gain needed to reach target
        let desiredGain = targetRMS / overallRMS
        let clampedGain = min(max(desiredGain, minGain), maxGain)

        // Apply gain using vDSP
        var gain = clampedGain
        var output = [Float](repeating: 0, count: samples.count)
        samples.withContiguousStorageIfAvailable { inBuffer in
            output.withUnsafeMutableBufferPointer { outBuffer in
                vDSP_vsmul(
                    inBuffer.baseAddress!, 1,
                    &gain,
                    outBuffer.baseAddress!, 1,
                    vDSP_Length(samples.count)
                )
            }
        }

        // Clip to prevent distortion
        return clipSamples(output)
    }

    // MARK: - Clipping

    /// Hard-clip samples to [-1.0, 1.0] range.
    nonisolated private func clipSamples(_ samples: [Float]) -> [Float] {
        var lower: Float = -1.0
        var upper: Float = 1.0
        var output = [Float](repeating: 0, count: samples.count)
        samples.withContiguousStorageIfAvailable { inBuffer in
            output.withUnsafeMutableBufferPointer { outBuffer in
                vDSP_vclip(
                    inBuffer.baseAddress!, 1,
                    &lower, &upper,
                    outBuffer.baseAddress!, 1,
                    vDSP_Length(samples.count)
                )
            }
        }
        return output
    }
}
