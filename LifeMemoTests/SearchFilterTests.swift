import XCTest
@testable import LifeMemo

final class SearchFilterTests: XCTestCase {

    func testEmptyFilterIsEmpty() {
        let filter = SearchFilter()
        XCTAssertTrue(filter.isEmpty)
        XCTAssertFalse(filter.hasActiveFilters)
    }

    func testQueryMakesNonEmpty() {
        var filter = SearchFilter()
        filter.query = "hello"
        XCTAssertFalse(filter.isEmpty)
    }

    func testWhitespaceQueryIsStillEmpty() {
        var filter = SearchFilter()
        filter.query = "   "
        XCTAssertTrue(filter.isEmpty)
    }

    func testTagNameMakesNonEmpty() {
        var filter = SearchFilter()
        filter.tagName = "Work"
        XCTAssertFalse(filter.isEmpty)
        XCTAssertTrue(filter.hasActiveFilters)
    }

    func testFolderNameMakesNonEmpty() {
        var filter = SearchFilter()
        filter.folderName = "Meetings"
        XCTAssertFalse(filter.isEmpty)
        XCTAssertTrue(filter.hasActiveFilters)
    }

    func testDateFilterIsActive() {
        var filter = SearchFilter()
        filter.dateFrom = Date()
        XCTAssertTrue(filter.hasActiveFilters)
    }

    func testHighlightsOnlyIsActive() {
        var filter = SearchFilter()
        filter.highlightsOnly = true
        XCTAssertTrue(filter.hasActiveFilters)
    }
}
