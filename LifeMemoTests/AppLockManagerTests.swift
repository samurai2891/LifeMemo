import XCTest
@testable import LifeMemo

@MainActor
final class AppLockManagerTests: XCTestCase {

    private static let enabledKey = "appLockEnabled"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.enabledKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.enabledKey)
        super.tearDown()
    }

    // MARK: - Default State

    func testDefaultDisabled() {
        let manager = AppLockManager()
        XCTAssertFalse(manager.isEnabled)
        XCTAssertFalse(manager.isLocked)
    }

    // MARK: - Lock Behavior

    func testLockWhenDisabledDoesNotLock() {
        let manager = AppLockManager()
        manager.lock()
        XCTAssertFalse(manager.isLocked, "Should NOT lock when isEnabled is false")
    }

    func testLockWhenEnabledDoesLock() {
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        let manager = AppLockManager()
        XCTAssertTrue(manager.isEnabled)
        manager.lock()
        XCTAssertTrue(manager.isLocked, "Should lock when isEnabled is true")
    }

    // MARK: - Persistence

    func testIsEnabledPersistence() {
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        let manager = AppLockManager()
        XCTAssertTrue(manager.isEnabled)
    }

    func testIsEnabledWritesToUserDefaults() {
        let manager = AppLockManager()
        manager.isEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: Self.enabledKey))
    }

    func testDisablingWritesToUserDefaults() {
        let manager = AppLockManager()
        manager.isEnabled = true
        manager.isEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: Self.enabledKey))
    }

    // MARK: - Biometric Type

    func testBiometricTypeHasDisplayName() {
        let manager = AppLockManager()
        let bioType = manager.biometricType
        XCTAssertFalse(bioType.displayName.isEmpty,
                       "biometricType.displayName should never be empty")
    }

    func testBiometricTypeHasSystemImage() {
        let manager = AppLockManager()
        let bioType = manager.biometricType
        XCTAssertFalse(bioType.systemImage.isEmpty,
                       "biometricType.systemImage should never be empty")
    }

    // MARK: - BiometricType Enum

    func testBiometricTypeDisplayNames() {
        XCTAssertEqual(AppLockManager.BiometricType.faceID.displayName, "Face ID")
        XCTAssertEqual(AppLockManager.BiometricType.touchID.displayName, "Touch ID")
        XCTAssertEqual(AppLockManager.BiometricType.opticID.displayName, "Optic ID")
        XCTAssertEqual(AppLockManager.BiometricType.none.displayName, String(localized: "Passcode"))
    }

    func testBiometricTypeSystemImages() {
        XCTAssertEqual(AppLockManager.BiometricType.faceID.systemImage, "faceid")
        XCTAssertEqual(AppLockManager.BiometricType.touchID.systemImage, "touchid")
        XCTAssertEqual(AppLockManager.BiometricType.opticID.systemImage, "opticid")
        XCTAssertEqual(AppLockManager.BiometricType.none.systemImage, "lock.fill")
    }
}
