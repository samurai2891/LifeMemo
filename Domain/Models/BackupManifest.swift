import Foundation

/// Describes the contents of an encrypted backup file.
///
/// Serialized to JSON inside the encrypted backup. Contains all session
/// metadata, transcripts, and audio file references needed for restoration.
struct BackupManifest: Codable {
    let version: Int
    let createdAt: Date
    let appVersion: String
    let sessions: [SessionBackup]
    let audioFiles: [AudioFileEntry]

    static let currentVersion = 1

    struct SessionBackup: Codable {
        let id: UUID
        let title: String
        let createdAt: Date
        let startedAt: Date
        let endedAt: Date?
        let languageModeRaw: String
        let statusRaw: Int16
        let audioKept: Bool
        let summary: String?
        let bodyText: String?
        let chunks: [ChunkBackup]
        let segments: [SegmentBackup]
        let highlights: [HighlightBackup]
    }

    struct ChunkBackup: Codable {
        let id: UUID
        let index: Int32
        let startAt: Date
        let endAt: Date?
        let relativePath: String?
        let durationSec: Double
        let sizeBytes: Int64
        let transcriptionStatusRaw: Int16
        let audioDeleted: Bool
    }

    struct SegmentBackup: Codable {
        let id: UUID
        let startMs: Int64
        let endMs: Int64
        let text: String
        let isUserEdited: Bool
        let originalText: String?
        let createdAt: Date
    }

    struct HighlightBackup: Codable {
        let id: UUID
        let atMs: Int64
        let label: String?
        let createdAt: Date
    }

    struct AudioFileEntry: Codable {
        let relativePath: String
        let offset: Int64
        let length: Int64
    }
}
