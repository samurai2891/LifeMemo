import SwiftUI

/// Multi-step onboarding flow for first-time users.
///
/// Steps:
/// 0. Welcome
/// 1. Privacy explanation
/// 2. Always-on consent toggle
/// 3. Permission requests (microphone + speech)
/// 4. Done / get started
struct OnboardingView: View {

    // MARK: - Environment

    @EnvironmentObject private var permissionService: SpeechPermissionService
    @StateObject private var viewModel: OnboardingViewModel

    // MARK: - Callback

    let onComplete: () -> Void

    // MARK: - Init

    init(
        permissionService: SpeechPermissionService,
        onComplete: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: OnboardingViewModel(permissionService: permissionService)
        )
        self.onComplete = onComplete
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressBar
                .padding(.horizontal, 24)
                .padding(.top, 16)

            // Step content
            TabView(selection: $viewModel.currentStep) {
                welcomeStep.tag(0)
                privacyStep.tag(1)
                consentStep.tag(2)
                permissionStep.tag(3)
                doneStep.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)

            // Navigation buttons
            navigationButtons
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let progress = CGFloat(viewModel.currentStep + 1)
                / CGFloat(OnboardingViewModel.totalSteps)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray5))
                    .frame(height: 4)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: totalWidth * progress, height: 4)
                    .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.pulse, isActive: true)

            Text("Welcome to LifeMemo")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Text("Your always-on voice recorder with on-device transcription. Capture every important moment, hands-free.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }

    // MARK: - Step 1: Privacy

    private var privacyStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Your Privacy Matters")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 16) {
                privacyRow(
                    icon: "iphone",
                    title: "On-Device Only",
                    detail: "All audio and transcription stays on your device. Nothing is uploaded to any server."
                )

                privacyRow(
                    icon: "waveform.path",
                    title: "Always-On Recording",
                    detail: "LifeMemo records continuously while active. A visible indicator is always shown."
                )

                privacyRow(
                    icon: "trash",
                    title: "You Control Your Data",
                    detail: "Delete audio files at any time while keeping transcripts, or delete everything."
                )
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding()
    }

    private func privacyRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step 2: Consent

    private var consentStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text("Always-On Consent")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text("LifeMemo continuously records audio while a session is active. This is essential for capturing everything without manual intervention.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Toggle(isOn: $viewModel.hasAcceptedConsent) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("I understand and consent")
                        .font(.subheadline.bold())

                    Text("I agree that LifeMemo will record audio continuously during active sessions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.accentColor)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding()
    }

    // MARK: - Step 3: Permissions

    private var permissionStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "mic.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text("Permissions Required")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text("LifeMemo needs access to your microphone and speech recognition to record and transcribe audio.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 12) {
                permissionStatusRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    state: permissionService.mic
                )

                permissionStatusRow(
                    icon: "waveform.badge.mic",
                    title: "Speech Recognition",
                    state: permissionService.speech
                )
            }
            .padding(.horizontal, 24)

            if let error = viewModel.permissionError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)

                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
            }

            Button {
                Task {
                    await viewModel.requestPermissions()
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isRequestingPermission {
                        ProgressView()
                            .tint(.white)
                    }

                    Text(
                        permissionService.allGranted
                            ? "Permissions Granted"
                            : "Grant Permissions"
                    )
                    .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isRequestingPermission || permissionService.allGranted)
            .padding(.horizontal, 24)

            if !permissionService.allGranted && permissionService.mic == .denied {
                Button("Open Settings") {
                    openAppSettings()
                }
                .font(.subheadline)
            }

            Spacer()
        }
        .padding()
        .onAppear {
            permissionService.refresh()
        }
    }

    private func permissionStatusRow(
        icon: String,
        title: String,
        state: PermissionState
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            Text(title)
                .font(.subheadline)

            Spacer()

            statusBadge(for: state)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func statusBadge(for state: PermissionState) -> some View {
        switch state {
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .font(.caption.bold())
                .foregroundStyle(.green)

        case .denied:
            Label("Denied", systemImage: "xmark.circle.fill")
                .font(.caption.bold())
                .foregroundStyle(.red)

        case .unknown:
            Label("Not Set", systemImage: "questionmark.circle")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 4: Done

    private var doneStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Text("Start your first recording session and let LifeMemo capture everything for you.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if viewModel.currentStep > 0 {
                Button {
                    withAnimation { viewModel.goBack() }
                } label: {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
            }

            Button {
                if viewModel.isOnLastStep {
                    viewModel.completeOnboarding()
                    onComplete()
                } else {
                    withAnimation { viewModel.advance() }
                }
            } label: {
                Text(viewModel.isOnLastStep ? "Get Started" : "Continue")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canAdvanceCurrentStep)
        }
    }

    private var canAdvanceCurrentStep: Bool {
        switch viewModel.currentStep {
        case 2:
            return viewModel.canAdvanceFromConsent
        case 3:
            return permissionService.allGranted
        default:
            return true
        }
    }

    // MARK: - Helpers

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    OnboardingView(
        permissionService: SpeechPermissionService(),
        onComplete: {}
    )
    .environmentObject(SpeechPermissionService())
}
