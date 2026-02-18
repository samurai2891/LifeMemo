import XCTest
@testable import LifeMemo

final class EditHistoryTests: XCTestCase {

    // MARK: - Equality

    func testEditHistoryEntryEquality() {
        let id = UUID()
        let segmentId = UUID()
        let date = Date()

        let entry1 = EditHistoryEntry(
            id: id,
            segmentId: segmentId,
            previousText: "Hello",
            newText: "Hello World",
            editedAt: date,
            editIndex: 1
        )

        let entry2 = EditHistoryEntry(
            id: id,
            segmentId: segmentId,
            previousText: "Hello",
            newText: "Hello World",
            editedAt: date,
            editIndex: 1
        )

        XCTAssertEqual(entry1, entry2)
    }

    func testEditHistoryEntryInequalityById() {
        let segmentId = UUID()
        let date = Date()

        let entry1 = EditHistoryEntry(
            id: UUID(),
            segmentId: segmentId,
            previousText: "Hello",
            newText: "Hello World",
            editedAt: date,
            editIndex: 1
        )

        let entry2 = EditHistoryEntry(
            id: UUID(),
            segmentId: segmentId,
            previousText: "Hello",
            newText: "Hello World",
            editedAt: date,
            editIndex: 1
        )

        XCTAssertNotEqual(entry1, entry2)
    }

    func testEditHistoryEntryInequalityByText() {
        let id = UUID()
        let segmentId = UUID()
        let date = Date()

        let entry1 = EditHistoryEntry(
            id: id,
            segmentId: segmentId,
            previousText: "Hello",
            newText: "Hello World",
            editedAt: date,
            editIndex: 1
        )

        let entry2 = EditHistoryEntry(
            id: id,
            segmentId: segmentId,
            previousText: "Hello",
            newText: "Different Text",
            editedAt: date,
            editIndex: 1
        )

        XCTAssertNotEqual(entry1, entry2)
    }

    func testEditHistoryEntryInequalityByEditIndex() {
        let id = UUID()
        let segmentId = UUID()
        let date = Date()

        let entry1 = EditHistoryEntry(
            id: id,
            segmentId: segmentId,
            previousText: "Hello",
            newText: "World",
            editedAt: date,
            editIndex: 1
        )

        let entry2 = EditHistoryEntry(
            id: id,
            segmentId: segmentId,
            previousText: "Hello",
            newText: "World",
            editedAt: date,
            editIndex: 2
        )

        XCTAssertNotEqual(entry1, entry2)
    }

    // MARK: - Identifiable Conformance

    func testEditHistoryEntryIdentifiable() {
        let id = UUID()
        let entry = EditHistoryEntry(
            id: id,
            segmentId: UUID(),
            previousText: "Old",
            newText: "New",
            editedAt: Date(),
            editIndex: 1
        )

        XCTAssertEqual(entry.id, id)
    }

    func testEditHistoryEntryFieldValues() {
        let id = UUID()
        let segmentId = UUID()
        let date = Date()

        let entry = EditHistoryEntry(
            id: id,
            segmentId: segmentId,
            previousText: "Original text",
            newText: "Updated text",
            editedAt: date,
            editIndex: 3
        )

        XCTAssertEqual(entry.id, id)
        XCTAssertEqual(entry.segmentId, segmentId)
        XCTAssertEqual(entry.previousText, "Original text")
        XCTAssertEqual(entry.newText, "Updated text")
        XCTAssertEqual(entry.editedAt, date)
        XCTAssertEqual(entry.editIndex, 3)
    }
}
