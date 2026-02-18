import XCTest
import CoreLocation
@testable import LifeMemo

@MainActor
final class LocationPreferenceTests: XCTestCase {

    override func tearDown() {
        // Clean up UserDefaults after each test
        UserDefaults.standard.removeObject(forKey: "lifememo.location.enabled")
        UserDefaults.standard.removeObject(forKey: "lifememo.location.accuracy")
        UserDefaults.standard.removeObject(forKey: "lifememo.location.timing")
        UserDefaults.standard.removeObject(forKey: "lifememo.location.reverseGeocode")
        super.tearDown()
    }

    // MARK: - Default Values

    func testDefaultIsDisabled() {
        XCTAssertFalse(LocationPreference.isEnabled)
    }

    func testDefaultAccuracyIsBalanced() {
        XCTAssertEqual(LocationPreference.accuracy, .balanced)
    }

    func testDefaultTimingIsOnStart() {
        XCTAssertEqual(LocationPreference.captureTiming, .onStart)
    }

    func testDefaultReverseGeocodeIsDisabled() {
        XCTAssertFalse(LocationPreference.reverseGeocodeEnabled)
    }

    // MARK: - Persistence

    func testEnableDisablePersists() {
        LocationPreference.isEnabled = true
        XCTAssertTrue(LocationPreference.isEnabled)
        LocationPreference.isEnabled = false
        XCTAssertFalse(LocationPreference.isEnabled)
    }

    func testAccuracyPersists() {
        LocationPreference.accuracy = .precise
        XCTAssertEqual(LocationPreference.accuracy, .precise)
        LocationPreference.accuracy = .approximate
        XCTAssertEqual(LocationPreference.accuracy, .approximate)
    }

    func testTimingPersists() {
        LocationPreference.captureTiming = .onStop
        XCTAssertEqual(LocationPreference.captureTiming, .onStop)
        LocationPreference.captureTiming = .both
        XCTAssertEqual(LocationPreference.captureTiming, .both)
    }

    func testReverseGeocodePersists() {
        LocationPreference.reverseGeocodeEnabled = true
        XCTAssertTrue(LocationPreference.reverseGeocodeEnabled)
        LocationPreference.reverseGeocodeEnabled = false
        XCTAssertFalse(LocationPreference.reverseGeocodeEnabled)
    }

    // MARK: - Accuracy Enum

    func testAccuracyAllCasesCount() {
        XCTAssertEqual(LocationPreference.Accuracy.allCases.count, 3)
    }

    func testAccuracyDisplayNames() {
        XCTAssertFalse(LocationPreference.Accuracy.approximate.displayName.isEmpty)
        XCTAssertFalse(LocationPreference.Accuracy.balanced.displayName.isEmpty)
        XCTAssertFalse(LocationPreference.Accuracy.precise.displayName.isEmpty)
    }

    func testAccuracyCLValues() {
        XCTAssertEqual(LocationPreference.Accuracy.approximate.clAccuracy, kCLLocationAccuracyThreeKilometers)
        XCTAssertEqual(LocationPreference.Accuracy.balanced.clAccuracy, kCLLocationAccuracyHundredMeters)
        XCTAssertEqual(LocationPreference.Accuracy.precise.clAccuracy, kCLLocationAccuracyNearestTenMeters)
    }

    func testAccuracyIdentifiable() {
        for accuracy in LocationPreference.Accuracy.allCases {
            XCTAssertEqual(accuracy.id, accuracy.rawValue)
        }
    }

    func testAccuracyRawValues() {
        XCTAssertEqual(LocationPreference.Accuracy.approximate.rawValue, "approximate")
        XCTAssertEqual(LocationPreference.Accuracy.balanced.rawValue, "balanced")
        XCTAssertEqual(LocationPreference.Accuracy.precise.rawValue, "precise")
    }

    // MARK: - CaptureTiming Enum

    func testCaptureTimingAllCasesCount() {
        XCTAssertEqual(LocationPreference.CaptureTiming.allCases.count, 3)
    }

    func testCaptureTimingDisplayNames() {
        XCTAssertFalse(LocationPreference.CaptureTiming.onStart.displayName.isEmpty)
        XCTAssertFalse(LocationPreference.CaptureTiming.onStop.displayName.isEmpty)
        XCTAssertFalse(LocationPreference.CaptureTiming.both.displayName.isEmpty)
    }

    func testCaptureTimingIdentifiable() {
        for timing in LocationPreference.CaptureTiming.allCases {
            XCTAssertEqual(timing.id, timing.rawValue)
        }
    }

    func testCaptureTimingRawValues() {
        XCTAssertEqual(LocationPreference.CaptureTiming.onStart.rawValue, "start")
        XCTAssertEqual(LocationPreference.CaptureTiming.onStop.rawValue, "stop")
        XCTAssertEqual(LocationPreference.CaptureTiming.both.rawValue, "both")
    }

    // MARK: - Invalid UserDefaults Values

    func testInvalidAccuracyDefaultsToBalanced() {
        UserDefaults.standard.set("invalid", forKey: "lifememo.location.accuracy")
        XCTAssertEqual(LocationPreference.accuracy, .balanced)
    }

    func testInvalidTimingDefaultsToOnStart() {
        UserDefaults.standard.set("invalid", forKey: "lifememo.location.timing")
        XCTAssertEqual(LocationPreference.captureTiming, .onStart)
    }
}
