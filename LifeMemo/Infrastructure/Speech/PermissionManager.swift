import AVFoundation
import Foundation
import Speech

/// Manages microphone and speech recognition permissions.
///
/// Provides an observable `state` property for the UI to react to
/// permission changes. Handles requesting and checking both permissions
/// required for live transcription.
@Observable
final class PermissionManager: Sendable {
    private(set) var state: PermissionState = .unknown

    /// Request both microphone and speech recognition permissions.
    func requestAll() async {
        await requestMicrophonePermission()
        await requestSpeechPermission()
    }

    /// Check current authorization status without prompting.
    func checkCurrent() {
        let micStatus = currentMicrophoneStatus()
        let speechStatus = currentSpeechStatus()
        state = PermissionState(
            microphone: micStatus,
            speechRecognition: speechStatus
        )
    }

    // MARK: - Microphone

    private func requestMicrophonePermission() async {
        #if os(iOS)
        let granted = await AVAudioApplication.requestRecordPermission()
        let status: PermissionStatus = granted ? .authorized : .denied
        #else
        let status: PermissionStatus = .authorized
        #endif
        state = PermissionState(
            microphone: status,
            speechRecognition: state.speechRecognition
        )
    }

    private func currentMicrophoneStatus() -> PermissionStatus {
        #if os(iOS)
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .granted:
            return .authorized
        @unknown default:
            return .notDetermined
        }
        #else
        return .authorized
        #endif
    }

    // MARK: - Speech Recognition

    private func requestSpeechPermission() async {
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        let status = mapSpeechStatus(authStatus)
        state = PermissionState(
            microphone: state.microphone,
            speechRecognition: status
        )
    }

    private func currentSpeechStatus() -> PermissionStatus {
        mapSpeechStatus(SFSpeechRecognizer.authorizationStatus())
    }

    private func mapSpeechStatus(
        _ status: SFSpeechRecognizerAuthorizationStatus
    ) -> PermissionStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .authorized:
            return .authorized
        @unknown default:
            return .notDetermined
        }
    }
}
