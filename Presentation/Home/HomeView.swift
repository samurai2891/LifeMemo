import SwiftUI

/// Main home screen showing a searchable list of recording sessions
/// with a prominent button to start a new always-on recording.
struct HomeView: View {

    // MARK: - Environment

    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var coordinator: RecordingCoordinator
    @StateObject private var viewModel: HomeViewModel

    // MARK: - State

    @State private var showRecordingView = false
    @State private var selectedLanguage: LanguageMode = .auto
    @State private var showLanguagePicker = false
    @State private var isInEditMode = false

    // MARK: - Init

    init(repository: SessionRepository, searchService: SimpleSearchService) {
        _viewModel = StateObject(
            wrappedValue: HomeViewModel(
                repository: repository,
                searchService: searchService
            )
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                sessionList

                if !isInEditMode {
                    VStack {
                        Spacer()
                        startRecordingButton
                            .padding(.bottom, 24)
                            .padding(.horizontal, 24)
                    }
                }
            }
            .navigationTitle("LifeMemo")
            .toolbar {
                if isInEditMode {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(viewModel.allFilteredSelected
                               ? "Deselect All"
                               : "Select All") {
                            viewModel.toggleSelectAll()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            exitEditMode()
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            viewModel.requestBatchDelete()
                        } label: {
                            Label(
                                String(
                                    format: NSLocalizedString(
                                        "Delete Selected (%lld)",
                                        comment: ""
                                    ),
                                    viewModel.selectedCount
                                ),
                                systemImage: "trash"
                            )
                        }
                        .disabled(viewModel.selectedSessionIds.isEmpty)
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink {
                            AdvancedSearchView()
                                .environmentObject(container)
                                .environmentObject(coordinator)
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 16) {
                            if !viewModel.filteredSessions.isEmpty {
                                Button {
                                    enterEditMode()
                                } label: {
                                    Image(systemName: "checklist")
                                }
                            }
                            NavigationLink {
                                SettingsView(container: container)
                            } label: {
                                Image(systemName: "gear")
                            }
                        }
                    }
                }
            }
            .environment(
                \.editMode,
                isInEditMode
                    ? .constant(.active)
                    : .constant(.inactive)
            )
            .searchable(
                text: $viewModel.searchQuery,
                prompt: "Search sessions..."
            )
            .overlay { RecordingIndicatorOverlay() }
            .fullScreenCover(isPresented: $showRecordingView) {
                RecordingView(container: container)
            }
            .confirmationDialog(
                "Select Language",
                isPresented: $showLanguagePicker,
                titleVisibility: .visible
            ) {
                ForEach(LanguageMode.allCases) { mode in
                    Button(mode.displayName) {
                        selectedLanguage = mode
                        startRecording(language: mode)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Delete Session",
                isPresented: $viewModel.showSwipeDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) {
                    viewModel.swipeDeleteCompletely()
                }
                Button("Cancel", role: .cancel) {
                    viewModel.swipeDeleteTargetId = nil
                }
            } message: {
                Text("Choose how to delete this session. Deleting audio only preserves the transcript.")
            }
            .confirmationDialog(
                "Delete Sessions",
                isPresented: $viewModel.showBatchDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Session", role: .destructive) {
                    viewModel.batchDeleteCompletely()
                    exitEditMode()
                }
                Button("Delete Audio Only", role: .destructive) {
                    viewModel.batchDeleteAudioOnly()
                    exitEditMode()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose how to delete the selected sessions. Deleting audio only preserves transcripts.")
            }
            .alert(
                "Batch Operation Complete",
                isPresented: Binding(
                    get: { viewModel.batchResultMessage != nil },
                    set: { if !$0 { viewModel.batchResultMessage = nil } }
                )
            ) {
                Button("OK") {
                    viewModel.batchResultMessage = nil
                }
            } message: {
                if let message = viewModel.batchResultMessage {
                    Text(message)
                }
            }
        }
        .onAppear {
            viewModel.loadSessions()
            loadLanguagePreference()
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading sessions...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredSessions.isEmpty {
                VStack(spacing: 0) {
                    if !viewModel.availableFolders.isEmpty {
                        folderFilterBar
                    }
                    emptyState
                }
            } else {
                List(selection: $viewModel.selectedSessionIds) {
                    if !viewModel.availableFolders.isEmpty {
                        folderFilterBar
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }

                    ForEach(viewModel.filteredSessions) { session in
                        NavigationLink {
                            SessionDetailView(
                                sessionId: session.id,
                                container: container
                            )
                        } label: {
                            SessionRowView(session: session)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !isInEditMode {
                                Button(role: .destructive) {
                                    viewModel.requestSwipeDelete(sessionId: session.id)
                                } label: {
                                    Label("Delete Session", systemImage: "trash")
                                }

                                if session.audioKept {
                                    Button {
                                        viewModel.swipeDeleteAudioOnly(sessionId: session.id)
                                    } label: {
                                        Label("Delete Audio Only", systemImage: "speaker.slash")
                                    }
                                    .tint(.orange)
                                }
                            }
                        }
                    }

                    // Bottom spacer so FAB doesn't cover last row
                    Color.clear.frame(height: 80)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .refreshable {
                    viewModel.loadSessions()
                }
            }
        }
    }

    // MARK: - Folder Filter Bar

    private var folderFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                folderChip(label: "All", isSelected: viewModel.selectedFolderFilter == nil) {
                    viewModel.selectedFolderFilter = nil
                }

                ForEach(viewModel.availableFolders) { folder in
                    folderChip(
                        label: folder.name,
                        isSelected: viewModel.selectedFolderFilter == folder
                    ) {
                        viewModel.selectedFolderFilter = folder
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func folderChip(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.caption2)
                Text(label)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.systemGray5))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("No Sessions Yet")
                .font(.title2.bold())

            Text("Start your first recording session to capture and transcribe audio.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Start Recording Button

    private var startRecordingButton: some View {
        Group {
            if coordinator.state.isRecording {
                Button {
                    showRecordingView = true
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)

                        Text("View Recording")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.red.opacity(0.15))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.red.opacity(0.3), lineWidth: 1)
                    )
                }
            } else {
                Button {
                    showLanguagePicker = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "record.circle")
                            .font(.title3)

                        Text("Start Recording")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 4)
                }
            }
        }
    }

    // MARK: - Actions

    private func startRecording(language: LanguageMode) {
        coordinator.startAlwaysOn(languageMode: language)
        showRecordingView = true
    }

    private func enterEditMode() {
        viewModel.deselectAll()
        isInEditMode = true
    }

    private func exitEditMode() {
        isInEditMode = false
        viewModel.deselectAll()
    }

    private func loadLanguagePreference() {
        let raw = UserDefaults.standard.string(forKey: "selectedLanguageMode") ?? "auto"
        selectedLanguage = LanguageMode(rawValue: raw) ?? .auto
    }
}

// MARK: - Session Row

private struct SessionRowView: View {

    let session: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.title.isEmpty ? "Untitled Session" : session.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                StatusBadge(status: session.status)
            }

            Text(session.startedAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
            + Text(" ")
            + Text(session.startedAt, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let preview = session.transcriptPreview, !preview.isEmpty {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                Label("\(session.chunkCount)", systemImage: "square.stack.3d.up")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !session.audioKept {
                    Label("Audio removed", systemImage: "speaker.slash.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if session.summary != nil {
                    Label("Summary", systemImage: "doc.text")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }

                if let folderName = session.folderName {
                    Label(folderName, systemImage: "folder")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let placeName = session.placeName, !placeName.isEmpty {
                    Label(placeName, systemImage: "location")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !session.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(session.tags) { tag in
                            TagChipView(tag: tag)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {

    let status: SessionStatus

    var body: some View {
        Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor.opacity(0.15))
            .foregroundStyle(backgroundColor)
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case .idle:
            return "Idle"
        case .recording:
            return "Recording"
        case .processing:
            return "Processing"
        case .ready:
            return "Ready"
        case .error:
            return "Error"
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .idle:
            return .secondary
        case .recording:
            return .red
        case .processing:
            return .orange
        case .ready:
            return .green
        case .error:
            return .red
        }
    }
}

#if DEBUG
private struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        Text("HomeView requires AppContainer")
    }
}
#endif
