import Foundation

/// ViewModel for setting up audio playback from a recording session.
///
/// Loads chunk information from the session entity and configures
/// both the audio player and synced playback controller.
@MainActor
final class PlaybackViewModel: ObservableObject {

    @Published private(set) var isReady = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasAudio = false

    let audioPlayer: AudioPlayer
    let controller: SyncedPlaybackController

    private let repository: SessionRepository
    private let fileStore: FileStore

    init(repository: SessionRepository, fileStore: FileStore) {
        self.repository = repository
        self.fileStore = fileStore
        self.audioPlayer = AudioPlayer()
        self.controller = SyncedPlaybackController(audioPlayer: audioPlayer)
    }

    func loadSession(sessionId: UUID) {
        guard let session = repository.fetchSession(id: sessionId) else {
            errorMessage = "Session not found"
            return
        }

        guard session.audioKept else {
            errorMessage = "Audio has been deleted for this session"
            hasAudio = false
            return
        }

        // Build chunk info list
        let chunks: [AudioPlayer.ChunkInfo] = session.chunksArray.compactMap { chunk in
            guard !chunk.audioDeleted,
                  chunk.durationSec > 0,
                  let relPath = chunk.relativePath,
                  let url = fileStore.resolveAbsoluteURL(relativePath: relPath) else { return nil }

            let startAt = chunk.startAt ?? session.startedAt ?? Date()
            let sessionStart = session.startedAt ?? Date()
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
            errorMessage = "No playable audio chunks found"
            hasAudio = false
            return
        }

        hasAudio = true
        audioPlayer.loadSession(chunks: chunks)

        // Load transcript segments with speaker data
        let speakerNames = session.speakerNames
        let segments = session.segmentsArray.map { seg in
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
        controller.loadSegments(segments)

        isReady = true
    }

    func cleanup() {
        audioPlayer.stop()
    }
}
