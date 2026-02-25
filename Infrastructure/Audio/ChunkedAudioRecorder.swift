import Foundation
import AVFAudio
import os.log

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
        let bitRate: Int

        static let `default` = Config(
            chunkSeconds: 60,
            sampleRate: 16_000,
            channels: 1,
            bitRate: 64_000
        )
    }

    // MARK: - Dependencies

    private let repository: SessionRepository
    private let fileStore: FileStore
    private let transcriptionQueue: TranscriptionQueueActor
    private let logger = Logger(subsystem: "com.lifememo.app", category: "ChunkedAudioRecorder")

    // MARK: - Metering

    weak var meterCollector: AudioMeterCollector?

    // MARK: - Internal State

    private var recorder: AVAudioRecorder?
    private var timer: DispatchSourceTimer?
    private var meterTimer: DispatchSourceTimer?
    private var sessionId: UUID?
    private var chunkIndex: Int = 0
    private var currentChunkId: UUID?
    private var currentLanguage: LanguageMode = .auto
    private var activeConfig: Config = .default

    // MARK: - Initializer

    init(
        repository: SessionRepository,
        fileStore: FileStore,
        transcriptionQueue: TranscriptionQueueActor
    ) {
        self.repository = repository
        self.fileStore = fileStore
        self.transcriptionQueue = transcriptionQueue
    }

    // MARK: - Public API

    /// Starts recording a new session, splitting audio into chunks of `config.chunkSeconds`.
    ///
    /// - Parameters:
    ///   - sessionId: The session identifier to associate chunks with.
    ///   - languageMode: The language for downstream transcription.
    /// - Throws: An error if the first chunk cannot be started.
    func start(sessionId: UUID, languageMode: LanguageMode, config: Config? = nil) throws {
        self.sessionId = sessionId
        self.chunkIndex = 0
        self.currentLanguage = languageMode
        self.activeConfig = config ?? .default
        try startNewChunk(sessionId: sessionId)
        startRotationTimer()
        startMeterTimer()
    }

    /// Stops recording, finalizes the current chunk, and cleans up timers.
    func stop() async {
        cancelTimer()
        stopMeterTimer()
        await finalizeCurrentChunk()
        recorder = nil
        sessionId = nil
    }

    // MARK: - Chunk Rotation Timer

    private func startRotationTimer() {
        let source = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        source.schedule(
            deadline: .now() + activeConfig.chunkSeconds,
            repeating: activeConfig.chunkSeconds
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
            logger.error("Chunk rotation failed: \(error.localizedDescription, privacy: .public)")
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
            AVSampleRateKey: activeConfig.sampleRate,
            AVNumberOfChannelsKey: activeConfig.channels,
            AVEncoderBitRateKey: activeConfig.bitRate,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        let audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
        audioRecorder.delegate = self
        audioRecorder.isMeteringEnabled = true
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

        // Clear immediately to prevent double-finalize from stop()/rotate() race
        currentChunkId = nil

        // Capture duration BEFORE stop() — currentTime returns 0 after stop()
        let duration = rec.currentTime
        let fileURL = rec.url

        rec.stop()

        // Allow file I/O to flush on real devices before reading size or
        // changing protection. Without this, the file may be incomplete.
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        let endAt = Date()
        let fileSize = Self.fileSize(at: fileURL)

        // Validate the chunk produced a usable file
        guard fileSize > 0, duration > 0 else {
            logger.warning(
                "Discarding empty chunk \(chunkId.uuidString, privacy: .public) (size=\(fileSize), duration=\(duration))"
            )
            return
        }

        // Escalate from recording protection to at-rest protection (P0-03).
        // File is now fully flushed to disk.
        fileStore.setAtRestProtection(at: fileURL)

        repository.finalizeChunk(
            chunkId: chunkId,
            sessionId: sid,
            endAt: endAt,
            durationSec: duration,
            sizeBytes: fileSize
        )

        await transcriptionQueue.enqueue(chunkId: chunkId, sessionId: sid)
    }

    // MARK: - Metering Timer

    private func startMeterTimer() {
        let source = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        source.schedule(deadline: .now(), repeating: 0.1)
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.updateMeterLevels()
            }
        }
        source.resume()
        meterTimer = source
    }

    private func stopMeterTimer() {
        meterTimer?.cancel()
        meterTimer = nil
    }

    private func updateMeterLevels() {
        guard let rec = recorder else { return }
        rec.updateMeters()
        let avg = rec.averagePower(forChannel: 0)
        let peak = rec.peakPower(forChannel: 0)
        meterCollector?.update(averagePower: avg, peakPower: peak)
    }

    // MARK: - Helpers

    private static func fileSize(at url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
