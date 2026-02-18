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

    static let currentVersion = 3

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
        let speakerNamesJSON: String?
        let chunks: [ChunkBackup]
        let segments: [SegmentBackup]
        let highlights: [HighlightBackup]

        /// Backward-compatible decoding: older backups without speakerNamesJSON.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            createdAt = try container.decode(Date.self, forKey: .createdAt)
            startedAt = try container.decode(Date.self, forKey: .startedAt)
            endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
            languageModeRaw = try container.decode(String.self, forKey: .languageModeRaw)
            statusRaw = try container.decode(Int16.self, forKey: .statusRaw)
            audioKept = try container.decode(Bool.self, forKey: .audioKept)
            summary = try container.decodeIfPresent(String.self, forKey: .summary)
            bodyText = try container.decodeIfPresent(String.self, forKey: .bodyText)
            speakerNamesJSON = try container.decodeIfPresent(String.self, forKey: .speakerNamesJSON)
            chunks = try container.decode([ChunkBackup].self, forKey: .chunks)
            segments = try container.decode([SegmentBackup].self, forKey: .segments)
            highlights = try container.decode([HighlightBackup].self, forKey: .highlights)
        }

        init(
            id: UUID, title: String, createdAt: Date, startedAt: Date,
            endedAt: Date?, languageModeRaw: String, statusRaw: Int16,
            audioKept: Bool, summary: String?, bodyText: String?,
            speakerNamesJSON: String?,
            chunks: [ChunkBackup], segments: [SegmentBackup],
            highlights: [HighlightBackup]
        ) {
            self.id = id
            self.title = title
            self.createdAt = createdAt
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.languageModeRaw = languageModeRaw
            self.statusRaw = statusRaw
            self.audioKept = audioKept
            self.summary = summary
            self.bodyText = bodyText
            self.speakerNamesJSON = speakerNamesJSON
            self.chunks = chunks
            self.segments = segments
            self.highlights = highlights
        }
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
        let speakerIndex: Int16
        let createdAt: Date
        let editHistory: [EditHistoryBackup]

        /// Backward-compatible decoding: older backups without editHistory/speakerIndex.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            startMs = try container.decode(Int64.self, forKey: .startMs)
            endMs = try container.decode(Int64.self, forKey: .endMs)
            text = try container.decode(String.self, forKey: .text)
            isUserEdited = try container.decode(Bool.self, forKey: .isUserEdited)
            originalText = try container.decodeIfPresent(String.self, forKey: .originalText)
            speakerIndex = try container.decodeIfPresent(Int16.self, forKey: .speakerIndex) ?? -1
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
            speakerIndex: Int16,
            createdAt: Date,
            editHistory: [EditHistoryBackup]
        ) {
            self.id = id
            self.startMs = startMs
            self.endMs = endMs
            self.text = text
            self.isUserEdited = isUserEdited
            self.originalText = originalText
            self.speakerIndex = speakerIndex
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
