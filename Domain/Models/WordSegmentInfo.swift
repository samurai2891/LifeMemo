import Foundation

/// Word-level transcription data extracted from `SFTranscriptionSegment`.
///
/// Speech-framework independent value type used to pass word timing and
/// pitch information from the transcriber to the diarization engine.
struct WordSegmentInfo {
    let substring: String
    let timestamp: TimeInterval     // Seconds from chunk start
    let duration: TimeInterval
    let confidence: Float
    let averagePitch: Float?        // From voiceAnalytics; nil when unavailable
}
