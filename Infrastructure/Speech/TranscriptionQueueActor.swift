import Foundation
import os.log

/// Actor-based serial queue for processing transcription jobs.
///
/// Chunks are enqueued as they finish recording and processed one at a time
/// to avoid overloading the on-device speech recognizer. Each job updates
/// the chunk's transcription status in Core Data, runs the recognizer, and
/// saves the resulting transcript with speaker diarization.
///
/// Processing is deferred while recording is active, under low power mode,
/// or when thermal state is serious/critical.
actor TranscriptionQueueActor {

    // MARK: - Dependencies

    private let repository: SessionRepository
    private let transcriber: OnDeviceTranscriber
    private let diarizer: SpeakerDiarizer
    private let logger = Logger(subsystem: "com.lifememo.app", category: "TranscriptionQueue")

    // MARK: - Queue State

    private var isRunning = false
    private var isRecordingActive = false
    private var pendingJobs: [(sessionId: UUID, chunkId: UUID)] = []

    // MARK: - Initializer

    init(
        repository: SessionRepository,
        transcriber: OnDeviceTranscriber,
        diarizer: SpeakerDiarizer
    ) {
        self.repository = repository
        self.transcriber = transcriber
        self.diarizer = diarizer
    }

    // MARK: - Public API

    /// Enqueues a chunk for transcription and starts processing if not already running.
    ///
    /// - Parameters:
    ///   - chunkId: The identifier of the audio chunk to transcribe.
    ///   - sessionId: The session the chunk belongs to.
    func enqueue(chunkId: UUID, sessionId: UUID) async {
        pendingJobs.append((sessionId: sessionId, chunkId: chunkId))
        await processQueueIfNeeded()
    }

    /// Removes all pending jobs from the queue.
    func cancelAll() {
        pendingJobs.removeAll()
    }

    /// Removes a specific pending job by chunk identifier.
    ///
    /// - Parameter chunkId: The identifier of the chunk to remove from the queue.
    func cancelJob(chunkId: UUID) {
        pendingJobs.removeAll { $0.chunkId == chunkId }
    }

    /// Re-enqueues a chunk for transcription after a retry from the session detail screen.
    /// The caller is responsible for resetting the chunk via `SessionRepository.resetChunkForRetranscription`
    /// before invoking this method.
    ///
    /// Note: `await` returns once the job has been enqueued and the queue has processed
    /// as far as it can. If other jobs are already running, the new job may not be complete
    /// when this method returns.
    ///
    /// - Parameters:
    ///   - chunkId: The identifier of the audio chunk to retranscribe.
    ///   - sessionId: The session the chunk belongs to.
    func retranscribeChunk(chunkId: UUID, sessionId: UUID) async {
        await enqueue(chunkId: chunkId, sessionId: sessionId)
    }

    /// Sets whether recording is currently active.
    ///
    /// While recording is active, transcription processing is deferred to avoid
    /// competing for resources. When recording stops, the queue is flushed.
    ///
    /// - Parameter active: Whether recording is currently in progress.
    func setRecordingActive(_ active: Bool) async {
        isRecordingActive = active
        if !active {
            await processQueueIfNeeded()
        }
    }

    // MARK: - Queue Processing

    private var shouldDefer: Bool {
        if isRecordingActive { return true }
        let processInfo = ProcessInfo.processInfo
        if processInfo.isLowPowerModeEnabled { return true }
        if processInfo.thermalState == .serious
            || processInfo.thermalState == .critical {
            return true
        }
        return false
    }

    private func processQueueIfNeeded() async {
        guard !isRunning else { return }
        guard !shouldDefer else { return }
        isRunning = true
        defer { isRunning = false }

        while !pendingJobs.isEmpty && !shouldDefer {
            let job = pendingJobs.removeFirst()
            await processJob(sessionId: job.sessionId, chunkId: job.chunkId)
        }
    }

    private func processJob(sessionId: UUID, chunkId: UUID) async {
        await MainActor.run {
            repository.updateChunkTranscriptionStatus(
                chunkId: chunkId,
                status: .running
            )
        }

        let chunkURL: URL? = await MainActor.run {
            repository.getChunkFileURL(chunkId: chunkId)
        }

        guard let fileURL = chunkURL else {
            await markFailed(chunkId: chunkId, sessionId: sessionId)
            return
        }

        let locale: Locale = await MainActor.run {
            repository.getLocaleForSession(sessionId: sessionId)
        }
        let chunkDurationSec: Double = await MainActor.run {
            repository.getChunkDurationSec(chunkId: chunkId)
        }

        do {
            let detail = try await transcriber.transcribeFileWithSegments(
                url: fileURL,
                locale: locale
            )

            let diarization = diarizer.diarize(
                audioURL: fileURL,
                wordSegments: detail.wordSegments
            )

            logger.info(
                "Chunk \(chunkId.uuidString, privacy: .public) recognized source=\(detail.diagnostics.textSource.rawValue, privacy: .public) textLen=\(detail.diagnostics.textLength, privacy: .public) wordCount=\(detail.diagnostics.wordCount, privacy: .public) firstWordMs=\(detail.diagnostics.firstWordStartMs ?? -1, privacy: .public) lastWordMs=\(detail.diagnostics.lastWordEndMs ?? -1, privacy: .public) conflictRate=\(detail.diagnostics.conflictWordRate, privacy: .public) alignment=\(detail.diagnostics.alignmentScore, privacy: .public)"
            )

            let evaluation = TranscriptionCompletenessEvaluator.evaluate(
                fullText: detail.formattedString,
                wordSegments: detail.wordSegments,
                diarizedSegments: diarization.segments,
                chunkDurationSec: chunkDurationSec
            )
            let useDiarizedPersistence = diarization.speakerCount > 1 && !evaluation.shouldFallbackToFullText

            if evaluation.isSuspectTruncation {
                logger.warning(
                    "Diarization completeness warning chunk \(chunkId.uuidString, privacy: .public) reason=\(evaluation.reason ?? "unknown", privacy: .public) fullLen=\(evaluation.fullTextLength, privacy: .public) diarizedLen=\(evaluation.diarizedTextLength, privacy: .public) wordSpanMs=\(evaluation.wordSpanMs ?? -1, privacy: .public) diarizedSpanMs=\(evaluation.diarizedSpanMs ?? -1, privacy: .public)"
                )
            }

            await MainActor.run {
                if useDiarizedPersistence {
                    repository.saveTranscriptWithSpeakers(
                        sessionId: sessionId,
                        chunkId: chunkId,
                        diarization: diarization,
                        fullText: detail.formattedString
                    )
                    // Save speaker profiles for cross-chunk alignment
                    if !diarization.speakerProfiles.isEmpty {
                        let chunkIndex = repository.getChunkIndex(chunkId: chunkId)
                        repository.saveSpeakerProfiles(
                            sessionId: sessionId,
                            chunkIndex: chunkIndex,
                            profiles: diarization.speakerProfiles
                        )
                    }
                } else {
                    // Single-speaker path or defensive fallback to prevent truncation.
                    repository.saveTranscript(
                        sessionId: sessionId,
                        chunkId: chunkId,
                        text: detail.formattedString
                    )
                }
                repository.updateChunkTranscriptionStatus(
                    chunkId: chunkId,
                    status: .done
                )
                repository.refreshSessionSummary(sessionId: sessionId)
                repository.checkAndFinalizeSessionStatus(sessionId: sessionId)
            }
        } catch {
            logger.error(
                "Transcription failed for chunk \(chunkId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            await markFailed(chunkId: chunkId, sessionId: sessionId)
        }
    }

    // MARK: - Helpers

    private func markFailed(chunkId: UUID, sessionId: UUID) async {
        await MainActor.run {
            repository.updateChunkTranscriptionStatus(
                chunkId: chunkId,
                status: .failed
            )
            repository.checkAndFinalizeSessionStatus(sessionId: sessionId)
        }
    }
}
