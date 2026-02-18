import Foundation

struct SearchResult: Identifiable {
    let id: UUID
    let sessionId: UUID
    let segmentText: String
    let startMs: Int64
    let endMs: Int64
    let sessionTitle: String
}

@MainActor
protocol SearchServiceProtocol: AnyObject {
    func search(query: String) -> [SearchResult]
    func searchSessions(query: String) -> [UUID]
}
