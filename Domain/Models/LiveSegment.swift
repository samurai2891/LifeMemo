import Foundation

/// A confirmed segment of live speech recognition during recording.
///
/// Each segment represents a finalized result from a single recognition cycle
/// (up to 55 seconds). Immutable value type — use `withText(_:)` to create
/// a copy with edited text.
struct LiveSegment: Identifiable, Equatable {
    let id: UUID
    let text: String
    let confirmedAt: Date
    let cycleIndex: Int

    func withText(_ newText: String) -> LiveSegment {
        LiveSegment(
            id: id,
            text: newText,
            confirmedAt: confirmedAt,
            cycleIndex: cycleIndex
        )
    }
}
