import Foundation

/// ViewModel for the recording screen.
///
/// Coordinates permissions, recording lifecycle, and transcription display.
/// Exposes observable properties for SwiftUI data binding.
@Observable
final class RecordingViewModel {
    // MARK: - Observable state

    private(set) var recordingState: RecordingState = .idle
    private(set) var transcribedText: String = ""
    private(set) var audioLevel: AudioLevel = .silence
    private(set) var permissionState: PermissionState = .unknown
    private(set) var segments: [TranscriptionSegment] = []
    private(set) var errorMessage: String?

    // MARK: - Dependencies

    private let transcriber: LiveTranscriber
    private let permissionManager: PermissionManager

    // Background observation tasks
    private var stateObservationTask: Task<Void, Never>?

    init(
        textCorrector: TextCorrectionProtocol? = nil,
        locale: Locale = Locale(identifier: "ja-JP")
    ) {
        let corrector = textCorrector ?? TextCorrectionPipeline()
        self.transcriber = LiveTranscriber(
            textCorrector: corrector,
            locale: locale
        )
        self.permissionManager = PermissionManager()
    }

    // MARK: - Actions

    /// Toggle recording on/off.
    func toggleRecording() async {
        switch recordingState {
        case .idle, .error:
            await startRecording()
        case .recording:
            await stopRecording()
        case .preparing, .stopping:
            break // Ignore during transitions
        }
    }

    /// Request microphone and speech recognition permissions.
    func requestPermissions() async {
        await permissionManager.requestAll()
        permissionState = permissionManager.state
    }

    /// Check current permission status.
    func checkPermissions() {
        permissionManager.checkCurrent()
        permissionState = permissionManager.state
    }

    /// Clear the current transcription.
    func clearTranscription() {
        transcribedText = ""
        segments = []
        errorMessage = nil
    }

    // MARK: - Recording lifecycle

    private func startRecording() async {
        if !permissionState.allGranted {
            await requestPermissions()
            guard permissionState.allGranted else {
                errorMessage = "マイクと音声認識の許可が必要です"
                return
            }
        }

        errorMessage = nil
        recordingState = .preparing

        do {
            try await transcriber.start()
            recordingState = .recording
            startObservingTranscriber()
        } catch {
            recordingState = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    private func stopRecording() async {
        recordingState = .stopping
        stateObservationTask?.cancel()
        await transcriber.stop()
        recordingState = .idle
    }

    // MARK: - Observation

    private func startObservingTranscriber() {
        stateObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.transcribedText = self.transcriber.currentText
                self.audioLevel = self.transcriber.currentLevel
                self.segments = self.transcriber.segments

                if case .error(let msg) = self.transcriber.state {
                    self.errorMessage = msg
                    self.recordingState = .error(msg)
                }

                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// Whether the record button should show as active.
    var isRecording: Bool {
        recordingState == .recording
    }

    /// Full transcription text combining all finalized segments.
    var fullTranscription: String {
        guard !segments.isEmpty else { return transcribedText }
        let finalized = segments.map(\.correctedText).joined()
        if transcribedText.isEmpty {
            return finalized
        }
        return finalized + "\n" + transcribedText
    }
}
