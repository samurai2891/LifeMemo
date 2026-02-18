import SwiftUI

/// Full-screen recording view displayed during an active recording session.
///
/// Shows a large elapsed time display, animated waveform visualization,
/// highlight button with haptic feedback, chunk counter, and a prominent
/// stop button.
struct RecordingView: View {

    // MARK: - Environment

    @EnvironmentObject private var coordinator: RecordingCoordinator
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: RecordingViewModel

    // MARK: - State

    @State private var highlightFlash = false

    // MARK: - Init

    init(container: AppContainer) {
        _viewModel = StateObject(
            wrappedValue: RecordingViewModel(
                coordinator: container.recordingCoordinator,
                repository: container.repository,
                meterCollector: container.chunkRecorder.meterCollector
            )
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color.red.opacity(0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                // Top bar
                topBar

                Spacer()

                // Recording indicator
                recordingIndicator

                // Elapsed time
                elapsedTimeDisplay

                // Waveform
                waveformView
                    .frame(height: 80)
                    .padding(.horizontal, 32)

                // Live transcript
                if !viewModel.liveTranscriptText.isEmpty {
                    liveTranscriptArea
                        .frame(maxHeight: 120)
                        .padding(.horizontal, 16)
                }

                // Chunk counter
                chunkCounter

                Spacer()

                // Action buttons
                actionButtons

                Spacer()
                    .frame(height: 24)
            }
            .padding()

            // Highlight flash overlay
            if highlightFlash {
                Color.yellow.opacity(0.15)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onAppear {
            viewModel.startWaveformAnimation()
        }
        .onDisappear {
            viewModel.stopWaveformAnimation()
        }
        .onChange(of: coordinator.state.isRecording) { _, isRecording in
            if !isRecording {
                dismiss()
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            if coordinator.state.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)

                    Text("LIVE")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.red.opacity(0.1))
                .clipShape(Capsule())
            }

            Spacer()

            // Spacer to balance the close button
            Color.clear.frame(width: 44, height: 44)
        }
    }

    // MARK: - Recording Indicator

    private var recordingIndicator: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.red.opacity(0.1))
                    .frame(width: 100, height: 100)

                Circle()
                    .fill(.red.opacity(0.2))
                    .frame(width: 72, height: 72)

                Circle()
                    .fill(.red)
                    .frame(width: 48, height: 48)
                    .shadow(color: .red.opacity(0.4), radius: 12)
            }

            Text("Recording")
                .font(.title3.bold())
                .foregroundStyle(.red)
        }
    }

    // MARK: - Elapsed Time

    private var elapsedTimeDisplay: some View {
        Text(RecordingIndicatorOverlay.formatElapsed(coordinator.elapsedSeconds))
            .font(.system(size: 56, weight: .light, design: .monospaced))
            .foregroundStyle(.primary)
            .contentTransition(.numericText())
            .animation(.linear(duration: 0.3), value: coordinator.elapsedSeconds)
    }

    // MARK: - Waveform

    private var waveformView: some View {
        HStack(spacing: 3) {
            ForEach(Array(viewModel.waveformLevels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [.red.opacity(0.6), .red],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 4, height: max(4, CGFloat(level) * 80))
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
    }

    // MARK: - Live Transcript

    private var liveTranscriptArea: some View {
        ScrollView {
            Text(viewModel.liveTranscriptText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Chunk Counter

    private var chunkCounter: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up")
                .font(.caption)

            Text("\(viewModel.chunkCount) chunks")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(Capsule())
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 48) {
            // Highlight button
            VStack(spacing: 8) {
                Button {
                    viewModel.addHighlight()
                    flashHighlight()
                } label: {
                    Image(systemName: "star.fill")
                        .font(.title2)
                        .foregroundStyle(.yellow)
                        .frame(width: 64, height: 64)
                        .background(
                            Circle()
                                .fill(Color(.secondarySystemGroupedBackground))
                                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                        )
                }

                Text("Highlight")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Stop button
            VStack(spacing: 8) {
                Button {
                    viewModel.stopRecording()
                } label: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white)
                        .frame(width: 28, height: 28)
                        .frame(width: 72, height: 72)
                        .background(
                            Circle()
                                .fill(.red)
                                .shadow(color: .red.opacity(0.4), radius: 8, y: 4)
                        )
                }

                Text("Stop")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Highlight Flash

    private func flashHighlight() {
        withAnimation(.easeIn(duration: 0.1)) {
            highlightFlash = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.3)) {
                highlightFlash = false
            }
        }
    }
}

#Preview {
    Text("RecordingView requires AppContainer")
}
