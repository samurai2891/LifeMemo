import Foundation

/// Real-time audio level data for UI metering.
struct AudioLevel: Sendable, Equatable {
    let rms: Float
    let peak: Float
    let isSpeech: Bool

    static let silence = AudioLevel(rms: 0, peak: 0, isSpeech: false)
}

/// A single processing stage in the audio preprocessing chain.
///
/// All methods are `nonisolated` because they execute on the audio render thread.
/// Implementations must be pure functions with no mutable shared state.
protocol AudioProcessingStage: Sendable {
    nonisolated var name: String { get }
    /// Process raw Float32 PCM samples and return the processed result.
    nonisolated func process(_ samples: [Float], sampleRate: Double) -> [Float]
}
