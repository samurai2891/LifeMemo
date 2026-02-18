import SwiftUI

/// Full-screen lock view requiring authentication to access the app.
///
/// Displays app icon and unlock button. Automatically attempts biometric
/// authentication on appear.
struct LockScreenView: View {

    @EnvironmentObject private var appLockManager: AppLockManager
    @State private var authFailed = false

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.accentColor)

                Text("LifeMemo")
                    .font(.largeTitle.bold())

                Text("Locked")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                if authFailed {
                    Text("Authentication failed. Please try again.")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.bottom, 8)
                }

                Button {
                    Task {
                        authFailed = false
                        let success = await appLockManager.authenticate()
                        if !success {
                            authFailed = true
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: appLockManager.biometricType.systemImage)
                        Text("Unlock")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 40)

                Spacer()
                    .frame(height: 60)
            }
        }
        .onAppear {
            Task {
                let success = await appLockManager.authenticate()
                if !success {
                    authFailed = true
                }
            }
        }
    }
}
