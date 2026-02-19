import Foundation
import LocalAuthentication

/// Manages app lock state using biometric authentication (Face ID / Touch ID).
///
/// When enabled, the app requires authentication after returning from background.
/// Falls back to device passcode if biometrics are unavailable.
@MainActor
final class AppLockManager: ObservableObject {

    // MARK: - Constants

    private static let enabledKey = "appLockEnabled"

    // MARK: - Published State

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
        }
    }
    @Published private(set) var isLocked: Bool = false

    // MARK: - Init

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    // MARK: - Biometric Info

    var biometricType: BiometricType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        @unknown default: return .none
        }
    }

    enum BiometricType {
        case faceID
        case touchID
        case opticID
        case none

        var displayName: String {
            switch self {
            case .faceID: return "Face ID"
            case .touchID: return "Touch ID"
            case .opticID: return "Optic ID"
            case .none: return String(localized: "Passcode")
            }
        }

        var systemImage: String {
            switch self {
            case .faceID: return "faceid"
            case .touchID: return "touchid"
            case .opticID: return "opticid"
            case .none: return "lock.fill"
            }
        }
    }

    // MARK: - Lock / Unlock

    func lock() {
        guard isEnabled else { return }
        isLocked = true
    }

    func authenticate() async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        let reason = "Unlock LifeMemo to access your recordings"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication, // Falls back to passcode
                localizedReason: reason
            )
            if success {
                isLocked = false
            }
            return success
        } catch {
            return false
        }
    }
}
