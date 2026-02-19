import Foundation

/// Records an edit made to a live transcription segment during recording.
///
/// Stored as JSON in `SessionEntity.liveEditsJSON` and used after recording
/// to reconcile edits with the final persistent transcription segments.
struct LiveEditRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let liveSegmentId: UUID
    let sequenceIndex: Int
    let originalText: String
    let editedText: String
    let editedAt: Date
}
