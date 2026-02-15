import SwiftUI

/// Full session detail screen showing summary, transcript, Q&A,
/// highlights, chunk status, and action buttons for export and deletion.
struct SessionDetailView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SessionDetailViewModel

    // MARK: - Init

    init(sessionId: UUID, container: AppContainer) {
        _viewModel = StateObject(
            wrappedValue: SessionDetailViewModel(
                sessionId: sessionId,
                repository: container.repository,
                qnaService: container.qna,
                summarizer: container.summarizer,
                exportService: container.exportService
            )
        )
    }

    // MARK: - Body

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading session...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let session = viewModel.session {
                sessionContent(session)
            } else {
                ContentUnavailableView(
                    "Session Not Found",
                    systemImage: "questionmark.folder",
                    description: Text("This session may have been deleted.")
                )
            }
        }
        .navigationTitle(viewModel.session?.title.isEmpty == false
            ? viewModel.session!.title
            : "Session Detail"
        )
        .navigationBarTitleDisplayMode(.inline)
        .overlay { RecordingIndicatorOverlay() }
        .sheet(isPresented: $viewModel.showExportSheet) {
            if let url = viewModel.exportFileURL {
                ShareSheet(activityItems: [url])
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .confirmationDialog(
            "Delete Audio",
            isPresented: $viewModel.showDeleteAudioConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Audio, Keep Transcript", role: .destructive) {
                viewModel.deleteAudioKeepTranscript()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Audio files will be permanently deleted. Transcripts will be preserved.")
        }
        .confirmationDialog(
            "Delete Session",
            isPresented: $viewModel.showDeleteSessionConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                viewModel.deleteSessionCompletely()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the session, audio, and all transcripts.")
        }
        .onChange(of: viewModel.didDeleteSession) { _, deleted in
            if deleted { dismiss() }
        }
        .onAppear {
            viewModel.loadSession()
        }
    }

    // MARK: - Session Content

    private func sessionContent(_ session: SessionSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                sessionHeader(session)

                Divider()

                // Summary section
                summarySection(session)

                Divider()

                // Ask section
                askSection

                Divider()

                // Highlights
                if !viewModel.highlights.isEmpty {
                    highlightsSection
                    Divider()
                }

                // Full transcript
                transcriptSection

                Divider()

                // Chunk status
                chunkStatusSection

                Divider()

                // Actions
                actionsSection(session)
            }
            .padding()
        }
    }

    // MARK: - Header

    private func sessionHeader(_ session: SessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StatusBadge(status: session.status)

                if !session.audioKept {
                    Label("Audio Removed", systemImage: "speaker.slash.fill")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }

                Spacer()
            }

            HStack(spacing: 16) {
                Label {
                    Text(session.startedAt, style: .date)
                        + Text(" ")
                        + Text(session.startedAt, style: .time)
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let endedAt = session.endedAt {
                let duration = endedAt.timeIntervalSince(session.startedAt)
                Label(
                    RecordingIndicatorOverlay.formatElapsed(duration),
                    systemImage: "clock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Label(
                LanguageMode(rawValue: session.languageMode)?.displayName ?? "Auto",
                systemImage: "globe"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Summary Section

    @ViewBuilder
    private func summarySection(_ session: SessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Summary", systemImage: "doc.text")
                    .font(.headline)

                Spacer()

                Button {
                    viewModel.buildSummary()
                } label: {
                    HStack(spacing: 4) {
                        if viewModel.isBuildingSummary {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text(session.summary != nil ? "Rebuild" : "Generate")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isBuildingSummary)
            }

            if let summary = session.summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("No summary available. Tap Generate to create one.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
    }

    // MARK: - Ask Section

    private var askSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ask a Question", systemImage: "questionmark.bubble")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("Ask about this session...", text: $viewModel.questionText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        viewModel.askQuestion()
                    }

                Button {
                    viewModel.askQuestion()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .disabled(
                    viewModel.questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || viewModel.isAskingQuestion
                )
            }

            if viewModel.isAskingQuestion {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.answerEmpty {
                Text("No relevant segments found for this question.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            if !viewModel.answerSegments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.answerSegments) { segment in
                        AnswerSegmentRow(segment: segment)
                    }

                    Button("Clear") {
                        viewModel.clearAnswer()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Highlights Section

    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Highlights", systemImage: "star.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            ForEach(viewModel.highlights) { highlight in
                HStack(spacing: 10) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)

                    Text(formatMs(highlight.atMs))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.accentColor)

                    if let label = highlight.label {
                        Text(label)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Transcript Section

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Full Transcript", systemImage: "text.alignleft")
                .font(.headline)

            if viewModel.transcript.isEmpty {
                Text("No transcript available yet.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                Text(viewModel.transcript)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineSpacing(4)
            }
        }
    }

    // MARK: - Chunk Status Section

    private var chunkStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Chunks (\(viewModel.chunks.count))", systemImage: "square.stack.3d.up")
                .font(.headline)

            if viewModel.chunks.isEmpty {
                Text("No chunks recorded.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.chunks) { chunk in
                        ChunkStatusRow(chunk: chunk)
                    }
                }
            }
        }
    }

    // MARK: - Actions Section

    private func actionsSection(_ session: SessionSummary) -> some View {
        VStack(spacing: 12) {
            Label("Actions", systemImage: "ellipsis.circle")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                ActionButton(
                    title: "Export MD",
                    icon: "doc.richtext",
                    color: Color.accentColor
                ) {
                    viewModel.exportMarkdown()
                }

                ActionButton(
                    title: "Export TXT",
                    icon: "doc.plaintext",
                    color: Color.accentColor
                ) {
                    viewModel.exportText()
                }
            }

            HStack(spacing: 12) {
                if session.audioKept {
                    ActionButton(
                        title: "Remove Audio",
                        icon: "speaker.slash",
                        color: .orange
                    ) {
                        viewModel.showDeleteAudioConfirm = true
                    }
                }

                ActionButton(
                    title: "Delete Session",
                    icon: "trash",
                    color: .red
                ) {
                    viewModel.showDeleteSessionConfirm = true
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatMs(_ ms: Int64) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Answer Segment Row

private struct AnswerSegmentRow: View {

    let segment: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(segment.segmentText)
                .font(.subheadline)
                .lineLimit(3)

            HStack(spacing: 8) {
                Text(formatTimeRange(start: segment.startMs, end: segment.endMs))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func formatTimeRange(start: Int64, end: Int64) -> String {
        let startSec = start / 1000
        let endSec = end / 1000
        return String(
            format: "%02d:%02d - %02d:%02d",
            startSec / 60, startSec % 60,
            endSec / 60, endSec % 60
        )
    }
}

// MARK: - Chunk Status Row

private struct ChunkStatusRow: View {

    let chunk: ChunkDisplayInfo

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(chunk.index + 1)")
                .font(.caption.bold().monospacedDigit())
                .frame(width: 36, alignment: .leading)

            Text(chunk.statusLabel)
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(chunk.statusColor.opacity(0.15))
                .foregroundStyle(chunk.statusColor)
                .clipShape(Capsule())

            Spacer()

            if chunk.durationSec > 0 {
                Text(String(format: "%.0fs", chunk.durationSec))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if chunk.audioDeleted {
                Image(systemName: "speaker.slash.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Action Button

private struct ActionButton: View {

    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)

                Text(title)
                    .font(.caption.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
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

#Preview {
    Text("SessionDetailView requires AppContainer")
}
