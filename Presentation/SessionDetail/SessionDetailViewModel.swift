import Foundation
import SwiftUI

/// ViewModel for the session detail screen.
///
/// Manages loading of session data, transcript, highlights, Q&A,
/// summary generation, export, and deletion actions.
@MainActor
final class SessionDetailViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var session: SessionSummary?
    @Published private(set) var transcript: String = ""
    @Published private(set) var highlights: [HighlightInfo] = []
    @Published private(set) var chunks: [ChunkDisplayInfo] = []
    @Published private(set) var isLoading: Bool = false

    // Q&A
    @Published var questionText: String = ""
    @Published private(set) var answerSegments: [SearchResult] = []
    @Published private(set) var isAskingQuestion: Bool = false
    @Published private(set) var answerEmpty: Bool = false

    // Summary
    @Published private(set) var isBuildingSummary: Bool = false
    @Published var selectedAlgorithm: SummarizationAlgorithm = SummarizationPreference.preferredAlgorithm

    // Export
    @Published var exportFileURL: URL?
    @Published var showExportSheet: Bool = false
    @Published var showExportOptions: Bool = false

    // Playback
    @Published var showPlayback: Bool = false
    @Published private(set) var playbackController: SyncedPlaybackController?

    // Retranscription
    @Published private(set) var isRetranscribing: Bool = false

    // Errors
    @Published var errorMessage: String?

    // Deletion
    @Published var showDeleteAudioConfirm: Bool = false
    @Published var showDeleteSessionConfirm: Bool = false
    @Published private(set) var didDeleteSession: Bool = false

    // Tags & Folder
    @Published private(set) var tags: [TagInfo] = []
    @Published private(set) var folderName: String?
    @Published private(set) var currentFolderId: UUID?
    @Published var showTagPicker: Bool = false
    @Published var showFolderPicker: Bool = false

    // Body Text
    @Published var bodyText: String = ""
    @Published var isEditingBodyText: Bool = false

    // Transcript Editing
    @Published var editingSegmentId: UUID?
    @Published var editingSegmentText: String = ""
    @Published private(set) var segments: [SegmentDisplayInfo] = []

    // Speaker Management
    @Published var showSpeakerManagement: Bool = false
    @Published private(set) var speakerNames: [Int: String] = [:]
    @Published private(set) var speakerCount: Int = 0

    // Edit History
    @Published private(set) var selectedSegmentHistory: [EditHistoryEntry] = []
    @Published var showingHistoryForSegmentId: UUID?

    // MARK: - Dependencies

    let sessionId: UUID
    let repository: SessionRepository
    private let fileStore: FileStore
    private let qnaService: SimpleQnAService
    private let summarizer: SimpleSummarizer
    private let exportService: ExportService
    let enhancedExportService: EnhancedExportService
    private let transcriptionQueue: TranscriptionQueueActor
    private var audioPlayer: AudioPlayer?

    // MARK: - Init

    init(
        sessionId: UUID,
        repository: SessionRepository,
        fileStore: FileStore,
        qnaService: SimpleQnAService,
        summarizer: SimpleSummarizer,
        exportService: ExportService,
        enhancedExportService: EnhancedExportService,
        transcriptionQueue: TranscriptionQueueActor
    ) {
        self.sessionId = sessionId
        self.repository = repository
        self.fileStore = fileStore
        self.qnaService = qnaService
        self.summarizer = summarizer
        self.exportService = exportService
        self.enhancedExportService = enhancedExportService
        self.transcriptionQueue = transcriptionQueue
    }

    // MARK: - Data Loading

    func loadSession() {
        isLoading = true

        guard let entity = repository.fetchSession(id: sessionId) else {
            errorMessage = "Session not found."
            isLoading = false
            return
        }

        session = entity.toSummary()
        transcript = repository.getFullTranscriptText(sessionId: sessionId)
        highlights = repository.getHighlights(sessionId: sessionId)
        chunks = entity.chunksArray.map { chunk in
            ChunkDisplayInfo(
                id: chunk.id ?? UUID(),
                index: Int(chunk.index),
                status: chunk.transcriptionStatus,
                durationSec: chunk.durationSec,
                audioDeleted: chunk.audioDeleted
            )
        }

        // Tags & Folder
        tags = entity.tagsArray.map { $0.toInfo() }
        folderName = entity.folder?.name
        currentFolderId = entity.folder?.id

        // Body Text
        bodyText = entity.bodyText ?? ""

        // Speaker data
        speakerNames = entity.speakerNames
        let allSpeakerIndices = Set(entity.segmentsArray.map { Int($0.speakerIndex) }).filter { $0 >= 0 }
        speakerCount = allSpeakerIndices.count

        // Segments
        segments = entity.segmentsArray.map { seg in
            let idx = Int(seg.speakerIndex)
            let name: String? = idx >= 0 ? (speakerNames[idx] ?? SpeakerColors.defaultName(for: idx)) : nil
            return SegmentDisplayInfo(
                id: seg.id ?? UUID(),
                text: seg.text ?? "",
                startMs: seg.startMs,
                endMs: seg.endMs,
                isUserEdited: seg.isUserEdited,
                originalText: seg.originalText,
                speakerIndex: idx,
                speakerName: name
            )
        }

        setupPlayback(entity: entity)
        isLoading = false
    }

    // MARK: - Body Text

    func saveBodyText() {
        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        repository.updateSessionBodyText(
            sessionId: sessionId,
            bodyText: trimmed.isEmpty ? nil : trimmed
        )
        isEditingBodyText = false

        if let entity = repository.fetchSession(id: sessionId) {
            session = entity.toSummary()
        }
    }

    func cancelBodyTextEdit() {
        bodyText = session?.bodyText ?? ""
        isEditingBodyText = false
    }

    // MARK: - Transcript Editing

    func beginSegmentEdit(_ segment: SegmentDisplayInfo) {
        editingSegmentId = segment.id
        editingSegmentText = segment.text
    }

    func saveSegmentEdit() {
        guard let segmentId = editingSegmentId else { return }
        let trimmed = editingSegmentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        repository.updateSegmentText(segmentId: segmentId, newText: trimmed)
        editingSegmentId = nil
        editingSegmentText = ""

        // Reload segments from entity
        reloadSegmentsFromEntity()

        // If we're viewing history for the segment that was just edited, refresh it
        if showingHistoryForSegmentId == segmentId {
            selectedSegmentHistory = repository.fetchEditHistory(segmentId: segmentId)
        }
    }

    func cancelSegmentEdit() {
        editingSegmentId = nil
        editingSegmentText = ""
    }

    // MARK: - Edit History

    func loadEditHistory(for segmentId: UUID) {
        selectedSegmentHistory = repository.fetchEditHistory(segmentId: segmentId)
        showingHistoryForSegmentId = segmentId
    }

    func dismissEditHistory() {
        selectedSegmentHistory = []
        showingHistoryForSegmentId = nil
    }

    func revertToVersion(historyEntryId: UUID) {
        guard let segmentId = showingHistoryForSegmentId else { return }

        repository.revertSegment(segmentId: segmentId, toHistoryEntryId: historyEntryId)
        reloadSegmentsFromEntity()
        dismissEditHistory()
    }

    func revertToOriginal(segmentId: UUID) {
        repository.revertSegmentToOriginal(segmentId: segmentId)
        reloadSegmentsFromEntity()
        dismissEditHistory()
    }

    func editCount(for segmentId: UUID) -> Int {
        repository.fetchEditHistory(segmentId: segmentId).count
    }

    // MARK: - Tag Management

    func removeTag(_ tag: TagInfo) {
        repository.removeTag(tagId: tag.id, fromSession: sessionId)

        if let entity = repository.fetchSession(id: sessionId) {
            tags = entity.tagsArray.map { $0.toInfo() }
            session = entity.toSummary()
        }
    }

    // MARK: - Playback

    private func setupPlayback(entity: SessionEntity) {
        guard entity.audioKept else {
            playbackController = nil
            return
        }

        let chunks: [AudioPlayer.ChunkInfo] = entity.chunksArray.compactMap { chunk in
            guard !chunk.audioDeleted,
                  let relPath = chunk.relativePath,
                  let url = fileStore.resolveAbsoluteURL(relativePath: relPath) else { return nil }

            let startAt = chunk.startAt ?? entity.startedAt ?? Date()
            let sessionStart = entity.startedAt ?? Date()
            let offsetMs = Int64(startAt.timeIntervalSince(sessionStart) * 1000)
            let durationMs = Int64(chunk.durationSec * 1000)

            return AudioPlayer.ChunkInfo(
                chunkId: chunk.id ?? UUID(),
                url: url,
                startOffsetMs: max(0, offsetMs),
                durationMs: durationMs
            )
        }

        guard !chunks.isEmpty else {
            playbackController = nil
            return
        }

        let player = AudioPlayer()
        player.loadSession(chunks: chunks)
        self.audioPlayer = player

        let controller = SyncedPlaybackController(audioPlayer: player)
        let playbackSegments = entity.segmentsArray.map { seg in
            let idx = Int(seg.speakerIndex)
            let name: String? = idx >= 0 ? (speakerNames[idx] ?? SpeakerColors.defaultName(for: idx)) : nil
            return (
                id: seg.id ?? UUID(),
                startMs: seg.startMs,
                endMs: seg.endMs,
                text: seg.text ?? "",
                speakerIndex: idx,
                speakerName: name
            )
        }
        controller.loadSegments(playbackSegments)
        self.playbackController = controller
    }

    // MARK: - Q&A

    func askQuestion() {
        let question = questionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        isAskingQuestion = true
        answerEmpty = false

        let result = qnaService.answer(question: question, in: sessionId)
        answerSegments = result.segments
        answerEmpty = result.isEmpty

        isAskingQuestion = false
    }

    func clearAnswer() {
        answerSegments = []
        answerEmpty = false
        questionText = ""
    }

    // MARK: - Summary

    func buildSummary() {
        isBuildingSummary = true
        SummarizationPreference.preferredAlgorithm = selectedAlgorithm
        let markdown = summarizer.buildSummaryMarkdown(
            sessionId: sessionId, algorithm: selectedAlgorithm
        )
        repository.updateSessionSummary(sessionId: sessionId, markdown: markdown)

        if let entity = repository.fetchSession(id: sessionId) {
            session = entity.toSummary()
        }

        isBuildingSummary = false
    }

    // MARK: - Export

    func exportMarkdown() {
        do {
            let url = try exportService.exportMarkdown(sessionId: sessionId)
            exportFileURL = url
            showExportSheet = true
        } catch {
            errorMessage = "Failed to export Markdown: \(error.localizedDescription)"
        }
    }

    func exportText() {
        do {
            let url = try exportService.exportText(sessionId: sessionId)
            exportFileURL = url
            showExportSheet = true
        } catch {
            errorMessage = "Failed to export text: \(error.localizedDescription)"
        }
    }

    // MARK: - Deletion

    func deleteAudioKeepTranscript() {
        repository.deleteAudioKeepTranscript(sessionId: sessionId)
        loadSession()
    }

    func deleteSessionCompletely() {
        repository.deleteSessionCompletely(sessionId: sessionId)
        didDeleteSession = true
    }

    // MARK: - Retranscription

    /// Whether any chunks are eligible for retry (failed or pending with audio available).
    var hasRetryableChunks: Bool {
        chunks.contains { ($0.status == .failed || $0.status == .pending) && !$0.audioDeleted }
    }

    /// Retranscribes a single chunk by resetting its state and re-enqueuing it.
    func retranscribeChunk(chunkId: UUID) {
        guard !isRetranscribing else { return }
        guard let chunkInfo = chunks.first(where: { $0.id == chunkId }),
              !chunkInfo.audioDeleted else {
            errorMessage = "Audio file has been deleted. Cannot retranscribe."
            return
        }

        isRetranscribing = true
        repository.resetChunkForRetranscription(chunkId: chunkId, sessionId: sessionId)
        loadSession()

        Task {
            await transcriptionQueue.retranscribeChunk(chunkId: chunkId, sessionId: sessionId)
            loadSession()
            isRetranscribing = false
        }
    }

    /// Retranscribes all failed and pending chunks that still have audio files.
    func retranscribeAllFailed() {
        guard !isRetranscribing else { return }
        let retryTargets = chunks.filter { chunk in
            (chunk.status == .failed || chunk.status == .pending) && !chunk.audioDeleted
        }
        guard !retryTargets.isEmpty else { return }

        isRetranscribing = true
        let chunkIds = retryTargets.map(\.id)
        repository.resetChunksForRetranscription(chunkIds: chunkIds, sessionId: sessionId)
        loadSession()

        Task {
            for chunk in retryTargets {
                await transcriptionQueue.retranscribeChunk(chunkId: chunk.id, sessionId: sessionId)
            }
            loadSession()
            isRetranscribing = false
        }
    }

    // MARK: - Private Helpers

    private func reloadSegmentsFromEntity() {
        if let entity = repository.fetchSession(id: sessionId) {
            speakerNames = entity.speakerNames
            let allSpeakerIndices = Set(entity.segmentsArray.map { Int($0.speakerIndex) }).filter { $0 >= 0 }
            speakerCount = allSpeakerIndices.count

            segments = entity.segmentsArray.map { seg in
                let idx = Int(seg.speakerIndex)
                let name: String? = idx >= 0 ? (speakerNames[idx] ?? SpeakerColors.defaultName(for: idx)) : nil
                return SegmentDisplayInfo(
                    id: seg.id ?? UUID(),
                    text: seg.text ?? "",
                    startMs: seg.startMs,
                    endMs: seg.endMs,
                    isUserEdited: seg.isUserEdited,
                    originalText: seg.originalText,
                    speakerIndex: idx,
                    speakerName: name
                )
            }
            transcript = repository.getFullTranscriptText(sessionId: sessionId)
        }
    }

    // MARK: - Speaker Management

    func renameSpeaker(index: Int, newName: String) {
        repository.renameSpeaker(sessionId: sessionId, speakerIndex: index, newName: newName)
        reloadSegmentsFromEntity()
    }

    func reassignSegmentSpeaker(segmentId: UUID, newSpeakerIndex: Int) {
        repository.reassignSegmentSpeaker(segmentId: segmentId, newSpeakerIndex: newSpeakerIndex)
        reloadSegmentsFromEntity()
    }
}

// MARK: - Segment Display Info

struct SegmentDisplayInfo: Identifiable {
    let id: UUID
    let text: String
    let startMs: Int64
    let endMs: Int64
    let isUserEdited: Bool
    let originalText: String?
    let speakerIndex: Int       // -1 = undiarized
    let speakerName: String?    // Custom or default name; nil when undiarized
}

// MARK: - Chunk Display Info

struct ChunkDisplayInfo: Identifiable {
    let id: UUID
    let index: Int
    let status: TranscriptionStatus
    let durationSec: Double
    let audioDeleted: Bool

    var statusLabel: String {
        switch status {
        case .pending: return "Pending"
        case .running: return "Transcribing"
        case .done: return "Done"
        case .failed: return "Failed"
        }
    }

    var statusColor: SwiftUI.Color {
        switch status {
        case .pending: return .secondary
        case .running: return .orange
        case .done: return .green
        case .failed: return .red
        }
    }
}
