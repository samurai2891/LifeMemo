import Foundation

/// Prevents content exposure through iOS system features (Spotlight, Siri, App Switcher).
@MainActor
protocol ExposureGuardServiceProtocol: AnyObject {
    var isPrivacyScreenVisible: Bool { get }
    func enforceOnLaunch()
    func handleScenePhase(_ phase: ScenePhaseValue)
    func auditExposureVectors()
}

/// Lightweight mirror of SwiftUI.ScenePhase so Domain stays free of SwiftUI imports.
enum ScenePhaseValue {
    case active
    case inactive
    case background
}
