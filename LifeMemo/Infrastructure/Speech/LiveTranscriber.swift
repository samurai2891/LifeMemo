import AVFoundation
import Foundation

/// Coordinates the full recording → preprocessing → recognition → correction pipeline.
///
/// Bridges `AudioEngineManager` and `SpeechRecognitionManager`, forwarding
/// preprocessed audio buffers to the speech recognizer and publishing
/// transcription events and audio levels for the UI layer.
@Observable
final class LiveTranscriber: @unchecked Sendable {
    private(set) var state: RecordingState = .idle
    private(set) var currentText: String = ""
    private(set) var currentLevel: AudioLevel = .silence
    private(set) var segments: [TranscriptionSegment] = []

    let transcriptionStream: AsyncStream<TranscriptionEvent>
    let audioLevelStream: AsyncStream<AudioLevel>

    private let audioEngine: AudioEngineManager
    private let recognitionManager: SpeechRecognitionManager
    private var transcriptionContinuation: AsyncStream<TranscriptionEvent>.Continuation?
    private var levelContinuation: AsyncStream<AudioLevel>.Continuation?

    // Background tasks for forwarding streams
    private var bufferForwardTask: Task<Void, Never>?
    private var levelForwardTask: Task<Void, Never>?
    private var transcriptionForwardTask: Task<Void, Never>?

    init(
        textCorrector: TextCorrectionProtocol? = nil,
        locale: Locale = Locale(identifier: "ja-JP")
    ) {
        self.audioEngine = AudioEngineManager()
        self.recognitionManager = SpeechRecognitionManager(
            locale: locale,
            textCorrector: textCorrector
        )

        var tCont: AsyncStream<TranscriptionEvent>.Continuation!
        self.transcriptionStream = AsyncStream { tCont = $0 }
        self.transcriptionContinuation = tCont

        var lCont: AsyncStream<AudioLevel>.Continuation!
        self.audioLevelStream = AsyncStream { lCont = $0 }
        self.levelContinuation = lCont
    }

    deinit {
        transcriptionContinuation?.finish()
        levelContinuation?.finish()
    }

    /// Start recording, preprocessing, and transcription.
    func start() async throws {
        guard state == .idle || isErrorState else { return }
        state = .preparing
        segments = []
        currentText = ""

        do {
            // Start audio engine (configures session, installs tap)
            try audioEngine.start()

            // Start speech recognition
            try recognitionManager.startRecognition()

            // Forward preprocessed buffers to recognizer
            startBufferForwarding()

            // Forward audio levels to UI
            startLevelForwarding()

            // Forward transcription events
            startTranscriptionForwarding()

            state = .recording
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }

    /// Stop recording and finalize transcription.
    func stop() async {
        guard state == .recording else { return }
        state = .stopping

        // Cancel forwarding tasks
        bufferForwardTask?.cancel()
        levelForwardTask?.cancel()
        transcriptionForwardTask?.cancel()

        // Stop recognition first (to get final result)
        recognitionManager.stopRecognition()

        // Then stop audio engine
        audioEngine.stop()

        // Finish our own streams
        transcriptionContinuation?.finish()
        levelContinuation?.finish()

        state = .idle
    }

    // MARK: - Stream forwarding

    private func startBufferForwarding() {
        let engine = audioEngine
        let recognizer = recognitionManager
        bufferForwardTask = Task.detached { [weak engine, weak recognizer] in
            guard let engine else { return }
            for await buffer in engine.processedBufferStream {
                guard !Task.isCancelled else { break }
                recognizer?.appendBuffer(buffer)
            }
        }
    }

    private func startLevelForwarding() {
        let engine = audioEngine
        let levelCont = levelContinuation
        levelForwardTask = Task.detached { [weak self, weak engine, levelCont] in
            guard let engine else { return }
            for await level in engine.audioLevelStream {
                guard !Task.isCancelled else { break }
                levelCont?.yield(level)
                await MainActor.run {
                    self?.currentLevel = level
                }
            }
        }
    }

    private func startTranscriptionForwarding() {
        let recognizer = recognitionManager
        let tCont = transcriptionContinuation
        transcriptionForwardTask = Task.detached { [weak self, weak recognizer, tCont] in
            guard let recognizer else { return }
            for await event in recognizer.transcriptionStream {
                guard !Task.isCancelled else { break }
                tCont?.yield(event)
                await MainActor.run {
                    switch event {
                    case .partial(let text):
                        self?.currentText = text
                    case .finalResult(let segment):
                        self?.currentText = segment.correctedText
                        self?.segments.append(segment)
                    case .error(let message):
                        self?.state = .error(message)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var isErrorState: Bool {
        if case .error = state { return true }
        return false
    }
}
