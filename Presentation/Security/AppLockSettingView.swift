import SwiftUI

/// Settings row for configuring App Lock (biometric authentication).
struct AppLockSettingView: View {

    @EnvironmentObject private var appLockManager: AppLockManager
    @State private var showAuthError = false

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { appLockManager.isEnabled },
                set: { newValue in
                    if newValue {
                        // Verify biometrics work before enabling
                        Task {
                            let success = await appLockManager.authenticate()
                            if success {
                                appLockManager.isEnabled = true
                            } else {
                                showAuthError = true
                            }
                        }
                    } else {
                        appLockManager.isEnabled = false
                    }
                }
            )) {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("App Lock")
                            .font(.subheadline)
                        Text("Require \(appLockManager.biometricType.displayName) to open LifeMemo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: appLockManager.biometricType.systemImage)
                        .foregroundStyle(Color.accentColor)
                }
            }
        } header: {
            Text("Security")
        } footer: {
            Text("When enabled, LifeMemo will require authentication each time you return to the app.")
        }
        .alert("Authentication Required", isPresented: $showAuthError) {
            Button("OK") {}
        } message: {
            Text("Could not verify your identity. App Lock was not enabled.")
        }
    }
}
