import Foundation
import Speech

/// On-device speech transcription using Apple's Speech framework.
///
/// Uses `SFSpeechURLRecognitionRequest` with `requiresOnDeviceRecognition = true`
/// so that audio data never leaves the device. This satisfies privacy requirements
/// but limits support to languages that have on-device models downloaded.
final class OnDeviceTranscriber: TranscriptionServiceProtocol {

    /// Transcribes an audio file at the given URL using on-device recognition.
    ///
    /// - Parameters:
    ///   - url: The file URL of the audio chunk to transcribe.
    ///   - locale: The locale indicating the expected language of the audio.
    /// - Returns: The best transcription as a formatted string.
    /// - Throws: `TranscriptionError` if the locale is unsupported, on-device
    ///   recognition is unavailable, or recognition fails.
    func transcribeFile(url: URL, locale: Locale) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw TranscriptionError.unsupportedLocale
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.onDeviceNotSupported
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = false

            var hasResumed = false

            recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }

                if let error = error {
                    hasResumed = true
                    continuation.resume(
                        throwing: TranscriptionError.recognitionFailed(underlying: error)
                    )
                    return
                }

                if let result = result, result.isFinal {
                    hasResumed = true
                    continuation.resume(
                        returning: result.bestTranscription.formattedString
                    )
                }
            }
        }
    }
}
