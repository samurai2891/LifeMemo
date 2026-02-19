import Foundation

struct SearchResult: Identifiable {
    let id: UUID
    let sessionId: UUID
    let segmentText: String
    let startMs: Int64
    let endMs: Int64
    let sessionTitle: String
    let speakerName: String?

    /// Backward-compatible initializer without speakerName.
    init(
        id: UUID,
        sessionId: UUID,
        segmentText: String,
        startMs: Int64,
        endMs: Int64,
        sessionTitle: String
    ) {
        self.id = id
        self.sessionId = sessionId
        self.segmentText = segmentText
        self.startMs = startMs
        self.endMs = endMs
        self.sessionTitle = sessionTitle
        self.speakerName = nil
    }

    /// Full initializer with speakerName.
    init(
        id: UUID,
        sessionId: UUID,
        segmentText: String,
        startMs: Int64,
        endMs: Int64,
        sessionTitle: String,
        speakerName: String?
    ) {
        self.id = id
        self.sessionId = sessionId
        self.segmentText = segmentText
        self.startMs = startMs
        self.endMs = endMs
        self.sessionTitle = sessionTitle
        self.speakerName = speakerName
    }
}

@MainActor
protocol SearchServiceProtocol: AnyObject {
    func search(query: String) -> [SearchResult]
    func searchSessions(query: String) -> [UUID]
}
