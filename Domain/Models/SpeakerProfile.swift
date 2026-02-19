import Foundation

/// Persistent speaker profile used for cross-chunk speaker alignment.
///
/// Each profile represents a unique speaker detected across one or more chunks,
/// with a centroid feature vector that is progressively refined as more speech
/// data from the same speaker is processed.
struct SpeakerProfile: Codable, Equatable, Identifiable {
    let id: UUID
    let speakerIndex: Int
    let centroid: SpeakerFeatureVector
    let sampleCount: Int

    /// Creates a new profile by merging additional speech data into the existing centroid.
    ///
    /// Uses weighted averaging where the existing centroid is weighted by its sample count
    /// and the new data is weighted by the new sample count.
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
            sampleCount: totalCount
        )
    }
}
