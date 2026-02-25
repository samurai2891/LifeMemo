import Foundation
import Speech
import AVFAudio

/// Thread-safe holder for the active recognition request.
///
/// Shared between the main actor (which swaps requests during 55-second restart)
/// and the audio render callback. Uses NSLock for synchronization.
final class ActiveRequestHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ newRequest: SFSpeechAudioBufferRecognitionRequest?) {
        lock.withLock { request = newRequest }
    }

    /// Appends a buffer to the active request if one exists.
    /// Buffers arriving during recognition restart (when request is nil) are safely dropped.
    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { request?.append(buffer) }
    }
}

/// Provides real-time speech-to-text preview during recording.
///
/// Uses a dual-path architecture via `AudioEngineManager`:
/// - **Path 1 (Recognition):** Raw voice-processed buffers flow unconditionally to
///   SFSpeechRecognizer — no custom preprocessing, no gating, no buffer dropping.
/// - **Path 2 (UI):** The preprocessed `audioLevelStream` path is currently disabled
///   (waveform is driven by `AudioMeterCollector` from `ChunkedAudioRecorder`).
///
/// The 60-second SFSpeechRecognizer limit is handled by restarting the recognition task
/// at 55 seconds while keeping the audio engine running continuously.
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

    private var audioEngineManager: AudioEngineManager?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var restartTimer: Timer?
    private var currentLocale: Locale = .current
    private var nextCycleIndex: Int = 0

    /// Thread-safe holder used by the audio render callback to append buffers.
    private let activeRequestHolder = ActiveRequestHolder()

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
            // Start audio engine (session already configured by RecordingCoordinator)
            let holder = activeRequestHolder
            let manager = AudioEngineManager(
                // Pod-2 decision: keep waveform driven by AudioMeterCollector and
                // disable the unused audioLevelStream preprocessing path.
                uiLevelPolicy: .disabled,
                rawBufferHandler: { buffer in
                    holder.appendBuffer(buffer)
                }
            )
            try manager.start()
            self.audioEngineManager = manager

            // Start speech recognition
            try startRecognition(recognizer: recognizer)
            state = .listening
        } catch {
            stopEngine()
            state = .error(
                "Failed to start live transcription: \(error.localizedDescription)"
            )
        }
    }

    func stop() {
        stopRecognitionOnly()
        stopEngine()
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
        stopRecognitionOnly()
        stopEngine()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            state = .error("Recognizer no longer available")
            return
        }
        do {
            let holder = activeRequestHolder
            let manager = AudioEngineManager(
                // Keep the same policy on resume to avoid extra CPU on the
                // currently unused UI preprocessing path.
                uiLevelPolicy: .disabled,
                rawBufferHandler: { buffer in
                    holder.appendBuffer(buffer)
                }
            )
            try manager.start()
            self.audioEngineManager = manager
            try startRecognition(recognizer: recognizer)
            state = .listening
        } catch {
            stopEngine()
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

    // MARK: - Recognition

    private func startRecognition(recognizer: SFSpeechRecognizer) throws {
        // Cancel any existing recognition task
        recognitionTask?.cancel()
        recognitionRequest = nil
        activeRequestHolder.set(nil)

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
        activeRequestHolder.set(request)

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

        // Stop only the recognition task — audio engine keeps running
        stopRecognitionOnly()

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

    /// Stops recognition task and request without touching the audio engine.
    /// Used during the 55-second restart cycle to keep audio flowing.
    private func stopRecognitionOnly() {
        restartTimer?.invalidate()
        restartTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        activeRequestHolder.set(nil)
    }

    /// Stops the audio engine.
    private func stopEngine() {
        audioEngineManager?.stop()
        audioEngineManager = nil
    }
}
