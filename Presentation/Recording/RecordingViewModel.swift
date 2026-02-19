import Foundation
import UIKit
import Combine

/// ViewModel for the active recording screen.
///
/// Wraps `RecordingCoordinator` to provide recording actions with
/// haptic feedback. Manages waveform animation data, live transcription
/// segment display, and inline segment editing for the UI.
@MainActor
final class RecordingViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var waveformLevels: [Float] = Array(repeating: 0.1, count: 30)
    @Published var liveTranscriptText: String = ""
    @Published private(set) var liveSegments: [LiveSegment] = []
    @Published private(set) var partialText: String = ""
    @Published private(set) var chunkCount: Int = 0
    @Published var editingSegmentId: UUID?
    @Published var editingSegmentText: String = ""

    // MARK: - Private State

    private var liveEditRecords: [LiveEditRecord] = []
    private var nextEditSequence: Int = 0

    // MARK: - Dependencies

    private let coordinator: RecordingCoordinator
    private let repository: SessionRepository
    private weak var meterCollector: AudioMeterCollector?
    private let liveTranscriber: LiveTranscriber
    private var meterCancellable: AnyCancellable?
    private var transcriptCancellable: AnyCancellable?
    private var chunkCountTimer: Timer?

    // MARK: - Computed

    var state: RecordingState { coordinator.state }
    var elapsedSeconds: TimeInterval { coordinator.elapsedSeconds }

    // MARK: - Init

    init(
        coordinator: RecordingCoordinator,
        repository: SessionRepository,
        meterCollector: AudioMeterCollector?,
        liveTranscriber: LiveTranscriber
    ) {
        self.coordinator = coordinator
        self.repository = repository
        self.meterCollector = meterCollector
        self.liveTranscriber = liveTranscriber
    }

    // MARK: - Actions

    func addHighlight() {
        triggerHaptic(.medium)
        coordinator.addHighlight()
    }

    func stopRecording() {
        triggerHaptic(.heavy)
        if let sessionId = coordinator.state.sessionId, !liveEditRecords.isEmpty {
            repository.saveLiveEditRecords(sessionId: sessionId, records: liveEditRecords)
        }
        coordinator.stop()
    }

    // MARK: - Segment Editing

    func beginSegmentEdit(_ segment: LiveSegment) {
        editingSegmentId = segment.id
        editingSegmentText = segment.text
    }

    func saveSegmentEdit() {
        guard let segmentId = editingSegmentId else { return }
        guard let index = liveSegments.firstIndex(where: { $0.id == segmentId }) else {
            cancelSegmentEdit()
            return
        }

        let original = liveSegments[index]
        let trimmed = editingSegmentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != original.text else {
            cancelSegmentEdit()
            return
        }

        // Update segment immutably
        let updated = original.withText(trimmed)
        var newSegments = liveSegments
        newSegments[index] = updated
        liveSegments = newSegments

        // Update LiveTranscriber so fullText stays in sync
        liveTranscriber.updateSegmentText(id: segmentId, newText: trimmed)

        // Record the edit — keep only the latest edit per segment
        liveEditRecords.removeAll { $0.liveSegmentId == segmentId }
        let record = LiveEditRecord(
            id: UUID(),
            liveSegmentId: segmentId,
            sequenceIndex: nextEditSequence,
            originalText: original.text,
            editedText: trimmed,
            editedAt: Date()
        )
        nextEditSequence += 1
        liveEditRecords.append(record)

        // Recompute transcript text
        recomputeTranscriptText()
        cancelSegmentEdit()
    }

    func cancelSegmentEdit() {
        editingSegmentId = nil
        editingSegmentText = ""
    }

    func hasPendingEdit(for segmentId: UUID) -> Bool {
        liveEditRecords.contains { $0.liveSegmentId == segmentId }
    }

    // MARK: - Segment Sync

    /// Synchronizes segments from provided values, preserving user-edited segments.
    private func syncLiveSegments(
        transcriberSegments: [LiveSegment],
        transcriberPartial: String
    ) {
        let editedIds = Set(liveEditRecords.map(\.liveSegmentId))

        // Merge: keep edited segments, update/add non-edited
        var merged: [LiveSegment] = []
        for segment in transcriberSegments {
            if editedIds.contains(segment.id),
               let existing = liveSegments.first(where: { $0.id == segment.id }) {
                merged.append(existing)
            } else {
                merged.append(segment)
            }
        }

        liveSegments = merged
        partialText = transcriberPartial
        recomputeTranscriptText()
    }

    // MARK: - Waveform

    func startWaveformAnimation() {
        // Subscribe to meter collector updates
        if let collector = meterCollector {
            meterCancellable = collector.$recentLevels
                .receive(on: RunLoop.main)
                .sink { [weak self] levels in
                    self?.waveformLevels = levels
                }
        }

        // Subscribe to live transcription segment + partial updates
        // Use $confirmedSegments + $partialText to get values AFTER they change
        transcriptCancellable = liveTranscriber.$confirmedSegments
            .combineLatest(liveTranscriber.$partialText)
            .receive(on: RunLoop.main)
            .sink { [weak self] segments, partial in
                guard let self else { return }
                self.syncLiveSegments(
                    transcriberSegments: segments,
                    transcriberPartial: partial
                )
            }

        // Periodically refresh chunk count (every 5s) instead of fetching on every render
        refreshChunkCount()
        chunkCountTimer = Timer.scheduledTimer(
            withTimeInterval: 5.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshChunkCount()
            }
        }
    }

    func stopWaveformAnimation() {
        meterCancellable?.cancel()
        meterCancellable = nil
        transcriptCancellable?.cancel()
        transcriptCancellable = nil
        chunkCountTimer?.invalidate()
        chunkCountTimer = nil
        waveformLevels = Array(repeating: 0.1, count: 30)
    }

    // MARK: - Private

    private func refreshChunkCount() {
        guard let sessionId = coordinator.state.sessionId else {
            chunkCount = 0
            return
        }
        let session = repository.fetchSession(id: sessionId)
        chunkCount = session?.chunksArray.count ?? 0
    }

    private func recomputeTranscriptText() {
        liveTranscriptText = liveTranscriber.fullText
    }

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}
