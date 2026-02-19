import Foundation
import AVFoundation
import Accelerate

/// Multi-feature audio analyzer replacing the pitch-only `AudioPitchAnalyzer`.
///
/// Extracts 6 acoustic features per time window using only the Accelerate framework:
/// 1. Pitch (F0) via autocorrelation
/// 2. Pitch standard deviation across frames
/// 3. RMS energy via `vDSP_rmsqv`
/// 4. Spectral centroid via FFT
/// 5. Jitter (pitch period perturbation)
/// 6. Shimmer (amplitude perturbation)
enum AudioFeatureExtractor {

    // MARK: - Types

    struct WindowFeatures {
        let meanPitch: Float?
        let pitchStdDev: Float?
        let meanEnergy: Float?
        let meanSpectralCentroid: Float?
        let jitter: Float?
        let shimmer: Float?
    }

    // MARK: - Configuration

    private static let minPitchHz: Float = 50
    private static let maxPitchHz: Float = 500
    private static let frameSize: Int = 1024         // ~23ms at 44.1kHz
    private static let frameHop: Int = 512

    // MARK: - Public API

    /// Extracts multi-dimensional features for each time window in an audio file.
    ///
    /// - Parameters:
    ///   - url: File URL of the audio.
    ///   - windows: Array of (startSec, durationSec) time ranges.
    /// - Returns: Array of `WindowFeatures`, parallel to `windows`.
    static func extractFeatures(
        url: URL,
        windows: [(startSec: TimeInterval, durationSec: TimeInterval)]
    ) -> [WindowFeatures] {
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            return Array(repeating: WindowFeatures(
                meanPitch: nil, pitchStdDev: nil, meanEnergy: nil,
                meanSpectralCentroid: nil, jitter: nil, shimmer: nil
            ), count: windows.count)
        }

        let sampleRate = Float(audioFile.processingFormat.sampleRate)

        return windows.map { window in
            let samples = readSamples(
                from: audioFile,
                startSec: window.startSec,
                durationSec: max(window.durationSec, 0.03)
            )
            guard samples.count >= frameSize else {
                return WindowFeatures(
                    meanPitch: nil, pitchStdDev: nil, meanEnergy: nil,
                    meanSpectralCentroid: nil, jitter: nil, shimmer: nil
                )
            }
            return analyzeWindow(samples: samples, sampleRate: sampleRate)
        }
    }

    // MARK: - Window Analysis

    private static func analyzeWindow(samples: [Float], sampleRate: Float) -> WindowFeatures {
        let frames = splitIntoFrames(samples: samples)
        guard !frames.isEmpty else {
            return WindowFeatures(
                meanPitch: nil, pitchStdDev: nil, meanEnergy: nil,
                meanSpectralCentroid: nil, jitter: nil, shimmer: nil
            )
        }

        // Per-frame analysis
        var pitches: [Float] = []
        var energies: [Float] = []
        var centroids: [Float] = []

        for frame in frames {
            if let pitch = detectPitch(in: frame, sampleRate: sampleRate) {
                pitches.append(pitch)
            }
            energies.append(computeRMSEnergy(frame))
            if let centroid = computeSpectralCentroid(frame, sampleRate: sampleRate) {
                centroids.append(centroid)
            }
        }

        let meanPitch: Float? = pitches.isEmpty ? nil : pitches.reduce(0, +) / Float(pitches.count)

        let pitchStdDev: Float? = {
            guard pitches.count > 1, let mean = meanPitch else { return nil }
            let variance = pitches.reduce(Float(0)) { acc, p in acc + (p - mean) * (p - mean) }
            return sqrt(variance / Float(pitches.count))
        }()

        let meanEnergy: Float? = energies.isEmpty ? nil : energies.reduce(0, +) / Float(energies.count)
        let meanCentroid: Float? = centroids.isEmpty ? nil : centroids.reduce(0, +) / Float(centroids.count)

        let jitter = computeJitter(pitches: pitches, sampleRate: sampleRate)
        let shimmer = computeShimmer(energies: energies)

        return WindowFeatures(
            meanPitch: meanPitch,
            pitchStdDev: pitchStdDev,
            meanEnergy: meanEnergy,
            meanSpectralCentroid: meanCentroid,
            jitter: jitter,
            shimmer: shimmer
        )
    }

    // MARK: - Frame Splitting

    private static func splitIntoFrames(samples: [Float]) -> [[Float]] {
        var frames: [[Float]] = []
        var offset = 0
        while offset + frameSize <= samples.count {
            let frame = Array(samples[offset..<(offset + frameSize)])
            frames.append(frame)
            offset += frameHop
        }
        return frames
    }

    // MARK: - Pitch Detection (Autocorrelation)

    private static func detectPitch(in samples: [Float], sampleRate: Float) -> Float? {
        let count = samples.count
        guard count > 64 else { return nil }

        var windowed = [Float](repeating: 0, count: count)
        var window = [Float](repeating: 0, count: count)
        vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_NORM))
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(count))

        var autocorrelation = [Float](repeating: 0, count: count)
        vDSP_conv(windowed, 1, windowed, 1, &autocorrelation, 1,
                  vDSP_Length(count), vDSP_Length(count))

        let minLag = Int(sampleRate / maxPitchHz)
        let maxLag = min(count - 1, Int(sampleRate / minPitchHz))
        guard minLag < maxLag, maxLag < count else { return nil }

        var bestLag = minLag
        var bestValue: Float = -Float.infinity

        for lag in minLag...maxLag {
            if autocorrelation[lag] > bestValue {
                bestValue = autocorrelation[lag]
                bestLag = lag
            }
        }

        guard bestValue > 0, bestLag > 0 else { return nil }
        let zeroLagValue = autocorrelation[0]
        guard zeroLagValue > 0 else { return nil }
        guard bestValue / zeroLagValue > 0.2 else { return nil }

        let pitch = sampleRate / Float(bestLag)
        guard pitch >= minPitchHz, pitch <= maxPitchHz else { return nil }
        return pitch
    }

    // MARK: - RMS Energy

    private static func computeRMSEnergy(_ samples: [Float]) -> Float {
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))

        // Convert to dB, clamped to [0, 1] normalized range
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        // Normalize: -60dB -> 0, 0dB -> 1
        return max(0, min(1, (db + 60) / 60))
    }

    // MARK: - Spectral Centroid

    private static func computeSpectralCentroid(_ samples: [Float], sampleRate: Float) -> Float? {
        let count = samples.count
        guard count >= 64 else { return nil }

        // Apply window
        var windowed = [Float](repeating: 0, count: count)
        var window = [Float](repeating: 0, count: count)
        vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_NORM))
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(count))

        // Compute magnitude spectrum via DFT
        let halfN = count / 2
        var realPart = [Float](repeating: 0, count: halfN)
        _ = [Float](repeating: 0, count: halfN)  // imagPart unused directly

        // Simple DFT for small windows (frameSize is fixed at 1024)
        // Use vDSP_DFT for efficiency
        guard let dftSetup = vDSP_DFT_zop_CreateSetup(
            nil, vDSP_Length(count), .FORWARD
        ) else { return nil }

        var inputReal = windowed
        var inputImag = [Float](repeating: 0, count: count)
        var outputReal = [Float](repeating: 0, count: count)
        var outputImag = [Float](repeating: 0, count: count)

        vDSP_DFT_Execute(dftSetup, &inputReal, &inputImag, &outputReal, &outputImag)
        vDSP_DFT_DestroySetup(dftSetup)

        // Compute magnitudes for the first half
        for i in 0..<halfN {
            let re = outputReal[i]
            let im = outputImag[i]
            realPart[i] = sqrt(re * re + im * im)
        }

        // Spectral centroid = Σ(f_i * |X_i|) / Σ(|X_i|)
        var sumWeighted: Float = 0
        var sumMagnitude: Float = 0
        let freqResolution = sampleRate / Float(count)

        for i in 0..<halfN {
            let freq = Float(i) * freqResolution
            sumWeighted += freq * realPart[i]
            sumMagnitude += realPart[i]
        }

        guard sumMagnitude > 0 else { return nil }
        return sumWeighted / sumMagnitude
    }

    // MARK: - Jitter

    /// Computes relative jitter: mean absolute pitch period difference / mean period.
    private static func computeJitter(pitches: [Float], sampleRate: Float) -> Float? {
        guard pitches.count > 1 else { return nil }

        let periods = pitches.map { sampleRate / $0 }
        let meanPeriod = periods.reduce(0, +) / Float(periods.count)
        guard meanPeriod > 0 else { return nil }

        var sumDiff: Float = 0
        for i in 1..<periods.count {
            sumDiff += abs(periods[i] - periods[i - 1])
        }
        let meanDiff = sumDiff / Float(periods.count - 1)

        return meanDiff / meanPeriod
    }

    // MARK: - Shimmer

    /// Computes relative shimmer: mean absolute energy difference / mean energy.
    private static func computeShimmer(energies: [Float]) -> Float? {
        guard energies.count > 1 else { return nil }

        let meanEnergy = energies.reduce(0, +) / Float(energies.count)
        guard meanEnergy > 0 else { return nil }

        var sumDiff: Float = 0
        for i in 1..<energies.count {
            sumDiff += abs(energies[i] - energies[i - 1])
        }
        let meanDiff = sumDiff / Float(energies.count - 1)

        return meanDiff / meanEnergy
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
}
