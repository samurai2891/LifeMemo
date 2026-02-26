import SwiftUI

/// Full-screen recording view displayed during an active recording session.
///
/// Compact layout with a top bar (REC capsule + elapsed time + chunk counter),
/// waveform visualization, scrollable live transcript list with inline editing,
/// and action buttons (highlight + stop).
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
                meterCollector: container.chunkRecorder.meterCollector,
                liveTranscriber: container.liveTranscriber
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

            VStack(spacing: 0) {
                // Compact top bar: [v] ●REC 02:35 [N chunks]
                compactTopBar
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Waveform (60pt)
                waveformView
                    .frame(height: 60)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                // Live transcript list (flexible — takes remaining space)
                liveTranscriptList
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                // Action buttons
                actionButtons
                    .padding(.top, 12)
                    .padding(.bottom, 24)
            }

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

    // MARK: - Compact Top Bar

    private var compactTopBar: some View {
        HStack {
            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            // REC capsule with elapsed time
            if coordinator.state.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .shadow(color: .red.opacity(0.6), radius: 4)

                    Text(NSLocalizedString("REC", comment: ""))
                        .font(.caption.bold())
                        .foregroundStyle(.red)

                    Text(RecordingIndicatorOverlay.formatElapsed(coordinator.elapsedSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .animation(.linear(duration: 0.3), value: coordinator.elapsedSeconds)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.red.opacity(0.1))
                .clipShape(Capsule())
            }

            Spacer()

            // Chunk counter
            chunkCounter
        }
        .frame(height: 44)
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
                    .frame(width: 4, height: max(4, CGFloat(level) * 60))
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
    }

    // MARK: - Live Transcript List

    private var liveTranscriptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    // Confirmed segments
                    ForEach(viewModel.liveSegments) { segment in
                        LiveSegmentRow(
                            segment: segment,
                            isEditing: viewModel.editingSegmentId == segment.id,
                            editText: $viewModel.editingSegmentText,
                            isEdited: viewModel.hasPendingEdit(for: segment.id),
                            onTapEdit: { viewModel.beginSegmentEdit(segment) },
                            onSave: { viewModel.saveSegmentEdit() },
                            onCancel: { viewModel.cancelSegmentEdit() }
                        )
                        .id(segment.id)
                    }

                    // Partial text (currently recognizing)
                    if !viewModel.partialText.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Text(viewModel.partialText)
                                .font(.subheadline.italic())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            TypingIndicator()
                        }
                        .padding(10)
                        .id("partial")
                    }

                    // Empty state
                    if viewModel.liveSegments.isEmpty && viewModel.partialText.isEmpty {
                        Text(NSLocalizedString("Listening...", comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                            .id("empty")
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.liveSegments.count) { _, _ in
                withAnimation {
                    if let last = viewModel.liveSegments.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.partialText) { _, newValue in
                if !newValue.isEmpty {
                    withAnimation {
                        proxy.scrollTo("partial", anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Chunk Counter

    private var chunkCounter: some View {
        HStack(spacing: 4) {
            Image(systemName: "square.stack.3d.up")
                .font(.caption2)

            Text("\(viewModel.chunkCount)")
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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

                Text(NSLocalizedString("Highlight", comment: ""))
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

                Text(NSLocalizedString("Stop", comment: ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 100)
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

#if DEBUG
private struct RecordingView_Previews: PreviewProvider {
    static var previews: some View {
        Text("RecordingView requires AppContainer")
    }
}
#endif
