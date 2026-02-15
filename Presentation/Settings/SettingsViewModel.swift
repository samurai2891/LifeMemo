import Foundation

/// ViewModel for the Settings screen.
///
/// Manages language preference, audio quality profile, and provides
/// read-only access to permission states.
@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: - Constants

    static let languageKey = "selectedLanguageMode"

    // MARK: - Published State

    @Published var selectedLanguageMode: LanguageMode {
        didSet {
            defaults.set(selectedLanguageMode.rawValue, forKey: Self.languageKey)
        }
    }

    @Published var audioQualityProfile: AudioConfiguration.QualityProfile {
        didSet {
            AudioConfiguration.saveProfile(audioQualityProfile)
        }
    }

    // MARK: - Dependencies

    private let defaults: UserDefaults
    let permissionService: SpeechPermissionService

    // MARK: - Init

    init(
        permissionService: SpeechPermissionService,
        defaults: UserDefaults = .standard
    ) {
        self.permissionService = permissionService
        self.defaults = defaults

        let raw = defaults.string(forKey: Self.languageKey) ?? "auto"
        self.selectedLanguageMode = LanguageMode(rawValue: raw) ?? .auto
        self.audioQualityProfile = AudioConfiguration.loadProfile()
    }

    // MARK: - Actions

    func refreshPermissions() {
        permissionService.refresh()
    }
}
