import XCTest
@testable import LifeMemo

final class LiveEditReconcilerTests: XCTestCase {

    private let reconciler = LiveEditReconciler()

    // MARK: - Reconciliation

    func testReconcileMatchesSimilarText() {
        let segmentId = UUID()
        let records = [
            LiveEditRecord(
                id: UUID(),
                liveSegmentId: UUID(),
                sequenceIndex: 0,
                originalText: "today we talked about the weather forecast",
                editedText: "Today we talked about the weather forecast in Tokyo",
                editedAt: Date()
            )
        ]
        let finalSegments: [(id: UUID, text: String)] = [
            (id: segmentId, text: "today we talked about the weather forecast and temperature")
        ]

        let matches = reconciler.reconcile(editRecords: records, finalSegments: finalSegments)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].segmentId, segmentId)
        XCTAssertEqual(matches[0].editedText, "Today we talked about the weather forecast in Tokyo")
        XCTAssertGreaterThan(matches[0].confidence, 0.3)
    }

    func testReconcileRejectsLowSimilarity() {
        let records = [
            LiveEditRecord(
                id: UUID(),
                liveSegmentId: UUID(),
                sequenceIndex: 0,
                originalText: "apple banana cherry",
                editedText: "apple banana cherry delight",
                editedAt: Date()
            )
        ]
        let finalSegments: [(id: UUID, text: String)] = [
            (id: UUID(), text: "xyz completely different text nothing in common")
        ]

        let matches = reconciler.reconcile(editRecords: records, finalSegments: finalSegments)

        XCTAssertTrue(matches.isEmpty, "Should reject when similarity is below threshold")
    }

    func testReconcileHandlesEmptyInputs() {
        let emptyRecords: [LiveEditRecord] = []
        let emptySegments: [(id: UUID, text: String)] = []

        XCTAssertTrue(reconciler.reconcile(editRecords: emptyRecords, finalSegments: emptySegments).isEmpty)
        XCTAssertTrue(reconciler.reconcile(
            editRecords: emptyRecords,
            finalSegments: [(id: UUID(), text: "text")]
        ).isEmpty)
        XCTAssertTrue(reconciler.reconcile(
            editRecords: [LiveEditRecord(
                id: UUID(), liveSegmentId: UUID(), sequenceIndex: 0,
                originalText: "a", editedText: "b", editedAt: Date()
            )],
            finalSegments: emptySegments
        ).isEmpty)
    }

    func testReconcilePreventsDuplicateMatches() {
        let segId1 = UUID()
        let segId2 = UUID()

        let records = [
            LiveEditRecord(
                id: UUID(), liveSegmentId: UUID(), sequenceIndex: 0,
                originalText: "shared similar text content here",
                editedText: "Edit A",
                editedAt: Date()
            ),
            LiveEditRecord(
                id: UUID(), liveSegmentId: UUID(), sequenceIndex: 1,
                originalText: "shared similar text content here",
                editedText: "Edit B",
                editedAt: Date()
            )
        ]
        let finalSegments: [(id: UUID, text: String)] = [
            (id: segId1, text: "shared similar text content here now"),
            (id: segId2, text: "shared similar text content here today")
        ]

        let matches = reconciler.reconcile(editRecords: records, finalSegments: finalSegments)

        // Each final segment should be matched at most once
        let matchedIds = matches.map(\.segmentId)
        XCTAssertEqual(Set(matchedIds).count, matchedIds.count, "No duplicate segment matches")
    }

    // MARK: - Text Similarity

    func testTextSimilarityIdentical() {
        let score = reconciler.textSimilarity("hello world", "hello world")
        XCTAssertEqual(score, 1.0, accuracy: 0.001)
    }

    func testTextSimilarityDisjoint() {
        let score = reconciler.textSimilarity("apple banana", "cherry date")
        XCTAssertEqual(score, 0.0, accuracy: 0.001)
    }

    func testTextSimilarityPartialOverlap() {
        let score = reconciler.textSimilarity("apple banana cherry", "banana cherry date")
        // Intersection: {banana, cherry} = 2, Union: {apple, banana, cherry, date} = 4
        XCTAssertEqual(score, 0.5, accuracy: 0.001)
    }

    func testTextSimilarityBothEmpty() {
        let score = reconciler.textSimilarity("", "")
        XCTAssertEqual(score, 0.0, accuracy: 0.001)
    }

    func testTextSimilarityCaseInsensitive() {
        let score = reconciler.textSimilarity("Hello World", "hello world")
        XCTAssertEqual(score, 1.0, accuracy: 0.001)
    }
}
