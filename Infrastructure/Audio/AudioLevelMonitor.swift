import Accelerate
import Foundation

/// Calculates real-time audio levels from PCM sample buffers.
///
/// Provides RMS and peak values suitable for driving UI audio level meters.
/// Stateless — each call is independent.
struct AudioLevelMonitor: Sendable {
    nonisolated var name: String { "AudioLevelMonitor" }

    /// Calculate audio level from raw samples.
    /// - Parameters:
    ///   - samples: Float32 PCM samples
    ///   - isSpeech: Whether the VAD detected speech in this buffer
    /// - Returns: An `AudioLevel` with RMS and peak values normalized to 0.0–1.0.
    nonisolated func calculateLevel(
        from samples: [Float], isSpeech: Bool
    ) -> AudioLevel {
        guard !samples.isEmpty else { return .silence }

        // RMS via vDSP
        var rms: Float = 0
        samples.withContiguousStorageIfAvailable { buffer in
            vDSP_rmsqv(
                buffer.baseAddress!, 1, &rms, vDSP_Length(samples.count)
            )
        }

        // Peak via vDSP (absolute max)
        var peak: Float = 0
        samples.withContiguousStorageIfAvailable { buffer in
            vDSP_maxmgv(
                buffer.baseAddress!, 1, &peak, vDSP_Length(samples.count)
            )
        }

        // Clamp to 0–1 range (samples should already be in [-1, 1])
        let clampedRMS = min(rms, 1.0)
        let clampedPeak = min(peak, 1.0)

        return AudioLevel(
            rms: clampedRMS,
            peak: clampedPeak,
            isSpeech: isSpeech
        )
    }
}
