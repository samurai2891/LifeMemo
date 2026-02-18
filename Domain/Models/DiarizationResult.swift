import Foundation

/// Result of speaker diarization for a single audio chunk.
///
/// Contains the speaker-attributed segments and the total number of
/// distinct speakers detected in the chunk.
struct DiarizationResult {
    let segments: [DiarizedSegment]
    let speakerCount: Int
}
