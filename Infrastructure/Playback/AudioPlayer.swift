import Foundation
import AVFAudio

/// Audio player that handles seamless playback across multiple chunk files.
///
/// Since recordings are stored as 60-second chunks, this player manages
/// transitioning between chunks to provide a continuous playback experience.
/// Supports seeking to any point in the session by timestamp.
@MainActor
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {

    enum PlaybackState: Equatable {
        case idle
        case playing
        case paused
        case finished
        case error(String)
    }

    struct ChunkInfo {
        let chunkId: UUID
        let url: URL
        let startOffsetMs: Int64
        let durationMs: Int64
    }

    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var currentTimeMs: Int64 = 0
    @Published private(set) var totalDurationMs: Int64 = 0
    @Published var playbackRate: Float = 1.0

    private var chunks: [ChunkInfo] = []
    private var currentChunkIndex: Int = 0
    private var player: AVAudioPlayer?
    private var updateTimer: Timer?

    // MARK: - Setup

    func loadSession(chunks: [ChunkInfo]) {
        self.chunks = chunks.sorted { $0.startOffsetMs < $1.startOffsetMs }
        self.totalDurationMs = chunks.reduce(0) { $0 + $1.durationMs }
        self.currentChunkIndex = 0
        self.currentTimeMs = 0
        self.state = .idle
    }

    // MARK: - Playback Controls

    func play() {
        guard !chunks.isEmpty else {
            state = .error("No audio chunks available")
            return
        }

        if state == .paused, let player {
            player.play()
            state = .playing
            startUpdateTimer()
            return
        }

        playChunk(at: currentChunkIndex)
    }

    func pause() {
        player?.pause()
        state = .paused
        stopUpdateTimer()
    }

    func stop() {
        player?.stop()
        player = nil
        state = .idle
        currentTimeMs = 0
        currentChunkIndex = 0
        stopUpdateTimer()
    }

    func seekTo(ms: Int64) {
        let targetMs = max(0, min(ms, totalDurationMs))

        // Find the chunk containing this timestamp
        guard let (index, chunk) = findChunk(for: targetMs) else { return }

        let offsetInChunkMs = targetMs - chunk.startOffsetMs
        let wasPlaying = state == .playing

        currentChunkIndex = index
        currentTimeMs = targetMs

        if wasPlaying || state == .paused {
            preparePlayer(for: chunk)
            player?.currentTime = TimeInterval(offsetInChunkMs) / 1000.0
            if wasPlaying {
                player?.play()
                state = .playing
            }
        }
    }

    func skipForward(seconds: TimeInterval = 15) {
        seekTo(ms: currentTimeMs + Int64(seconds * 1000))
    }

    func skipBackward(seconds: TimeInterval = 15) {
        seekTo(ms: currentTimeMs - Int64(seconds * 1000))
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.advanceToNextChunk()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor in
            self.state = .error("Playback decode error: \(error?.localizedDescription ?? "Unknown")")
            self.stopUpdateTimer()
        }
    }

    // MARK: - Private

    private func playChunk(at index: Int) {
        guard index < chunks.count else {
            state = .finished
            stopUpdateTimer()
            return
        }

        let chunk = chunks[index]
        currentChunkIndex = index

        preparePlayer(for: chunk)
        player?.play()
        state = .playing
        startUpdateTimer()
    }

    private func preparePlayer(for chunk: ChunkInfo) {
        do {
            // Configure audio session for playback
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            let newPlayer = try AVAudioPlayer(contentsOf: chunk.url)
            newPlayer.delegate = self
            newPlayer.enableRate = true
            newPlayer.rate = playbackRate
            newPlayer.prepareToPlay()
            player = newPlayer
        } catch {
            state = .error("Failed to load audio: \(error.localizedDescription)")
        }
    }

    private func advanceToNextChunk() {
        let nextIndex = currentChunkIndex + 1
        if nextIndex < chunks.count {
            playChunk(at: nextIndex)
        } else {
            state = .finished
            stopUpdateTimer()
        }
    }

    private func findChunk(for ms: Int64) -> (Int, ChunkInfo)? {
        for (index, chunk) in chunks.enumerated() {
            let chunkEnd = chunk.startOffsetMs + chunk.durationMs
            if ms >= chunk.startOffsetMs && ms < chunkEnd {
                return (index, chunk)
            }
        }
        // If past all chunks, return last
        if let last = chunks.last {
            return (chunks.count - 1, last)
        }
        return nil
    }

    private func startUpdateTimer() {
        stopUpdateTimer()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCurrentTime()
            }
        }
    }

    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func updateCurrentTime() {
        guard let player, currentChunkIndex < chunks.count else { return }
        let chunk = chunks[currentChunkIndex]
        currentTimeMs = chunk.startOffsetMs + Int64(player.currentTime * 1000)
    }
}
