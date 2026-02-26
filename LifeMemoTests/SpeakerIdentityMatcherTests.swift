import XCTest
@testable import LifeMemo

final class SpeakerIdentityMatcherTests: XCTestCase {

    func testMatchReturnsMeWhenDistanceIsWithinAcceptThreshold() {
        let matcher = SpeakerIdentityMatcher()
        let enrollment = makeEnrollmentProfile(embedding: SpeakerEmbedding(values: [1, 0]))
        let profile = SpeakerProfile(
            id: UUID(),
            speakerIndex: 0,
            centroid: makeCentroid(),
            sampleCount: 4,
            mfccEmbedding: SpeakerEmbedding(values: [0.99, 0.01])
        )

        let assignment = matcher.match(globalProfiles: [profile], enrollment: enrollment)

        XCTAssertEqual(assignment?.globalSpeakerIndex, 0)
        XCTAssertEqual(assignment?.result.identity, .me)
    }

    func testMatchReturnsUnknownWhenDistanceIsTooFar() {
        let matcher = SpeakerIdentityMatcher()
        let enrollment = makeEnrollmentProfile(embedding: SpeakerEmbedding(values: [1, 0]))
        let farProfile = SpeakerProfile(
            id: UUID(),
            speakerIndex: 1,
            centroid: makeCentroid(),
            sampleCount: 4,
            mfccEmbedding: SpeakerEmbedding(values: [0, 1])
        )

        let assignment = matcher.match(globalProfiles: [farProfile], enrollment: enrollment)

        XCTAssertEqual(assignment?.globalSpeakerIndex, 1)
        XCTAssertEqual(assignment?.result.identity, .unknown)
        XCTAssertEqual(assignment?.result.decisionReason, "distance_too_far")
    }

    func testAdaptUpdatesEmbeddingAndCounter() {
        let matcher = SpeakerIdentityMatcher()
        let original = makeEnrollmentProfile(embedding: SpeakerEmbedding(values: [1, 0]))
        let matched = SpeakerProfile(
            id: UUID(),
            speakerIndex: 0,
            centroid: SpeakerFeatureVector(
                meanPitch: 220,
                pitchStdDev: 32,
                meanEnergy: 0.52,
                meanSpectralCentroid: 780,
                meanJitter: 0.03,
                meanShimmer: 0.04
            ),
            sampleCount: 2,
            mfccEmbedding: SpeakerEmbedding(values: [0, 1])
        )

        let adapted = matcher.adapt(profile: original, matchedProfile: matched)

        XCTAssertNotNil(adapted)
        XCTAssertEqual(adapted?.adaptationCount, original.adaptationCount + 1)
        XCTAssertNotEqual(adapted?.referenceEmbedding, original.referenceEmbedding)
    }

    private func makeEnrollmentProfile(embedding: SpeakerEmbedding) -> VoiceEnrollmentProfile {
        VoiceEnrollmentProfile(
            id: UUID(),
            displayName: "Me",
            referenceEmbedding: embedding,
            referenceCentroid: makeCentroid(),
            version: 1,
            isActive: true,
            qualityStats: VoiceEnrollmentQualityStats(
                acceptedSamples: 12,
                averageSnrDb: 12,
                averageSpeechRatio: 0.7,
                averageClippingRatio: 0.001
            ),
            adaptationCount: 0,
            updatedAt: Date()
        )
    }

    private func makeCentroid() -> SpeakerFeatureVector {
        SpeakerFeatureVector(
            meanPitch: 180,
            pitchStdDev: 28,
            meanEnergy: 0.45,
            meanSpectralCentroid: 700,
            meanJitter: 0.02,
            meanShimmer: 0.03
        )
    }
}
