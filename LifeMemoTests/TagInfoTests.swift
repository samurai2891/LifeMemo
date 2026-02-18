import XCTest
@testable import LifeMemo

final class TagInfoTests: XCTestCase {

    func testEquality() {
        let id = UUID()
        let tag1 = TagInfo(id: id, name: "Work", colorHex: "#FF0000")
        let tag2 = TagInfo(id: id, name: "Work", colorHex: "#FF0000")
        XCTAssertEqual(tag1, tag2)
    }

    func testInequality() {
        let tag1 = TagInfo(id: UUID(), name: "Work", colorHex: nil)
        let tag2 = TagInfo(id: UUID(), name: "Personal", colorHex: nil)
        XCTAssertNotEqual(tag1, tag2)
    }

    func testHashable() {
        let tag1 = TagInfo(id: UUID(), name: "Work", colorHex: nil)
        let tag2 = TagInfo(id: UUID(), name: "Personal", colorHex: nil)
        let set: Set<TagInfo> = [tag1, tag2, tag1]
        XCTAssertEqual(set.count, 2)
    }
}
