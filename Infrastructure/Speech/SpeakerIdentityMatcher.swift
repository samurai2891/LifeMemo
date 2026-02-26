import Foundation

/// Matching abstraction for assigning known identities to diarized speakers.
protocol SpeakerIdentityMatching {
    func match(
        globalProfiles: [SpeakerProfile],
        enrollment: VoiceEnrollmentProfile
    ) -> SpeakerIdentityAssignment?
    func shouldAdaptProfile(from result: SpeakerIdentityMatchResult) -> Bool
    func adapt(
        profile: VoiceEnrollmentProfile,
        matchedProfile: SpeakerProfile
    ) -> VoiceEnrollmentProfile?
}

/// Matches diarized speaker profiles to a single enrolled "Me" profile.
final class SpeakerIdentityMatcher: SpeakerIdentityMatching {

    struct Thresholds {
        let acceptMFCC: Float
        let reviewMFCC: Float
        let acceptLegacy: Float
        let reviewLegacy: Float
        let adaptMFCC: Float
        let adaptLegacy: Float

        static let `default` = Thresholds(
            acceptMFCC: 0.30,
            reviewMFCC: 0.40,
            acceptLegacy: 1.30,
            reviewLegacy: 2.00,
            adaptMFCC: 0.22,
            adaptLegacy: 0.90
        )
    }

    private let thresholds: Thresholds
    private let adaptationAlpha: Float

    init(
        thresholds: Thresholds = .default,
        adaptationAlpha: Float = 0.20
    ) {
        self.thresholds = thresholds
        self.adaptationAlpha = min(max(adaptationAlpha, 0.01), 0.80)
    }

    func match(
        globalProfiles: [SpeakerProfile],
        enrollment: VoiceEnrollmentProfile
    ) -> SpeakerIdentityAssignment? {
        guard !globalProfiles.isEmpty else { return nil }

        var bestIndex: Int?
        var bestDistance = Float.greatestFiniteMagnitude
        var bestUsedMFCC = false

        for profile in globalProfiles {
            let (distance, usedMFCC) = distance(profile: profile, enrollment: enrollment)
            if distance < bestDistance {
                bestDistance = distance
                bestUsedMFCC = usedMFCC
                bestIndex = profile.speakerIndex
            }
        }

        guard let speakerIndex = bestIndex else { return nil }

        let acceptThreshold = bestUsedMFCC ? thresholds.acceptMFCC : thresholds.acceptLegacy
        let reviewThreshold = bestUsedMFCC ? thresholds.reviewMFCC : thresholds.reviewLegacy
        let clampedReview = max(acceptThreshold + 0.01, reviewThreshold)
        let normalized = max(0, min(1, 1 - (bestDistance / clampedReview)))

        if bestDistance <= acceptThreshold {
            return SpeakerIdentityAssignment(
                globalSpeakerIndex: speakerIndex,
                result: SpeakerIdentityMatchResult(
                    identity: .me,
                    distance: bestDistance,
                    confidence: normalized,
                    usedMFCC: bestUsedMFCC,
                    decisionReason: "accepted_within_threshold"
                )
            )
        }

        let reason: String
        if bestDistance <= reviewThreshold {
            reason = "uncertain_between_accept_and_review"
        } else {
            reason = "distance_too_far"
        }

        return SpeakerIdentityAssignment(
            globalSpeakerIndex: speakerIndex,
            result: SpeakerIdentityMatchResult(
                identity: .unknown,
                distance: bestDistance,
                confidence: normalized,
                usedMFCC: bestUsedMFCC,
                decisionReason: reason
            )
        )
    }

    func shouldAdaptProfile(from result: SpeakerIdentityMatchResult) -> Bool {
        guard result.identity == .me else { return false }
        let threshold = result.usedMFCC ? thresholds.adaptMFCC : thresholds.adaptLegacy
        return result.distance <= threshold
    }

    func adapt(
        profile: VoiceEnrollmentProfile,
        matchedProfile: SpeakerProfile
    ) -> VoiceEnrollmentProfile? {
        guard let matchedEmbedding = matchedProfile.mfccEmbedding else { return nil }

        let current = profile.referenceEmbedding.values
        let incoming = matchedEmbedding.values
        guard current.count == incoming.count, !current.isEmpty else { return nil }

        let keep = 1 - adaptationAlpha
        var merged = [Float](repeating: 0, count: current.count)
        for idx in 0..<current.count {
            merged[idx] = keep * current[idx] + adaptationAlpha * incoming[idx]
        }
        let updatedEmbedding = SpeakerEmbedding(values: merged)

        let oldCentroid = profile.referenceCentroid
        let newCentroid = matchedProfile.centroid
        let updatedCentroid = SpeakerFeatureVector(
            meanPitch: keep * oldCentroid.meanPitch + adaptationAlpha * newCentroid.meanPitch,
            pitchStdDev: keep * oldCentroid.pitchStdDev + adaptationAlpha * newCentroid.pitchStdDev,
            meanEnergy: keep * oldCentroid.meanEnergy + adaptationAlpha * newCentroid.meanEnergy,
            meanSpectralCentroid: keep * oldCentroid.meanSpectralCentroid + adaptationAlpha * newCentroid.meanSpectralCentroid,
            meanJitter: keep * oldCentroid.meanJitter + adaptationAlpha * newCentroid.meanJitter,
            meanShimmer: keep * oldCentroid.meanShimmer + adaptationAlpha * newCentroid.meanShimmer
        )

        return VoiceEnrollmentProfile(
            id: profile.id,
            displayName: profile.displayName,
            referenceEmbedding: updatedEmbedding,
            referenceCentroid: updatedCentroid,
            version: profile.version,
            isActive: profile.isActive,
            qualityStats: profile.qualityStats,
            adaptationCount: profile.adaptationCount + 1,
            updatedAt: Date()
        )
    }

    private func distance(
        profile: SpeakerProfile,
        enrollment: VoiceEnrollmentProfile
    ) -> (distance: Float, usedMFCC: Bool) {
        if let profileEmbedding = profile.mfccEmbedding {
            return (
                distance: profileEmbedding.cosineDistance(to: enrollment.referenceEmbedding),
                usedMFCC: true
            )
        }
        return (
            distance: profile.centroid.distance(to: enrollment.referenceCentroid),
            usedMFCC: false
        )
    }
}
