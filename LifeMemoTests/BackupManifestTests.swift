import XCTest
@testable import LifeMemo

final class BackupManifestTests: XCTestCase {

    func testEncodeDecode() throws {
        let manifest = BackupManifest(
            version: BackupManifest.currentVersion,
            createdAt: Date(),
            appVersion: "1.0",
            sessions: [
                BackupManifest.SessionBackup(
                    id: UUID(),
                    title: "Test Session",
                    createdAt: Date(),
                    startedAt: Date(),
                    endedAt: Date(),
                    languageModeRaw: "auto",
                    statusRaw: 2,
                    audioKept: true,
                    summary: "A test summary",
                    bodyText: "Some notes",
                    chunks: [],
                    segments: [],
                    highlights: []
                )
            ],
            audioFiles: []
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(manifest)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(BackupManifest.self, from: data)

        XCTAssertEqual(decoded.version, manifest.version)
        XCTAssertEqual(decoded.sessions.count, 1)
        XCTAssertEqual(decoded.sessions.first?.title, "Test Session")
        XCTAssertEqual(decoded.sessions.first?.bodyText, "Some notes")
    }

    func testCurrentVersion() {
        XCTAssertEqual(BackupManifest.currentVersion, 2)
    }
}
