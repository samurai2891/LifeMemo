import Foundation

/// A single edit event in a transcript segment's history.
struct EditHistoryEntry: Identifiable, Equatable {
    let id: UUID
    let segmentId: UUID
    let previousText: String
    let newText: String
    let editedAt: Date
    let editIndex: Int  // Sequential edit number (1, 2, 3...)
}
