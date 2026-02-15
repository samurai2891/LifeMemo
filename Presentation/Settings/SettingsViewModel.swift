import Foundation

/// ViewModel for the Settings screen.
///
/// Manages language preference stored in UserDefaults and provides
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
    }

    // MARK: - Actions

    func refreshPermissions() {
        permissionService.refresh()
    }
}
