import Speech
import AVFAudio

/// Manages microphone and speech recognition permission states.
///
/// Publishes `mic` and `speech` as `PermissionState` values so the UI can
/// reactively show permission prompts or disabled states. Both permissions
/// must be `.granted` before recording can begin.
@MainActor
final class SpeechPermissionService: ObservableObject {

    // MARK: - Published State

    @Published var mic: PermissionState = .unknown
    @Published var speech: PermissionState = .unknown

    /// Returns `true` when both microphone and speech permissions are granted.
    var allGranted: Bool { mic == .granted && speech == .granted }

    // MARK: - Refresh

    /// Synchronously reads the current permission status from the system.
    ///
    /// Call this on app launch or when returning from Settings to update
    /// the published state without triggering a permission prompt.
    func refresh() {
        mic = Self.mapRecordPermission(
            AVAudioSession.sharedInstance().recordPermission
        )
        speech = Self.mapSpeechAuthorizationStatus(
            SFSpeechRecognizer.authorizationStatus()
        )
    }

    // MARK: - Request

    /// Requests microphone recording permission from the user.
    ///
    /// Updates `mic` to `.granted` or `.denied` based on the user's response.
    func requestMicrophone() async {
        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        mic = granted ? .granted : .denied
    }

    /// Requests speech recognition authorization from the user.
    ///
    /// Updates `speech` to `.granted` or `.denied` based on the user's response.
    func requestSpeech() async {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authorizationStatus in
                continuation.resume(returning: authorizationStatus)
            }
        }
        speech = Self.mapSpeechAuthorizationStatus(status)
    }

    // MARK: - Mapping Helpers

    private static func mapRecordPermission(
        _ permission: AVAudioSession.RecordPermission
    ) -> PermissionState {
        switch permission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    private static func mapSpeechAuthorizationStatus(
        _ status: SFSpeechRecognizerAuthorizationStatus
    ) -> PermissionState {
        switch status {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .unknown
        @unknown default:
            return .unknown
        }
    }
}
