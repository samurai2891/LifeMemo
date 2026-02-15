import Foundation
import Combine

/// Coordinates audio playback with transcript segment highlighting.
///
/// Monitors the audio player's current time and determines which
/// transcript segment should be highlighted, enabling synchronized
/// audio-text playback.
@MainActor
final class SyncedPlaybackController: ObservableObject {

    struct SegmentDisplay: Identifiable, Equatable {
        let id: UUID
        let startMs: Int64
        let endMs: Int64
        let text: String
        var isActive: Bool
    }

    @Published private(set) var segments: [SegmentDisplay] = []
    @Published private(set) var activeSegmentId: UUID?

    let audioPlayer: AudioPlayer

    private var allSegments: [SegmentDisplay] = []
    private var cancellables = Set<AnyCancellable>()

    init(audioPlayer: AudioPlayer) {
        self.audioPlayer = audioPlayer
        observePlaybackTime()
    }

    // MARK: - Setup

    func loadSegments(_ rawSegments: [(id: UUID, startMs: Int64, endMs: Int64, text: String)]) {
        allSegments = rawSegments.map {
            SegmentDisplay(id: $0.id, startMs: $0.startMs, endMs: $0.endMs, text: $0.text, isActive: false)
        }.sorted { $0.startMs < $1.startMs }

        segments = allSegments
    }

    // MARK: - Tap to Seek

    func seekToSegment(_ segmentId: UUID) {
        guard let segment = allSegments.first(where: { $0.id == segmentId }) else { return }
        audioPlayer.seekTo(ms: segment.startMs)

        if audioPlayer.state != .playing {
            audioPlayer.play()
        }
    }

    // MARK: - Observation

    private func observePlaybackTime() {
        audioPlayer.$currentTimeMs
            .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] timeMs in
                self?.updateActiveSegment(for: timeMs)
            }
            .store(in: &cancellables)
    }

    private func updateActiveSegment(for timeMs: Int64) {
        let newActiveId = allSegments.first(where: { timeMs >= $0.startMs && timeMs < $0.endMs })?.id

        guard newActiveId != activeSegmentId else { return }
        activeSegmentId = newActiveId

        segments = allSegments.map { segment in
            var updated = segment
            updated.isActive = segment.id == newActiveId
            return updated
        }
    }
}
