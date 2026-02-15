import AVFAudio

/// Configures AVAudioSession for background recording.
///
/// Activates the session with `.record` category and `.measurement` mode,
/// which provides high-fidelity mono input suitable for speech recognition.
final class AudioSessionConfigurator {

    // MARK: - Activation

    /// Activates the audio session for recording.
    ///
    /// - Throws: An error if the session cannot be configured or activated.
    func activateRecordingSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .record,
            mode: .measurement,
            options: [.allowBluetooth]
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
