import XCTest
@testable import LifeMemo

final class ExportSpeakerLabelTests: XCTestCase {

    private func makeModel(withSpeakers: Bool) -> ExportModel {
        let segments: [ExportSegment] = withSpeakers
            ? [
                ExportSegment(speakerIndex: 0, speakerName: "Alice", text: "Hello there.", startMs: 0, endMs: 2000),
                ExportSegment(speakerIndex: 1, speakerName: "Bob", text: "Hi Alice!", startMs: 2500, endMs: 4000),
                ExportSegment(speakerIndex: 0, speakerName: "Alice", text: "How are you?", startMs: 4500, endMs: 6000),
            ]
            : []

        return ExportModel(
            title: "Test Session",
            startedAt: Date(),
            endedAt: Date(),
            languageMode: "en",
            audioKept: true,
            summaryMarkdown: nil,
            fullTranscript: "Hello there. Hi Alice! How are you?",
            highlights: [],
            bodyText: nil,
            tags: [],
            folderName: nil,
            locationName: nil,
            speakerSegments: segments
        )
    }

    // MARK: - Markdown

    func testMarkdownIncludesSpeakerLabels() {
        let model = makeModel(withSpeakers: true)
        let md = MarkdownExporter.make(model: model)

        XCTAssertTrue(md.contains("**Alice**"))
        XCTAssertTrue(md.contains("**Bob**"))
        XCTAssertTrue(md.contains("[00:00]"))
    }

    func testMarkdownWithoutSpeakersUsesFullTranscript() {
        let model = makeModel(withSpeakers: false)
        let md = MarkdownExporter.make(model: model)

        XCTAssertTrue(md.contains("Hello there. Hi Alice! How are you?"))
        XCTAssertFalse(md.contains("**Alice**"))
    }

    // MARK: - Text

    func testTextIncludesSpeakerLabels() {
        let model = makeModel(withSpeakers: true)
        let txt = TextExporter.make(model: model)

        XCTAssertTrue(txt.contains("[Alice]"))
        XCTAssertTrue(txt.contains("[Bob]"))
    }

    func testTextWithoutSpeakersUsesFullTranscript() {
        let model = makeModel(withSpeakers: false)
        let txt = TextExporter.make(model: model)

        XCTAssertTrue(txt.contains("Hello there. Hi Alice! How are you?"))
        XCTAssertFalse(txt.contains("[Alice]"))
    }

    // MARK: - JSON

    func testJSONIncludesSpeakerSegments() {
        let model = makeModel(withSpeakers: true)
        let options = ExportOptions.full
        let json = JSONExporter.make(model: model, options: options)

        XCTAssertTrue(json.contains("\"speakerIndex\""))
        XCTAssertTrue(json.contains("\"speakerName\""))
        XCTAssertTrue(json.contains("Alice"))
        XCTAssertTrue(json.contains("Bob"))
    }

    func testJSONWithoutSpeakersOmitsSegments() {
        let model = makeModel(withSpeakers: false)
        let options = ExportOptions.full
        let json = JSONExporter.make(model: model, options: options)

        // segments should be null/absent when no speaker data
        XCTAssertFalse(json.contains("\"speakerIndex\""))
    }

    // MARK: - ExportModel Helpers

    func testHasSpeakerSegmentsTrue() {
        let model = makeModel(withSpeakers: true)
        XCTAssertTrue(model.hasSpeakerSegments)
    }

    func testHasSpeakerSegmentsFalseWhenEmpty() {
        let model = makeModel(withSpeakers: false)
        XCTAssertFalse(model.hasSpeakerSegments)
    }

    func testHasSpeakerSegmentsFalseWhenAllNegativeOne() {
        let segments = [
            ExportSegment(speakerIndex: -1, speakerName: nil, text: "text", startMs: 0, endMs: 1000)
        ]
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
            speakerSegments: segments
        )
        XCTAssertFalse(model.hasSpeakerSegments)
    }

    // MARK: - Default Speaker Names

    func testDefaultSpeakerNameWhenNoCustomName() {
        let segments = [
            ExportSegment(speakerIndex: 0, speakerName: nil, text: "Hello", startMs: 0, endMs: 1000),
            ExportSegment(speakerIndex: 1, speakerName: nil, text: "World", startMs: 1000, endMs: 2000),
        ]
        let model = ExportModel(
            title: "Test",
            startedAt: Date(),
            endedAt: nil,
            languageMode: "en",
            audioKept: true,
            summaryMarkdown: nil,
            fullTranscript: "Hello World",
            highlights: [],
            bodyText: nil,
            tags: [],
            folderName: nil,
            locationName: nil,
            speakerSegments: segments
        )

        let md = MarkdownExporter.make(model: model)
        XCTAssertTrue(md.contains("**Speaker 1**"))
        XCTAssertTrue(md.contains("**Speaker 2**"))
    }
}
