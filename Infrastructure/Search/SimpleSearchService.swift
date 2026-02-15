import Foundation

@MainActor
final class SimpleSearchService: SearchServiceProtocol {

    // MARK: - Dependencies

    private let repository: SessionRepository

    // MARK: - Init

    init(repository: SessionRepository) {
        self.repository = repository
    }

    // MARK: - SearchServiceProtocol

    func search(query: String) -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return repository.searchSegments(query: query, sessionId: nil)
    }

    func searchSessions(query: String) -> [UUID] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return repository.searchSessionsContaining(query: query)
    }
}
