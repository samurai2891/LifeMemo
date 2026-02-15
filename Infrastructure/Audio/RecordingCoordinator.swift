import Foundation

/// Coordinates the full recording lifecycle for the UI layer.
///
/// Manages transitions between `RecordingState` values, drives the elapsed-time
/// counter, and delegates audio capture to `ChunkedAudioRecorder`. Conforms to
/// `ObservableObject` so SwiftUI views can bind directly to `state` and
/// `elapsedSeconds`.
@MainActor
final class RecordingCoordinator: ObservableObject {

    // MARK: - Published State

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var elapsedSeconds: TimeInterval = 0

    // MARK: - Dependencies

    private let repository: SessionRepository
    private let audioSession: AudioSessionConfigurator
    private let chunkRecorder: ChunkedAudioRecorder

    // MARK: - Internal State

    private var currentLanguage: LanguageMode = .auto
    private var elapsedTimer: Timer?

    // MARK: - Initializer

    init(
        repository: SessionRepository,
        audioSession: AudioSessionConfigurator,
        chunkRecorder: ChunkedAudioRecorder
    ) {
        self.repository = repository
        self.audioSession = audioSession
        self.chunkRecorder = chunkRecorder
    }

    // MARK: - Public API

    /// Starts an always-on recording session.
    ///
    /// Creates a new session in the repository, activates the audio session,
    /// and begins chunked recording. On failure, the audio session is deactivated
    /// and state transitions to `.error`.
    ///
    /// - Parameter languageMode: The language for downstream transcription.
    func startAlwaysOn(languageMode: LanguageMode) {
        do {
            try audioSession.activateRecordingSession()
            let sessionId = repository.createSession(languageMode: languageMode)
            self.currentLanguage = languageMode
            try chunkRecorder.start(sessionId: sessionId, languageMode: languageMode)
            repository.updateSessionStatus(sessionId: sessionId, status: .recording)
            self.state = .recording(sessionId: sessionId)
            startElapsedTimer()
        } catch {
            audioSession.deactivate()
            self.state = .error(
                message: "Failed to start recording: \(error.localizedDescription)"
            )
        }
    }

    /// Stops the current recording session.
    ///
    /// Transitions through `.stopping`, finalizes the last chunk, marks the
    /// session as `.processing`, and returns to `.idle`.
    func stop() {
        guard case let .recording(sessionId) = state else { return }
        state = .stopping
        stopElapsedTimer()

        Task {
            await chunkRecorder.stop()
            repository.updateSessionEnded(
                sessionId: sessionId,
                endedAt: Date(),
                status: .processing
            )
            audioSession.deactivate()
            state = .idle
            elapsedSeconds = 0
        }
    }

    /// Adds a highlight marker at the current position in the recording.
    func addHighlight() {
        guard case let .recording(sessionId) = state else { return }
        let ms = repository.currentElapsedMs(sessionId: sessionId)
        repository.addHighlight(sessionId: sessionId, atMs: ms)
    }

    // MARK: - Elapsed Timer

    private func startElapsedTimer() {
        elapsedSeconds = 0
        elapsedTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedSeconds += 1
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }
}
