import Foundation
import AVFAudio
import Combine

/// Handles audio session interruptions and route changes.
///
/// Monitors `AVAudioSession.interruptionNotification` and `.routeChangeNotification`
/// to detect events that pause recording (phone calls, alarms, Siri). Provides
/// auto-recovery logic that attempts to resume recording after the interruption ends.
@MainActor
final class AudioInterruptionHandler: ObservableObject {

    enum InterruptionState: Equatable {
        case none
        case interrupted(reason: String)
        case recovering
    }

    @Published private(set) var interruptionState: InterruptionState = .none
    @Published private(set) var lastInterruptionDate: Date?

    /// Callback invoked when recording should be paused
    var onShouldPause: (() -> Void)?
    /// Callback invoked when recording can be resumed
    var onShouldResume: (() -> Void)?
    /// Callback invoked when recovery failed
    var onRecoveryFailed: ((String) -> Void)?

    private var cancellables = Set<AnyCancellable>()
    private let maxRecoveryAttempts = 3
    private var recoveryAttempts = 0

    init() {
        setupNotifications()
    }

    deinit {
        // NotificationCenter observations via Combine are auto-cancelled
    }

    // MARK: - Setup

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                Task { @MainActor in
                    self?.handleInterruption(notification)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                Task { @MainActor in
                    self?.handleRouteChange(notification)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleMediaServicesReset()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Interruption Handling

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeRaw = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }

        switch type {
        case .began:
            let reason = interruptionReason(from: userInfo)
            interruptionState = .interrupted(reason: reason)
            lastInterruptionDate = Date()
            recoveryAttempts = 0
            onShouldPause?()

        case .ended:
            let shouldResume = shouldResumeAfterInterruption(userInfo: userInfo)
            if shouldResume {
                attemptRecovery()
            } else {
                interruptionState = .none
                onRecoveryFailed?("Audio session interruption ended but resume not recommended")
            }

        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonRaw = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }

        switch reason {
        case .oldDeviceUnavailable:
            // Headset unplugged - explicitly fall back to built-in mic
            let session = AVAudioSession.sharedInstance()
            if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try? session.setPreferredInput(builtIn)
            }
        case .newDeviceAvailable:
            break
        case .categoryChange:
            break
        default:
            break
        }
    }

    private func handleMediaServicesReset() {
        // Media services were reset entirely - need full re-initialization
        interruptionState = .none
        recoveryAttempts = 0
        // Notify that a full restart is needed
        onShouldPause?()

        // Delay to allow system to stabilize, then attempt restart
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            onShouldResume?()
        }
    }

    // MARK: - Recovery

    private func attemptRecovery() {
        guard recoveryAttempts < maxRecoveryAttempts else {
            interruptionState = .none
            onRecoveryFailed?("Failed to recover after \(maxRecoveryAttempts) attempts")
            return
        }

        interruptionState = .recovering
        recoveryAttempts += 1

        // Delay slightly to allow the system to settle
        let delay = Double(recoveryAttempts) * 0.5
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            do {
                let session = AVAudioSession.sharedInstance()
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                self.interruptionState = .none
                self.onShouldResume?()
            } catch {
                // Retry
                self.attemptRecovery()
            }
        }
    }

    // MARK: - Helpers

    private func interruptionReason(from userInfo: [AnyHashable: Any]) -> String {
        if let reasonRaw = userInfo[AVAudioSessionInterruptionReasonKey] as? UInt {
            switch AVAudioSession.InterruptionReason(rawValue: reasonRaw) {
            case .default:
                return "System interruption (e.g., phone call)"
            case .appWasSuspended:
                return "App was suspended by the system"
            case .builtInMicMuted:
                return "Built-in microphone was muted"
            @unknown default:
                return "Unknown interruption"
            }
        }
        return "Audio interruption"
    }

    private func shouldResumeAfterInterruption(userInfo: [AnyHashable: Any]) -> Bool {
        if let optionsRaw = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            return options.contains(.shouldResume)
        }
        return false
    }

    func resetState() {
        interruptionState = .none
        recoveryAttempts = 0
        lastInterruptionDate = nil
    }
}
