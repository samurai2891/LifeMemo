import Foundation

/// BIC-based speaker change point detection using a growing window approach.
///
/// Tests whether a window of MFCC frames is better modeled as one Gaussian
/// distribution or two. A split is accepted only when ΔBIC > 0, meaning the
/// two-Gaussian model is statistically justified after the complexity penalty.
///
/// ## Algorithm
/// 1. Start from the beginning of each speech region.
/// 2. Grow the analysis window by `growthFrames` steps.
/// 3. At each window size, test all candidate split points.
/// 4. If ΔBIC > 0 at the best split point, record the boundary.
/// 5. Restart the search from the split point.
enum BICSegmenter {

    /// A detected speaker change boundary.
    struct Boundary: Equatable {
        let frameIndex: Int
        let bicDelta: Float
    }

    // MARK: - Configuration

    /// Penalty coefficient λ for model complexity (higher = fewer splits).
    static let lambda: Float = 1.5

    /// Minimum window size in frames before testing for splits (~1.0 second).
    static let minWindowFrames = 100

    /// Window growth step in frames (~0.5 seconds).
    static let growthFrames = 50

    // MARK: - Public API

    /// Segments MFCC frames into speaker-homogeneous regions using BIC.
    ///
    /// - Parameters:
    ///   - mfccFrames: Per-frame MFCC vectors (13-dimensional).
    ///   - speechRegions: VAD-detected speech regions to analyze.
    /// - Returns: Detected speaker change boundaries, sorted by frame index.
    static func segment(
        mfccFrames: [[Float]],
        speechRegions: [EnergyVAD.SpeechRegion]
    ) -> [Boundary] {
        var boundaries: [Boundary] = []

        for region in speechRegions {
            let regionBoundaries = segmentRegion(
                mfccFrames: mfccFrames,
                startFrame: region.startFrame,
                endFrame: region.endFrame
            )
            boundaries.append(contentsOf: regionBoundaries)
        }

        return boundaries.sorted { $0.frameIndex < $1.frameIndex }
    }

    // MARK: - Internal

    static func segmentRegion(
        mfccFrames: [[Float]],
        startFrame: Int,
        endFrame: Int
    ) -> [Boundary] {
        var boundaries: [Boundary] = []
        var searchStart = startFrame

        while searchStart < endFrame {
            var windowEnd = searchStart + minWindowFrames

            guard windowEnd <= endFrame else { break }

            var bestSplit = -1
            var bestBIC: Float = 0

            // Grow the window and test for change points
            while windowEnd <= endFrame {
                let windowFrames = extractFrames(
                    mfccFrames: mfccFrames,
                    start: searchStart,
                    end: windowEnd
                )

                let windowLength = windowEnd - searchStart
                guard windowLength >= minWindowFrames else {
                    windowEnd += growthFrames
                    continue
                }

                // Test candidate split points within the window
                let (splitOffset, bic) = findBestSplit(frames: windowFrames)

                if bic > bestBIC {
                    bestBIC = bic
                    bestSplit = searchStart + splitOffset
                }

                // If we found a strong change point, stop growing
                if bestBIC > 0 {
                    break
                }

                windowEnd += growthFrames
            }

            if bestBIC > 0, bestSplit > searchStart {
                boundaries.append(Boundary(frameIndex: bestSplit, bicDelta: bestBIC))
                searchStart = bestSplit
            } else {
                // No change found in this region
                break
            }
        }

        return boundaries
    }

    /// Finds the best split point within a window of frames.
    ///
    /// - Parameter frames: MFCC frames within the analysis window.
    /// - Returns: Tuple of (split offset from window start, ΔBIC value).
    static func findBestSplit(frames: [[Float]]) -> (splitOffset: Int, bicDelta: Float) {
        guard frames.count >= minWindowFrames else { return (0, 0) }
        guard let dim = frames.first?.count, dim > 0 else { return (0, 0) }

        let n = frames.count

        // Combined covariance and its log-determinant
        let covCombined = CovarianceUtil.covarianceMatrix(frames: frames)
        let logDetCombined = CovarianceUtil.logDeterminant(matrix: covCombined, dimension: dim)

        guard logDetCombined > -.infinity else { return (0, 0) }

        // BIC penalty term
        let d = Float(dim)
        let p = d + 0.5 * d * (d + 1)  // Free parameters per Gaussian
        let penalty = lambda * 0.5 * p * logf(Float(n))

        var bestOffset = 0
        var bestBIC: Float = -.infinity

        // Test split points (avoid too-small segments: at least minWindowFrames/3)
        let margin = max(minWindowFrames / 3, 30)
        let splitStart = margin
        let splitEnd = n - margin

        guard splitStart < splitEnd else { return (0, 0) }

        for splitAt in stride(from: splitStart, to: splitEnd, by: 10) {
            let leftFrames = Array(frames[0..<splitAt])
            let rightFrames = Array(frames[splitAt..<n])

            let covLeft = CovarianceUtil.covarianceMatrix(frames: leftFrames)
            let covRight = CovarianceUtil.covarianceMatrix(frames: rightFrames)

            let logDetLeft = CovarianceUtil.logDeterminant(matrix: covLeft, dimension: dim)
            let logDetRight = CovarianceUtil.logDeterminant(matrix: covRight, dimension: dim)

            guard logDetLeft > -.infinity, logDetRight > -.infinity else { continue }

            let n1 = Float(splitAt)
            let n2 = Float(n - splitAt)
            let nf = Float(n)

            // ΔBIC = 0.5 * (n * log|Σ_c| - n1 * log|Σ_1| - n2 * log|Σ_2|) - penalty
            let bic = 0.5 * (nf * logDetCombined - n1 * logDetLeft - n2 * logDetRight) - penalty

            if bic > bestBIC {
                bestBIC = bic
                bestOffset = splitAt
            }
        }

        return (splitOffset: bestOffset, bicDelta: max(bestBIC, 0))
    }

    private static func extractFrames(
        mfccFrames: [[Float]],
        start: Int,
        end: Int
    ) -> [[Float]] {
        let safeStart = max(0, min(start, mfccFrames.count))
        let safeEnd = max(safeStart, min(end, mfccFrames.count))
        return Array(mfccFrames[safeStart..<safeEnd])
    }
}
