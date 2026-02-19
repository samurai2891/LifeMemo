import Foundation
import Combine

/// ViewModel for the Home screen session list.
///
/// Loads all sessions from the repository, supports text-based search
/// filtering, and provides a debounced search query to avoid excessive
/// repository calls.
@MainActor
final class HomeViewModel: ObservableObject {

    // MARK: - Published State

    @Published var searchQuery: String = ""
    @Published var selectedFolderFilter: FolderInfo? = nil
    @Published var selectedSessionIds: Set<UUID> = []
    @Published var showBatchDeleteConfirm: Bool = false
    @Published var batchResultMessage: String? = nil
    @Published var swipeDeleteTargetId: UUID? = nil
    @Published var showSwipeDeleteConfirm: Bool = false
    @Published private(set) var sessions: [SessionSummary] = []
    @Published private(set) var filteredSessions: [SessionSummary] = []
    @Published private(set) var availableFolders: [FolderInfo] = []
    @Published private(set) var isLoading: Bool = false

    // MARK: - Dependencies

    private let repository: SessionRepository
    private let searchService: SimpleSearchService
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(repository: SessionRepository, searchService: SimpleSearchService) {
        self.repository = repository
        self.searchService = searchService
        setupSearchDebounce()
        setupFolderFilterObserver()
    }

    // MARK: - Data Loading

    func loadSessions() {
        isLoading = true
        let entities = repository.fetchAllSessions()
        sessions = entities.map { $0.toSummary() }
        loadFolders()
        applyFilter()
        isLoading = false
    }

    func loadFolders() {
        availableFolders = repository.fetchAllFolders().map { $0.toInfo() }
    }

    func deleteSession(sessionId: UUID) {
        repository.deleteSessionCompletely(sessionId: sessionId)
        sessions = sessions.filter { $0.id != sessionId }
        applyFilter()
    }

    // MARK: - Single Session Swipe Delete

    func requestSwipeDelete(sessionId: UUID) {
        swipeDeleteTargetId = sessionId
        showSwipeDeleteConfirm = true
    }

    func swipeDeleteCompletely() {
        guard let targetId = swipeDeleteTargetId else { return }
        swipeDeleteTargetId = nil
        deleteSession(sessionId: targetId)
    }

    func swipeDeleteAudioOnly(sessionId: UUID) {
        repository.deleteAudioKeepTranscript(sessionId: sessionId)
        loadSessions()
    }

    // MARK: - Batch Selection

    var selectedCount: Int { selectedSessionIds.count }

    var allFilteredSelected: Bool {
        !filteredSessions.isEmpty
            && filteredSessions.allSatisfy { selectedSessionIds.contains($0.id) }
    }

    func selectAll() {
        selectedSessionIds = Set(filteredSessions.map(\.id))
    }

    func deselectAll() {
        selectedSessionIds = []
    }

    func toggleSelectAll() {
        if allFilteredSelected {
            deselectAll()
        } else {
            selectAll()
        }
    }

    func requestBatchDelete() {
        guard !selectedSessionIds.isEmpty else { return }
        showBatchDeleteConfirm = true
    }

    func batchDeleteCompletely() {
        let count = repository.deleteSessionsCompletely(sessionIds: selectedSessionIds)
        sessions = sessions.filter { !selectedSessionIds.contains($0.id) }
        selectedSessionIds = []
        applyFilter()
        batchResultMessage = String(
            format: NSLocalizedString("Delete %lld Session(s)", comment: ""),
            count
        )
    }

    func batchDeleteAudioOnly() {
        let count = repository.deleteAudioKeepTranscript(sessionIds: selectedSessionIds)
        selectedSessionIds = []
        loadSessions()
        batchResultMessage = String(
            format: NSLocalizedString(
                "Removed audio from %lld session(s). Transcripts preserved.",
                comment: ""
            ),
            count
        )
    }

    // MARK: - Search

    private func setupSearchDebounce() {
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.applyFilter()
            }
            .store(in: &cancellables)
    }

    private func setupFolderFilterObserver() {
        $selectedFolderFilter
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.applyFilter()
            }
            .store(in: &cancellables)
    }

    // MARK: - Filtering

    private func applyFilter() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        var filtered = sessions

        // Folder filter
        if let folder = selectedFolderFilter {
            filtered = filtered.filter { $0.folderName == folder.name }
        }

        // Text search
        if !query.isEmpty {
            let matchingIds = Set(searchService.searchSessions(query: query))
            filtered = filtered.filter { session in
                matchingIds.contains(session.id)
                    || session.title.localizedCaseInsensitiveContains(query)
                    || (session.transcriptPreview?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }

        filteredSessions = filtered
    }
}
