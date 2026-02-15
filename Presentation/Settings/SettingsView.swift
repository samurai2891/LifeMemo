import SwiftUI

/// Settings screen with language picker, permission status, and app info.
struct SettingsView: View {

    // MARK: - Environment

    @EnvironmentObject private var permissionService: SpeechPermissionService
    @StateObject private var viewModel: SettingsViewModel

    // MARK: - Init

    init(container: AppContainer) {
        _viewModel = StateObject(
            wrappedValue: SettingsViewModel(
                permissionService: container.speechPermission
            )
        )
    }

    // MARK: - Body

    var body: some View {
        Form {
            languageSection
            permissionsSection
            privacySection
            aboutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { RecordingIndicatorOverlay() }
        .onAppear {
            viewModel.refreshPermissions()
        }
    }

    // MARK: - Language Section

    private var languageSection: some View {
        Section {
            Picker("Language", selection: $viewModel.selectedLanguageMode) {
                ForEach(LanguageMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("Transcription")
        } footer: {
            Text("Select the language for speech recognition. Auto will attempt to detect the language automatically.")
        }
    }

    // MARK: - Permissions Section

    private var permissionsSection: some View {
        Section {
            permissionRow(
                icon: "mic.fill",
                title: "Microphone",
                state: permissionService.mic
            )

            permissionRow(
                icon: "waveform.badge.mic",
                title: "Speech Recognition",
                state: permissionService.speech
            )

            if permissionService.mic == .denied || permissionService.speech == .denied {
                Button {
                    openAppSettings()
                } label: {
                    Label("Open System Settings", systemImage: "gear")
                }
            }
        } header: {
            Text("Permissions")
        } footer: {
            Text("Both permissions are required for recording and transcription.")
        }
    }

    private func permissionRow(
        icon: String,
        title: String,
        state: PermissionState
    ) -> some View {
        HStack {
            Label(title, systemImage: icon)

            Spacer()

            switch state {
            case .granted:
                Text("Granted")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .denied:
                Text("Denied")
                    .font(.caption)
                    .foregroundStyle(.red)
            case .unknown:
                Text("Not Requested")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("On-Device Processing")
                        .font(.subheadline)
                    Text("All audio recording and speech recognition happens locally on your device. No data is sent to any server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
            }

            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Data Control")
                        .font(.subheadline)
                    Text("You can delete audio files while keeping transcripts, or delete entire sessions at any time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(Color.accentColor)
            }
        } header: {
            Text("Privacy")
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Build")
                Spacer()
                Text(buildNumber)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("About")
        } footer: {
            Text("LifeMemo - Always-on voice recorder with on-device transcription.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    NavigationStack {
        Text("SettingsView requires AppContainer")
    }
}
