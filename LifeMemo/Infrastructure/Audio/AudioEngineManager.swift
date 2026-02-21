import AVFoundation
import Foundation

/// Manages the AVAudioEngine lifecycle for real-time audio capture and preprocessing.
///
/// Installs a tap on the input node, routes audio through the `AudioPreprocessor`,
/// and publishes processed buffers and audio levels via `AsyncStream`s.
/// Enables voice processing on the input node for built-in iOS noise suppression
/// and echo cancellation — critical for far-field recording.
@Observable
final class AudioEngineManager: @unchecked Sendable {
    private(set) var isRunning = false

    let processedBufferStream: AsyncStream<AVAudioPCMBuffer>
    let audioLevelStream: AsyncStream<AudioLevel>

    private let sessionConfigurator: AudioSessionConfigurator
    private let preprocessor: AudioPreprocessor

    // Engine and tap (accessed on MainActor only during start/stop)
    private var engine: AVAudioEngine?
    private var bufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var levelContinuation: AsyncStream<AudioLevel>.Continuation?

    init(
        sessionConfigurator: AudioSessionConfigurator = AudioSessionConfigurator(),
        preprocessor: AudioPreprocessor = AudioPreprocessor()
    ) {
        self.sessionConfigurator = sessionConfigurator
        self.preprocessor = preprocessor

        var bufCont: AsyncStream<AVAudioPCMBuffer>.Continuation!
        self.processedBufferStream = AsyncStream { bufCont = $0 }
        self.bufferContinuation = bufCont

        var lvlCont: AsyncStream<AudioLevel>.Continuation!
        self.audioLevelStream = AsyncStream { lvlCont = $0 }
        self.levelContinuation = lvlCont
    }

    deinit {
        bufferContinuation?.finish()
        levelContinuation?.finish()
    }

    /// Start the audio engine with preprocessing enabled.
    ///
    /// Configures the audio session for far-field recording, enables
    /// voice processing on the input node, and installs a tap to
    /// capture and preprocess audio buffers.
    func start() throws {
        guard !isRunning else { return }

        do {
            // 1. Configure audio session
            try sessionConfigurator.configureForFarFieldRecording()

            // 2. Create and configure engine
            let newEngine = AVAudioEngine()

            #if os(iOS)
            // Enable Apple's built-in voice processing (AEC + noise suppression)
            try newEngine.inputNode.setVoiceProcessingEnabled(true)
            #endif

            let inputNode = newEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            // Use 16kHz mono Float32 for speech recognition
            let recordingFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputFormat.sampleRate,
                channels: 1,
                interleaved: false
            )!

            // Capture references for the Sendable tap closure
            let preprocessor = self.preprocessor
            let bufferCont = self.bufferContinuation
            let levelCont = self.levelContinuation
            let sampleRate = inputFormat.sampleRate

            // 3. Install tap on input node
            inputNode.installTap(
                onBus: 0,
                bufferSize: 4096,
                format: recordingFormat
            ) { buffer, _ in
                // Runs on audio render thread — must be fast and non-blocking
                guard let channelData = buffer.floatChannelData,
                      buffer.format.channelCount > 0,
                      buffer.frameLength > 0
                else { return }

                let frameCount = Int(buffer.frameLength)
                let samples = Array(
                    UnsafeBufferPointer(start: channelData[0], count: frameCount)
                )

                // Preprocess: denoise → AGC → VAD
                let result = preprocessor.process(samples, sampleRate: sampleRate)

                // Publish audio level for UI
                levelCont?.yield(result.level)

                // Only forward buffers with speech to the recognizer
                guard result.isSpeech else { return }

                // Create a new buffer with processed samples
                guard let processedBuffer = AVAudioPCMBuffer(
                    pcmFormat: buffer.format,
                    frameCapacity: AVAudioFrameCount(result.samples.count)
                ) else { return }

                processedBuffer.frameLength = AVAudioFrameCount(result.samples.count)
                if let dest = processedBuffer.floatChannelData?[0] {
                    let count = min(
                        result.samples.count,
                        Int(processedBuffer.frameCapacity)
                    )
                    result.samples.withContiguousStorageIfAvailable { src in
                        guard let srcPtr = src.baseAddress else { return }
                        dest.update(from: srcPtr, count: count)
                    }
                }

                bufferCont?.yield(processedBuffer)
            }

            // 4. Start engine
            newEngine.prepare()
            try newEngine.start()

            self.engine = newEngine
            preprocessor.reset()
            isRunning = true
        } catch {
            // Deactivate audio session on error to release resources
            sessionConfigurator.deactivate()
            throw error
        }
    }

    /// Stop the audio engine and deactivate the audio session.
    func stop() {
        guard isRunning else { return }

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil

        // Finish streams so consumers know recording has ended
        bufferContinuation?.finish()
        levelContinuation?.finish()

        sessionConfigurator.deactivate()
        isRunning = false
    }
}
