import Foundation

/// 6-dimensional speaker feature vector for multi-feature speaker diarization.
///
/// Combines pitch, energy, spectral, and voice quality features to create
/// a robust speaker embedding. Uses weighted normalized Euclidean distance
/// for speaker similarity comparison.
struct SpeakerFeatureVector: Codable, Equatable {
    let meanPitch: Float              // Hz (F0 average)
    let pitchStdDev: Float            // Hz (F0 variability)
    let meanEnergy: Float             // Normalized RMS (dB)
    let meanSpectralCentroid: Float   // Hz (voice brightness)
    let meanJitter: Float             // Relative jitter (0..1)
    let meanShimmer: Float            // Relative shimmer (0..1)

    /// Normalization denominators representing typical human ranges for each feature.
    static let normalizationDenominators: [Float] = [150, 50, 20, 1500, 0.05, 0.10]

    /// Feature weights reflecting discriminative power (pitch and spectral centroid weighted highest).
    static let featureWeights: [Float] = [2.0, 1.0, 1.5, 1.5, 0.5, 0.5]

    /// All feature values as an ordered array for vectorized operations.
    var asArray: [Float] {
        [meanPitch, pitchStdDev, meanEnergy, meanSpectralCentroid, meanJitter, meanShimmer]
    }

    /// Weighted normalized Euclidean distance to another feature vector.
    ///
    /// Each dimension is normalized by its typical human range, then weighted
    /// by discriminative importance before computing L2 distance.
    func distance(to other: SpeakerFeatureVector) -> Float {
        let selfValues = asArray
        let otherValues = other.asArray
        let denoms = Self.normalizationDenominators
        let weights = Self.featureWeights

        var sumSq: Float = 0
        for i in 0..<selfValues.count {
            let denom = denoms[i]
            guard denom > 0 else { continue }
            let normalized = (selfValues[i] - otherValues[i]) / denom
            sumSq += weights[i] * normalized * normalized
        }
        return sqrt(sumSq)
    }

    /// Computes the centroid (element-wise mean) of multiple feature vectors.
    ///
    /// - Parameter vectors: Non-empty array of feature vectors.
    /// - Returns: The mean feature vector, or `nil` if the array is empty.
    static func centroid(of vectors: [SpeakerFeatureVector]) -> SpeakerFeatureVector? {
        guard !vectors.isEmpty else { return nil }
        let count = Float(vectors.count)

        let sumPitch = vectors.reduce(Float(0)) { $0 + $1.meanPitch }
        let sumStdDev = vectors.reduce(Float(0)) { $0 + $1.pitchStdDev }
        let sumEnergy = vectors.reduce(Float(0)) { $0 + $1.meanEnergy }
        let sumSpectral = vectors.reduce(Float(0)) { $0 + $1.meanSpectralCentroid }
        let sumJitter = vectors.reduce(Float(0)) { $0 + $1.meanJitter }
        let sumShimmer = vectors.reduce(Float(0)) { $0 + $1.meanShimmer }

        return SpeakerFeatureVector(
            meanPitch: sumPitch / count,
            pitchStdDev: sumStdDev / count,
            meanEnergy: sumEnergy / count,
            meanSpectralCentroid: sumSpectral / count,
            meanJitter: sumJitter / count,
            meanShimmer: sumShimmer / count
        )
    }
}
