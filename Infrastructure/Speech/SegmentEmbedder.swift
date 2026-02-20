import Accelerate
import Foundation

/// Generates 130-dimensional speaker embeddings from MFCC frame statistics.
///
/// Dimension breakdown:
/// - 13 MFCC means
/// - 13 MFCC standard deviations
/// - 13 delta means
/// - 13 delta-delta means
/// - 78 upper-triangular correlation coefficients (13×12/2)
///
/// The resulting vector is L2-normalized to enable cosine distance comparison.
enum SegmentEmbedder {

    /// Expected embedding dimensionality.
    static let embeddingDimension = 130

    /// Computes a speaker embedding from a segment's MFCC, delta, and delta-delta frames.
    ///
    /// - Parameters:
    ///   - mfccFrames: Per-frame 13-dimensional MFCC vectors for the segment.
    ///   - deltas: Per-frame 13-dimensional delta vectors.
    ///   - deltaDeltas: Per-frame 13-dimensional delta-delta vectors.
    /// - Returns: A 130D L2-normalized `SpeakerEmbedding`, or `nil` if input is empty.
    static func computeEmbedding(
        mfccFrames: [[Float]],
        deltas: [[Float]],
        deltaDeltas: [[Float]]
    ) -> SpeakerEmbedding? {
        guard !mfccFrames.isEmpty else { return nil }
        let dim = mfccFrames[0].count  // 13
        guard dim > 0 else { return nil }
        let n = Float(mfccFrames.count)

        // 1. MFCC means (13D)
        let mfccMeans = computeMeans(frames: mfccFrames, dim: dim, count: n)

        // 2. MFCC standard deviations (13D)
        let mfccStds = computeStds(frames: mfccFrames, means: mfccMeans, dim: dim, count: n)

        // 3. Delta means (13D)
        let deltaMeans = computeMeans(frames: deltas, dim: dim, count: n)

        // 4. Delta-delta means (13D)
        let ddMeans = computeMeans(frames: deltaDeltas, dim: dim, count: n)

        // 5. Upper-triangular correlation matrix (78D = 13*12/2)
        let correlations = computeUpperTriCorrelation(
            frames: mfccFrames, means: mfccMeans, stds: mfccStds, dim: dim
        )

        // Concatenate: 13 + 13 + 13 + 13 + 78 = 130
        var embedding: [Float] = []
        embedding.reserveCapacity(embeddingDimension)
        embedding.append(contentsOf: mfccMeans)
        embedding.append(contentsOf: mfccStds)
        embedding.append(contentsOf: deltaMeans)
        embedding.append(contentsOf: ddMeans)
        embedding.append(contentsOf: correlations)

        return SpeakerEmbedding(values: embedding)
    }

    // MARK: - Statistics

    private static func computeMeans(frames: [[Float]], dim: Int, count: Float) -> [Float] {
        var means = [Float](repeating: 0, count: dim)
        for frame in frames {
            for d in 0..<min(dim, frame.count) {
                means[d] += frame[d]
            }
        }
        if count > 0 {
            var divisor = count
            vDSP_vsdiv(means, 1, &divisor, &means, 1, vDSP_Length(dim))
        }
        return means
    }

    private static func computeStds(
        frames: [[Float]], means: [Float], dim: Int, count: Float
    ) -> [Float] {
        var variance = [Float](repeating: 0, count: dim)
        for frame in frames {
            for d in 0..<min(dim, frame.count) {
                let diff = frame[d] - means[d]
                variance[d] += diff * diff
            }
        }
        if count > 1 {
            var divisor = count - 1
            vDSP_vsdiv(variance, 1, &divisor, &variance, 1, vDSP_Length(dim))
        }

        // Square root for standard deviation
        var stds = [Float](repeating: 0, count: dim)
        var dimInt = Int32(dim)
        vvsqrtf(&stds, variance, &dimInt)
        return stds
    }

    private static func computeUpperTriCorrelation(
        frames: [[Float]], means: [Float], stds: [Float], dim: Int
    ) -> [Float] {
        // Number of pairs: dim * (dim - 1) / 2
        let numPairs = dim * (dim - 1) / 2
        var correlations = [Float](repeating: 0, count: numPairs)
        let n = Float(frames.count)
        guard n > 1 else { return correlations }

        // Compute covariances for each pair (i, j) where i < j
        var idx = 0
        for i in 0..<dim {
            for j in (i + 1)..<dim {
                var cov: Float = 0
                for frame in frames {
                    let di = frame[i] - means[i]
                    let dj = frame[j] - means[j]
                    cov += di * dj
                }
                cov /= (n - 1)

                // Correlation = cov / (std_i * std_j)
                let denom = stds[i] * stds[j]
                correlations[idx] = denom > 1e-10 ? cov / denom : 0
                idx += 1
            }
        }

        return correlations
    }
}
