import AVFoundation
import Foundation

/// Real-time audio level data for UI metering.
struct AudioLevel: Sendable, Equatable {
    let rms: Float
    let peak: Float
    let isSpeech: Bool

    static let silence = AudioLevel(rms: 0, peak: 0, isSpeech: false)
}

/// State machine for the recording lifecycle.
enum RecordingState: Sendable, Equatable {
    case idle
    case preparing
    case recording
    case stopping
    case error(String)
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

/// Protocol for managing audio recording lifecycle.
protocol AudioRecordingService: Sendable {
    func startRecording() async throws
    func stopRecording() async
    var audioLevelStream: AsyncStream<AudioLevel> { get }
    var stateStream: AsyncStream<RecordingState> { get }
}
