import XCTest
@testable import LifeMemo

final class LiveSegmentTests: XCTestCase {

    // MARK: - LiveSegment

    func testWithTextReturnsNewInstance() {
        let original = LiveSegment(
            id: UUID(),
            text: "Hello world",
            confirmedAt: Date(),
            cycleIndex: 0
        )
        let updated = original.withText("Hello updated")

        XCTAssertEqual(original.id, updated.id, "ID should be preserved")
        XCTAssertEqual(original.confirmedAt, updated.confirmedAt, "confirmedAt should be preserved")
        XCTAssertEqual(original.cycleIndex, updated.cycleIndex, "cycleIndex should be preserved")
        XCTAssertEqual(updated.text, "Hello updated")
        XCTAssertNotEqual(original.text, updated.text, "Original text should not change")
    }

    func testEquality() {
        let id = UUID()
        let date = Date()
        let a = LiveSegment(id: id, text: "Same text", confirmedAt: date, cycleIndex: 1)
        let b = LiveSegment(id: id, text: "Same text", confirmedAt: date, cycleIndex: 1)

        XCTAssertEqual(a, b)
    }

    func testInequalityDifferentText() {
        let id = UUID()
        let date = Date()
        let a = LiveSegment(id: id, text: "Text A", confirmedAt: date, cycleIndex: 0)
        let b = LiveSegment(id: id, text: "Text B", confirmedAt: date, cycleIndex: 0)

        XCTAssertNotEqual(a, b)
    }

    // MARK: - LiveEditRecord

    func testLiveEditRecordCodable() throws {
        let record = LiveEditRecord(
            id: UUID(),
            liveSegmentId: UUID(),
            sequenceIndex: 3,
            originalText: "original text here",
            editedText: "edited text here",
            editedAt: Date()
        )

        let data = try JSONEncoder().encode([record])
        let decoded = try JSONDecoder().decode([LiveEditRecord].self, from: data)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].id, record.id)
        XCTAssertEqual(decoded[0].liveSegmentId, record.liveSegmentId)
        XCTAssertEqual(decoded[0].sequenceIndex, record.sequenceIndex)
        XCTAssertEqual(decoded[0].originalText, record.originalText)
        XCTAssertEqual(decoded[0].editedText, record.editedText)
    }

    func testLiveEditRecordEquality() {
        let id = UUID()
        let segId = UUID()
        let date = Date()
        let a = LiveEditRecord(
            id: id, liveSegmentId: segId, sequenceIndex: 0,
            originalText: "orig", editedText: "edit", editedAt: date
        )
        let b = LiveEditRecord(
            id: id, liveSegmentId: segId, sequenceIndex: 0,
            originalText: "orig", editedText: "edit", editedAt: date
        )
        XCTAssertEqual(a, b)
    }
}
