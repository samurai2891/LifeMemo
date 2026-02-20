import Foundation

/// Energy-based Voice Activity Detection with morphological smoothing.
///
/// Detects speech regions from per-frame RMS energy values using an adaptive
/// threshold (percentile-based), then applies morphological close (fill gaps)
/// and open (remove short bursts) operations to produce clean speech regions.
enum EnergyVAD {

    /// A contiguous speech region defined by frame indices.
    struct SpeechRegion: Equatable {
        let startFrame: Int
        let endFrame: Int

        var frameCount: Int { endFrame - startFrame }
    }

    // MARK: - Configuration

    /// Morphological close kernel: fills gaps up to 300ms (30 frames at 10ms hop).
    static let closeKernelFrames = 30

    /// Morphological open kernel: removes speech bursts shorter than 200ms (20 frames).
    static let openKernelFrames = 20

    /// Percentile of energy distribution used as adaptive threshold.
    static let energyPercentile: Float = 0.3

    // MARK: - Public API

    /// Detects speech regions from per-frame RMS energy values.
    ///
    /// - Parameter rmsEnergies: Per-frame RMS energy values (one per MFCC frame).
    /// - Returns: Sorted, non-overlapping speech regions.
    static func detectSpeechRegions(rmsEnergies: [Float]) -> [SpeechRegion] {
        guard !rmsEnergies.isEmpty else { return [] }

        // Step 1: Compute adaptive threshold
        let threshold = computeAdaptiveThreshold(energies: rmsEnergies)

        // Step 2: Binary speech mask
        var mask = rmsEnergies.map { $0 > threshold }

        // Step 3: Morphological close (fill short gaps)
        mask = morphologicalClose(mask: mask, kernelSize: closeKernelFrames)

        // Step 4: Morphological open (remove short bursts)
        mask = morphologicalOpen(mask: mask, kernelSize: openKernelFrames)

        // Step 5: Extract contiguous regions
        return extractRegions(from: mask)
    }

    // MARK: - Internal

    static func computeAdaptiveThreshold(energies: [Float]) -> Float {
        let sorted = energies.sorted()
        guard !sorted.isEmpty else { return 0 }

        let percentileIndex = min(
            Int(Float(sorted.count) * energyPercentile),
            sorted.count - 1
        )
        let noiseFloor = sorted[percentileIndex]

        // Threshold = noise floor + 40% of (max - noise floor)
        let maxEnergy = sorted.last ?? 0
        return noiseFloor + 0.4 * (maxEnergy - noiseFloor)
    }

    static func morphologicalClose(mask: [Bool], kernelSize: Int) -> [Bool] {
        // Close = dilate then erode (fills gaps smaller than kernelSize)
        let dilated = dilate(mask: mask, kernelSize: kernelSize)
        return erode(mask: dilated, kernelSize: kernelSize)
    }

    static func morphologicalOpen(mask: [Bool], kernelSize: Int) -> [Bool] {
        // Open = erode then dilate (removes regions smaller than kernelSize)
        let eroded = erode(mask: mask, kernelSize: kernelSize)
        return dilate(mask: eroded, kernelSize: kernelSize)
    }

    private static func dilate(mask: [Bool], kernelSize: Int) -> [Bool] {
        guard !mask.isEmpty else { return mask }
        var result = mask
        let halfKernel = kernelSize / 2

        for i in 0..<mask.count where mask[i] {
            let start = max(0, i - halfKernel)
            let end = min(mask.count - 1, i + halfKernel)
            for j in start...end {
                result[j] = true
            }
        }
        return result
    }

    private static func erode(mask: [Bool], kernelSize: Int) -> [Bool] {
        guard !mask.isEmpty else { return mask }
        var result = mask
        let halfKernel = kernelSize / 2

        for i in 0..<mask.count where !mask[i] {
            let start = max(0, i - halfKernel)
            let end = min(mask.count - 1, i + halfKernel)
            for j in start...end {
                result[j] = false
            }
        }
        return result
    }

    static func extractRegions(from mask: [Bool]) -> [SpeechRegion] {
        var regions: [SpeechRegion] = []
        var regionStart: Int?

        for (i, isSpeech) in mask.enumerated() {
            if isSpeech {
                if regionStart == nil {
                    regionStart = i
                }
            } else if let start = regionStart {
                regions.append(SpeechRegion(startFrame: start, endFrame: i))
                regionStart = nil
            }
        }

        // Close final region
        if let start = regionStart {
            regions.append(SpeechRegion(startFrame: start, endFrame: mask.count))
        }

        return regions
    }
}
