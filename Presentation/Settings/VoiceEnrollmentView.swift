import SwiftUI

struct VoiceEnrollmentView: View {

    @StateObject private var viewModel: VoiceEnrollmentViewModel

    init(container: AppContainer) {
        _viewModel = StateObject(
            wrappedValue: VoiceEnrollmentViewModel(
                enrollmentService: container.voiceEnrollmentService,
                permissionService: container.speechPermission,
                audioSession: container.audioSession,
                fileStore: container.fileStore
            )
        )
    }

    var body: some View {
        Form {
            profileSection
            progressSection
            promptSection
            controlsSection
            feedbackSection
        }
        .navigationTitle("Voice Enrollment")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.refresh()
        }
    }

    private var profileSection: some View {
        Section {
            if let profile = viewModel.activeProfile {
                LabeledContent("Display Name", value: profile.displayName)
                LabeledContent("Version", value: "\(profile.version)")
                LabeledContent("Updated", value: profile.updatedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Adaptations", value: "\(profile.adaptationCount)")
                LabeledContent("Accepted Takes", value: "\(profile.qualityStats.acceptedSamples)")
            } else {
                Text("No active enrollment profile.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Current Profile")
        } footer: {
            Text("Enrollment stores only voice feature vectors on-device. Raw enrollment audio is discarded.")
        }
    }

    private var progressSection: some View {
        Section("Progress") {
            ProgressView(value: viewModel.progressRatio)
            Text("\(viewModel.completedCount) / \(viewModel.totalCount) prompts completed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var promptSection: some View {
        Section {
            if let prompt = viewModel.currentPrompt {
                Text(prompt.styleLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("「\(prompt.text)」")
                    .font(.body)
            } else {
                Label("All prompts completed.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        } header: {
            Text("Current Prompt")
        } footer: {
            Text("Read each sentence naturally for 6-8 seconds. Record in a quiet environment and keep microphone distance stable.")
        }
    }

    private var controlsSection: some View {
        Section("Actions") {
            Button {
                Task { await viewModel.toggleRecording() }
            } label: {
                HStack {
                    Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "record.circle.fill")
                    Text(viewModel.isRecording ? "Stop Recording" : "Start Recording")
                    Spacer()
                    if viewModel.isRecording {
                        Text(String(format: "%.1fs", viewModel.elapsedSec))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(viewModel.currentPrompt == nil && !viewModel.isRecording)

            Button("Finalize Enrollment") {
                Task { await viewModel.finalizeEnrollment() }
            }
            .disabled(!viewModel.canFinalize || viewModel.isFinalizing)

            Button("Reset Current Enrollment Session", role: .destructive) {
                Task { await viewModel.resetCurrentEnrollment() }
            }
            .disabled(viewModel.isRecording)

            Button("Delete Active Enrollment Profile", role: .destructive) {
                Task { await viewModel.clearEnrollmentProfile() }
            }
            .disabled(viewModel.isRecording || viewModel.activeProfile == nil)
        }
    }

    private var feedbackSection: some View {
        Section("Status") {
            if let status = viewModel.statusMessage {
                Label(status, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if viewModel.statusMessage == nil && viewModel.errorMessage == nil {
                Text("No messages yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
