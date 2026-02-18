import Foundation
import os.log

/// Monitors overall recording health during long sessions (24h+).
///
/// Tracks chunk completion rates, transcription success rates,
/// disk space availability, and battery level to provide health status.
@MainActor
final class RecordingHealthMonitor: ObservableObject {

    struct HealthSnapshot: Equatable {
        let timestamp: Date
        let totalChunks: Int
        let successfulTranscriptions: Int
        let failedTranscriptions: Int
        let diskFreeGB: Double
        let sessionDurationHours: Double
        let estimatedBatteryHoursRemaining: Double?

        var transcriptionSuccessRate: Double {
            let total = successfulTranscriptions + failedTranscriptions
            guard total > 0 else { return 1.0 }
            return Double(successfulTranscriptions) / Double(total)
        }

        var isDiskSpaceLow: Bool { diskFreeGB < 1.0 }
        var isDiskSpaceCritical: Bool { diskFreeGB < 0.5 }
    }

    @Published private(set) var latestSnapshot: HealthSnapshot?
    @Published private(set) var isHealthy: Bool = true
    @Published private(set) var warnings: [String] = []

    private let logger = Logger(subsystem: "com.lifememo.app", category: "RecordingHealth")
    private var checkTimer: Timer?
    private var sessionStartDate: Date?
    private var chunkCount = 0
    private var successCount = 0
    private var failCount = 0
    private var lastKnownFileModification: Date?

    // MARK: - Lifecycle

    func startMonitoring(sessionStart: Date) {
        sessionStartDate = sessionStart
        chunkCount = 0
        successCount = 0
        failCount = 0
        warnings = []
        isHealthy = true

        checkTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performHealthCheck()
            }
        }
    }

    func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    // MARK: - Events

    func recordChunkCompleted() {
        chunkCount += 1
    }

    func recordTranscriptionSuccess() {
        successCount += 1
    }

    func recordTranscriptionFailure() {
        failCount += 1
    }

    func updateLastFileModification(_ date: Date) {
        lastKnownFileModification = date
    }

    // MARK: - Health Check

    private func performHealthCheck() {
        let snapshot = HealthSnapshot(
            timestamp: Date(),
            totalChunks: chunkCount,
            successfulTranscriptions: successCount,
            failedTranscriptions: failCount,
            diskFreeGB: diskFreeSpaceGB(),
            sessionDurationHours: sessionDurationHours(),
            estimatedBatteryHoursRemaining: nil
        )

        latestSnapshot = snapshot

        var newWarnings: [String] = []

        if snapshot.isDiskSpaceCritical {
            newWarnings.append("Disk space critically low (\(String(format: "%.1f", snapshot.diskFreeGB)) GB)")
            logger.critical("Disk space critical: \(snapshot.diskFreeGB) GB")
        } else if snapshot.isDiskSpaceLow {
            newWarnings.append("Disk space low (\(String(format: "%.1f", snapshot.diskFreeGB)) GB)")
            logger.warning("Disk space low: \(snapshot.diskFreeGB) GB")
        }

        if snapshot.transcriptionSuccessRate < 0.5 && (successCount + failCount) > 5 {
            newWarnings.append("Transcription failure rate is high (\(Int((1 - snapshot.transcriptionSuccessRate) * 100))%)")
        }

        if snapshot.sessionDurationHours > 24 {
            newWarnings.append("Recording session exceeds 24 hours")
        }

        if let lastMod = lastKnownFileModification {
            let staleDuration = Date().timeIntervalSince(lastMod)
            if staleDuration > 120 { // 2 minutes without file activity
                newWarnings.append("Recording may have stalled (no file activity for \(Int(staleDuration))s)")
                logger.warning("File write stall detected: \(staleDuration)s since last write")
            }
        }

        warnings = newWarnings
        isHealthy = newWarnings.isEmpty
    }

    // MARK: - Helpers

    private func diskFreeSpaceGB() -> Double {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let freeSize = attrs[.systemFreeSize] as? NSNumber else { return 0 }
        return freeSize.doubleValue / (1024 * 1024 * 1024)
    }

    private func sessionDurationHours() -> Double {
        guard let start = sessionStartDate else { return 0 }
        return Date().timeIntervalSince(start) / 3600
    }
}
