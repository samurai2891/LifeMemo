import XCTest
@testable import LifeMemo

final class ExportOptionsTests: XCTestCase {

    func testDefaultOptions() {
        let options = ExportOptions()
        XCTAssertTrue(options.includeMetadata)
        XCTAssertTrue(options.includeSummary)
        XCTAssertTrue(options.includeTranscript)
        XCTAssertEqual(options.format, .markdown)
    }

    func testMinimalOptions() {
        let options = ExportOptions.minimal
        XCTAssertFalse(options.includeSummary)
        XCTAssertEqual(options.format, .text)
    }

    func testAllFormatsHaveExtensions() {
        for format in ExportOptions.ExportFormat.allCases {
            XCTAssertFalse(format.fileExtension.isEmpty)
            XCTAssertFalse(format.icon.isEmpty)
        }
    }

    func testJsonFormat() {
        let format = ExportOptions.ExportFormat.json
        XCTAssertEqual(format.fileExtension, "json")
        XCTAssertEqual(format.rawValue, "JSON")
    }
}
