import AVFAudio

/// Configures AVAudioSession for background recording.
///
/// Activates the session with `.playAndRecord` category and `.voiceChat` mode,
/// which enables Apple's built-in voice processing pipeline (AEC, noise suppression,
/// AGC, beamforming) — critical for far-field speech recognition.
final class AudioSessionConfigurator {

    // MARK: - Activation

    /// Activates the audio session for recording.
    ///
    /// Uses `.voiceChat` mode to enable Apple's voice processing, which provides
    /// far-field noise suppression and echo cancellation. This mode is recommended
    /// when `setVoiceProcessingEnabled(true)` is used on the audio engine input node.
    ///
    /// - Throws: An error if the session cannot be configured or activated.
    func activateRecordingSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetooth, .defaultToSpeaker, .duckOthers]
        )
        try session.setActive(true)
    }

    // MARK: - Deactivation

    /// Deactivates the audio session.
    ///
    /// Errors are intentionally suppressed because deactivation can fail
    /// when another audio session is active, which is a harmless condition.
    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}
