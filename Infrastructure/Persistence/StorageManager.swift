import Foundation
import os.log

/// Tracks storage usage and provides bulk management operations.
///
/// Calculates disk space used by audio files, transcripts, exports, and FTS index.
/// Provides operations for bulk cleanup of old audio files and backup/restore.
@MainActor
final class StorageManager: ObservableObject {

    // MARK: - Types

    struct StorageBreakdown: Equatable {
        let audioBytes: Int64
        let databaseBytes: Int64
        let exportBytes: Int64
        let ftsIndexBytes: Int64

        var totalBytes: Int64 {
            audioBytes + databaseBytes + exportBytes + ftsIndexBytes
        }

        var audioMB: Double { Double(audioBytes) / Self.bytesPerMB }
        var databaseMB: Double { Double(databaseBytes) / Self.bytesPerMB }
        var exportMB: Double { Double(exportBytes) / Self.bytesPerMB }
        var ftsIndexMB: Double { Double(ftsIndexBytes) / Self.bytesPerMB }
        var totalMB: Double { Double(totalBytes) / Self.bytesPerMB }
        var totalGB: Double { totalMB / 1024 }

        /// Fraction of total for each category (0.0 - 1.0). Returns 0 if total is 0.
        var audioFraction: Double { totalBytes > 0 ? Double(audioBytes) / Double(totalBytes) : 0 }
        var databaseFraction: Double { totalBytes > 0 ? Double(databaseBytes) / Double(totalBytes) : 0 }
        var exportFraction: Double { totalBytes > 0 ? Double(exportBytes) / Double(totalBytes) : 0 }
        var ftsFraction: Double { totalBytes > 0 ? Double(ftsIndexBytes) / Double(totalBytes) : 0 }

        static let zero = StorageBreakdown(
            audioBytes: 0,
            databaseBytes: 0,
            exportBytes: 0,
            ftsIndexBytes: 0
        )

        private static let bytesPerMB: Double = 1024 * 1024
    }

    struct SessionStorageInfo: Identifiable, Equatable {
        let id: UUID
        let title: String
        let createdAt: Date
        let audioSizeBytes: Int64
        let hasAudio: Bool
        let chunkCount: Int

        var audioSizeMB: Double { Double(audioSizeBytes) / (1024 * 1024) }
    }

    struct BackupInfo: Identifiable {
        let id: UUID
        let url: URL
        let name: String
        let createdAt: Date
        let sizeBytes: Int64

        var sizeMB: Double { Double(sizeBytes) / (1024 * 1024) }
    }

    // MARK: - Published State

    @Published private(set) var breakdown = StorageBreakdown.zero
    @Published private(set) var sessionStorageList: [SessionStorageInfo] = []
    @Published private(set) var backups: [BackupInfo] = []
    @Published private(set) var isCalculating = false
    @Published private(set) var deviceFreeSpaceGB: Double = 0
    @Published private(set) var lastError: String?

    // MARK: - Dependencies

    private let fileStore: FileStore
    private let repository: SessionRepository
    private let logger = Logger(subsystem: "com.lifememo.app", category: "Storage")

    // MARK: - Init

    init(fileStore: FileStore, repository: SessionRepository) {
        self.fileStore = fileStore
        self.repository = repository
    }

    // MARK: - Calculate Storage

    func calculateStorage() {
        isCalculating = true
        lastError = nil

        let audioSize = fileStore.totalAudioSize()
        let dbSize = databaseFileSize()
        let exportSize = exportDirectorySize()
        let ftsSize = ftsIndexSize()

        breakdown = StorageBreakdown(
            audioBytes: audioSize,
            databaseBytes: dbSize,
            exportBytes: exportSize,
            ftsIndexBytes: ftsSize
        )

        deviceFreeSpaceGB = diskFreeSpaceGB()
        calculateSessionStorage()
        refreshBackupList()

        isCalculating = false
        logger.info("Storage calculated: \(self.breakdown.totalMB, format: .fixed(precision: 1)) MB total")
    }

    private func calculateSessionStorage() {
        let sessions = repository.fetchAllSessions()
        sessionStorageList = sessions.map { session in
            let audioSize = session.chunksArray.reduce(Int64(0)) { total, chunk in
                total + chunk.sizeBytes
            }
            return SessionStorageInfo(
                id: session.id ?? UUID(),
                title: session.title ?? "",
                createdAt: session.createdAt ?? Date(),
                audioSizeBytes: audioSize,
                hasAudio: session.audioKept,
                chunkCount: session.chunksArray.count
            )
        }.sorted { $0.audioSizeBytes > $1.audioSizeBytes }
    }

    // MARK: - Bulk Operations

    /// Deletes audio files for sessions older than a given number of days.
    ///
    /// Transcripts are preserved. Returns the count of sessions whose audio was deleted.
    func deleteAudioOlderThan(days: Int) -> Int {
        guard days > 0 else {
            logger.warning("Invalid days parameter: \(days)")
            return 0
        }

        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -days,
            to: Date()
        ) ?? Date()

        let sessions = repository.fetchAllSessions()
        var deletedCount = 0

        for session in sessions {
            guard session.audioKept,
                  let startedAt = session.startedAt,
                  startedAt < cutoffDate else {
                continue
            }

            let sessionId = session.id ?? UUID()
            repository.deleteAudioKeepTranscript(sessionId: sessionId)
            deletedCount += 1
            logger.debug("Deleted audio for session: \(sessionId.uuidString)")
        }

        if deletedCount > 0 {
            calculateStorage()
            logger.info("Deleted audio for \(deletedCount) session(s) older than \(days) day(s)")
        }

        return deletedCount
    }

    /// Removes all files in the Export directory.
    func deleteAllExports() {
        guard let base = try? fileStore.appDataDir() else {
            lastError = "Could not access app data directory"
            return
        }

        let exportDir = base.appendingPathComponent("Exports", isDirectory: true)
        let fm = FileManager.default

        do {
            if fm.fileExists(atPath: exportDir.path) {
                try fm.removeItem(at: exportDir)
            }
            try fm.createDirectory(at: exportDir, withIntermediateDirectories: true)
            calculateStorage()
            logger.info("All exports deleted")
        } catch {
            lastError = "Failed to delete exports: \(error.localizedDescription)"
            logger.error("Export deletion failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Backup

    /// Creates a backup of the Core Data store files.
    ///
    /// The backup is stored as a directory containing copies of the SQLite
    /// store, WAL, and SHM files. Returns the URL of the created backup.
    @available(*, deprecated, message: "Use BackupService instead")
    func createBackup() -> Result<URL, StorageError> {
        do {
            let base = try fileStore.appDataDir()
            let backupDir = base.appendingPathComponent("Backups", isDirectory: true)
            try FileManager.default.createDirectory(
                at: backupDir,
                withIntermediateDirectories: true
            )

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = formatter.string(from: Date())
            let backupName = "LifeMemo_Backup_\(timestamp)"
            let backupURL = backupDir.appendingPathComponent(backupName, isDirectory: true)

            try FileManager.default.createDirectory(
                at: backupURL,
                withIntermediateDirectories: true
            )

            let storeURL = coreDataStoreURL(base: base)
            try copyFileIfExists(from: storeURL, to: backupURL, name: "LifeMemo.sqlite")
            try copyFileIfExists(
                from: URL(fileURLWithPath: storeURL.path + "-wal"),
                to: backupURL,
                name: "LifeMemo.sqlite-wal"
            )
            try copyFileIfExists(
                from: URL(fileURLWithPath: storeURL.path + "-shm"),
                to: backupURL,
                name: "LifeMemo.sqlite-shm"
            )

            refreshBackupList()
            logger.info("Backup created at: \(backupURL.lastPathComponent)")
            return .success(backupURL)
        } catch {
            let message = "Backup failed: \(error.localizedDescription)"
            lastError = message
            logger.error("\(message)")
            return .failure(.backupFailed(error.localizedDescription))
        }
    }

    /// Returns a list of existing backups sorted by creation date (newest first).
    func refreshBackupList() {
        guard let base = try? fileStore.appDataDir() else {
            backups = []
            return
        }

        let backupDir = base.appendingPathComponent("Backups", isDirectory: true)
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.creationDateKey, .totalFileAllocatedSizeKey]
        ) else {
            backups = []
            return
        }

        backups = contents.compactMap { url -> BackupInfo? in
            let name = url.lastPathComponent
            guard name.hasPrefix("LifeMemo_Backup_") else { return nil }

            let values = try? url.resourceValues(forKeys: [.creationDateKey])
            let createdAt = values?.creationDate ?? Date.distantPast
            let size = directorySize(at: url)

            return BackupInfo(
                id: UUID(),
                url: url,
                name: name,
                createdAt: createdAt,
                sizeBytes: size
            )
        }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Deletes a specific backup by its URL.
    func deleteBackup(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            refreshBackupList()
            logger.info("Backup deleted: \(url.lastPathComponent)")
        } catch {
            lastError = "Failed to delete backup: \(error.localizedDescription)"
            logger.error("Backup deletion failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Error Types

    enum StorageError: LocalizedError {
        case backupFailed(String)
        case restoreFailed(String)
        case directoryAccessFailed

        var errorDescription: String? {
            switch self {
            case .backupFailed(let detail):
                return "Backup failed: \(detail)"
            case .restoreFailed(let detail):
                return "Restore failed: \(detail)"
            case .directoryAccessFailed:
                return "Could not access app data directory"
            }
        }
    }

    // MARK: - Formatting Helpers

    /// Formats a byte count as a human-readable string (e.g. "12.3 MB").
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Private Helpers

    private func coreDataStoreURL(base: URL) -> URL {
        base.appendingPathComponent("CoreData/LifeMemo.sqlite")
    }

    private func copyFileIfExists(from source: URL, to directory: URL, name: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return }
        let destination = directory.appendingPathComponent(name)
        try fm.copyItem(at: source, to: destination)
    }

    private func databaseFileSize() -> Int64 {
        guard let base = try? fileStore.appDataDir() else { return 0 }
        let storeURL = coreDataStoreURL(base: base)
        return fileSize(at: storeURL)
            + fileSize(at: URL(fileURLWithPath: storeURL.path + "-wal"))
            + fileSize(at: URL(fileURLWithPath: storeURL.path + "-shm"))
    }

    private func exportDirectorySize() -> Int64 {
        guard let base = try? fileStore.appDataDir() else { return 0 }
        return directorySize(at: base.appendingPathComponent("Exports"))
    }

    private func ftsIndexSize() -> Int64 {
        guard let base = try? fileStore.appDataDir() else { return 0 }
        return directorySize(at: base.appendingPathComponent("FTS"))
    }

    private func fileSize(at url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private func diskFreeSpaceGB() -> Double {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        ) else { return 0 }

        guard let freeSize = attrs[.systemFreeSize] as? NSNumber else { return 0 }
        return freeSize.doubleValue / (1024 * 1024 * 1024)
    }
}
