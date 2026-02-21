import Foundation

/// Events emitted during live speech transcription.
enum TranscriptionEvent: Sendable {
    case partial(String)
    case finalResult(TranscriptionSegment)
    case error(String)
}

/// A finalized segment of transcribed speech.
struct TranscriptionSegment: Sendable, Equatable {
    let text: String
    let correctedText: String
    let confidence: Float
    let timestamp: Date
    let duration: TimeInterval
}

/// Authorization status for a single permission.
enum PermissionStatus: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

/// Combined authorization state for microphone and speech recognition.
struct PermissionState: Sendable, Equatable {
    let microphone: PermissionStatus
    let speechRecognition: PermissionStatus

    var allGranted: Bool {
        microphone == .authorized && speechRecognition == .authorized
    }

    static let unknown = PermissionState(
        microphone: .notDetermined,
        speechRecognition: .notDetermined
    )
}

/// Protocol for managing speech-to-text recognition.
protocol SpeechRecognitionService: Sendable {
    func startTranscription(locale: Locale) async throws
    func stopTranscription() async
    var transcriptionStream: AsyncStream<TranscriptionEvent> { get }
}
