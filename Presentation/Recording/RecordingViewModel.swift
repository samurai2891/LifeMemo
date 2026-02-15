import Foundation
import UIKit

/// ViewModel for the active recording screen.
///
/// Wraps `RecordingCoordinator` to provide recording actions with
/// haptic feedback. Manages waveform animation data for the UI.
@MainActor
final class RecordingViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var waveformLevels: [CGFloat] = Array(repeating: 0.1, count: 30)

    // MARK: - Dependencies

    private let coordinator: RecordingCoordinator
    private let repository: SessionRepository
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

    init(coordinator: RecordingCoordinator, repository: SessionRepository) {
        self.coordinator = coordinator
        self.repository = repository
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

    // MARK: - Waveform Simulation

    func startWaveformAnimation() {
        waveformTimer?.invalidate()
        waveformTimer = Timer.scheduledTimer(
            withTimeInterval: 0.1,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateWaveformLevels()
            }
        }
    }

    func stopWaveformAnimation() {
        waveformTimer?.invalidate()
        waveformTimer = nil
        waveformLevels = Array(repeating: 0.1, count: 30)
    }

    // MARK: - Private

    private func updateWaveformLevels() {
        waveformLevels = (0..<30).map { _ in
            CGFloat.random(in: 0.05...1.0)
        }
    }

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}
