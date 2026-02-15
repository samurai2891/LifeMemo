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

    // Export
    @Published var exportFileURL: URL?
    @Published var showExportSheet: Bool = false
    @Published var showExportOptions: Bool = false

    // Playback
    @Published var showPlayback: Bool = false
    @Published private(set) var playbackController: SyncedPlaybackController?

    // Errors
    @Published var errorMessage: String?

    // Deletion
    @Published var showDeleteAudioConfirm: Bool = false
    @Published var showDeleteSessionConfirm: Bool = false
    @Published private(set) var didDeleteSession: Bool = false

    // MARK: - Dependencies

    let sessionId: UUID
    private let repository: SessionRepository
    private let fileStore: FileStore
    private let qnaService: SimpleQnAService
    private let summarizer: SimpleSummarizer
    private let exportService: ExportService
    let enhancedExportService: EnhancedExportService
    private var audioPlayer: AudioPlayer?

    // MARK: - Init

    init(
        sessionId: UUID,
        repository: SessionRepository,
        fileStore: FileStore,
        qnaService: SimpleQnAService,
        summarizer: SimpleSummarizer,
        exportService: ExportService,
        enhancedExportService: EnhancedExportService
    ) {
        self.sessionId = sessionId
        self.repository = repository
        self.fileStore = fileStore
        self.qnaService = qnaService
        self.summarizer = summarizer
        self.exportService = exportService
        self.enhancedExportService = enhancedExportService
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

        setupPlayback(entity: entity)
        isLoading = false
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
        let segments = entity.segmentsArray.map { seg in
            (id: seg.id ?? UUID(), startMs: seg.startMs, endMs: seg.endMs, text: seg.text ?? "")
        }
        controller.loadSegments(segments)
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
        let markdown = summarizer.buildSummaryMarkdown(sessionId: sessionId)
        repository.updateSessionSummary(sessionId: sessionId, markdown: markdown)

        // Reload session to pick up the new summary
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
