import Foundation
import AVFAudio

/// Collects real audio metering data from AVAudioRecorder for waveform visualization.
///
/// Converts dB power levels to normalized 0.0-1.0 values and maintains a ring buffer
/// of recent levels for waveform display, including during background recording.
@MainActor
final class AudioMeterCollector: ObservableObject {

    // MARK: - Published State

    @Published private(set) var currentLevel: Float = 0
    @Published private(set) var recentLevels: [Float] = []

    // MARK: - Configuration

    private let maxSamples: Int
    private let minDb: Float = -60.0

    // MARK: - Ring Buffer

    private var buffer: [Float]
    private var writeIndex: Int = 0
    private var count: Int = 0

    // MARK: - Init

    init(maxSamples: Int = 3000) {
        self.maxSamples = maxSamples
        self.buffer = [Float](repeating: 0, count: maxSamples)
    }

    // MARK: - Public API

    /// Call this with the AVAudioRecorder's averagePower(forChannel: 0) value.
    /// Must be called from MainActor.
    func update(averagePower: Float, peakPower: Float) {
        let normalizedAvg = normalizeDb(averagePower)
        let normalizedPeak = normalizeDb(peakPower)

        // Blend average and peak for visually appealing display
        let blended = normalizedAvg * 0.7 + normalizedPeak * 0.3

        currentLevel = blended

        // Write to ring buffer
        buffer[writeIndex] = blended
        writeIndex = (writeIndex + 1) % maxSamples
        count = min(count + 1, maxSamples)

        // Update recent levels (last 30 for display)
        updateRecentLevels()
    }

    /// Resets the collector state.
    func reset() {
        currentLevel = 0
        buffer = [Float](repeating: 0, count: maxSamples)
        writeIndex = 0
        count = 0
        recentLevels = []
    }

    // MARK: - Private

    private func normalizeDb(_ db: Float) -> Float {
        // db ranges from about -160 (silence) to 0 (max).
        // We clamp to minDb..-0 and normalize to 0..1
        guard db > minDb else { return 0 }
        guard db < 0 else { return 1 }
        // Perceptual scaling: dB/50 gives visually responsive bars
        // (dB/20 was too compressed — normal speech barely moved the bars)
        return pow(10, db / 50)
    }

    private func updateRecentLevels() {
        let displayCount = 30
        guard count > 0 else {
            recentLevels = Array(repeating: 0, count: displayCount)
            return
        }

        let available = min(count, displayCount)
        var levels = [Float]()
        levels.reserveCapacity(displayCount)

        for i in (0..<available).reversed() {
            let idx = (writeIndex - 1 - i + maxSamples) % maxSamples
            levels.append(buffer[idx])
        }

        // Pad with zeros if we don't have enough
        while levels.count < displayCount {
            levels.insert(0, at: 0)
        }

        recentLevels = levels
    }
}
