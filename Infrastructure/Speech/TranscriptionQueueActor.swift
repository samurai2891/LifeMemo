import Foundation

/// Actor-based serial queue for processing transcription jobs.
///
/// Chunks are enqueued as they finish recording and processed one at a time
/// to avoid overloading the on-device speech recognizer. Each job updates
/// the chunk's transcription status in Core Data, runs the recognizer, and
/// saves the resulting transcript.
actor TranscriptionQueueActor {

    // MARK: - Dependencies

    private let repository: SessionRepository
    private let transcriber: OnDeviceTranscriber

    // MARK: - Queue State

    private var isRunning = false
    private var pendingJobs: [(sessionId: UUID, chunkId: UUID)] = []

    // MARK: - Initializer

    init(repository: SessionRepository, transcriber: OnDeviceTranscriber) {
        self.repository = repository
        self.transcriber = transcriber
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

    // MARK: - Queue Processing

    private func processQueueIfNeeded() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        while !pendingJobs.isEmpty {
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
            await markFailed(chunkId: chunkId)
            return
        }

        let locale: Locale = await MainActor.run {
            repository.getLocaleForSession(sessionId: sessionId)
        }

        do {
            let text = try await transcriber.transcribeFile(url: fileURL, locale: locale)
            await MainActor.run {
                repository.saveTranscript(
                    sessionId: sessionId,
                    chunkId: chunkId,
                    text: text
                )
                repository.updateChunkTranscriptionStatus(
                    chunkId: chunkId,
                    status: .done
                )
                repository.refreshSessionSummary(sessionId: sessionId)
            }
        } catch {
            print(
                "TranscriptionQueueActor: transcription failed for chunk "
                + "\(chunkId): \(error.localizedDescription)"
            )
            await markFailed(chunkId: chunkId)
        }
    }

    // MARK: - Helpers

    private func markFailed(chunkId: UUID) async {
        await MainActor.run {
            repository.updateChunkTranscriptionStatus(
                chunkId: chunkId,
                status: .failed
            )
        }
    }
}
