import XCTest
import CoreData
@testable import LifeMemo

@MainActor
final class AdvancedSearchServiceTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!
    private var repository: SessionRepository!
    private var searchService: AdvancedSearchService!
    private var fts5Manager: FTS5Manager!

    override func setUp() {
        super.setUp()
        let model = CoreDataStack.createManagedObjectModel()
        container = NSPersistentContainer(name: "AdvancedSearchServiceTests", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            XCTAssertNil(error)
        }

        context = container.viewContext
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        let fileStore = FileStore()
        fts5Manager = FTS5Manager()
        repository = SessionRepository(
            context: context,
            fileStore: fileStore,
            searchIndexer: fts5Manager
        )
        searchService = AdvancedSearchService(
            fts5Manager: fts5Manager,
            context: context,
            pageSize: 1
        )
        searchService.rebuildSearchIndex()
    }

    override func tearDown() {
        fts5Manager = nil
        searchService = nil
        repository = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testFilterOnlySearchFiltersByTagAndFolder() {
        let workTagId = repository.createTag(name: "Work")
        _ = repository.createTag(name: "Private")
        let meetingsFolderId = repository.createFolder(name: "Meetings")
        let journalFolderId = repository.createFolder(name: "Journal")

        let matchedSessionId = repository.createSession(languageMode: .auto)
        repository.addTag(tagId: workTagId, toSession: matchedSessionId)
        repository.setSessionFolder(sessionId: matchedSessionId, folderId: meetingsFolderId)

        let wrongFolderSessionId = repository.createSession(languageMode: .auto)
        repository.addTag(tagId: workTagId, toSession: wrongFolderSessionId)
        repository.setSessionFolder(sessionId: wrongFolderSessionId, folderId: journalFolderId)

        var filter = SearchFilter()
        filter.tagName = "Work"
        filter.folderName = "Meetings"

        let result = searchService.search(filter: filter, page: 0)

        XCTAssertEqual(result.totalCount, 1)
        XCTAssertEqual(result.sessionIds, [matchedSessionId])
    }

    func testFilterOnlySearchPaginationUsesFilteredCount() {
        let folderId = repository.createFolder(name: "Projects")

        let firstSessionId = repository.createSession(languageMode: .auto)
        repository.setSessionFolder(sessionId: firstSessionId, folderId: folderId)

        let secondSessionId = repository.createSession(languageMode: .auto)
        repository.setSessionFolder(sessionId: secondSessionId, folderId: folderId)

        var filter = SearchFilter()
        filter.folderName = "Projects"
        filter.sortOrder = .oldest

        let firstPage = searchService.search(filter: filter, page: 0)
        XCTAssertEqual(firstPage.totalCount, 2)
        XCTAssertEqual(firstPage.sessionIds.count, 1)
        XCTAssertTrue(firstPage.hasMore)

        let secondPage = searchService.search(filter: filter, page: 1)
        XCTAssertEqual(secondPage.totalCount, 2)
        XCTAssertEqual(secondPage.sessionIds.count, 1)
        XCTAssertFalse(secondPage.hasMore)

        let merged = Set(firstPage.sessionIds + secondPage.sessionIds)
        XCTAssertEqual(merged, Set([firstSessionId, secondSessionId]))
    }

    func testFTSIndexAutoUpdatesAfterTranscriptSave() {
        let sessionId = repository.createSession(languageMode: .auto)
        let chunkId = UUID()
        let startAt = Date()

        repository.createOrUpdateChunkStarted(
            chunkId: chunkId,
            sessionId: sessionId,
            index: 0,
            startAt: startAt,
            relativePath: "Audio/\(sessionId.uuidString)/0000.m4a"
        )
        repository.finalizeChunk(
            chunkId: chunkId,
            sessionId: sessionId,
            endAt: startAt.addingTimeInterval(3),
            durationSec: 3,
            sizeBytes: 1234
        )
        repository.saveTranscript(
            sessionId: sessionId,
            chunkId: chunkId,
            text: "apple banana"
        )

        var filter = SearchFilter()
        filter.query = "banana"
        let result = searchService.search(filter: filter, page: 0)

        XCTAssertEqual(result.totalCount, 1)
        XCTAssertEqual(result.segments.first?.sessionId, sessionId)
    }

    func testFTSIndexRemovesSegmentsOnRetranscriptionReset() {
        let sessionId = repository.createSession(languageMode: .auto)
        let chunkId = UUID()
        let startAt = Date()

        repository.createOrUpdateChunkStarted(
            chunkId: chunkId,
            sessionId: sessionId,
            index: 0,
            startAt: startAt,
            relativePath: "Audio/\(sessionId.uuidString)/0000.m4a"
        )
        repository.finalizeChunk(
            chunkId: chunkId,
            sessionId: sessionId,
            endAt: startAt.addingTimeInterval(3),
            durationSec: 3,
            sizeBytes: 1234
        )
        repository.saveTranscript(
            sessionId: sessionId,
            chunkId: chunkId,
            text: "stale keyword"
        )

        var filter = SearchFilter()
        filter.query = "stale"
        XCTAssertEqual(searchService.search(filter: filter, page: 0).totalCount, 1)

        repository.resetChunkForRetranscription(chunkId: chunkId, sessionId: sessionId)
        XCTAssertEqual(searchService.search(filter: filter, page: 0).totalCount, 0)
    }
}
