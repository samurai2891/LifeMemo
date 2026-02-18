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

    static let currentVersion = 2

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
        let editHistory: [EditHistoryBackup]

        /// Backward-compatible decoding: older backups without editHistory default to empty array.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            startMs = try container.decode(Int64.self, forKey: .startMs)
            endMs = try container.decode(Int64.self, forKey: .endMs)
            text = try container.decode(String.self, forKey: .text)
            isUserEdited = try container.decode(Bool.self, forKey: .isUserEdited)
            originalText = try container.decodeIfPresent(String.self, forKey: .originalText)
            createdAt = try container.decode(Date.self, forKey: .createdAt)
            editHistory = try container.decodeIfPresent([EditHistoryBackup].self, forKey: .editHistory) ?? []
        }

        init(
            id: UUID,
            startMs: Int64,
            endMs: Int64,
            text: String,
            isUserEdited: Bool,
            originalText: String?,
            createdAt: Date,
            editHistory: [EditHistoryBackup]
        ) {
            self.id = id
            self.startMs = startMs
            self.endMs = endMs
            self.text = text
            self.isUserEdited = isUserEdited
            self.originalText = originalText
            self.createdAt = createdAt
            self.editHistory = editHistory
        }
    }

    struct EditHistoryBackup: Codable {
        let id: UUID
        let previousText: String
        let newText: String
        let editedAt: Date
        let editIndex: Int16
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
