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
