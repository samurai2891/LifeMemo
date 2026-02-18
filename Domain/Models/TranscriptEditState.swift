import Foundation

/// Tracks whether the user is viewing or editing a transcript segment.
enum TranscriptEditState: Equatable {
    case viewing
    case editing
}
