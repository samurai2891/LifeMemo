import XCTest
@testable import LifeMemo

/// Tests for FileStore's file protection methods.
///
/// Note: File protection attributes (.protectionKey) are not readable
/// on the iOS Simulator. These tests verify that methods execute without
/// errors and that the protection API is called correctly.
final class FileStoreProtectionTests: XCTestCase {

    private var fileStore: FileStore!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        fileStore = FileStore()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        fileStore = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func createTempFile(named name: String = "test.m4a") -> URL {
        let url = tempDir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("test".utf8))
        return url
    }

    // MARK: - Protection Methods Do Not Crash

    func testRecordingProtectionOnValidFile() {
        let file = createTempFile()
        fileStore.setRecordingProtection(at: file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path),
                      "File must still exist after applying recording protection")
    }

    func testAtRestProtectionOnValidFile() {
        let file = createTempFile()
        fileStore.setAtRestProtection(at: file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path),
                      "File must still exist after applying at-rest protection")
    }

    func testDatabaseProtectionOnValidFile() {
        let file = createTempFile(named: "test.sqlite")
        fileStore.setDatabaseProtection(at: file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path),
                      "File must still exist after applying database protection")
    }

    // MARK: - Protection Escalation Sequence

    func testProtectionEscalationDoesNotCrash() {
        let file = createTempFile()

        // Simulate the recording lifecycle:
        // 1. Recording protection during recording
        fileStore.setRecordingProtection(at: file)

        // 2. At-rest protection after recording stops
        fileStore.setAtRestProtection(at: file)

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path),
                      "File must survive the full protection escalation lifecycle")
    }

    // MARK: - Non-existent File Safety

    func testProtectionOnNonExistentFileDoesNotCrash() {
        let fakeURL = tempDir.appendingPathComponent("nonexistent.m4a")
        fileStore.setRecordingProtection(at: fakeURL)
        fileStore.setAtRestProtection(at: fakeURL)
        fileStore.setDatabaseProtection(at: fakeURL)
        // No crash = pass
    }

    // MARK: - Directory Protection

    func testRecordingProtectionOnDirectory() {
        fileStore.setRecordingProtection(at: tempDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path),
                      "Directory must still exist after protection")
    }

    // MARK: - Backup Exclusion

    func testExcludeFromBackup() throws {
        let file = createTempFile()
        fileStore.excludeFromBackup(url: file)

        let values = try file.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertTrue(values.isExcludedFromBackup ?? false,
                      "File must be excluded from backup")
    }

    // MARK: - Audio File Path Creation

    func testMakeChunkRelativePath() {
        let sessionId = UUID()
        let path = fileStore.makeChunkRelativePath(sessionId: sessionId, index: 0, ext: "m4a")
        XCTAssertEqual(path, "Audio/\(sessionId.uuidString)/0000.m4a")
    }

    func testMakeChunkRelativePathMultipleIndices() {
        let sessionId = UUID()
        let path5 = fileStore.makeChunkRelativePath(sessionId: sessionId, index: 5, ext: "m4a")
        XCTAssertTrue(path5.hasSuffix("0005.m4a"))

        let path99 = fileStore.makeChunkRelativePath(sessionId: sessionId, index: 99, ext: "m4a")
        XCTAssertTrue(path99.hasSuffix("0099.m4a"))
    }

    func testEnsureAudioFileURLCreatesDirectory() throws {
        let sessionId = UUID()
        let relativePath = fileStore.makeChunkRelativePath(
            sessionId: sessionId, index: 0, ext: "m4a"
        )
        let url = try fileStore.ensureAudioFileURL(relativePath: relativePath)

        let parentDir = url.deletingLastPathComponent()
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: parentDir.path, isDirectory: &isDir),
                      "Parent directory must be created")
        XCTAssertTrue(isDir.boolValue, "Must be a directory")
    }
}
