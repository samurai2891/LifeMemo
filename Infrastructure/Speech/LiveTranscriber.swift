import Foundation
import Speech
import AVFAudio

/// Provides real-time speech-to-text preview during recording.
///
/// Uses SFSpeechAudioBufferRecognitionRequest with AVAudioEngine tap.
/// This is UI-preview only; persistent transcription is handled by TranscriptionQueueActor.
/// The 60-second SFSpeechRecognizer limit is handled by restarting the recognition task
/// at 55 seconds, synchronized with chunk rotation.
@MainActor
final class LiveTranscriber: ObservableObject {

    // MARK: - Types

    enum State: Equatable {
        case idle
        case listening
        case paused
        case error(String)
    }

    // MARK: - Published

    @Published private(set) var state: State = .idle
    @Published private(set) var partialText: String = ""
    @Published private(set) var confirmedSegments: [String] = []

    // MARK: - Private

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var restartTimer: Timer?
    private var currentLocale: Locale = .current

    // MARK: - Lifecycle

    func start(locale: Locale) {
        currentLocale = locale
        speechRecognizer = SFSpeechRecognizer(locale: locale)

        guard let recognizer = speechRecognizer,
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            state = .error("On-device recognition not available")
            return
        }

        do {
            try startRecognition(recognizer: recognizer)
            state = .listening
        } catch {
            state = .error(
                "Failed to start live transcription: \(error.localizedDescription)"
            )
        }
    }

    func stop() {
        stopRecognition()
        state = .idle
        partialText = ""
    }

    func pause() {
        guard state == .listening else { return }
        stopRecognition()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            state = .error("Recognizer no longer available")
            return
        }
        do {
            try startRecognition(recognizer: recognizer)
            state = .listening
        } catch {
            state = .error("Failed to resume: \(error.localizedDescription)")
        }
    }

    var fullText: String {
        let confirmed = confirmedSegments.joined(separator: " ")
        if partialText.isEmpty {
            return confirmed
        }
        return confirmed.isEmpty ? partialText : confirmed + " " + partialText
    }

    // MARK: - Private

    private func startRecognition(recognizer: SFSpeechRecognizer) throws {
        // Cancel any existing
        recognitionTask?.cancel()
        recognitionRequest = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Remove existing tap if any
        inputNode.removeTap(onBus: 0)

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: recordingFormat
        ) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer.recognitionTask(
            with: request
        ) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.partialText = result.bestTranscription.formattedString

                    if result.isFinal {
                        let finalText = result.bestTranscription.formattedString
                        if !finalText.isEmpty {
                            self.confirmedSegments.append(finalText)
                        }
                        self.partialText = ""
                    }
                }

                if let error {
                    // Ignore cancellation errors during normal restart
                    let nsError = error as NSError
                    let ignoredCodes: Set<Int> = [216, 209]
                    if !ignoredCodes.contains(nsError.code) {
                        self.state = .error(error.localizedDescription)
                    }
                }
            }
        }

        // Schedule restart at 55 seconds to handle 60-second limit
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(
            withTimeInterval: 55,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.restartRecognition()
            }
        }
    }

    private func restartRecognition() {
        guard state == .listening else { return }

        // Save current partial as confirmed
        if !partialText.isEmpty {
            confirmedSegments.append(partialText)
            partialText = ""
        }

        stopRecognition()

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            state = .error("Recognizer unavailable after restart")
            return
        }

        do {
            try startRecognition(recognizer: recognizer)
        } catch {
            state = .error(
                "Failed to restart recognition: \(error.localizedDescription)"
            )
        }
    }

    private func stopRecognition() {
        restartTimer?.invalidate()
        restartTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }
}
