import SwiftUI

/// Root view that determines whether to show onboarding or the main app.
///
/// Checks `onboardingComplete` in UserDefaults and routes accordingly.
/// After onboarding completes, transitions to the main `HomeView` with
/// a smooth animation.
struct RootView: View {

    // MARK: - Environment

    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var coordinator: RecordingCoordinator
    @EnvironmentObject private var permissionService: SpeechPermissionService
    @EnvironmentObject private var appLockManager: AppLockManager

    // MARK: - State

    @State private var showOnboarding: Bool

    // MARK: - Init

    init() {
        let isComplete = UserDefaults.standard.bool(
            forKey: OnboardingViewModel.onboardingCompleteKey
        )
        _showOnboarding = State(initialValue: !isComplete)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Group {
                if showOnboarding {
                    OnboardingView(
                        permissionService: permissionService
                    ) {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            showOnboarding = false
                        }
                    }
                    .transition(.opacity)
                } else {
                    HomeView(
                        repository: container.repository,
                        searchService: container.search
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: showOnboarding)

            // App Lock overlay (highest priority)
            if appLockManager.isLocked && appLockManager.isEnabled {
                LockScreenView()
                    .transition(.opacity)
            }
        }
    }
}

#Preview {
    Text("RootView requires AppContainer environment")
}
