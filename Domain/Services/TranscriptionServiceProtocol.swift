import Foundation

protocol TranscriptionServiceProtocol: AnyObject {
    func transcribeFile(url: URL, locale: Locale) async throws -> String
}

enum TranscriptionError: LocalizedError {
    case unsupportedLocale
    case onDeviceNotSupported
    case recognitionFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale:
            return "This language is not supported for transcription."
        case .onDeviceNotSupported:
            return "On-device transcription is not available on this device/language."
        case .recognitionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        }
    }
}
