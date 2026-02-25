import AVFoundation
import Foundation
import os.log

/// Manages the AVAudioEngine lifecycle for real-time audio capture with dual-path processing.
///
/// Installs a tap on the input node and routes audio through two independent paths:
/// - **Path 1 (Recognition):** Buffers are forwarded directly via `rawBufferHandler` when provided.
///   If no handler is provided, raw buffer copies are yielded to `rawBufferStream`.
/// - **Path 2 (UI):** Samples are run through `AudioPreprocessor` to produce `AudioLevel`
///   values for the level meter and speech indicator when `uiLevelPolicy == .enabled`.
///
/// Enables voice processing on the input node for Apple's built-in noise suppression,
/// echo cancellation, AGC, and beamforming — critical for far-field recording.
/// Does NOT manage the audio session (that responsibility stays with RecordingCoordinator).
///
/// **Lifecycle:** Single-use. Call `start()` once, then `stop()` once. After `stop()`,
/// discard this instance and create a new one to restart recording. The `AsyncStream`s
/// are finished on `stop()` and cannot be restarted.
final class AudioEngineManager: @unchecked Sendable {
    enum UILevelProcessingPolicy: Sendable {
        case disabled
        case enabled
    }

    struct RuntimeMetrics: Sendable {
        let tapCallbacks: Int
        let rawBufferCopies: Int
        let levelSampleCopies: Int
    }

    typealias RawBufferHandler = @Sendable (AVAudioPCMBuffer) -> Void

    private final class MetricsStore: @unchecked Sendable {
        private let lock = NSLock()
        private var tapCallbacks = 0
        private var rawBufferCopies = 0
        private var levelSampleCopies = 0

        func incrementTapCallbacks() {
            lock.lock()
            tapCallbacks += 1
            lock.unlock()
        }

        func incrementRawBufferCopies() {
            lock.lock()
            rawBufferCopies += 1
            lock.unlock()
        }

        func incrementLevelSampleCopies() {
            lock.lock()
            levelSampleCopies += 1
            lock.unlock()
        }

        func snapshot() -> RuntimeMetrics {
            lock.lock()
            let snapshot = RuntimeMetrics(
                tapCallbacks: tapCallbacks,
                rawBufferCopies: rawBufferCopies,
                levelSampleCopies: levelSampleCopies
            )
            lock.unlock()
            return snapshot
        }
    }

    private let logger = Logger(subsystem: "com.lifememo.app", category: "AudioEngineManager")
    private let stateLock = NSLock()
    private var _isRunning = false

    private(set) var isRunning: Bool {
        get { stateLock.withLock { _isRunning } }
        set { stateLock.withLock { _isRunning = newValue } }
    }

    let rawBufferStream: AsyncStream<AVAudioPCMBuffer>
    let audioLevelStream: AsyncStream<AudioLevel>

    private let preprocessor: AudioPreprocessor
    private let uiLevelPolicy: UILevelProcessingPolicy
    private let rawBufferHandler: RawBufferHandler?
    private let metrics = MetricsStore()

    // Engine and tap (accessed only during start/stop)
    private var engine: AVAudioEngine?
    private var bufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var levelContinuation: AsyncStream<AudioLevel>.Continuation?

    init(
        preprocessor: AudioPreprocessor = AudioPreprocessor(),
        uiLevelPolicy: UILevelProcessingPolicy = .disabled,
        rawBufferHandler: RawBufferHandler? = nil
    ) {
        self.preprocessor = preprocessor
        self.uiLevelPolicy = uiLevelPolicy
        self.rawBufferHandler = rawBufferHandler

        var bufCont: AsyncStream<AVAudioPCMBuffer>.Continuation!
        self.rawBufferStream = AsyncStream { bufCont = $0 }
        self.bufferContinuation = bufCont

        var lvlCont: AsyncStream<AudioLevel>.Continuation!
        self.audioLevelStream = AsyncStream { lvlCont = $0 }
        self.levelContinuation = lvlCont
    }

    deinit {
        // Safety net: stop the engine if stop() was never called.
        // Continuations are finished in stop(); finishing twice is safe (idempotent).
        if _isRunning {
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
        }
        bufferContinuation?.finish()
        levelContinuation?.finish()
    }

    /// Start the audio engine with voice processing and dual-path tap.
    ///
    /// The audio session must already be configured and active before calling this
    /// (handled by RecordingCoordinator via AudioSessionConfigurator).
    func start() throws {
        guard !isRunning else { return }

        let newEngine = AVAudioEngine()

        do {
            // Enable Apple's built-in voice processing (AEC + noise suppression + beamforming)
            try newEngine.inputNode.setVoiceProcessingEnabled(true)

            let inputNode = newEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            // Use the input node's native format for the tap
            let recordingFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputFormat.sampleRate,
                channels: 1,
                interleaved: false
            )!

            // Capture references for the Sendable tap closure to avoid
            // retaining self and to ensure thread safety on the audio render thread.
            let preprocessor = self.preprocessor
            let bufferCont = self.bufferContinuation
            let levelCont = self.levelContinuation
            let sampleRate = inputFormat.sampleRate
            let uiLevelPolicy = self.uiLevelPolicy
            let rawBufferHandler = self.rawBufferHandler
            let metrics = self.metrics

            // Install tap with dual-path processing
            inputNode.installTap(
                onBus: 0,
                bufferSize: 4096,
                format: recordingFormat
            ) { buffer, _ in
                // Runs on audio render thread — must be fast and non-blocking
                guard buffer.frameLength > 0 else { return }
                metrics.incrementTapCallbacks()

                // PATH 1: Forward to recognizer.
                // Prefer direct forwarding when a handler is provided to avoid
                // per-callback buffer allocation on the render thread.
                if let rawBufferHandler {
                    rawBufferHandler(buffer)
                } else if let rawCopy = Self.copyBuffer(buffer) {
                    metrics.incrementRawBufferCopies()
                    bufferCont?.yield(rawCopy)
                }

                // PATH 2: Run preprocessor for UI audio level (advisory only)
                guard uiLevelPolicy == .enabled,
                      let channelData = buffer.floatChannelData,
                      buffer.format.channelCount > 0 else { return }

                let samples = Array(
                    UnsafeBufferPointer(
                        start: channelData[0],
                        count: Int(buffer.frameLength)
                    )
                )
                metrics.incrementLevelSampleCopies()
                let result = preprocessor.process(samples, sampleRate: sampleRate)
                levelCont?.yield(result.level)
            }

            // Start engine
            newEngine.prepare()
            try newEngine.start()

            self.engine = newEngine
            if uiLevelPolicy == .enabled {
                preprocessor.reset()
            }
            isRunning = true
        } catch {
            // Clean up the tap if engine start or voice processing failed
            newEngine.inputNode.removeTap(onBus: 0)
            throw error
        }
    }

    /// Stop the audio engine and finish all streams.
    func stop() {
        guard isRunning else { return }

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil

        // Finish streams so consumers know recording has ended
        bufferContinuation?.finish()
        levelContinuation?.finish()

        isRunning = false

        let snapshot = metrics.snapshot()
        logger.info(
            "Tap metrics callbacks=\(snapshot.tapCallbacks, privacy: .public) rawCopies=\(snapshot.rawBufferCopies, privacy: .public) levelCopies=\(snapshot.levelSampleCopies, privacy: .public)"
        )
    }

    func runtimeMetrics() -> RuntimeMetrics {
        metrics.snapshot()
    }

    // MARK: - Buffer Copy

    /// Creates an independent copy of an AVAudioPCMBuffer to avoid lifetime issues
    /// with engine-owned buffers.
    private static func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: buffer.frameLength
        ) else { return nil }

        copy.frameLength = buffer.frameLength

        if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
            for ch in 0..<Int(buffer.format.channelCount) {
                dst[ch].update(from: src[ch], count: Int(buffer.frameLength))
            }
        }

        return copy
    }
}
