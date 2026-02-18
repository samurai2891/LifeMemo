import XCTest
@testable import LifeMemo

final class SessionSummaryTests: XCTestCase {

    // MARK: - Full Initialization

    func testSessionSummaryFields() {
        let now = Date()
        let tags = [
            TagInfo(id: UUID(), name: "Work", colorHex: "#0000FF"),
            TagInfo(id: UUID(), name: "Meeting", colorHex: nil),
        ]

        let summary = SessionSummary(
            id: UUID(),
            title: "Test Session",
            createdAt: now,
            startedAt: now,
            endedAt: now.addingTimeInterval(3600),
            status: .ready,
            audioKept: true,
            languageMode: "auto",
            summary: "A test summary",
            chunkCount: 5,
            transcriptPreview: "Hello world...",
            bodyText: "My notes here",
            tags: tags,
            folderName: "Work",
            placeName: "Tokyo, Japan"
        )

        XCTAssertEqual(summary.title, "Test Session")
        XCTAssertEqual(summary.status, .ready)
        XCTAssertEqual(summary.chunkCount, 5)
        XCTAssertEqual(summary.transcriptPreview, "Hello world...")
        XCTAssertTrue(summary.audioKept)
        XCTAssertEqual(summary.languageMode, "auto")
        XCTAssertEqual(summary.summary, "A test summary")
        XCTAssertEqual(summary.bodyText, "My notes here")
        XCTAssertEqual(summary.tags.count, 2)
        XCTAssertEqual(summary.tags[0].name, "Work")
        XCTAssertEqual(summary.tags[1].colorHex, nil)
        XCTAssertEqual(summary.folderName, "Work")
        XCTAssertEqual(summary.placeName, "Tokyo, Japan")
        XCTAssertNotNil(summary.endedAt)
    }

    // MARK: - Optional Fields as Nil

    func testSessionSummaryOptionalFieldsNil() {
        let summary = SessionSummary(
            id: UUID(),
            title: "",
            createdAt: Date(),
            startedAt: Date(),
            endedAt: nil,
            status: .idle,
            audioKept: false,
            languageMode: "auto",
            summary: nil,
            chunkCount: 0,
            transcriptPreview: nil,
            bodyText: nil,
            tags: [],
            folderName: nil,
            placeName: nil
        )

        XCTAssertTrue(summary.title.isEmpty)
        XCTAssertNil(summary.endedAt)
        XCTAssertEqual(summary.status, .idle)
        XCTAssertFalse(summary.audioKept)
        XCTAssertNil(summary.summary)
        XCTAssertEqual(summary.chunkCount, 0)
        XCTAssertNil(summary.transcriptPreview)
        XCTAssertNil(summary.bodyText)
        XCTAssertTrue(summary.tags.isEmpty)
        XCTAssertNil(summary.folderName)
        XCTAssertNil(summary.placeName)
    }

    // MARK: - Identifiable Conformance

    func testSessionSummaryIdentifiable() {
        let id = UUID()
        let summary = SessionSummary(
            id: id,
            title: "ID Test",
            createdAt: Date(),
            startedAt: Date(),
            endedAt: nil,
            status: .recording,
            audioKept: true,
            languageMode: "en-US",
            summary: nil,
            chunkCount: 1,
            transcriptPreview: nil,
            bodyText: nil,
            tags: [],
            folderName: nil,
            placeName: nil
        )

        XCTAssertEqual(summary.id, id)
    }
}
