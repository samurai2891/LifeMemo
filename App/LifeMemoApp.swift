import SwiftUI

@main
struct LifeMemoApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, container.coreData.viewContext)
                .environmentObject(container)
                .environmentObject(container.recordingCoordinator)
                .environmentObject(container.speechPermission)
        }
    }
}
