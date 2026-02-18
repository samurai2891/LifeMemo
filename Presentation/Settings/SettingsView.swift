import SwiftUI

/// Settings screen with language picker, permission status, and app info.
struct SettingsView: View {

    // MARK: - Environment

    @EnvironmentObject private var permissionService: SpeechPermissionService
    @EnvironmentObject private var container: AppContainer
    @StateObject private var viewModel: SettingsViewModel

    // MARK: - Init

    init(container: AppContainer) {
        _viewModel = StateObject(
            wrappedValue: SettingsViewModel(
                permissionService: container.speechPermission
            )
        )
    }

    // MARK: - State

    @State private var showLogShareSheet = false
    @State private var logFileURL: URL?

    // MARK: - Body

    var body: some View {
        Form {
            languageSection
            audioQualitySection
            summarizationSection
            permissionsSection
            securitySection
            storageSection
            locationSection
            privacySection
            supportSection
            aboutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { RecordingIndicatorOverlay() }
        .onAppear {
            viewModel.refreshPermissions()
        }
        .sheet(isPresented: $showLogShareSheet) {
            if let logFileURL {
                ShareSheet(activityItems: [logFileURL])
            }
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

            if !viewModel.transcriptionCapability.isAvailable {
                Label {
                    Text(viewModel.transcriptionCapability.userMessage)
                        .font(.caption)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Transcription")
        } footer: {
            Text("Select the language for speech recognition. Only Japanese and English are supported for on-device transcription.")
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

    // MARK: - Audio Quality Section

    private var audioQualitySection: some View {
        Section {
            Picker("Recording Quality", selection: $viewModel.audioQualityProfile) {
                ForEach(AudioConfiguration.QualityProfile.allCases) { profile in
                    VStack(alignment: .leading) {
                        Text(profile.displayName)
                    }
                    .tag(profile)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("Audio Quality")
        } footer: {
            Text(viewModel.audioQualityProfile.description)
        }
    }

    // MARK: - Summarization Section

    private var summarizationSection: some View {
        Section {
            NavigationLink {
                BenchmarkResultsView(benchmark: container.summarizationBenchmark)
            } label: {
                Label("Run Benchmark", systemImage: "gauge.with.dots.needle.33percent")
            }
        } header: {
            Text("Summarization")
        } footer: {
            Text("On-device extractive summarization using Apple NaturalLanguage. No data leaves your device.")
        }
    }

    // MARK: - Security Section

    private var securitySection: some View {
        AppLockSettingView()
    }

    // MARK: - Storage Section

    private var storageSection: some View {
        Section {
            NavigationLink {
                StorageManagementView(
                    storageManager: container.storageManager
                )
            } label: {
                Label("Storage", systemImage: "externaldrive")
            }
        } header: {
            Text("Data")
        }
    }

    // MARK: - Location Section

    private var locationSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { container.locationService.isEnabled },
                set: { newValue in
                    container.locationService.isEnabled = newValue
                    if newValue {
                        container.locationService.requestPermission()
                    }
                }
            )) {
                Label("Capture Location", systemImage: "location")
            }
        } header: {
            Text("Location")
        } footer: {
            Text("When enabled, the approximate location will be saved when starting a recording. Location data stays on your device.")
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

    // MARK: - Support Section

    private var supportSection: some View {
        Section {
            Button {
                exportLogs()
            } label: {
                Label("Export Logs", systemImage: "doc.text.magnifyingglass")
            }
        } header: {
            Text("Support")
        } footer: {
            Text("Export diagnostic logs for troubleshooting. No personal data is included.")
        }
    }

    private func exportLogs() {
        do {
            logFileURL = try container.logExporter.exportLogs()
            showLogShareSheet = true
        } catch {
            // Silently fail - logging export failure is not critical
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

// MARK: - Share Sheet (UIKit bridge)

private struct ShareSheet: UIViewControllerRepresentable {

    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

// MARK: - Benchmark Results View

private struct BenchmarkResultsView: View {
    @ObservedObject var benchmark: SummarizationBenchmark

    var body: some View {
        List {
            if benchmark.isRunning {
                HStack {
                    ProgressView()
                    Text(benchmark.currentTest)
                        .font(.subheadline)
                }
            }

            if !benchmark.isRunning && benchmark.results.isEmpty {
                Button("Start Benchmark") {
                    Task { await benchmark.runAll() }
                }
                .frame(maxWidth: .infinity)
            }

            ForEach(benchmark.results) { result in
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.inputSize.rawValue)
                        .font(.subheadline.bold())
                    HStack(spacing: 16) {
                        Label("\(String(format: "%.0f", result.processingTimeMs))ms", systemImage: "clock")
                        Label("\(String(format: "%.0f", result.wordsPerSecond)) w/s", systemImage: "text.word.spacing")
                        Label(result.thermalState, systemImage: "thermometer.medium")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Summarization Benchmark")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await benchmark.runAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(benchmark.isRunning)
            }
        }
    }
}

#Preview {
    NavigationStack {
        Text("SettingsView requires AppContainer")
    }
}
