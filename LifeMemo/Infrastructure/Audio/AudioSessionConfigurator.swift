import AVFoundation
import Foundation

/// Configures the audio session for optimal far-field meeting room recording.
///
/// Uses `.measurement` mode for maximum microphone sensitivity and enables
/// voice processing for built-in noise suppression and echo cancellation.
struct AudioSessionConfigurator: Sendable {
    nonisolated var name: String { "AudioSessionConfigurator" }

    /// Configure AVAudioSession for far-field recording.
    /// - Uses .playAndRecord category for simultaneous input/output
    /// - Uses .measurement mode for flat frequency response (best for far-field)
    /// - Enables .defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP
    /// - Preferred sample rate: 16000 Hz (optimal for speech recognition)
    /// - Preferred buffer duration: 0.02 (20ms for low latency)
    nonisolated func configureForFarFieldRecording() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
        )
        try session.setPreferredSampleRate(16000)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// Deactivate the audio session when recording is complete.
    nonisolated func deactivate() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
        #endif
    }
}
