import SwiftUI

/// Main recording view with live transcription, audio level meter, and controls.
///
/// Designed for meeting room use: large record button, visible audio levels,
/// and real-time transcription display.
struct RecordingView: View {
    @State private var viewModel = RecordingViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Transcription area
                transcriptionArea
                    .frame(maxHeight: .infinity)

                Divider()

                // Audio level indicator
                audioLevelBar
                    .padding(.horizontal)
                    .padding(.top, 12)

                // Controls
                controlArea
                    .padding(.vertical, 20)
            }
            .navigationTitle("録音")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !viewModel.fullTranscription.isEmpty {
                        Button("クリア") {
                            viewModel.clearTranscription()
                        }
                        .disabled(viewModel.isRecording)
                    }
                }
            }
            .task {
                viewModel.checkPermissions()
            }
            .alert(
                "エラー",
                isPresented: .init(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.clearTranscription() } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - Transcription area

    private var transcriptionArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.fullTranscription.isEmpty {
                    placeholderText
                } else {
                    Text(viewModel.fullTranscription)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var placeholderText: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("録音ボタンを押して開始してください")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("広い会議室でもクリアな文字起こしが可能です")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Audio level bar

    private var audioLevelBar: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))

                    // Level indicator
                    RoundedRectangle(cornerRadius: 4)
                        .fill(levelColor)
                        .frame(
                            width: geometry.size.width * CGFloat(viewModel.audioLevel.rms)
                        )
                        .animation(.linear(duration: 0.05), value: viewModel.audioLevel.rms)
                }
            }
            .frame(height: 8)

            // Speech indicator
            HStack {
                Circle()
                    .fill(viewModel.audioLevel.isSpeech ? .green : .gray)
                    .frame(width: 6, height: 6)
                Text(viewModel.audioLevel.isSpeech ? "音声検出中" : "待機中")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var levelColor: Color {
        let level = viewModel.audioLevel.rms
        if level > 0.5 {
            return .red
        } else if level > 0.2 {
            return .orange
        } else {
            return .green
        }
    }

    // MARK: - Controls

    private var controlArea: some View {
        VStack(spacing: 16) {
            if !viewModel.permissionState.allGranted {
                permissionButton
            }

            recordButton

            stateLabel
        }
    }

    private var recordButton: some View {
        Button {
            Task {
                await viewModel.toggleRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(viewModel.isRecording ? .red : .blue)
                    .frame(width: 72, height: 72)
                    .shadow(
                        color: viewModel.isRecording ? .red.opacity(0.4) : .blue.opacity(0.3),
                        radius: viewModel.isRecording ? 12 : 6
                    )

                Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
            }
        }
        .disabled(
            viewModel.recordingState == .preparing
                || viewModel.recordingState == .stopping
        )
        .accessibilityLabel(viewModel.isRecording ? "録音停止" : "録音開始")
    }

    private var permissionButton: some View {
        Button {
            Task {
                await viewModel.requestPermissions()
            }
        } label: {
            Label("マイクと音声認識を許可", systemImage: "lock.shield")
                .font(.subheadline)
        }
        .buttonStyle(.borderedProminent)
    }

    private var stateLabel: some View {
        Group {
            switch viewModel.recordingState {
            case .idle:
                Text("タップして録音開始")
            case .preparing:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("準備中...")
                }
            case .recording:
                Text("録音中...")
                    .foregroundStyle(.red)
            case .stopping:
                Text("停止中...")
            case .error(let msg):
                Text(msg)
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

#Preview {
    RecordingView()
}
