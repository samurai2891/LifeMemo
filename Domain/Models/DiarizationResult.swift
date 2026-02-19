import Foundation

/// Result of speaker diarization for a single audio chunk.
///
/// Contains the speaker-attributed segments, the total number of
/// distinct speakers detected in the chunk, and speaker profiles
/// for cross-chunk alignment.
struct DiarizationResult {
    let segments: [DiarizedSegment]
    let speakerCount: Int
    let speakerProfiles: [SpeakerProfile]

    /// Backward-compatible initializer without speaker profiles.
    init(segments: [DiarizedSegment], speakerCount: Int) {
        self.segments = segments
        self.speakerCount = speakerCount
        self.speakerProfiles = []
    }

    /// Full initializer with speaker profiles for cross-chunk alignment.
    init(segments: [DiarizedSegment], speakerCount: Int, speakerProfiles: [SpeakerProfile]) {
        self.segments = segments
        self.speakerCount = speakerCount
        self.speakerProfiles = speakerProfiles
    }
}
