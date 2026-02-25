import XCTest
@testable import LifeMemo

final class RecognitionModeTests: XCTestCase {

    private let suiteName = "RecognitionModeTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultModeIsOnDevice() {
        XCTAssertEqual(RecognitionMode.load(defaults: defaults), .onDevice)
    }

    func testCanPersistServerAllowedMode() {
        RecognitionMode.save(.serverAllowed, defaults: defaults)
        XCTAssertEqual(RecognitionMode.load(defaults: defaults), .serverAllowed)
    }
}
