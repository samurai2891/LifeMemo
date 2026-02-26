import XCTest
@testable import LifeMemo

final class VoiceEnrollmentRepositoryTests: XCTestCase {

    private var defaults: UserDefaults!
    private var repository: VoiceEnrollmentRepository!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "VoiceEnrollmentRepositoryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        repository = VoiceEnrollmentRepository(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        repository = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSaveAndLoadActiveProfile() {
        let profile = VoiceEnrollmentProfile(
            id: UUID(),
            displayName: "Me",
            referenceEmbedding: SpeakerEmbedding(values: [1, 0]),
            referenceCentroid: SpeakerFeatureVector(
                meanPitch: 180,
                pitchStdDev: 25,
                meanEnergy: 0.4,
                meanSpectralCentroid: 700,
                meanJitter: 0.02,
                meanShimmer: 0.03
            ),
            version: 2,
            isActive: true,
            qualityStats: VoiceEnrollmentQualityStats(
                acceptedSamples: 12,
                averageSnrDb: 12,
                averageSpeechRatio: 0.72,
                averageClippingRatio: 0.001
            ),
            adaptationCount: 1,
            updatedAt: Date()
        )

        repository.saveActiveProfile(profile)
        let loaded = repository.activeProfile()

        XCTAssertEqual(loaded, profile)
    }

    func testDeactivateRemovesProfile() {
        let profile = VoiceEnrollmentProfile(
            id: UUID(),
            displayName: "Me",
            referenceEmbedding: SpeakerEmbedding(values: [1, 0]),
            referenceCentroid: SpeakerFeatureVector(
                meanPitch: 180,
                pitchStdDev: 25,
                meanEnergy: 0.4,
                meanSpectralCentroid: 700,
                meanJitter: 0.02,
                meanShimmer: 0.03
            ),
            version: 1,
            isActive: true,
            qualityStats: VoiceEnrollmentQualityStats(
                acceptedSamples: 12,
                averageSnrDb: 12,
                averageSpeechRatio: 0.72,
                averageClippingRatio: 0.001
            ),
            adaptationCount: 0,
            updatedAt: Date()
        )

        repository.saveActiveProfile(profile)
        repository.deactivateProfile()

        XCTAssertNil(repository.activeProfile())
    }
}
