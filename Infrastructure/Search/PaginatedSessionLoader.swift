import Foundation
import CoreData

/// Paginated session loader optimized for large datasets.
///
/// Uses Core Data batch fetching with configurable page sizes
/// to efficiently load sessions without loading all data into memory.
@MainActor
final class PaginatedSessionLoader: ObservableObject {

    @Published private(set) var sessions: [SessionSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMore = true
    @Published private(set) var totalCount = 0

    private let context: NSManagedObjectContext
    private let pageSize: Int
    private var currentPage = 0

    init(context: NSManagedObjectContext, pageSize: Int = 20) {
        self.context = context
        self.pageSize = pageSize
    }

    // MARK: - Loading

    func loadFirstPage() {
        currentPage = 0
        sessions = []
        hasMore = true
        loadNextPage()
    }

    func loadNextPage() {
        guard !isLoading, hasMore else { return }
        isLoading = true

        do {
            // Count total (only on first page to avoid repeated counting)
            if currentPage == 0 {
                totalCount = try fetchTotalCount()
            }

            let newSummaries = try fetchPage(page: currentPage)
            sessions.append(contentsOf: newSummaries)
            hasMore = newSummaries.count == pageSize
            currentPage += 1
        } catch {
            print("PaginatedSessionLoader: fetch failed: \(error)")
        }

        isLoading = false
    }

    func refresh() {
        loadFirstPage()
    }

    // MARK: - Private Fetching

    private func fetchTotalCount() throws -> Int {
        let countRequest = NSFetchRequest<NSNumber>(entityName: "SessionEntity")
        countRequest.resultType = .countResultType
        let countResults = try context.fetch(countRequest)
        return countResults.first?.intValue ?? 0
    }

    private func fetchPage(page: Int) throws -> [SessionSummary] {
        let request = NSFetchRequest<SessionEntity>(entityName: "SessionEntity")
        request.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        request.fetchOffset = page * pageSize
        request.fetchLimit = pageSize
        request.fetchBatchSize = pageSize

        let entities = try context.fetch(request)
        return entities.map { $0.toSummary() }
    }
}
