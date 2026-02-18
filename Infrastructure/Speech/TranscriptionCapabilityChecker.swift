import Foundation
import Speech

/// Checks on-device speech recognition capability for a given locale.
///
/// Performs a 3-step check: SFSpeechRecognizer availability, locale support,
/// and on-device recognition support. Provides user-friendly messages.
@MainActor
final class TranscriptionCapabilityChecker {

    enum Capability: Equatable {
        case available
        case unavailableNoRecognizer
        case unavailableNotReady
        case unavailableNoOnDevice

        var isAvailable: Bool {
            self == .available
        }

        var userMessage: String {
            switch self {
            case .available:
                return "On-device transcription is available."
            case .unavailableNoRecognizer:
                return "Speech recognition is not supported for this language on this device."
            case .unavailableNotReady:
                return "Speech recognizer is not available. Please check your device settings."
            case .unavailableNoOnDevice:
                return "On-device speech model is not downloaded. "
                    + "Go to Settings > General > Keyboard > Dictation "
                    + "to download the language model."
            }
        }
    }

    func check(for locale: Locale) -> Capability {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            return .unavailableNoRecognizer
        }

        guard recognizer.isAvailable else {
            return .unavailableNotReady
        }

        guard recognizer.supportsOnDeviceRecognition else {
            return .unavailableNoOnDevice
        }

        return .available
    }

    func check(for languageMode: LanguageMode) -> Capability {
        check(for: languageMode.locale)
    }
}
