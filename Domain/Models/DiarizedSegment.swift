import Foundation

/// A contiguous run of text attributed to a single speaker.
///
/// Transient value type produced by the diarization engine before
/// persistence. Each segment covers a speaker turn within one audio chunk.
struct DiarizedSegment: Identifiable {
    let id: UUID
    let speakerIndex: Int           // 0-based speaker identifier
    let text: String
    let startOffsetMs: Int64        // Relative to chunk start
    let endOffsetMs: Int64
}
