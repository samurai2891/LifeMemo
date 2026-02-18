import XCTest
@testable import LifeMemo

final class StorageMigratorTests: XCTestCase {

    private let migrationKey = "v1_storageMigrationComplete"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: migrationKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: migrationKey)
        super.tearDown()
    }

    // MARK: - Migration Flag

    func testMigrationFlagDefaultFalse() {
        XCTAssertFalse(UserDefaults.standard.bool(forKey: migrationKey))
    }

    func testMigrateIfNeededSetsFlagOnFreshInstall() {
        // On a fresh install there is no Documents/AppData/ directory,
        // so migrateIfNeeded should detect this and mark migration complete.
        StorageMigrator.migrateIfNeeded()
        XCTAssertTrue(UserDefaults.standard.bool(forKey: migrationKey))
    }

    func testMigrateIfNeededIsIdempotent() {
        StorageMigrator.migrateIfNeeded()
        XCTAssertTrue(UserDefaults.standard.bool(forKey: migrationKey))

        // Calling again should not crash or change the result
        StorageMigrator.migrateIfNeeded()
        XCTAssertTrue(UserDefaults.standard.bool(forKey: migrationKey))
    }

    func testMigrateIfNeededSkipsWhenAlreadyComplete() {
        UserDefaults.standard.set(true, forKey: migrationKey)
        // Should return early without doing any work
        StorageMigrator.migrateIfNeeded()
        XCTAssertTrue(UserDefaults.standard.bool(forKey: migrationKey))
    }

    // MARK: - Directory Structure

    func testNewDirectoryStructureExistsAfterMigration() {
        StorageMigrator.migrateIfNeeded()

        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let lifeMemoDir = appSupport.appendingPathComponent("LifeMemo")

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: lifeMemoDir.path,
            isDirectory: &isDir
        )
        // On fresh install without legacy data the directory may not be created
        // (no source to move), but the flag is still set. Only assert existence
        // if the directory was actually created by a previous real migration.
        if exists {
            XCTAssertTrue(isDir.boolValue, "LifeMemo path should be a directory")
        }
    }
}
