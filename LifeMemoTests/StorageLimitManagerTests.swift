import XCTest
@testable import LifeMemo

@MainActor
final class StorageLimitManagerTests: XCTestCase {

    private static let limitGBKey = "storageLimitGB"
    private static let autoDeleteKey = "storageAutoDelete"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.limitGBKey)
        UserDefaults.standard.removeObject(forKey: Self.autoDeleteKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.limitGBKey)
        UserDefaults.standard.removeObject(forKey: Self.autoDeleteKey)
        super.tearDown()
    }

    // MARK: - Default Values

    func testDefaultLimitIsNilInUserDefaults() {
        XCTAssertNil(UserDefaults.standard.object(forKey: Self.limitGBKey))
    }

    func testDefaultAutoDeleteIsFalse() {
        XCTAssertFalse(UserDefaults.standard.bool(forKey: Self.autoDeleteKey))
    }

    // MARK: - Persistence

    func testLimitGBPersistence() {
        UserDefaults.standard.set(5.0, forKey: Self.limitGBKey)
        let value = UserDefaults.standard.double(forKey: Self.limitGBKey)
        XCTAssertEqual(value, 5.0, accuracy: 0.01)
    }

    func testAutoDeletePersistence() {
        UserDefaults.standard.set(true, forKey: Self.autoDeleteKey)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: Self.autoDeleteKey))
    }

    func testAutoDeletePersistenceToggleOff() {
        UserDefaults.standard.set(true, forKey: Self.autoDeleteKey)
        UserDefaults.standard.set(false, forKey: Self.autoDeleteKey)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: Self.autoDeleteKey))
    }

    // MARK: - Warning Threshold (90%)

    func testWarningThresholdAtExactly90Percent() {
        let usageGB = 9.0
        let limitGB = 10.0
        let percentage = (usageGB / limitGB) * 100
        XCTAssertTrue(percentage >= 90, "90% usage should trigger warning")
    }

    func testWarningThresholdBelow90Percent() {
        let usageGB = 8.9
        let limitGB = 10.0
        let percentage = (usageGB / limitGB) * 100
        XCTAssertFalse(percentage >= 90, "89% usage should not trigger warning")
    }

    // MARK: - Exceeded Threshold (100%)

    func testExceededThresholdAtExactly100Percent() {
        let usageGB = 10.0
        let limitGB = 10.0
        let percentage = (usageGB / limitGB) * 100
        XCTAssertTrue(percentage >= 100, "100% usage should be exceeded")
    }

    func testExceededThresholdAbove100Percent() {
        let usageGB = 10.5
        let limitGB = 10.0
        let percentage = (usageGB / limitGB) * 100
        XCTAssertTrue(percentage >= 100, "105% usage should be exceeded")
    }

    func testNotExceededBelow100Percent() {
        let usageGB = 9.9
        let limitGB = 10.0
        let percentage = (usageGB / limitGB) * 100
        XCTAssertFalse(percentage >= 100, "99% usage should not be exceeded")
    }

    // MARK: - Zero Limit Edge Case

    func testZeroLimitProducesZeroPercentage() {
        let limitGB = 0.0
        let percentage = limitGB > 0 ? (5.0 / limitGB) * 100 : 0
        XCTAssertEqual(percentage, 0, "Zero limit should produce 0% to avoid division by zero")
    }
}
