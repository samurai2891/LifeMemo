import Foundation
import CoreData

/// Advanced search service using FTS5 for fast full-text search
/// with support for date range filtering, highlight filtering, and pagination.
@MainActor
final class AdvancedSearchService {

    struct SearchResults {
        let segments: [SearchResult]
        let sessionIds: [UUID]
        let totalCount: Int
        let hasMore: Bool
    }

    private let fts5Manager: FTS5Manager
    private let context: NSManagedObjectContext
    private let pageSize: Int

    init(
        fts5Manager: FTS5Manager,
        context: NSManagedObjectContext,
        pageSize: Int = 20
    ) {
        self.fts5Manager = fts5Manager
        self.context = context
        self.pageSize = pageSize
    }

    // MARK: - Search

    func search(filter: SearchFilter, page: Int = 0) -> SearchResults {
        let trimmedQuery = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedQuery.isEmpty {
            return ftsSearch(filter: filter, page: page)
        } else if filter.hasActiveFilters {
            return filterOnlySearch(filter: filter, page: page)
        } else {
            return SearchResults(
                segments: [],
                sessionIds: [],
                totalCount: 0,
                hasMore: false
            )
        }
    }

    // MARK: - FTS Search

    private func ftsSearch(filter: SearchFilter, page: Int) -> SearchResults {
        let ftsMatches = fts5Manager.search(query: filter.query, limit: 200)

        // Apply additional Core Data filters when active
        let filteredMatches: [FTS5Manager.FTSMatch]
        if filter.hasActiveFilters {
            let validSessionIds = fetchFilteredSessionIds(filter: filter)
            filteredMatches = ftsMatches.filter { validSessionIds.contains($0.sessionId) }
        } else {
            filteredMatches = ftsMatches
        }

        // FTS5 returns results ranked by relevance by default.
        // For date-based sorting, we would need to join with Core Data dates,
        // but relevance ordering from FTS5 is preserved as-is.
        let sorted = filteredMatches

        // Paginate
        let offset = page * pageSize
        let pageMatches = Array(sorted.dropFirst(offset).prefix(pageSize))

        // Enrich with Core Data details
        let segments = enrichMatches(pageMatches)
        let sessionIds = Array(Set(segments.map(\.sessionId)))

        return SearchResults(
            segments: segments,
            sessionIds: sessionIds,
            totalCount: filteredMatches.count,
            hasMore: offset + pageSize < filteredMatches.count
        )
    }

    // MARK: - Filter-Only Search

    private func filterOnlySearch(filter: SearchFilter, page: Int) -> SearchResults {
        let sessionIds = fetchFilteredSessionIds(filter: filter)

        let request = NSFetchRequest<SessionEntity>(entityName: "SessionEntity")
        request.predicate = NSPredicate(
            format: "id IN %@",
            sessionIds.map { $0 as CVarArg }
        )

        let sortKey: String
        let ascending: Bool
        switch filter.sortOrder {
        case .newest:
            sortKey = "createdAt"
            ascending = false
        case .oldest:
            sortKey = "createdAt"
            ascending = true
        case .relevance:
            sortKey = "createdAt"
            ascending = false
        }
        request.sortDescriptors = [
            NSSortDescriptor(key: sortKey, ascending: ascending)
        ]

        let offset = page * pageSize
        request.fetchOffset = offset
        request.fetchLimit = pageSize

        return SearchResults(
            segments: [],
            sessionIds: Array(sessionIds),
            totalCount: sessionIds.count,
            hasMore: offset + pageSize < sessionIds.count
        )
    }

    // MARK: - Filtered Session IDs

    private func fetchFilteredSessionIds(filter: SearchFilter) -> Set<UUID> {
        let request = NSFetchRequest<NSDictionary>(entityName: "SessionEntity")
        var predicates: [NSPredicate] = []

        if let dateFrom = filter.dateFrom {
            predicates.append(NSPredicate(
                format: "startedAt >= %@",
                dateFrom as NSDate
            ))
        }
        if let dateTo = filter.dateTo {
            predicates.append(NSPredicate(
                format: "startedAt <= %@",
                dateTo as NSDate
            ))
        }
        if filter.highlightsOnly {
            predicates.append(NSPredicate(
                format: "highlights.@count > 0"
            ))
        }
        if let lang = filter.languageMode {
            predicates.append(NSPredicate(
                format: "languageModeRaw == %@",
                lang
            ))
        }
        if let hasAudio = filter.hasAudio {
            predicates.append(NSPredicate(
                format: "audioKept == %@",
                NSNumber(value: hasAudio)
            ))
        }

        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(
                andPredicateWithSubpredicates: predicates
            )
        }

        request.propertiesToFetch = ["id"]
        request.resultType = .dictionaryResultType

        do {
            let results = try context.fetch(request)
            return Set(results.compactMap { $0["id"] as? UUID })
        } catch {
            print("AdvancedSearchService: fetch filtered sessions failed: \(error)")
            return []
        }
    }

    // MARK: - Enrichment

    private func enrichMatches(
        _ matches: [FTS5Manager.FTSMatch]
    ) -> [SearchResult] {
        guard !matches.isEmpty else { return [] }

        let segmentIds = matches.map(\.segmentId)
        let request = NSFetchRequest<TranscriptSegmentEntity>(
            entityName: "TranscriptSegmentEntity"
        )
        request.predicate = NSPredicate(
            format: "id IN %@",
            segmentIds.map { $0 as CVarArg }
        )

        do {
            let entities = try context.fetch(request)
            let entityMap = Dictionary(
                uniqueKeysWithValues: entities.compactMap { entity -> (UUID, TranscriptSegmentEntity)? in
                    guard let id = entity.id else { return nil }
                    return (id, entity)
                }
            )

            return matches.compactMap { match -> SearchResult? in
                guard let entity = entityMap[match.segmentId],
                      let session = entity.session else { return nil }

                return SearchResult(
                    id: match.segmentId,
                    sessionId: match.sessionId,
                    segmentText: entity.text ?? "",
                    startMs: entity.startMs,
                    endMs: entity.endMs,
                    sessionTitle: session.title ?? ""
                )
            }
        } catch {
            print("AdvancedSearchService: enrich matches failed: \(error)")
            return []
        }
    }

    // MARK: - Index Management

    func rebuildSearchIndex() {
        let request = NSFetchRequest<TranscriptSegmentEntity>(
            entityName: "TranscriptSegmentEntity"
        )

        do {
            let entities = try context.fetch(request)
            let segments: [(segmentId: UUID, sessionId: UUID, text: String)] = entities.compactMap { entity in
                guard let segId = entity.id,
                      let session = entity.session,
                      let sesId = session.id,
                      let text = entity.text else { return nil }
                return (segId, sesId, text)
            }
            fts5Manager.rebuildIndex(segments: segments)
        } catch {
            print("AdvancedSearchService: rebuild index failed: \(error)")
        }
    }
}
