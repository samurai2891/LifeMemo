import SwiftUI

@main
struct LifeMemoApp: App {
    @StateObject private var container = AppContainer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, container.coreData.viewContext)
                .environmentObject(container)
                .environmentObject(container.recordingCoordinator)
                .environmentObject(container.speechPermission)
                .environmentObject(container.appLockManager)
                .overlay {
                    // P1-02: Unconditional privacy screen for App Switcher.
                    // Separate from App Lock — activates even when App Lock is disabled
                    // so the App Switcher thumbnail never reveals content.
                    if container.exposureGuard.isPrivacyScreenVisible {
                        PrivacyOverlayView()
                            .transition(.opacity)
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .inactive, .background:
                container.exposureGuard.handleScenePhase(
                    newPhase == .inactive ? .inactive : .background
                )
                container.appLockManager.lock()
            case .active:
                container.exposureGuard.handleScenePhase(.active)
                container.exposureGuard.auditExposureVectors()
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Privacy Overlay

/// Opaque overlay shown in App Switcher to prevent content leakage.
/// Displays only the app icon and name — no recordings, transcripts, or session data.
private struct PrivacyOverlayView: View {

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)

                Text("LifeMemo")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
            }
        }
    }
}
