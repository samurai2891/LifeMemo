import XCTest
import CoreData
@testable import LifeMemo

@MainActor
final class EditHistoryIntegrationTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!
    private var repository: SessionRepository!

    override func setUp() {
        super.setUp()
        let model = CoreDataStack.createManagedObjectModel()
        container = NSPersistentContainer(name: "EditHistoryTest", managedObjectModel: model)
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
    }

    override func tearDown() {
        context?.reset()
        repository = nil
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - First Edit Creates History Entry

    func testFirstEditCreatesHistoryEntry() {
        let (_, segmentId) = createSessionWithSegment(text: "Original text")

        repository.updateSegmentText(segmentId: segmentId, newText: "Edited text")

        let segment = fetchSegment(id: segmentId)
        XCTAssertNotNil(segment, "Segment should exist")

        let history = segment?.editHistoryArray ?? []
        XCTAssertEqual(history.count, 1, "Should have exactly 1 history entry")

        let entry = history.first
        XCTAssertEqual(entry?.previousText, "Original text")
        XCTAssertEqual(entry?.newText, "Edited text")
        XCTAssertEqual(entry?.editIndex, 1)
    }

    // MARK: - Multiple Edits Create Sequential History

    func testMultipleEditsCreateSequentialHistory() {
        let (_, segmentId) = createSessionWithSegment(text: "Version 0")

        repository.updateSegmentText(segmentId: segmentId, newText: "Version 1")
        repository.updateSegmentText(segmentId: segmentId, newText: "Version 2")
        repository.updateSegmentText(segmentId: segmentId, newText: "Version 3")

        let segment = fetchSegment(id: segmentId)
        let history = segment?.editHistoryArray ?? []

        XCTAssertEqual(history.count, 3, "Should have 3 history entries")
        XCTAssertEqual(history[0].editIndex, 1)
        XCTAssertEqual(history[1].editIndex, 2)
        XCTAssertEqual(history[2].editIndex, 3)

        XCTAssertEqual(history[0].previousText, "Version 0")
        XCTAssertEqual(history[0].newText, "Version 1")

        XCTAssertEqual(history[1].previousText, "Version 1")
        XCTAssertEqual(history[1].newText, "Version 2")

        XCTAssertEqual(history[2].previousText, "Version 2")
        XCTAssertEqual(history[2].newText, "Version 3")
    }

    // MARK: - Original Text Preserved on First Edit

    func testOriginalTextPreservedOnFirstEdit() {
        let (_, segmentId) = createSessionWithSegment(text: "The original")

        repository.updateSegmentText(segmentId: segmentId, newText: "First edit")
        var segment = fetchSegment(id: segmentId)
        XCTAssertEqual(segment?.originalText, "The original")

        repository.updateSegmentText(segmentId: segmentId, newText: "Second edit")
        segment = fetchSegment(id: segmentId)
        XCTAssertEqual(
            segment?.originalText,
            "The original",
            "originalText must not change on subsequent edits"
        )

        repository.updateSegmentText(segmentId: segmentId, newText: "Third edit")
        segment = fetchSegment(id: segmentId)
        XCTAssertEqual(segment?.originalText, "The original")
    }

    // MARK: - Fetch Edit History Returns Sorted Entries

    func testFetchEditHistoryReturnsSortedEntries() {
        let (_, segmentId) = createSessionWithSegment(text: "Start")

        repository.updateSegmentText(segmentId: segmentId, newText: "Alpha")
        repository.updateSegmentText(segmentId: segmentId, newText: "Beta")
        repository.updateSegmentText(segmentId: segmentId, newText: "Gamma")

        let history = repository.fetchEditHistory(segmentId: segmentId)

        XCTAssertEqual(history.count, 3)

        // Verify sorted ascending by editIndex
        for i in 0..<(history.count - 1) {
            XCTAssertLessThan(
                history[i].editIndex,
                history[i + 1].editIndex,
                "History entries should be sorted by editIndex ascending"
            )
        }

        XCTAssertEqual(history[0].editIndex, 1)
        XCTAssertEqual(history[1].editIndex, 2)
        XCTAssertEqual(history[2].editIndex, 3)
    }

    // MARK: - Fetch Edit History for Unedited Segment

    func testFetchEditHistoryForUneditedSegment() {
        let (_, segmentId) = createSessionWithSegment(text: "Never edited")

        let history = repository.fetchEditHistory(segmentId: segmentId)

        XCTAssertTrue(history.isEmpty, "Unedited segment should have empty edit history")
    }

    // MARK: - Revert to Specific Version

    func testRevertToSpecificVersion() {
        let (_, segmentId) = createSessionWithSegment(text: "Version 0")

        repository.updateSegmentText(segmentId: segmentId, newText: "Version 1")
        repository.updateSegmentText(segmentId: segmentId, newText: "Version 2")
        repository.updateSegmentText(segmentId: segmentId, newText: "Version 3")

        // Get the third edit's history entry ID so we can revert it.
        // revertSegment reverts to the state BEFORE the target entry,
        // so targeting edit #3 restores text to "Version 2" and deletes edit #3.
        let history = repository.fetchEditHistory(segmentId: segmentId)
        let thirdEntryId = history.first(where: { $0.editIndex == 3 })!.id

        repository.revertSegment(segmentId: segmentId, toHistoryEntryId: thirdEntryId)

        let segment = fetchSegment(id: segmentId)
        XCTAssertEqual(
            segment?.text,
            "Version 2",
            "Text should revert to the state before the target edit"
        )
        XCTAssertTrue(
            segment?.isUserEdited == true,
            "Segment should still be marked as user-edited"
        )

        let remainingHistory = segment?.editHistoryArray ?? []
        XCTAssertEqual(remainingHistory.count, 2, "Only edits #1 and #2 should remain")
        XCTAssertEqual(remainingHistory[0].editIndex, 1)
        XCTAssertEqual(remainingHistory[1].editIndex, 2)
    }

    // MARK: - Revert to Original

    func testRevertToOriginal() {
        let (_, segmentId) = createSessionWithSegment(text: "The original text")

        repository.updateSegmentText(segmentId: segmentId, newText: "Edit 1")
        repository.updateSegmentText(segmentId: segmentId, newText: "Edit 2")
        repository.updateSegmentText(segmentId: segmentId, newText: "Edit 3")

        repository.revertSegmentToOriginal(segmentId: segmentId)

        let segment = fetchSegment(id: segmentId)
        XCTAssertEqual(
            segment?.text,
            "The original text",
            "Text should match the original"
        )
        XCTAssertFalse(
            segment?.isUserEdited ?? true,
            "isUserEdited should be false after full revert"
        )

        let history = segment?.editHistoryArray ?? []
        XCTAssertTrue(history.isEmpty, "All history entries should be deleted on full revert")
    }

    // MARK: - Revert First Edit Clears Edited Flag

    func testRevertFirstEditClearsEditedFlag() {
        let (_, segmentId) = createSessionWithSegment(text: "Original")

        repository.updateSegmentText(segmentId: segmentId, newText: "Only edit")

        repository.revertSegmentToOriginal(segmentId: segmentId)

        let segment = fetchSegment(id: segmentId)
        XCTAssertEqual(segment?.text, "Original")
        XCTAssertFalse(
            segment?.isUserEdited ?? true,
            "isUserEdited should be false when the only edit is reverted"
        )
        XCTAssertTrue(
            (segment?.editHistoryArray ?? []).isEmpty,
            "History should be empty after reverting the only edit"
        )
    }

    // MARK: - Edit History Deleted with Segment (Cascade)

    func testEditHistoryDeletedWithSegment() {
        let (sessionId, segmentId) = createSessionWithSegment(text: "To be deleted")

        repository.updateSegmentText(segmentId: segmentId, newText: "Edit 1")
        repository.updateSegmentText(segmentId: segmentId, newText: "Edit 2")

        // Verify history exists before deletion
        let historyBefore = fetchAllEditHistoryEntities()
        XCTAssertEqual(historyBefore.count, 2, "Should have 2 history entries before deletion")

        // Delete the entire session (cascades to segments, which cascades to edit history)
        repository.deleteSessionCompletely(sessionId: sessionId)

        let historyAfter = fetchAllEditHistoryEntities()
        XCTAssertTrue(
            historyAfter.isEmpty,
            "All edit history entries should be deleted when segment is cascade-deleted"
        )
    }

    // MARK: - Edit History Entity <-> Domain Conversion

    func testEditHistoryEntityToEntryConversion() {
        let segmentId = UUID()
        let context: NSManagedObjectContext = self.context

        let entity = EditHistoryEntity(context: context)
        entity.id = UUID()
        entity.previousText = "Before"
        entity.newText = "After"
        entity.editedAt = Date()
        entity.editIndex = 5

        let entry = entity.toEntry(segmentId: segmentId)

        XCTAssertEqual(entry.segmentId, segmentId)
        XCTAssertEqual(entry.previousText, "Before")
        XCTAssertEqual(entry.newText, "After")
        XCTAssertEqual(entry.editIndex, 5)
        XCTAssertEqual(entry.id, entity.id)
    }

    func testEditHistoryEntityToEntryDefaultsForNil() {
        let segmentId = UUID()
        let context: NSManagedObjectContext = self.context

        let entity = EditHistoryEntity(context: context)
        // Leave all properties nil (except editIndex which defaults to 0)

        let entry = entity.toEntry(segmentId: segmentId)

        XCTAssertEqual(entry.previousText, "", "Nil previousText should default to empty string")
        XCTAssertEqual(entry.newText, "", "Nil newText should default to empty string")
        XCTAssertEqual(entry.editIndex, 0)
        XCTAssertNotNil(entry.id, "Should generate a UUID when entity.id is nil")
    }

    // MARK: - Edit History Array Sorting

    func testEditHistoryArraySortedByEditIndex() {
        let (_, segmentId) = createSessionWithSegment(text: "Base")
        let segment = fetchSegment(id: segmentId)!
        let context: NSManagedObjectContext = self.context

        // Create entries in reverse order to test sorting
        let entry3 = EditHistoryEntity(context: context)
        entry3.id = UUID()
        entry3.previousText = "B"
        entry3.newText = "C"
        entry3.editedAt = Date()
        entry3.editIndex = 3
        entry3.segment = segment

        let entry1 = EditHistoryEntity(context: context)
        entry1.id = UUID()
        entry1.previousText = "Base"
        entry1.newText = "A"
        entry1.editedAt = Date()
        entry1.editIndex = 1
        entry1.segment = segment

        let entry2 = EditHistoryEntity(context: context)
        entry2.id = UUID()
        entry2.previousText = "A"
        entry2.newText = "B"
        entry2.editedAt = Date()
        entry2.editIndex = 2
        entry2.segment = segment

        try? context.save()

        let sorted = segment.editHistoryArray
        XCTAssertEqual(sorted.count, 3)
        XCTAssertEqual(sorted[0].editIndex, 1)
        XCTAssertEqual(sorted[1].editIndex, 2)
        XCTAssertEqual(sorted[2].editIndex, 3)
    }

    // MARK: - Segment isUserEdited Flag

    func testSegmentIsUserEditedSetOnFirstEdit() {
        let (_, segmentId) = createSessionWithSegment(text: "Untouched")

        let segmentBefore = fetchSegment(id: segmentId)
        XCTAssertFalse(
            segmentBefore?.isUserEdited ?? true,
            "New segment should not be marked as user-edited"
        )

        repository.updateSegmentText(segmentId: segmentId, newText: "Touched")

        let segmentAfter = fetchSegment(id: segmentId)
        XCTAssertTrue(
            segmentAfter?.isUserEdited ?? false,
            "Segment should be marked as user-edited after update"
        )
    }

    // MARK: - Revert Via revertSegment Restores Unedited State For First Entry

    func testRevertViaHistoryEntryIdResetsEditedFlagWhenFirstEntry() {
        let (_, segmentId) = createSessionWithSegment(text: "Original")

        repository.updateSegmentText(segmentId: segmentId, newText: "Changed")

        let history = repository.fetchEditHistory(segmentId: segmentId)
        XCTAssertEqual(history.count, 1)
        let firstEntryId = history[0].id

        repository.revertSegment(segmentId: segmentId, toHistoryEntryId: firstEntryId)

        let segment = fetchSegment(id: segmentId)
        XCTAssertEqual(segment?.text, "Original")
        XCTAssertFalse(
            segment?.isUserEdited ?? true,
            "Reverting the first edit via revertSegment should clear isUserEdited"
        )
        XCTAssertTrue(
            (segment?.editHistoryArray ?? []).isEmpty,
            "All history should be deleted when reverting to first entry"
        )
    }

    // MARK: - Fetch Edit History for Non-Existent Segment

    func testFetchEditHistoryForNonExistentSegment() {
        let history = repository.fetchEditHistory(segmentId: UUID())
        XCTAssertTrue(history.isEmpty, "Non-existent segment should return empty history")
    }

    // MARK: - Private Helpers

    /// Creates a session with a single transcript segment, returning both IDs.
    private func createSessionWithSegment(text: String) -> (sessionId: UUID, segmentId: UUID) {
        let context: NSManagedObjectContext = self.context

        let session = SessionEntity(context: context)
        let sessionId = UUID()
        session.id = sessionId
        session.createdAt = Date()
        session.startedAt = Date()
        session.title = "Test Session"
        session.languageModeRaw = "auto"
        session.statusRaw = Int16(2) // .ready
        session.audioKept = true

        let segment = TranscriptSegmentEntity(context: context)
        let segmentId = UUID()
        segment.id = segmentId
        segment.text = text
        segment.startMs = 0
        segment.endMs = 60000
        segment.createdAt = Date()
        segment.isUserEdited = false
        segment.session = session

        try? context.save()
        return (sessionId, segmentId)
    }

    private func fetchSegment(id: UUID) -> TranscriptSegmentEntity? {
        let request = NSFetchRequest<TranscriptSegmentEntity>(
            entityName: "TranscriptSegmentEntity"
        )
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private func fetchAllEditHistoryEntities() -> [EditHistoryEntity] {
        let request = NSFetchRequest<EditHistoryEntity>(entityName: "EditHistoryEntity")
        return (try? context.fetch(request)) ?? []
    }
}
