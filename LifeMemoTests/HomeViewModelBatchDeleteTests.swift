import XCTest
import CoreData
@testable import LifeMemo

@MainActor
final class HomeViewModelBatchDeleteTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!
    private var repository: SessionRepository!
    private var viewModel: HomeViewModel!

    override func setUp() {
        super.setUp()
        let model = CoreDataStack.createManagedObjectModel()
        container = NSPersistentContainer(name: "BatchDeleteTest", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error { fatalError("Test store failed: \(error)") }
        }
        context = container.viewContext
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        let fileStore = FileStore()
        repository = SessionRepository(context: context, fileStore: fileStore)
        let searchService = SimpleSearchService(repository: repository)
        viewModel = HomeViewModel(repository: repository, searchService: searchService)
    }

    override func tearDown() {
        viewModel = nil
        context?.reset()
        repository = nil
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Select All

    func testSelectAll() {
        let ids = createSessions(count: 3)
        viewModel.loadSessions()

        viewModel.selectAll()

        XCTAssertEqual(viewModel.selectedSessionIds.count, 3)
        for id in ids {
            XCTAssertTrue(viewModel.selectedSessionIds.contains(id))
        }
    }

    // MARK: - Deselect All

    func testDeselectAll() {
        let ids = createSessions(count: 3)
        viewModel.loadSessions()
        viewModel.selectedSessionIds = Set(ids)

        viewModel.deselectAll()

        XCTAssertTrue(viewModel.selectedSessionIds.isEmpty)
    }

    // MARK: - Toggle Select All

    func testToggleSelectAll() {
        _ = createSessions(count: 3)
        viewModel.loadSessions()

        // First toggle: select all
        viewModel.toggleSelectAll()
        XCTAssertEqual(viewModel.selectedSessionIds.count, 3)

        // Second toggle: deselect all
        viewModel.toggleSelectAll()
        XCTAssertTrue(viewModel.selectedSessionIds.isEmpty)
    }

    // MARK: - All Filtered Selected

    func testAllFilteredSelected() {
        let ids = createSessions(count: 3)
        viewModel.loadSessions()

        XCTAssertFalse(viewModel.allFilteredSelected, "Should be false when nothing selected")

        viewModel.selectedSessionIds = Set(ids)
        XCTAssertTrue(viewModel.allFilteredSelected, "Should be true when all selected")

        viewModel.selectedSessionIds = Set(ids.prefix(2))
        XCTAssertFalse(viewModel.allFilteredSelected, "Should be false when partially selected")
    }

    // MARK: - Batch Delete Completely

    func testBatchDeleteCompletely() {
        let ids = createSessions(count: 3)
        viewModel.loadSessions()
        XCTAssertEqual(viewModel.filteredSessions.count, 3)

        viewModel.selectedSessionIds = Set(ids.prefix(2))
        viewModel.batchDeleteCompletely()

        XCTAssertEqual(viewModel.filteredSessions.count, 1)
        XCTAssertTrue(viewModel.selectedSessionIds.isEmpty, "Selection should be cleared")
        XCTAssertNotNil(viewModel.batchResultMessage)
    }

    // MARK: - Batch Delete Audio Only

    func testBatchDeleteAudioOnly() {
        let ids = createSessions(count: 2)
        viewModel.loadSessions()

        viewModel.selectedSessionIds = Set(ids)
        viewModel.batchDeleteAudioOnly()

        XCTAssertEqual(viewModel.filteredSessions.count, 2, "Sessions should still exist")
        XCTAssertTrue(viewModel.selectedSessionIds.isEmpty, "Selection should be cleared")
        XCTAssertNotNil(viewModel.batchResultMessage)

        // Verify audio was removed and chunks updated
        for id in ids {
            let session = repository.fetchSession(id: id)
            XCTAssertEqual(session?.audioKept, false, "Audio should be removed")
            for chunk in session?.chunksArray ?? [] {
                XCTAssertTrue(chunk.audioDeleted, "Chunk should be marked as audio deleted")
                XCTAssertNil(chunk.relativePath, "Chunk relativePath should be nil")
            }
        }
    }

    // MARK: - Request Batch Delete Ignored When Empty

    func testRequestBatchDeleteIgnoredWhenEmpty() {
        _ = createSessions(count: 2)
        viewModel.loadSessions()

        viewModel.requestBatchDelete()

        XCTAssertFalse(
            viewModel.showBatchDeleteConfirm,
            "Should not show confirm when selection is empty"
        )
    }

    // MARK: - Request Batch Delete Shows Confirm

    func testRequestBatchDeleteShowsConfirm() {
        let ids = createSessions(count: 2)
        viewModel.loadSessions()

        viewModel.selectedSessionIds = Set(ids.prefix(1))
        viewModel.requestBatchDelete()

        XCTAssertTrue(
            viewModel.showBatchDeleteConfirm,
            "Should show confirm when selection is not empty"
        )
    }

    // MARK: - Single Session Swipe Delete

    func testRequestSwipeDeleteSetsTarget() {
        let ids = createSessions(count: 2)
        viewModel.loadSessions()

        viewModel.requestSwipeDelete(sessionId: ids[0])

        XCTAssertEqual(viewModel.swipeDeleteTargetId, ids[0])
        XCTAssertTrue(viewModel.showSwipeDeleteConfirm)
    }

    func testSwipeDeleteCompletelyRemovesSession() {
        let ids = createSessions(count: 3)
        viewModel.loadSessions()
        XCTAssertEqual(viewModel.filteredSessions.count, 3)

        viewModel.requestSwipeDelete(sessionId: ids[1])
        viewModel.swipeDeleteCompletely()

        XCTAssertEqual(viewModel.filteredSessions.count, 2)
        XCTAssertNil(viewModel.swipeDeleteTargetId)
        XCTAssertFalse(
            viewModel.filteredSessions.contains(where: { $0.id == ids[1] })
        )
    }

    func testSwipeDeleteCompletelyClearsTargetWhenNil() {
        _ = createSessions(count: 1)
        viewModel.loadSessions()

        viewModel.swipeDeleteCompletely()

        XCTAssertEqual(
            viewModel.filteredSessions.count, 1,
            "No session should be deleted when targetId is nil"
        )
    }

    func testSwipeDeleteAudioOnlyPreservesSession() {
        let ids = createSessions(count: 2)
        viewModel.loadSessions()

        viewModel.swipeDeleteAudioOnly(sessionId: ids[0])

        XCTAssertEqual(viewModel.filteredSessions.count, 2, "Session should still exist")
        let session = repository.fetchSession(id: ids[0])
        XCTAssertEqual(session?.audioKept, false, "Audio should be removed")
        for chunk in session?.chunksArray ?? [] {
            XCTAssertTrue(chunk.audioDeleted)
            XCTAssertNil(chunk.relativePath)
        }
    }

    func testSwipeDeleteDoesNotAffectBatchSelection() {
        let ids = createSessions(count: 3)
        viewModel.loadSessions()
        viewModel.selectedSessionIds = Set(ids)

        viewModel.swipeDeleteAudioOnly(sessionId: ids[0])

        XCTAssertEqual(
            viewModel.selectedSessionIds.count, 3,
            "Swipe delete should not affect batch selection state"
        )
    }

    // MARK: - Private Helpers

    @discardableResult
    private func createSessions(count: Int) -> [UUID] {
        var ids: [UUID] = []
        for i in 0..<count {
            let session = SessionEntity(context: context)
            let sessionId = UUID()
            session.id = sessionId
            session.createdAt = Date().addingTimeInterval(Double(-i) * 60)
            session.startedAt = session.createdAt
            session.title = "Session \(i)"
            session.languageModeRaw = "auto"
            session.statusRaw = SessionStatus.ready.rawValue
            session.audioKept = true

            // Add a chunk so audio deletion has something to work with
            let chunk = ChunkEntity(context: context)
            chunk.id = UUID()
            chunk.index = 0
            chunk.startAt = session.startedAt
            chunk.endAt = session.startedAt?.addingTimeInterval(60)
            chunk.durationSec = 60
            chunk.sizeBytes = 1024
            chunk.relativePath = "test/\(sessionId.uuidString)/chunk_0.m4a"
            chunk.transcriptionStatusRaw = TranscriptionStatus.done.rawValue
            chunk.audioDeleted = false
            chunk.session = session

            ids.append(sessionId)
        }
        do {
            try context.save()
        } catch {
            XCTFail("Failed to save test data: \(error)")
        }
        return ids
    }
}
