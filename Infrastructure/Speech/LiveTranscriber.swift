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
    @Published private(set) var confirmedSegments: [LiveSegment] = []

    // MARK: - Private

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var restartTimer: Timer?
    private var currentLocale: Locale = .current
    private var nextCycleIndex: Int = 0

    // MARK: - Lifecycle

    func start(locale: Locale) {
        currentLocale = locale
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        confirmedSegments = []
        nextCycleIndex = 0

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            state = .error("Speech recognition not available")
            return
        }

        let mode = RecognitionMode.load()
        if mode.requiresOnDevice {
            guard recognizer.supportsOnDeviceRecognition else {
                state = .error("On-device recognition not available")
                return
            }
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
        // confirmedSegments are cleared separately via reset() after coordinator cleanup
    }

    /// Clears all accumulated segments from memory. Called by the coordinator
    /// after the ViewModel has captured the segments.
    func reset() {
        confirmedSegments = []
        nextCycleIndex = 0
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
        let confirmed = confirmedSegments.map(\.text).joined(separator: " ")
        if partialText.isEmpty {
            return confirmed
        }
        return confirmed.isEmpty ? partialText : confirmed + " " + partialText
    }

    /// Updates the text of a confirmed segment by ID. Returns a new array with the
    /// updated segment (immutable pattern). Called from RecordingViewModel on save.
    func updateSegmentText(id: UUID, newText: String) {
        confirmedSegments = confirmedSegments.map { segment in
            segment.id == id ? segment.withText(newText) : segment
        }
    }

    // MARK: - Private

    private func startRecognition(recognizer: SFSpeechRecognizer) throws {
        // Cancel any existing
        recognitionTask?.cancel()
        recognitionRequest = nil

        let mode = RecognitionMode.load()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = mode.requiresOnDevice
        request.addsPunctuation = true
        request.taskHint = .dictation

        // Provide recent confirmed text as contextual hints for better accuracy
        if !confirmedSegments.isEmpty {
            let recentWords = confirmedSegments.suffix(3)
                .map(\.text)
                .joined(separator: " ")
                .split(separator: " ")
                .suffix(100)
                .map(String.init)
            if !recentWords.isEmpty {
                request.contextualStrings = recentWords
            }
        }

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

        let currentCycle = nextCycleIndex

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
                            let segment = LiveSegment(
                                id: UUID(),
                                text: finalText,
                                confirmedAt: Date(),
                                cycleIndex: currentCycle
                            )
                            self.confirmedSegments.append(segment)
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

        // Save current partial as confirmed segment
        if !partialText.isEmpty {
            let segment = LiveSegment(
                id: UUID(),
                text: partialText,
                confirmedAt: Date(),
                cycleIndex: nextCycleIndex
            )
            confirmedSegments.append(segment)
            partialText = ""
        }

        nextCycleIndex += 1
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
