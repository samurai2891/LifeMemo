import Foundation

/// ViewModel for the multi-step onboarding flow.
///
/// Manages step progression, consent tracking, and permission requests
/// through the `SpeechPermissionService`. Stores the user's consent flag
/// in UserDefaults so the onboarding is only shown once.
@MainActor
final class OnboardingViewModel: ObservableObject {

    // MARK: - Constants

    static let consentKey = "didAcceptAlwaysOnConsent"
    static let onboardingCompleteKey = "onboardingComplete"
    static let totalSteps = 5

    // MARK: - Published State

    @Published var currentStep: Int = 0
    @Published var hasAcceptedConsent: Bool = false
    @Published private(set) var isRequestingPermission: Bool = false
    @Published private(set) var permissionError: String?

    // MARK: - Dependencies

    private let permissionService: SpeechPermissionService
    private let defaults: UserDefaults

    // MARK: - Computed

    var canAdvanceFromConsent: Bool { hasAcceptedConsent }

    var isOnLastStep: Bool { currentStep >= Self.totalSteps - 1 }

    var isOnboardingNeeded: Bool {
        !defaults.bool(forKey: Self.onboardingCompleteKey)
    }

    // MARK: - Init

    init(
        permissionService: SpeechPermissionService,
        defaults: UserDefaults = .standard
    ) {
        self.permissionService = permissionService
        self.defaults = defaults
    }

    // MARK: - Navigation

    func advance() {
        guard currentStep < Self.totalSteps - 1 else { return }
        currentStep += 1
    }

    func goBack() {
        guard currentStep > 0 else { return }
        currentStep -= 1
    }

    // MARK: - Permissions

    func requestPermissions() async {
        isRequestingPermission = true
        permissionError = nil

        await permissionService.requestMicrophone()
        await permissionService.requestSpeech()

        if permissionService.allGranted {
            permissionError = nil
        } else {
            permissionError = buildPermissionErrorMessage()
        }

        isRequestingPermission = false
    }

    // MARK: - Completion

    func completeOnboarding() {
        defaults.set(hasAcceptedConsent, forKey: Self.consentKey)
        defaults.set(true, forKey: Self.onboardingCompleteKey)
    }

    // MARK: - Private

    private func buildPermissionErrorMessage() -> String {
        var missing: [String] = []
        if permissionService.mic != .granted {
            missing.append("Microphone")
        }
        if permissionService.speech != .granted {
            missing.append("Speech Recognition")
        }
        let names = missing.joined(separator: " and ")
        return "\(names) permission is required. Please enable it in Settings."
    }
}
