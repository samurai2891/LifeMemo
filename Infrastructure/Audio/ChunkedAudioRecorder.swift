import Foundation
import AVFAudio

/// Core recording engine that automatically splits audio into fixed-duration chunks.
///
/// Each chunk is persisted as an AAC file via `FileStore` and registered in Core Data
/// via `SessionRepository`. When a chunk completes, it is enqueued for transcription
/// through `TranscriptionQueueActor`.
@MainActor
final class ChunkedAudioRecorder: NSObject, AVAudioRecorderDelegate {

    // MARK: - Configuration

    struct Config {
        let chunkSeconds: TimeInterval
        let sampleRate: Double
        let channels: Int

        static let `default` = Config(
            chunkSeconds: 60,
            sampleRate: 16_000,
            channels: 1
        )
    }

    // MARK: - Dependencies

    private let config: Config
    private let repository: SessionRepository
    private let fileStore: FileStore
    private let transcriptionQueue: TranscriptionQueueActor

    // MARK: - Internal State

    private var recorder: AVAudioRecorder?
    private var timer: DispatchSourceTimer?
    private var sessionId: UUID?
    private var chunkIndex: Int = 0
    private var currentChunkId: UUID?
    private var currentLanguage: LanguageMode = .auto

    // MARK: - Initializer

    init(
        repository: SessionRepository,
        fileStore: FileStore,
        transcriptionQueue: TranscriptionQueueActor,
        config: Config = .default
    ) {
        self.repository = repository
        self.fileStore = fileStore
        self.transcriptionQueue = transcriptionQueue
        self.config = config
    }

    // MARK: - Public API

    /// Starts recording a new session, splitting audio into chunks of `config.chunkSeconds`.
    ///
    /// - Parameters:
    ///   - sessionId: The session identifier to associate chunks with.
    ///   - languageMode: The language for downstream transcription.
    /// - Throws: An error if the first chunk cannot be started.
    func start(sessionId: UUID, languageMode: LanguageMode) throws {
        self.sessionId = sessionId
        self.chunkIndex = 0
        self.currentLanguage = languageMode
        try startNewChunk(sessionId: sessionId)
        startRotationTimer()
    }

    /// Stops recording, finalizes the current chunk, and cleans up timers.
    func stop() async {
        cancelTimer()
        await finalizeCurrentChunk()
        recorder = nil
        sessionId = nil
    }

    // MARK: - Chunk Rotation Timer

    private func startRotationTimer() {
        let source = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        source.schedule(
            deadline: .now() + config.chunkSeconds,
            repeating: config.chunkSeconds
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                await self?.rotate()
            }
        }
        source.resume()
        timer = source
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Rotation

    private func rotate() async {
        await finalizeCurrentChunk()
        chunkIndex += 1
        guard let sid = sessionId else { return }
        do {
            try startNewChunk(sessionId: sid)
        } catch {
            print("ChunkedAudioRecorder: rotate failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Chunk Lifecycle

    private func startNewChunk(sessionId: UUID) throws {
        let chunkId = UUID()
        self.currentChunkId = chunkId

        let relativePath = fileStore.makeChunkRelativePath(
            sessionId: sessionId,
            index: chunkIndex,
            ext: "m4a"
        )
        let fileURL = try fileStore.ensureAudioFileURL(relativePath: relativePath)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: config.sampleRate,
            AVNumberOfChannelsKey: config.channels,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        let audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
        audioRecorder.delegate = self
        audioRecorder.isMeteringEnabled = false
        audioRecorder.record()

        recorder = audioRecorder

        repository.createOrUpdateChunkStarted(
            chunkId: chunkId,
            sessionId: sessionId,
            index: chunkIndex,
            startAt: Date(),
            relativePath: relativePath
        )
    }

    private func finalizeCurrentChunk() async {
        guard let rec = recorder,
              let sid = sessionId,
              let chunkId = currentChunkId else { return }

        rec.stop()

        let fileURL = rec.url
        let endAt = Date()
        let duration = rec.currentTime
        let fileSize = Self.fileSize(at: fileURL)

        repository.finalizeChunk(
            chunkId: chunkId,
            sessionId: sid,
            endAt: endAt,
            durationSec: duration,
            sizeBytes: fileSize
        )

        await transcriptionQueue.enqueue(chunkId: chunkId, sessionId: sid)
    }

    // MARK: - Helpers

    private static func fileSize(at url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
