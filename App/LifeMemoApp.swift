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
                    // App Switcher privacy mask
                    if container.appLockManager.isLocked && container.appLockManager.isEnabled {
                        Color(.systemBackground)
                            .ignoresSafeArea()
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background, .inactive:
                container.appLockManager.lock()
            case .active:
                break
            @unknown default:
                break
            }
        }
    }
}
