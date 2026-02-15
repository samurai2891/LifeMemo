import Foundation
import CoreData

@MainActor
final class SessionRepository {

    private let context: NSManagedObjectContext
    private let fileStore: FileStore

    init(context: NSManagedObjectContext, fileStore: FileStore) {
        self.context = context
        self.fileStore = fileStore
    }

    // MARK: - Session Lifecycle

    func createSession(languageMode: LanguageMode) -> UUID {
        let sessionId = UUID()
        let now = Date()

        let session = SessionEntity(context: context)
        session.id = sessionId
        session.createdAt = now
        session.startedAt = now
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        session.title = formatter.string(from: now)
        session.languageMode = languageMode
        session.status = .recording
        session.audioKept = true

        saveOrLog()
        return sessionId
    }

    func updateSessionStatus(sessionId: UUID, status: SessionStatus) {
        guard let session = fetchSession(id: sessionId) else { return }
        session.status = status
        saveOrLog()
    }

    func updateSessionEnded(sessionId: UUID, endedAt: Date, status: SessionStatus) {
        guard let session = fetchSession(id: sessionId) else { return }
        session.endedAt = endedAt
        session.status = status
        saveOrLog()
    }

    // MARK: - Chunk Lifecycle

    func createOrUpdateChunkStarted(
        chunkId: UUID,
        sessionId: UUID,
        index: Int,
        startAt: Date,
        relativePath: String
    ) {
        guard let session = fetchSession(id: sessionId) else { return }

        let chunk: ChunkEntity
        if let existing = fetchChunk(id: chunkId) {
            chunk = existing
        } else {
            chunk = ChunkEntity(context: context)
            chunk.id = chunkId
        }

        chunk.index = Int32(index)
        chunk.startAt = startAt
        chunk.relativePath = relativePath
        chunk.transcriptionStatus = .pending
        chunk.audioDeleted = false
        chunk.session = session

        saveOrLog()
    }

    func finalizeChunk(
        chunkId: UUID,
        sessionId: UUID,
        endAt: Date,
        durationSec: Double,
        sizeBytes: Int64
    ) {
        guard let chunk = fetchChunk(id: chunkId) else { return }
        chunk.endAt = endAt
        chunk.durationSec = durationSec
        chunk.sizeBytes = sizeBytes
        saveOrLog()
    }

    func updateChunkTranscriptionStatus(chunkId: UUID, status: TranscriptionStatus) {
        guard let chunk = fetchChunk(id: chunkId) else { return }
        chunk.transcriptionStatus = status
        saveOrLog()
    }

    func getChunkFileURL(chunkId: UUID) -> URL? {
        guard let chunk = fetchChunk(id: chunkId),
              let path = chunk.relativePath else { return nil }
        return fileStore.resolveAbsoluteURL(relativePath: path)
    }

    // MARK: - Transcription

    func saveTranscript(sessionId: UUID, chunkId: UUID, text: String) {
        guard let session = fetchSession(id: sessionId),
              let chunk = fetchChunk(id: chunkId) else { return }

        let chunkStartAt = chunk.startAt ?? Date()
        let sessionStartedAt = session.startedAt ?? Date()
        let offsetMs = Int64(chunkStartAt.timeIntervalSince(sessionStartedAt) * 1000)
        let durationMs = Int64(chunk.durationSec * 1000)

        let segment = TranscriptSegmentEntity(context: context)
        segment.id = UUID()
        segment.text = text
        segment.startMs = max(0, offsetMs)
        segment.endMs = max(0, offsetMs + durationMs)
        segment.createdAt = Date()
        segment.session = session
        segment.chunk = chunk

        chunk.transcriptionStatus = .done
        saveOrLog()
    }

    func getLocaleForSession(sessionId: UUID) -> Locale {
        guard let session = fetchSession(id: sessionId) else {
            return Locale.current
        }
        return session.languageMode.locale
    }

    // MARK: - Summary

    func refreshSessionSummary(sessionId: UUID) {
        // Placeholder: will be invoked by the summarizer service.
        // The summarizer should call updateSessionSummary(sessionId:markdown:) when done.
    }

    func updateSessionSummary(sessionId: UUID, markdown: String) {
        guard let session = fetchSession(id: sessionId) else { return }
        session.summary = markdown
        saveOrLog()
    }

    // MARK: - Highlights

    func addHighlight(sessionId: UUID, atMs: Int64) {
        guard let session = fetchSession(id: sessionId) else { return }

        let highlight = HighlightEntity(context: context)
        highlight.id = UUID()
        highlight.atMs = atMs
        highlight.createdAt = Date()
        highlight.session = session

        saveOrLog()
    }

    func getHighlights(sessionId: UUID) -> [HighlightInfo] {
        guard let session = fetchSession(id: sessionId) else { return [] }
        return session.highlightsArray.map { $0.toInfo() }
    }

    // MARK: - Elapsed Time

    func currentElapsedMs(sessionId: UUID) -> Int64 {
        guard let session = fetchSession(id: sessionId),
              let startedAt = session.startedAt else { return 0 }

        let reference = session.endedAt ?? Date()
        let elapsed = reference.timeIntervalSince(startedAt) * 1000
        return max(0, Int64(elapsed))
    }

    // MARK: - Deletion

    func deleteAudioKeepTranscript(sessionId: UUID) {
        guard let session = fetchSession(id: sessionId) else { return }

        for chunk in session.chunksArray {
            if let path = chunk.relativePath {
                fileStore.deleteFile(relativePath: path)
            }
            chunk.audioDeleted = true
            chunk.relativePath = nil
        }

        session.audioKept = false
        fileStore.deleteSessionAudioDir(sessionId: session.id ?? sessionId)
        saveOrLog()
    }

    func deleteSessionCompletely(sessionId: UUID) {
        guard let session = fetchSession(id: sessionId) else { return }

        fileStore.deleteSessionAudioDir(sessionId: session.id ?? sessionId)
        context.delete(session)
        saveOrLog()
    }

    // MARK: - Fetch

    func fetchAllSessions() -> [SessionEntity] {
        let request = NSFetchRequest<SessionEntity>(entityName: "SessionEntity")
        request.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]

        do {
            return try context.fetch(request)
        } catch {
            print("Failed to fetch sessions: \(error.localizedDescription)")
            return []
        }
    }

    func fetchSession(id: UUID) -> SessionEntity? {
        let request = NSFetchRequest<SessionEntity>(entityName: "SessionEntity")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        do {
            return try context.fetch(request).first
        } catch {
            print("Failed to fetch session \(id): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Full Transcript

    func getFullTranscriptText(sessionId: UUID) -> String {
        guard let session = fetchSession(id: sessionId) else { return "" }

        return session.segmentsArray
            .compactMap { $0.text }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // MARK: - Search

    func searchSessionsContaining(query: String) -> [UUID] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Search in session titles
        let titleRequest = NSFetchRequest<SessionEntity>(entityName: "SessionEntity")
        titleRequest.predicate = NSPredicate(
            format: "title CONTAINS[cd] %@",
            trimmed
        )
        titleRequest.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]

        // Search in transcript segments
        let segmentRequest = NSFetchRequest<TranscriptSegmentEntity>(
            entityName: "TranscriptSegmentEntity"
        )
        segmentRequest.predicate = NSPredicate(
            format: "text CONTAINS[cd] %@",
            trimmed
        )

        do {
            let titleMatches = try context.fetch(titleRequest)
            let segmentMatches = try context.fetch(segmentRequest)

            var seen = Set<UUID>()
            var results: [UUID] = []

            for session in titleMatches {
                if let sessionId = session.id, seen.insert(sessionId).inserted {
                    results.append(sessionId)
                }
            }

            for segment in segmentMatches {
                if let sessionId = segment.session?.id, seen.insert(sessionId).inserted {
                    results.append(sessionId)
                }
            }

            return results
        } catch {
            print("Search failed: \(error.localizedDescription)")
            return []
        }
    }

    func searchSegments(query: String, sessionId: UUID?) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let request = NSFetchRequest<TranscriptSegmentEntity>(
            entityName: "TranscriptSegmentEntity"
        )
        if let sessionId {
            request.predicate = NSPredicate(
                format: "text CONTAINS[cd] %@ AND session.id == %@",
                trimmed,
                sessionId as CVarArg
            )
        } else {
            request.predicate = NSPredicate(
                format: "text CONTAINS[cd] %@",
                trimmed
            )
        }
        request.sortDescriptors = [
            NSSortDescriptor(key: "startMs", ascending: true)
        ]

        do {
            let segments = try context.fetch(request)
            return segments.compactMap { segment -> SearchResult? in
                guard let session = segment.session else { return nil }
                return SearchResult(
                    id: segment.id ?? UUID(),
                    sessionId: session.id ?? UUID(),
                    segmentText: segment.text ?? "",
                    startMs: segment.startMs,
                    endMs: segment.endMs,
                    sessionTitle: session.title ?? ""
                )
            }
        } catch {
            print("Segment search failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Export

    func getSessionExportModel(sessionId: UUID) -> ExportModel {
        guard let session = fetchSession(id: sessionId) else {
            return ExportModel(
                title: "Unknown",
                startedAt: Date(),
                endedAt: nil,
                languageMode: "auto",
                audioKept: false,
                summaryMarkdown: nil,
                fullTranscript: "",
                highlights: []
            )
        }

        let transcript = getFullTranscriptText(sessionId: sessionId)
        let highlights = session.highlightsArray.map { $0.toInfo() }

        return ExportModel(
            title: session.title ?? "",
            startedAt: session.startedAt ?? Date(),
            endedAt: session.endedAt,
            languageMode: session.languageModeRaw ?? "auto",
            audioKept: session.audioKept,
            summaryMarkdown: session.summary,
            fullTranscript: transcript,
            highlights: highlights
        )
    }

    // MARK: - Private Helpers

    private func fetchChunk(id: UUID) -> ChunkEntity? {
        let request = NSFetchRequest<ChunkEntity>(entityName: "ChunkEntity")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        do {
            return try context.fetch(request).first
        } catch {
            print("Failed to fetch chunk \(id): \(error.localizedDescription)")
            return nil
        }
    }

    private func saveOrLog() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("CoreData save error: \(error.localizedDescription)")
        }
    }
}
