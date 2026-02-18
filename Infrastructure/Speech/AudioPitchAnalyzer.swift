import Foundation
import AVFoundation
import Accelerate

/// Estimates fundamental frequency (pitch) from raw audio using autocorrelation.
///
/// Used as a fallback when `SFTranscriptionSegment.voiceAnalytics` is unavailable
/// (common with on-device recognition). Reads the audio file, applies a Hanning
/// window, computes autocorrelation via vDSP, and finds the first peak after the
/// zero crossing to derive F0 in Hz.
enum AudioPitchAnalyzer {

    // MARK: - Configuration

    private static let minPitchHz: Float = 50
    private static let maxPitchHz: Float = 500
    private static let analysisWindowSec: Double = 0.03  // 30ms window

    // MARK: - Public API

    /// Estimates the pitch (Hz) for a specific time range in an audio file.
    ///
    /// - Parameters:
    ///   - url: File URL of the audio.
    ///   - startSec: Start time in seconds.
    ///   - durationSec: Duration to analyse in seconds.
    /// - Returns: Estimated pitch in Hz, or `nil` if estimation fails.
    static func estimatePitch(
        url: URL,
        startSec: TimeInterval,
        durationSec: TimeInterval
    ) -> Float? {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }
        let sampleRate = Float(audioFile.processingFormat.sampleRate)
        let samples = readSamples(
            from: audioFile,
            startSec: startSec,
            durationSec: durationSec
        )
        guard !samples.isEmpty else { return nil }
        return detectPitch(in: samples, sampleRate: sampleRate)
    }

    /// Batch-estimates pitch for multiple time windows.
    ///
    /// - Parameters:
    ///   - url: File URL of the audio.
    ///   - windows: Array of (startSec, durationSec) tuples.
    /// - Returns: Array of optional pitch values, parallel to `windows`.
    static func estimatePitches(
        url: URL,
        windows: [(startSec: TimeInterval, durationSec: TimeInterval)]
    ) -> [Float?] {
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            return Array(repeating: nil, count: windows.count)
        }
        let sampleRate = Float(audioFile.processingFormat.sampleRate)

        return windows.map { window in
            let samples = readSamples(
                from: audioFile,
                startSec: window.startSec,
                durationSec: window.durationSec
            )
            guard !samples.isEmpty else { return nil }
            return detectPitch(in: samples, sampleRate: sampleRate)
        }
    }

    // MARK: - Audio Reading

    private static func readSamples(
        from audioFile: AVAudioFile,
        startSec: TimeInterval,
        durationSec: TimeInterval
    ) -> [Float] {
        let sampleRate = audioFile.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(startSec * sampleRate)
        let frameCount = AVAudioFrameCount(durationSec * sampleRate)

        guard startFrame >= 0,
              frameCount > 0,
              startFrame < audioFile.length else { return [] }

        let actualFrameCount = min(
            frameCount,
            AVAudioFrameCount(audioFile.length - startFrame)
        )
        guard actualFrameCount > 0 else { return [] }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: actualFrameCount
        ) else { return [] }

        audioFile.framePosition = startFrame

        do {
            try audioFile.read(into: buffer, frameCount: actualFrameCount)
        } catch {
            return []
        }

        guard let channelData = buffer.floatChannelData else { return [] }
        let count = Int(buffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData[0], count: count))
    }

    // MARK: - Pitch Detection (Autocorrelation)

    private static func detectPitch(in samples: [Float], sampleRate: Float) -> Float? {
        let count = samples.count
        guard count > 64 else { return nil }

        // Apply Hanning window
        var windowed = [Float](repeating: 0, count: count)
        var window = [Float](repeating: 0, count: count)
        vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_NORM))
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(count))

        // Autocorrelation via vDSP
        var autocorrelation = [Float](repeating: 0, count: count)
        vDSP_conv(windowed, 1, windowed, 1, &autocorrelation, 1,
                  vDSP_Length(count), vDSP_Length(count))

        // Find valid lag range based on pitch bounds
        let minLag = Int(sampleRate / maxPitchHz)
        let maxLag = min(count - 1, Int(sampleRate / minPitchHz))

        guard minLag < maxLag, maxLag < count else { return nil }

        // Find first peak after zero crossing in the valid lag range
        var bestLag = minLag
        var bestValue: Float = -Float.infinity

        for lag in minLag...maxLag {
            let value = autocorrelation[lag]
            if value > bestValue {
                bestValue = value
                bestLag = lag
            }
        }

        guard bestValue > 0, bestLag > 0 else { return nil }

        // Verify the peak is significant relative to the zero-lag autocorrelation
        let zeroLagValue = autocorrelation[0]
        guard zeroLagValue > 0 else { return nil }
        let ratio = bestValue / zeroLagValue
        guard ratio > 0.2 else { return nil }  // Weak correlation → unreliable

        let pitch = sampleRate / Float(bestLag)

        // Validate range
        guard pitch >= minPitchHz, pitch <= maxPitchHz else { return nil }
        return pitch
    }
}
