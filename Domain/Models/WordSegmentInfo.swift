import Foundation

/// Word-level transcription data extracted from `SFTranscriptionSegment`.
///
/// Speech-framework independent value type used to pass word timing and
/// acoustic feature information from the transcriber to the diarization engine.
struct WordSegmentInfo {
    let substring: String
    let timestamp: TimeInterval     // Seconds from chunk start
    let duration: TimeInterval
    let confidence: Float
    let averagePitch: Float?        // From voiceAnalytics; nil when unavailable

    // Multi-feature diarization fields
    let pitchStdDev: Float?
    let averageEnergy: Float?
    let averageSpectralCentroid: Float?
    let averageJitter: Float?
    let averageShimmer: Float?

    /// Backward-compatible initializer for existing call sites that only provide 5 fields.
    init(
        substring: String,
        timestamp: TimeInterval,
        duration: TimeInterval,
        confidence: Float,
        averagePitch: Float?
    ) {
        self.substring = substring
        self.timestamp = timestamp
        self.duration = duration
        self.confidence = confidence
        self.averagePitch = averagePitch
        self.pitchStdDev = nil
        self.averageEnergy = nil
        self.averageSpectralCentroid = nil
        self.averageJitter = nil
        self.averageShimmer = nil
    }

    /// Full initializer with all 10 fields.
    init(
        substring: String,
        timestamp: TimeInterval,
        duration: TimeInterval,
        confidence: Float,
        averagePitch: Float?,
        pitchStdDev: Float?,
        averageEnergy: Float?,
        averageSpectralCentroid: Float?,
        averageJitter: Float?,
        averageShimmer: Float?
    ) {
        self.substring = substring
        self.timestamp = timestamp
        self.duration = duration
        self.confidence = confidence
        self.averagePitch = averagePitch
        self.pitchStdDev = pitchStdDev
        self.averageEnergy = averageEnergy
        self.averageSpectralCentroid = averageSpectralCentroid
        self.averageJitter = averageJitter
        self.averageShimmer = averageShimmer
    }
}
