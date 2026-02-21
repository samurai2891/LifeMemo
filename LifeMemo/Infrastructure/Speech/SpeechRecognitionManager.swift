import AVFoundation
import Foundation
import Speech

/// Manages SFSpeechRecognizer for real-time streaming transcription.
///
/// Receives preprocessed audio buffers via `appendBuffer(_:)` and produces
/// `TranscriptionEvent`s through an `AsyncStream`. Applies text correction
/// on partial (lightweight) and final (full) results.
///
/// Configured for on-device recognition with Japanese locale by default.
@Observable
final class SpeechRecognitionManager: @unchecked Sendable {
    private(set) var isRecognizing = false

    let transcriptionStream: AsyncStream<TranscriptionEvent>
    private var transcriptionContinuation: AsyncStream<TranscriptionEvent>.Continuation?

    private let locale: Locale
    private let textCorrector: TextCorrectionProtocol?

    // Thread-safe access to recognition request (accessed from audio thread + MainActor)
    private let lock = NSLock()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var startTime: Date?

    init(
        locale: Locale = Locale(identifier: "ja-JP"),
        textCorrector: TextCorrectionProtocol? = nil
    ) {
        self.locale = locale
        self.textCorrector = textCorrector

        var cont: AsyncStream<TranscriptionEvent>.Continuation!
        self.transcriptionStream = AsyncStream { cont = $0 }
        self.transcriptionContinuation = cont
    }

    deinit {
        transcriptionContinuation?.finish()
    }

    /// Append a preprocessed audio buffer to the recognition request.
    ///
    /// Called from the audio tap callback. Thread-safe via NSLock.
    nonisolated func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = recognitionRequest
        lock.unlock()
        // SFSpeechAudioBufferRecognitionRequest.append is itself thread-safe
        request?.append(buffer)
    }

    /// Start the speech recognition task.
    func startRecognition() throws {
        guard !isRecognizing else { return }

        let speechRecognizer = SFSpeechRecognizer(locale: locale)
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            transcriptionContinuation?.yield(
                .error("音声認識が利用できません")
            )
            return
        }

        // Prefer on-device recognition for privacy and speed
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
        request.taskHint = .dictation
        request.addsPunctuation = true

        lock.lock()
        self.recognizer = speechRecognizer
        self.recognitionRequest = request
        self.startTime = Date()
        lock.unlock()

        // Capture for the callback
        let continuation = self.transcriptionContinuation
        let corrector = self.textCorrector
        let recognitionLocale = self.locale
        let recordingStartTime = Date()

        let task = speechRecognizer.recognitionTask(
            with: request
        ) { result, error in
            if let error {
                continuation?.yield(.error(error.localizedDescription))
                return
            }

            guard let result else { return }

            let rawText = result.bestTranscription.formattedString

            if result.isFinal {
                // Apply full correction pipeline
                Task { @MainActor in
                    let correctedText: String
                    if let corrector {
                        let output = await corrector.correct(
                            rawText, locale: recognitionLocale
                        )
                        correctedText = output.correctedText
                    } else {
                        correctedText = rawText
                    }

                    let segment = TranscriptionSegment(
                        text: rawText,
                        correctedText: correctedText,
                        confidence: self.averageConfidence(result),
                        timestamp: recordingStartTime,
                        duration: Date().timeIntervalSince(recordingStartTime)
                    )
                    continuation?.yield(.finalResult(segment))
                }
            } else {
                // Apply lightweight correction for live display
                Task { @MainActor in
                    let displayText: String
                    if let corrector {
                        let output = await corrector.correctLive(
                            rawText, locale: recognitionLocale
                        )
                        displayText = output.correctedText
                    } else {
                        displayText = rawText
                    }
                    continuation?.yield(.partial(displayText))
                }
            }
        }

        lock.lock()
        self.recognitionTask = task
        lock.unlock()
        isRecognizing = true
    }

    /// Stop the recognition task and finalize.
    func stopRecognition() {
        lock.lock()
        let request = recognitionRequest
        let task = recognitionTask
        recognitionRequest = nil
        recognitionTask = nil
        recognizer = nil
        startTime = nil
        lock.unlock()

        request?.endAudio()
        task?.cancel()

        transcriptionContinuation?.finish()
        isRecognizing = false
    }

    // MARK: - Helpers

    private func averageConfidence(_ result: SFSpeechRecognitionResult) -> Float {
        let segments = result.bestTranscription.segments
        guard !segments.isEmpty else { return 0 }
        let total = segments.reduce(Float(0)) { $0 + $1.confidence }
        return total / Float(segments.count)
    }
}
