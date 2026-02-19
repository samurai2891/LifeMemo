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

    func updateSessionLocation(
        sessionId: UUID,
        latitude: Double,
        longitude: Double,
        placeName: String?
    ) {
        guard let session = fetchSession(id: sessionId) else { return }
        session.latitude = latitude
        session.longitude = longitude
        session.placeName = placeName
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
        segment.speakerIndex = -1 // Undiarized (single-speaker path)
        segment.createdAt = Date()
        segment.session = session
        segment.chunk = chunk

        chunk.transcriptionStatus = .done
        saveOrLog()
    }

    /// Saves diarized transcript segments for a chunk (multiple segments per chunk).
    ///
    /// Each `DiarizedSegment` becomes a separate `TranscriptSegmentEntity` with the
    /// appropriate `speakerIndex`. The chunk's session-relative offset is applied
    /// to each segment's timestamps.
    func saveTranscriptWithSpeakers(
        sessionId: UUID,
        chunkId: UUID,
        diarization: DiarizationResult,
        fullText: String
    ) {
        guard let session = fetchSession(id: sessionId),
              let chunk = fetchChunk(id: chunkId) else { return }

        let chunkStartAt = chunk.startAt ?? Date()
        let sessionStartedAt = session.startedAt ?? Date()
        let chunkOffsetMs = Int64(chunkStartAt.timeIntervalSince(sessionStartedAt) * 1000)

        for diarizedSeg in diarization.segments {
            let segment = TranscriptSegmentEntity(context: context)
            segment.id = UUID()
            segment.text = diarizedSeg.text
            segment.startMs = max(0, chunkOffsetMs + diarizedSeg.startOffsetMs)
            segment.endMs = max(0, chunkOffsetMs + diarizedSeg.endOffsetMs)
            segment.speakerIndex = Int16(diarizedSeg.speakerIndex)
            segment.createdAt = Date()
            segment.session = session
            segment.chunk = chunk
        }

        chunk.transcriptionStatus = .done
        saveOrLog()
    }

    /// Updates the display name for a speaker in a session.
    func renameSpeaker(sessionId: UUID, speakerIndex: Int, newName: String) {
        guard let session = fetchSession(id: sessionId) else { return }
        var names = session.speakerNames
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            names.removeValue(forKey: speakerIndex)
        } else {
            names[speakerIndex] = trimmed
        }
        session.setSpeakerNames(names)
        saveOrLog()
    }

    /// Reassigns a segment to a different speaker.
    func reassignSegmentSpeaker(segmentId: UUID, newSpeakerIndex: Int) {
        guard let segment = fetchSegment(id: segmentId) else { return }
        segment.speakerIndex = Int16(newSpeakerIndex)
        saveOrLog()
    }

    func getLocaleForSession(sessionId: UUID) -> Locale {
        guard let session = fetchSession(id: sessionId) else {
            return Locale.current
        }
        return session.languageMode.locale
    }

    // MARK: - Retranscription

    /// Deletes all transcript segments (and their edit history) for a given chunk.
    /// Used to clean up old results before retranscription.
    func deleteSegmentsForChunk(chunkId: UUID) {
        guard let chunk = fetchChunk(id: chunkId) else { return }
        if let segments = chunk.segments as? Set<TranscriptSegmentEntity> {
            for segment in segments {
                context.delete(segment)
            }
        }
        saveOrLog()
    }

    /// Resets a single chunk for retranscription: deletes existing segments, sets chunk
    /// status to `.pending`, and transitions the session back to `.processing`.
    /// Saves once at the end for efficiency.
    func resetChunkForRetranscription(chunkId: UUID, sessionId: UUID) {
        // Delete segments (without intermediate save)
        if let chunk = fetchChunk(id: chunkId),
           let segments = chunk.segments as? Set<TranscriptSegmentEntity> {
            for segment in segments {
                context.delete(segment)
            }
        }

        // Reset chunk status
        if let chunk = fetchChunk(id: chunkId) {
            chunk.transcriptionStatus = .pending
        }

        // Transition session to processing
        if let session = fetchSession(id: sessionId),
           session.status == .ready || session.status == .error {
            session.status = .processing
        }

        saveOrLog()
    }

    /// Resets multiple chunks for retranscription in a single batch save.
    func resetChunksForRetranscription(chunkIds: [UUID], sessionId: UUID) {
        for chunkId in chunkIds {
            if let chunk = fetchChunk(id: chunkId),
               let segments = chunk.segments as? Set<TranscriptSegmentEntity> {
                for segment in segments {
                    context.delete(segment)
                }
                chunk.transcriptionStatus = .pending
            }
        }

        if let session = fetchSession(id: sessionId),
           session.status == .ready || session.status == .error {
            session.status = .processing
        }

        saveOrLog()
    }

    // MARK: - Session Finalization

    /// Checks if all chunks in a session have completed transcription (done or failed).
    /// If so, transitions the session status from `.processing` to `.ready`.
    func checkAndFinalizeSessionStatus(sessionId: UUID) {
        guard let session = fetchSession(id: sessionId) else { return }
        guard session.status == .processing else { return }

        let chunks = session.chunksArray
        guard !chunks.isEmpty else { return }

        let allFinished = chunks.allSatisfy { chunk in
            chunk.transcriptionStatus == .done
                || chunk.transcriptionStatus == .failed
        }

        if allFinished {
            session.status = .ready
            saveOrLog()
        }
    }

    // MARK: - Session Editing

    func updateSegmentText(segmentId: UUID, newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let segment = fetchSegment(id: segmentId) else { return }

        let previousText = segment.text ?? ""

        // Save original text if this is the first edit
        if !segment.isUserEdited {
            segment.originalText = previousText
        }

        // Create edit history record
        let existingCount = segment.editHistoryArray.count
        let historyEntry = EditHistoryEntity(context: context)
        historyEntry.id = UUID()
        historyEntry.previousText = previousText
        historyEntry.newText = trimmed
        historyEntry.editedAt = Date()
        historyEntry.editIndex = Int16(existingCount + 1)
        historyEntry.segment = segment

        segment.text = trimmed
        segment.isUserEdited = true
        saveOrLog()
    }

    func renameSession(sessionId: UUID, newTitle: String) {
        guard let session = fetchSession(id: sessionId) else { return }
        session.title = newTitle
        saveOrLog()
    }

    func updateSessionBodyText(sessionId: UUID, bodyText: String?) {
        guard let session = fetchSession(id: sessionId) else { return }
        session.bodyText = bodyText
        saveOrLog()
    }

    // MARK: - Edit History

    /// Fetches all edit history entries for a segment, sorted by editIndex ascending.
    func fetchEditHistory(segmentId: UUID) -> [EditHistoryEntry] {
        guard let segment = fetchSegment(id: segmentId) else { return [] }
        let segId = segment.id ?? segmentId
        return segment.editHistoryArray.map { $0.toEntry(segmentId: segId) }
    }

    /// Reverts a segment's text to the state before a specific edit history entry.
    /// Deletes all edit history records with editIndex greater than the reverted entry.
    func revertSegment(segmentId: UUID, toHistoryEntryId: UUID) {
        guard let segment = fetchSegment(id: segmentId) else { return }

        let historyRequest = NSFetchRequest<EditHistoryEntity>(entityName: "EditHistoryEntity")
        historyRequest.predicate = NSPredicate(format: "id == %@", toHistoryEntryId as CVarArg)
        historyRequest.fetchLimit = 1

        guard let targetEntry = try? context.fetch(historyRequest).first else { return }

        segment.text = targetEntry.previousText

        // If reverting to the very first edit, restore to unedited state
        if targetEntry.editIndex == 1 {
            segment.isUserEdited = false
            segment.originalText = nil
        }

        // Delete the target entry and all entries with higher editIndex
        let targetIndex = targetEntry.editIndex
        let entriesToDelete = segment.editHistoryArray.filter { $0.editIndex >= targetIndex }
        for entry in entriesToDelete {
            context.delete(entry)
        }

        saveOrLog()
    }

    /// Reverts a segment to its original (pre-edit) text, deleting all edit history.
    func revertSegmentToOriginal(segmentId: UUID) {
        guard let segment = fetchSegment(id: segmentId) else { return }
        guard let original = segment.originalText else { return }

        segment.text = original
        segment.isUserEdited = false
        segment.originalText = nil

        // Delete all edit history for this segment
        for entry in segment.editHistoryArray {
            context.delete(entry)
        }

        saveOrLog()
    }

    // MARK: - Tags

    func createTag(name: String, colorHex: String? = nil) -> UUID {
        let tag = TagEntity(context: context)
        let tagId = UUID()
        tag.id = tagId
        tag.name = name
        tag.colorHex = colorHex
        tag.createdAt = Date()
        saveOrLog()
        return tagId
    }

    func fetchAllTags() -> [TagEntity] {
        let request = NSFetchRequest<TagEntity>(entityName: "TagEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    func addTag(tagId: UUID, toSession sessionId: UUID) {
        guard let session = fetchSession(id: sessionId) else { return }
        let request = NSFetchRequest<TagEntity>(entityName: "TagEntity")
        request.predicate = NSPredicate(format: "id == %@", tagId as CVarArg)
        request.fetchLimit = 1
        guard let tag = try? context.fetch(request).first else { return }

        let mutableTags = session.mutableSetValue(forKey: "tags")
        mutableTags.add(tag)
        saveOrLog()
    }

    func removeTag(tagId: UUID, fromSession sessionId: UUID) {
        guard let session = fetchSession(id: sessionId) else { return }
        let request = NSFetchRequest<TagEntity>(entityName: "TagEntity")
        request.predicate = NSPredicate(format: "id == %@", tagId as CVarArg)
        request.fetchLimit = 1
        guard let tag = try? context.fetch(request).first else { return }

        let mutableTags = session.mutableSetValue(forKey: "tags")
        mutableTags.remove(tag)
        saveOrLog()
    }

    // MARK: - Folders

    func createFolder(name: String) -> UUID {
        let folder = FolderEntity(context: context)
        let folderId = UUID()
        folder.id = folderId
        folder.name = name
        folder.sortOrder = 0
        folder.createdAt = Date()
        saveOrLog()
        return folderId
    }

    func fetchAllFolders() -> [FolderEntity] {
        let request = NSFetchRequest<FolderEntity>(entityName: "FolderEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    func setSessionFolder(sessionId: UUID, folderId: UUID?) {
        guard let session = fetchSession(id: sessionId) else { return }
        if let folderId {
            let request = NSFetchRequest<FolderEntity>(entityName: "FolderEntity")
            request.predicate = NSPredicate(format: "id == %@", folderId as CVarArg)
            request.fetchLimit = 1
            session.folder = try? context.fetch(request).first
        } else {
            session.folder = nil
        }
        saveOrLog()
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
                highlights: [],
                bodyText: nil,
                tags: [],
                folderName: nil,
                locationName: nil
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
            highlights: highlights,
            bodyText: session.bodyText,
            tags: session.tagsArray.map { $0.name ?? "" },
            folderName: session.folder?.name,
            locationName: session.placeName
        )
    }

    // MARK: - Backup Import

    /// Imports a session from a backup manifest entry, creating all related entities.
    /// Called by BackupService during restore. Skips if session with same ID already exists.
    func importSession(from backup: BackupManifest.SessionBackup) {
        let session = SessionEntity(context: context)
        session.id = backup.id
        session.title = backup.title
        session.createdAt = backup.createdAt
        session.startedAt = backup.startedAt
        session.endedAt = backup.endedAt
        session.languageModeRaw = backup.languageModeRaw
        session.statusRaw = backup.statusRaw
        session.audioKept = backup.audioKept
        session.summary = backup.summary
        session.bodyText = backup.bodyText

        for chunkBackup in backup.chunks {
            let chunk = ChunkEntity(context: context)
            chunk.id = chunkBackup.id
            chunk.index = chunkBackup.index
            chunk.startAt = chunkBackup.startAt
            chunk.endAt = chunkBackup.endAt
            chunk.relativePath = chunkBackup.relativePath
            chunk.durationSec = chunkBackup.durationSec
            chunk.sizeBytes = chunkBackup.sizeBytes
            chunk.transcriptionStatusRaw = chunkBackup.transcriptionStatusRaw
            chunk.audioDeleted = chunkBackup.audioDeleted
            chunk.session = session
        }

        session.speakerNamesJSON = backup.speakerNamesJSON

        for segmentBackup in backup.segments {
            let segment = TranscriptSegmentEntity(context: context)
            segment.id = segmentBackup.id
            segment.startMs = segmentBackup.startMs
            segment.endMs = segmentBackup.endMs
            segment.text = segmentBackup.text
            segment.isUserEdited = segmentBackup.isUserEdited
            segment.originalText = segmentBackup.originalText
            segment.speakerIndex = segmentBackup.speakerIndex
            segment.createdAt = segmentBackup.createdAt
            segment.session = session

            for historyBackup in segmentBackup.editHistory {
                let historyEntry = EditHistoryEntity(context: context)
                historyEntry.id = historyBackup.id
                historyEntry.previousText = historyBackup.previousText
                historyEntry.newText = historyBackup.newText
                historyEntry.editedAt = historyBackup.editedAt
                historyEntry.editIndex = historyBackup.editIndex
                historyEntry.segment = segment
            }
        }

        for highlightBackup in backup.highlights {
            let highlight = HighlightEntity(context: context)
            highlight.id = highlightBackup.id
            highlight.atMs = highlightBackup.atMs
            highlight.label = highlightBackup.label
            highlight.createdAt = highlightBackup.createdAt
            highlight.session = session
        }

        saveOrLog()
    }

    // MARK: - Private Helpers

    private func fetchSegment(id: UUID) -> TranscriptSegmentEntity? {
        let request = NSFetchRequest<TranscriptSegmentEntity>(entityName: "TranscriptSegmentEntity")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        do {
            return try context.fetch(request).first
        } catch {
            print("Failed to fetch segment \(id): \(error.localizedDescription)")
            return nil
        }
    }

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
