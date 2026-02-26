import CoreData
import XCTest
@testable import LifeMemo

@MainActor
final class SessionRepositoryVoiceEnrollmentTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var enrollmentStore: MockEnrollmentStore!
    private var matcher: MockMatcher!
    private var repository: SessionRepository!

    override func setUp() {
        super.setUp()
        let model = CoreDataStack.createManagedObjectModel()
        container = NSPersistentContainer(
            name: "SessionRepositoryVoiceEnrollmentTests",
            managedObjectModel: model
        )
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            XCTAssertNil(error)
        }

        enrollmentStore = MockEnrollmentStore(profile: makeEnrollmentProfile())
        matcher = MockMatcher()
        repository = SessionRepository(
            context: container.viewContext,
            fileStore: FileStore(),
            searchIndexer: nil,
            voiceEnrollmentRepository: enrollmentStore,
            speakerIdentityMatcher: matcher
        )
    }

    override func tearDown() {
        repository = nil
        matcher = nil
        enrollmentStore = nil
        container = nil
        super.tearDown()
    }

    func testFinalizationAssignsMeSpeakerNameWhenMatched() {
        let sessionId = prepareSessionWithOneChunkAndProfile()

        repository.checkAndFinalizeSessionStatus(sessionId: sessionId)

        guard let session = repository.fetchSession(id: sessionId) else {
            XCTFail("Session must exist")
            return
        }

        XCTAssertEqual(session.status, .ready)
        XCTAssertEqual(session.speakerNames[0], "Me")
    }

    func testFinalizationCanAdaptEnrollmentProfile() {
        matcher.shouldAdapt = true
        matcher.adaptedProfile = makeEnrollmentProfile(adaptationCount: 1)
        let sessionId = prepareSessionWithOneChunkAndProfile()

        repository.checkAndFinalizeSessionStatus(sessionId: sessionId)

        XCTAssertEqual(enrollmentStore.savedProfiles.count, 1)
        XCTAssertEqual(enrollmentStore.savedProfiles.first?.adaptationCount, 1)
    }

    private func prepareSessionWithOneChunkAndProfile() -> UUID {
        let sessionId = repository.createSession(languageMode: .english)
        repository.updateSessionStatus(sessionId: sessionId, status: .processing)

        let chunkId = UUID()
        let startedAt = Date()
        repository.createOrUpdateChunkStarted(
            chunkId: chunkId,
            sessionId: sessionId,
            index: 0,
            startAt: startedAt,
            relativePath: "audio/chunk-0.m4a"
        )
        repository.finalizeChunk(
            chunkId: chunkId,
            sessionId: sessionId,
            endAt: startedAt.addingTimeInterval(50),
            durationSec: 50,
            sizeBytes: 4096
        )

        let profile = SpeakerProfile(
            id: UUID(),
            speakerIndex: 0,
            centroid: SpeakerFeatureVector(
                meanPitch: 180,
                pitchStdDev: 25,
                meanEnergy: 0.45,
                meanSpectralCentroid: 700,
                meanJitter: 0.02,
                meanShimmer: 0.03
            ),
            sampleCount: 4,
            mfccEmbedding: SpeakerEmbedding(values: [1, 0])
        )

        let diarization = DiarizationResult(
            segments: [
                DiarizedSegment(
                    id: UUID(),
                    speakerIndex: 0,
                    text: "hello world",
                    startOffsetMs: 0,
                    endOffsetMs: 20_000
                )
            ],
            speakerCount: 2,
            speakerProfiles: [profile]
        )

        repository.saveTranscriptWithSpeakers(
            sessionId: sessionId,
            chunkId: chunkId,
            diarization: diarization,
            fullText: "hello world",
            applyFallbackGuard: false
        )
        repository.saveSpeakerProfiles(sessionId: sessionId, chunkIndex: 0, profiles: [profile])
        return sessionId
    }

    private func makeEnrollmentProfile(adaptationCount: Int = 0) -> VoiceEnrollmentProfile {
        VoiceEnrollmentProfile(
            id: UUID(),
            displayName: "Me",
            referenceEmbedding: SpeakerEmbedding(values: [1, 0]),
            referenceCentroid: SpeakerFeatureVector(
                meanPitch: 175,
                pitchStdDev: 20,
                meanEnergy: 0.40,
                meanSpectralCentroid: 650,
                meanJitter: 0.02,
                meanShimmer: 0.03
            ),
            version: 1,
            isActive: true,
            qualityStats: VoiceEnrollmentQualityStats(
                acceptedSamples: 12,
                averageSnrDb: 12,
                averageSpeechRatio: 0.7,
                averageClippingRatio: 0.001
            ),
            adaptationCount: adaptationCount,
            updatedAt: Date()
        )
    }
}

private final class MockEnrollmentStore: VoiceEnrollmentProfileStoring {
    var profile: VoiceEnrollmentProfile?
    var savedProfiles: [VoiceEnrollmentProfile] = []

    init(profile: VoiceEnrollmentProfile?) {
        self.profile = profile
    }

    func activeProfile() -> VoiceEnrollmentProfile? {
        profile
    }

    func saveActiveProfile(_ profile: VoiceEnrollmentProfile) {
        self.profile = profile
        savedProfiles.append(profile)
    }

    func deactivateProfile() {
        profile = nil
    }
}

private final class MockMatcher: SpeakerIdentityMatching {
    var shouldAdapt = false
    var adaptedProfile: VoiceEnrollmentProfile?

    func match(
        globalProfiles: [SpeakerProfile],
        enrollment: VoiceEnrollmentProfile
    ) -> SpeakerIdentityAssignment? {
        guard let first = globalProfiles.first else { return nil }
        return SpeakerIdentityAssignment(
            globalSpeakerIndex: first.speakerIndex,
            result: SpeakerIdentityMatchResult(
                identity: .me,
                distance: 0.10,
                confidence: 0.90,
                usedMFCC: true,
                decisionReason: "test"
            )
        )
    }

    func shouldAdaptProfile(from result: SpeakerIdentityMatchResult) -> Bool {
        shouldAdapt
    }

    func adapt(
        profile: VoiceEnrollmentProfile,
        matchedProfile: SpeakerProfile
    ) -> VoiceEnrollmentProfile? {
        adaptedProfile ?? profile
    }
}
