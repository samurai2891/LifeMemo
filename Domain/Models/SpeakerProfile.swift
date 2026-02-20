import Foundation

/// Persistent speaker profile used for cross-chunk speaker alignment.
///
/// Each profile represents a unique speaker detected across one or more chunks,
/// with a centroid feature vector that is progressively refined as more speech
/// data from the same speaker is processed.
///
/// ## Backward Compatibility
/// The `mfccEmbedding` field is optional so that profiles serialized before the
/// MFCC upgrade (which lack the key) decode with `mfccEmbedding = nil` and
/// fall back to the legacy `centroid` for distance computation.
struct SpeakerProfile: Codable, Equatable, Identifiable {
    let id: UUID
    let speakerIndex: Int
    let centroid: SpeakerFeatureVector
    let sampleCount: Int
    let mfccEmbedding: SpeakerEmbedding?

    // MARK: - Initializers

    /// Full initializer with MFCC embedding.
    init(
        id: UUID,
        speakerIndex: Int,
        centroid: SpeakerFeatureVector,
        sampleCount: Int,
        mfccEmbedding: SpeakerEmbedding?
    ) {
        self.id = id
        self.speakerIndex = speakerIndex
        self.centroid = centroid
        self.sampleCount = sampleCount
        self.mfccEmbedding = mfccEmbedding
    }

    /// Backward-compatible initializer without MFCC embedding.
    init(id: UUID, speakerIndex: Int, centroid: SpeakerFeatureVector, sampleCount: Int) {
        self.id = id
        self.speakerIndex = speakerIndex
        self.centroid = centroid
        self.sampleCount = sampleCount
        self.mfccEmbedding = nil
    }

    // MARK: - Merging

    /// Creates a new profile by merging additional speech data into the existing centroid.
    func merging(newCentroid: SpeakerFeatureVector, newSampleCount: Int) -> SpeakerProfile {
        let totalCount = sampleCount + newSampleCount
        guard totalCount > 0 else { return self }

        let oldWeight = Float(sampleCount) / Float(totalCount)
        let newWeight = Float(newSampleCount) / Float(totalCount)

        let merged = SpeakerFeatureVector(
            meanPitch: centroid.meanPitch * oldWeight + newCentroid.meanPitch * newWeight,
            pitchStdDev: centroid.pitchStdDev * oldWeight + newCentroid.pitchStdDev * newWeight,
            meanEnergy: centroid.meanEnergy * oldWeight + newCentroid.meanEnergy * newWeight,
            meanSpectralCentroid: centroid.meanSpectralCentroid * oldWeight + newCentroid.meanSpectralCentroid * newWeight,
            meanJitter: centroid.meanJitter * oldWeight + newCentroid.meanJitter * newWeight,
            meanShimmer: centroid.meanShimmer * oldWeight + newCentroid.meanShimmer * newWeight
        )

        return SpeakerProfile(
            id: id,
            speakerIndex: speakerIndex,
            centroid: merged,
            sampleCount: totalCount,
            mfccEmbedding: mfccEmbedding
        )
    }

    /// Creates a new profile by merging a new MFCC embedding via weighted averaging.
    func merging(newMFCCEmbedding: SpeakerEmbedding, newSampleCount: Int) -> SpeakerProfile {
        let totalCount = sampleCount + newSampleCount
        guard totalCount > 0 else { return self }

        let mergedEmbedding: SpeakerEmbedding?
        if let existing = mfccEmbedding {
            let dim = existing.values.count
            guard dim == newMFCCEmbedding.values.count else { return self }

            let oldWeight = Float(sampleCount) / Float(totalCount)
            let newWeight = Float(newSampleCount) / Float(totalCount)

            var merged = [Float](repeating: 0, count: dim)
            for i in 0..<dim {
                merged[i] = existing.values[i] * oldWeight + newMFCCEmbedding.values[i] * newWeight
            }
            mergedEmbedding = SpeakerEmbedding(values: merged)
        } else {
            mergedEmbedding = newMFCCEmbedding
        }

        return SpeakerProfile(
            id: id,
            speakerIndex: speakerIndex,
            centroid: centroid,
            sampleCount: totalCount,
            mfccEmbedding: mergedEmbedding
        )
    }
}
