import Foundation
import UIKit
import Combine

/// ViewModel for the active recording screen.
///
/// Wraps `RecordingCoordinator` to provide recording actions with
/// haptic feedback. Manages waveform animation data for the UI.
@MainActor
final class RecordingViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var waveformLevels: [Float] = Array(repeating: 0.1, count: 30)
    @Published var liveTranscriptText: String = ""

    // MARK: - Dependencies

    private let coordinator: RecordingCoordinator
    private let repository: SessionRepository
    private weak var meterCollector: AudioMeterCollector?
    private var meterCancellable: AnyCancellable?
    private var waveformTimer: Timer?

    // MARK: - Computed

    var state: RecordingState { coordinator.state }
    var elapsedSeconds: TimeInterval { coordinator.elapsedSeconds }

    var chunkCount: Int {
        guard let sessionId = coordinator.state.sessionId else { return 0 }
        let session = repository.fetchSession(id: sessionId)
        return session?.chunksArray.count ?? 0
    }

    // MARK: - Init

    init(coordinator: RecordingCoordinator, repository: SessionRepository, meterCollector: AudioMeterCollector?) {
        self.coordinator = coordinator
        self.repository = repository
        self.meterCollector = meterCollector
    }

    // MARK: - Actions

    func addHighlight() {
        triggerHaptic(.medium)
        coordinator.addHighlight()
    }

    func stopRecording() {
        triggerHaptic(.heavy)
        coordinator.stop()
    }

    // MARK: - Waveform

    func startWaveformAnimation() {
        waveformTimer?.invalidate()
        // Subscribe to meter collector updates
        if let collector = meterCollector {
            meterCancellable = collector.$recentLevels
                .receive(on: RunLoop.main)
                .sink { [weak self] levels in
                    self?.waveformLevels = levels
                }
        }
    }

    func stopWaveformAnimation() {
        meterCancellable?.cancel()
        meterCancellable = nil
        waveformTimer?.invalidate()
        waveformTimer = nil
        waveformLevels = Array(repeating: 0.1, count: 30)
    }

    // MARK: - Private

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}
