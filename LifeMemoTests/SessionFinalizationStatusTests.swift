import XCTest
import CoreData
@testable import LifeMemo

@MainActor
final class SessionFinalizationStatusTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var repository: SessionRepository!

    override func setUp() {
        super.setUp()
        let model = CoreDataStack.createManagedObjectModel()
        container = NSPersistentContainer(name: "SessionFinalizationStatusTests", managedObjectModel: model)
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

    func testSessionBecomesReadyWhenAllChunksDone() {
        let sessionId = prepareSessionWithTwoChunks()
        let chunkIds = fetchChunkIds(sessionId: sessionId)

        repository.updateChunkTranscriptionStatus(chunkId: chunkIds[0], status: .done)
        repository.updateChunkTranscriptionStatus(chunkId: chunkIds[1], status: .done)
        repository.checkAndFinalizeSessionStatus(sessionId: sessionId)

        let session = repository.fetchSession(id: sessionId)
        XCTAssertEqual(session?.status, .ready)
    }

    func testSessionBecomesErrorWhenAnyChunkFailed() {
        let sessionId = prepareSessionWithTwoChunks()
        let chunkIds = fetchChunkIds(sessionId: sessionId)

        repository.updateChunkTranscriptionStatus(chunkId: chunkIds[0], status: .done)
        repository.updateChunkTranscriptionStatus(chunkId: chunkIds[1], status: .failed)
        repository.checkAndFinalizeSessionStatus(sessionId: sessionId)

        let session = repository.fetchSession(id: sessionId)
        XCTAssertEqual(session?.status, .error)
    }

    // MARK: - Helpers

    private func prepareSessionWithTwoChunks() -> UUID {
        let sessionId = repository.createSession(languageMode: .english)
        repository.updateSessionStatus(sessionId: sessionId, status: .processing)
        repository.createOrUpdateChunkStarted(
            chunkId: UUID(),
            sessionId: sessionId,
            index: 0,
            startAt: Date(),
            relativePath: "audio/chunk0.m4a"
        )
        repository.createOrUpdateChunkStarted(
            chunkId: UUID(),
            sessionId: sessionId,
            index: 1,
            startAt: Date(),
            relativePath: "audio/chunk1.m4a"
        )
        return sessionId
    }

    private func fetchChunkIds(sessionId: UUID) -> [UUID] {
        let session = repository.fetchSession(id: sessionId)
        return session?.chunksArray.compactMap(\.id).sorted {
            $0.uuidString < $1.uuidString
        } ?? []
    }
}
