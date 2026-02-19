import XCTest
@testable import LifeMemo

final class SpeakerSummarizationTests: XCTestCase {

    // MARK: - ExportSegment Tests

    func testExportSegmentWithSpeakerName() {
        let segment = ExportSegment(
            speakerIndex: 0,
            speakerName: "Alice",
            text: "Hello world",
            startMs: 0,
            endMs: 2000
        )

        XCTAssertEqual(segment.speakerIndex, 0)
        XCTAssertEqual(segment.speakerName, "Alice")
        XCTAssertEqual(segment.text, "Hello world")
    }

    func testExportSegmentWithoutSpeakerName() {
        let segment = ExportSegment(
            speakerIndex: 1,
            speakerName: nil,
            text: "Testing",
            startMs: 1000,
            endMs: 3000
        )

        XCTAssertEqual(segment.speakerIndex, 1)
        XCTAssertNil(segment.speakerName)
    }

    // MARK: - ExportModel hasSpeakerSegments

    func testHasSpeakerSegmentsWithValidData() {
        let model = ExportModel(
            title: "Test",
            startedAt: Date(),
            endedAt: nil,
            languageMode: "en",
            audioKept: true,
            summaryMarkdown: nil,
            fullTranscript: "text",
            highlights: [],
            bodyText: nil,
            tags: [],
            folderName: nil,
            locationName: nil,
            speakerSegments: [
                ExportSegment(speakerIndex: 0, speakerName: "A", text: "Hello", startMs: 0, endMs: 1000),
                ExportSegment(speakerIndex: 1, speakerName: "B", text: "World", startMs: 1000, endMs: 2000),
            ]
        )

        XCTAssertTrue(model.hasSpeakerSegments)
    }

    func testHasSpeakerSegmentsWithNoSegments() {
        let model = ExportModel(
            title: "Test",
            startedAt: Date(),
            endedAt: nil,
            languageMode: "en",
            audioKept: true,
            summaryMarkdown: nil,
            fullTranscript: "text",
            highlights: [],
            bodyText: nil,
            tags: [],
            folderName: nil,
            locationName: nil
        )

        XCTAssertFalse(model.hasSpeakerSegments)
    }

    // MARK: - Speaker Statistics Calculation

    func testWordCountCalculation() {
        // Verify that word splitting works correctly for statistics
        let text1 = "Hello world how are you"  // 5 words
        let text2 = "I am fine"                 // 3 words

        let count1 = text1.split(separator: " ").count
        let count2 = text2.split(separator: " ").count

        XCTAssertEqual(count1, 5)
        XCTAssertEqual(count2, 3)

        let total = count1 + count2
        let pct1 = Int(round(Double(count1) / Double(total) * 100))
        let pct2 = Int(round(Double(count2) / Double(total) * 100))

        XCTAssertEqual(pct1, 63)  // 5/8 = 62.5 -> 63
        XCTAssertEqual(pct2, 38)  // 3/8 = 37.5 -> 38
    }

    // MARK: - DiarizationResult with Profiles

    func testDiarizationResultBackwardCompatible() {
        let result = DiarizationResult(segments: [], speakerCount: 1)
        XCTAssertTrue(result.speakerProfiles.isEmpty)
    }

    func testDiarizationResultWithProfiles() {
        let profiles = [
            SpeakerProfile(
                id: UUID(),
                speakerIndex: 0,
                centroid: SpeakerFeatureVector(
                    meanPitch: 150, pitchStdDev: 30, meanEnergy: 0.5,
                    meanSpectralCentroid: 800, meanJitter: 0.02, meanShimmer: 0.04
                ),
                sampleCount: 5
            )
        ]

        let result = DiarizationResult(
            segments: [],
            speakerCount: 1,
            speakerProfiles: profiles
        )

        XCTAssertEqual(result.speakerProfiles.count, 1)
        XCTAssertEqual(result.speakerProfiles[0].speakerIndex, 0)
    }

    // MARK: - SearchResult with Speaker Name

    func testSearchResultBackwardCompatible() {
        let result = SearchResult(
            id: UUID(),
            sessionId: UUID(),
            segmentText: "test",
            startMs: 0,
            endMs: 1000,
            sessionTitle: "Session"
        )
        XCTAssertNil(result.speakerName)
    }

    func testSearchResultWithSpeakerName() {
        let result = SearchResult(
            id: UUID(),
            sessionId: UUID(),
            segmentText: "test",
            startMs: 0,
            endMs: 1000,
            sessionTitle: "Session",
            speakerName: "Alice"
        )
        XCTAssertEqual(result.speakerName, "Alice")
    }
}
