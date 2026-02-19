import Foundation

/// Coordinates the full recording lifecycle for the UI layer.
///
/// Manages transitions between `RecordingState` values, drives the elapsed-time
/// counter, and delegates audio capture to `ChunkedAudioRecorder`. Integrates
/// with `AudioInterruptionHandler` for interruption recovery and
/// `RecordingHealthMonitor` for long-session health monitoring.
@MainActor
final class RecordingCoordinator: ObservableObject {

    // MARK: - Published State

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var elapsedSeconds: TimeInterval = 0

    // MARK: - Dependencies

    private let repository: SessionRepository
    private let audioSession: AudioSessionConfigurator
    private let chunkRecorder: ChunkedAudioRecorder
    private let interruptionHandler: AudioInterruptionHandler
    private let healthMonitor: RecordingHealthMonitor
    private let locationService: LocationService
    private let transcriptionQueue: TranscriptionQueueActor
    private let liveTranscriber: LiveTranscriber

    // MARK: - Callbacks

    var onRecordingError: ((String) -> Void)?

    // MARK: - Internal State

    private var currentLanguage: LanguageMode = .auto
    private var elapsedTimer: Timer?

    // MARK: - Initializer

    init(
        repository: SessionRepository,
        audioSession: AudioSessionConfigurator,
        chunkRecorder: ChunkedAudioRecorder,
        interruptionHandler: AudioInterruptionHandler,
        healthMonitor: RecordingHealthMonitor,
        locationService: LocationService,
        transcriptionQueue: TranscriptionQueueActor,
        liveTranscriber: LiveTranscriber
    ) {
        self.repository = repository
        self.audioSession = audioSession
        self.chunkRecorder = chunkRecorder
        self.interruptionHandler = interruptionHandler
        self.healthMonitor = healthMonitor
        self.locationService = locationService
        self.transcriptionQueue = transcriptionQueue
        self.liveTranscriber = liveTranscriber

        setupInterruptionHandling()
    }

    // MARK: - Public API

    /// Starts an always-on recording session.
    func startAlwaysOn(languageMode: LanguageMode) {
        do {
            try audioSession.activateRecordingSession()
            let sessionId = repository.createSession(languageMode: languageMode)
            self.currentLanguage = languageMode
            let captureTiming = LocationPreference.captureTiming
            if captureTiming == .onStart || captureTiming == .both {
                locationService.captureCurrentLocation()
            }
            let audioConfig = AudioConfiguration.current()
            try chunkRecorder.start(
                sessionId: sessionId,
                languageMode: languageMode,
                config: audioConfig.toRecorderConfig()
            )
            repository.updateSessionStatus(sessionId: sessionId, status: .recording)
            self.state = .recording(sessionId: sessionId)
            startElapsedTimer()
            healthMonitor.startMonitoring(sessionStart: Date())

            // Defer chunk transcription while recording is active
            Task { await transcriptionQueue.setRecordingActive(true) }

            // Start live transcription preview
            liveTranscriber.start(locale: languageMode.locale)
        } catch {
            audioSession.deactivate()
            let errorMessage = "Failed to start recording: \(error.localizedDescription)"
            self.state = .error(message: errorMessage)
            onRecordingError?(errorMessage)
        }
    }

    /// Stops the current recording session.
    func stop() {
        guard case let .recording(sessionId) = state else { return }
        state = .stopping
        stopElapsedTimer()
        healthMonitor.stopMonitoring()
        interruptionHandler.resetState()

        let stopTiming = LocationPreference.captureTiming
        if stopTiming == .onStop || stopTiming == .both {
            locationService.captureCurrentLocation()
        }

        // Stop live transcription preview and clear memory
        liveTranscriber.stop()
        liveTranscriber.reset()

        Task {
            await chunkRecorder.stop()
            repository.updateSessionEnded(
                sessionId: sessionId,
                endedAt: Date(),
                status: .processing
            )
            if let location = locationService.lastLocation {
                repository.updateSessionLocation(
                    sessionId: sessionId,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    placeName: locationService.lastPlaceName
                )
            }
            locationService.reset()
            audioSession.deactivate()

            // Flush transcription queue now that all chunks are finalized
            await transcriptionQueue.setRecordingActive(false)

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

    // MARK: - Interruption Handling

    private func setupInterruptionHandling() {
        interruptionHandler.onShouldPause = { [weak self] in
            guard let self else { return }
            // Pause chunked recording on interruption
            Task { @MainActor in
                await self.chunkRecorder.stop()
            }
        }

        interruptionHandler.onShouldResume = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard case let .recording(sessionId) = self.state else { return }
                do {
                    try self.audioSession.activateRecordingSession()
                    let audioConfig = AudioConfiguration.current()
                    try self.chunkRecorder.start(
                        sessionId: sessionId,
                        languageMode: self.currentLanguage,
                        config: audioConfig.toRecorderConfig()
                    )
                } catch {
                    let errorMessage = "Failed to resume after interruption: \(error.localizedDescription)"
                    self.state = .error(message: errorMessage)
                    self.onRecordingError?(errorMessage)
                }
            }
        }

        interruptionHandler.onRecoveryFailed = { [weak self] reason in
            guard let self else { return }
            Task { @MainActor in
                self.state = .error(message: reason)
            }
        }
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
