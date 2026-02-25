import XCTest
import CoreData
@testable import LifeMemo

@MainActor
final class SessionRepositoryDiarizationFallbackTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var repository: SessionRepository!

    override func setUp() {
        super.setUp()
        let model = CoreDataStack.createManagedObjectModel()
        container = NSPersistentContainer(
            name: "SessionRepositoryDiarizationFallbackTests",
            managedObjectModel: model
        )
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            XCTAssertNil(error)
        }
        repository = SessionRepository(context: container.viewContext, fileStore: FileStore())
    }

    override func tearDown() {
        repository = nil
        container = nil
        super.tearDown()
    }

    func testSaveTranscriptWithSpeakersFallsBackToFullTextWhenDiarizedTextLooksTruncated() {
        let (sessionId, chunkId) = prepareSessionWithChunk(durationSec: 60)
        let fullText = "This is a full transcript sentence that should never be replaced by a tiny tail."
        let diarization = DiarizationResult(
            segments: [
                DiarizedSegment(
                    id: UUID(),
                    speakerIndex: 0,
                    text: "tiny tail",
                    startOffsetMs: 56_000,
                    endOffsetMs: 59_000
                )
            ],
            speakerCount: 2,
            speakerProfiles: []
        )

        repository.saveTranscriptWithSpeakers(
            sessionId: sessionId,
            chunkId: chunkId,
            diarization: diarization,
            fullText: fullText
        )

        guard let session = repository.fetchSession(id: sessionId) else {
            XCTFail("Session should exist")
            return
        }

        XCTAssertEqual(session.segmentsArray.count, 1)
        XCTAssertEqual(session.segmentsArray.first?.text, fullText)
        XCTAssertEqual(session.segmentsArray.first?.speakerIndex, -1)
    }

    func testSaveTranscriptWithSpeakersKeepsSpeakerSegmentsWhenCoverageIsHealthy() {
        let (sessionId, chunkId) = prepareSessionWithChunk(durationSec: 8)
        let fullText = "Hello there how are you today"
        let diarization = DiarizationResult(
            segments: [
                DiarizedSegment(
                    id: UUID(),
                    speakerIndex: 0,
                    text: "Hello there",
                    startOffsetMs: 0,
                    endOffsetMs: 3_500
                ),
                DiarizedSegment(
                    id: UUID(),
                    speakerIndex: 1,
                    text: "how are you today",
                    startOffsetMs: 3_500,
                    endOffsetMs: 8_000
                )
            ],
            speakerCount: 2,
            speakerProfiles: []
        )

        repository.saveTranscriptWithSpeakers(
            sessionId: sessionId,
            chunkId: chunkId,
            diarization: diarization,
            fullText: fullText
        )

        guard let session = repository.fetchSession(id: sessionId) else {
            XCTFail("Session should exist")
            return
        }

        XCTAssertEqual(session.segmentsArray.count, 2)
        XCTAssertEqual(session.segmentsArray[0].speakerIndex, 0)
        XCTAssertEqual(session.segmentsArray[1].speakerIndex, 1)
        XCTAssertEqual(session.segmentsArray.map { $0.text ?? "" }.joined(separator: " "), fullText)
    }

    // MARK: - Helpers

    private func prepareSessionWithChunk(durationSec: Double) -> (UUID, UUID) {
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
            endAt: startedAt.addingTimeInterval(durationSec),
            durationSec: durationSec,
            sizeBytes: 1024
        )

        return (sessionId, chunkId)
    }
}
