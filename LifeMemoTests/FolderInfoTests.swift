import XCTest
@testable import LifeMemo

final class FolderInfoTests: XCTestCase {

    func testEquality() {
        let id = UUID()
        let f1 = FolderInfo(id: id, name: "Meetings", sortOrder: 0)
        let f2 = FolderInfo(id: id, name: "Meetings", sortOrder: 0)
        XCTAssertEqual(f1, f2)
    }

    func testSortOrderDoesNotAffectIdentity() {
        let id = UUID()
        let f1 = FolderInfo(id: id, name: "A", sortOrder: 0)
        let f2 = FolderInfo(id: id, name: "A", sortOrder: 5)
        // sortOrder is part of Equatable so these are NOT equal
        XCTAssertNotEqual(f1, f2)
    }
}
