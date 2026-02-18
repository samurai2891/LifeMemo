import Foundation
import CoreData
import os.log

/// Creates and restores encrypted backup files (.lifememobackup).
///
/// Backup files contain a JSON manifest with all session data, optionally
/// followed by concatenated audio files. The entire payload is encrypted
/// with AES-256-GCM using a user-provided password.
@MainActor
final class BackupService: ObservableObject {

    // MARK: - Published

    @Published private(set) var isProcessing = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var lastError: String?

    // MARK: - Dependencies

    private let repository: SessionRepository
    private let fileStore: FileStore
    private let logger = Logger(subsystem: "com.lifememo.app", category: "Backup")

    // MARK: - Init

    init(repository: SessionRepository, fileStore: FileStore) {
        self.repository = repository
        self.fileStore = fileStore
    }

    // MARK: - Create Backup

    func createEncryptedBackup(
        sessionIds: [UUID],
        includeAudio: Bool,
        password: String
    ) async throws -> URL {
        isProcessing = true
        progress = 0
        lastError = nil
        defer { isProcessing = false }

        // 1. Build manifest
        let sessions = repository.fetchAllSessions()
            .filter { sessionIds.contains($0.id ?? UUID()) }

        var sessionBackups: [BackupManifest.SessionBackup] = []
        var audioEntries: [BackupManifest.AudioFileEntry] = []
        var audioData = Data()

        for (index, session) in sessions.enumerated() {
            let chunks = session.chunksArray.map { chunk in
                BackupManifest.ChunkBackup(
                    id: chunk.id ?? UUID(),
                    index: chunk.index,
                    startAt: chunk.startAt ?? Date(),
                    endAt: chunk.endAt,
                    relativePath: chunk.relativePath,
                    durationSec: chunk.durationSec,
                    sizeBytes: chunk.sizeBytes,
                    transcriptionStatusRaw: chunk.transcriptionStatusRaw,
                    audioDeleted: chunk.audioDeleted
                )
            }

            let segments = session.segmentsArray.map { seg in
                let historyBackups = seg.editHistoryArray.map { entry in
                    BackupManifest.EditHistoryBackup(
                        id: entry.id ?? UUID(),
                        previousText: entry.previousText ?? "",
                        newText: entry.newText ?? "",
                        editedAt: entry.editedAt ?? Date(),
                        editIndex: entry.editIndex
                    )
                }
                return BackupManifest.SegmentBackup(
                    id: seg.id ?? UUID(),
                    startMs: seg.startMs,
                    endMs: seg.endMs,
                    text: seg.text ?? "",
                    isUserEdited: seg.isUserEdited,
                    originalText: seg.originalText,
                    createdAt: seg.createdAt ?? Date(),
                    editHistory: historyBackups
                )
            }

            let highlights = session.highlightsArray.map { h in
                BackupManifest.HighlightBackup(
                    id: h.id ?? UUID(),
                    atMs: h.atMs,
                    label: h.label,
                    createdAt: h.createdAt ?? Date()
                )
            }

            sessionBackups.append(BackupManifest.SessionBackup(
                id: session.id ?? UUID(),
                title: session.title ?? "",
                createdAt: session.createdAt ?? Date(),
                startedAt: session.startedAt ?? Date(),
                endedAt: session.endedAt,
                languageModeRaw: session.languageModeRaw ?? "auto",
                statusRaw: session.statusRaw,
                audioKept: session.audioKept,
                summary: session.summary,
                bodyText: nil,
                chunks: chunks,
                segments: segments,
                highlights: highlights
            ))

            // Collect audio files
            if includeAudio && session.audioKept {
                for chunk in session.chunksArray {
                    guard let path = chunk.relativePath,
                          let url = fileStore.resolveAbsoluteURL(relativePath: path) else { continue }
                    if let fileData = try? Data(contentsOf: url) {
                        let entry = BackupManifest.AudioFileEntry(
                            relativePath: path,
                            offset: Int64(audioData.count),
                            length: Int64(fileData.count)
                        )
                        audioEntries.append(entry)
                        audioData.append(fileData)
                    }
                }
            }

            progress = Double(index + 1) / Double(sessions.count) * 0.5
        }

        let manifest = BackupManifest(
            version: BackupManifest.currentVersion,
            createdAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            sessions: sessionBackups,
            audioFiles: audioEntries
        )

        // 2. Serialize
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let manifestData = try encoder.encode(manifest)

        // Combine: manifestLength(8 bytes) + manifestJSON + audioData
        var payload = Data()
        var manifestLength = UInt64(manifestData.count)
        payload.append(Data(bytes: &manifestLength, count: 8))
        payload.append(manifestData)
        payload.append(audioData)

        progress = 0.7

        // 3. Encrypt
        let encrypted = try BackupCrypto.encrypt(data: payload, password: password)

        progress = 0.9

        // 4. Write to file
        let base = try fileStore.appDataDir()
        let backupsDir = base.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "LifeMemo_\(formatter.string(from: Date())).lifememobackup"
        let fileURL = backupsDir.appendingPathComponent(fileName)

        try encrypted.write(to: fileURL, options: [.atomic])
        fileStore.setAtRestProtection(at: fileURL)

        progress = 1.0
        logger.info("Backup created: \(fileName)")
        return fileURL
    }

    // MARK: - Restore

    func restoreFromEncryptedBackup(url: URL, password: String) async throws {
        isProcessing = true
        progress = 0
        lastError = nil
        defer { isProcessing = false }

        // 1. Read and decrypt
        let encrypted = try Data(contentsOf: url)
        let payload = try BackupCrypto.decrypt(data: encrypted, password: password)

        progress = 0.3

        // 2. Parse manifest
        guard payload.count >= 8 else {
            throw BackupError.invalidFormat
        }

        let manifestLength = payload.prefix(8).withUnsafeBytes { $0.load(as: UInt64.self) }
        let manifestEnd = 8 + Int(manifestLength)
        guard manifestEnd <= payload.count else {
            throw BackupError.invalidFormat
        }

        let manifestData = payload[8..<manifestEnd]
        let audioData = payload[manifestEnd...]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(BackupManifest.self, from: Data(manifestData))

        guard manifest.version <= BackupManifest.currentVersion else {
            throw BackupError.incompatibleVersion(manifest.version)
        }

        progress = 0.5

        // 3. Import sessions (skip duplicates by UUID)
        for (index, sessionBackup) in manifest.sessions.enumerated() {
            // Check if session already exists
            if repository.fetchSession(id: sessionBackup.id) != nil {
                continue // Skip duplicate
            }

            repository.importSession(from: sessionBackup)

            // Write audio files
            let sessionAudioEntries = manifest.audioFiles.filter { entry in
                sessionBackup.chunks.contains { $0.relativePath == entry.relativePath }
            }

            for audioEntry in sessionAudioEntries {
                let startOffset = Int(audioEntry.offset)
                let endOffset = startOffset + Int(audioEntry.length)
                guard endOffset <= audioData.count else { continue }

                let audioStartIndex = audioData.startIndex + startOffset
                let audioEndIndex = audioData.startIndex + endOffset
                let fileData = audioData[audioStartIndex..<audioEndIndex]
                if let fileURL = try? fileStore.ensureAudioFileURL(relativePath: audioEntry.relativePath) {
                    try? Data(fileData).write(to: fileURL, options: [.atomic])
                }
            }

            progress = 0.5 + Double(index + 1) / Double(manifest.sessions.count) * 0.5
        }

        logger.info("Backup restored: \(manifest.sessions.count) sessions")
    }

    // MARK: - Errors

    enum BackupError: LocalizedError {
        case invalidFormat
        case incompatibleVersion(Int)
        case corruptedData

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "Invalid backup file format."
            case .incompatibleVersion(let version):
                return "Backup version \(version) is not supported by this version of LifeMemo."
            case .corruptedData:
                return "The backup file appears to be corrupted."
            }
        }
    }
}
