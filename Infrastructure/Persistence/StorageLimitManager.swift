import Foundation
import os.log

/// Manages storage usage limits and auto-cleanup policies.
///
/// Monitors total app storage against a user-configured limit. When the limit
/// is exceeded, either warns the user or automatically removes old audio files
/// (preserving transcripts) depending on the auto-delete setting.
@MainActor
final class StorageLimitManager: ObservableObject {

    // MARK: - Constants

    private static let limitGBKey = "storageLimitGB"
    private static let autoDeleteKey = "storageAutoDelete"
    private static let defaultLimitGB: Double = 10.0

    // MARK: - Published State

    @Published var limitGB: Double {
        didSet { UserDefaults.standard.set(limitGB, forKey: Self.limitGBKey) }
    }
    @Published var autoDeleteEnabled: Bool {
        didSet { UserDefaults.standard.set(autoDeleteEnabled, forKey: Self.autoDeleteKey) }
    }
    @Published private(set) var currentUsageGB: Double = 0
    @Published private(set) var usagePercentage: Double = 0
    @Published private(set) var isWarning: Bool = false
    @Published private(set) var isExceeded: Bool = false

    // MARK: - Dependencies

    private let fileStore: FileStore
    private let repository: SessionRepository
    private let logger = Logger(subsystem: "com.lifememo.app", category: "StorageLimit")

    // MARK: - Init

    init(fileStore: FileStore, repository: SessionRepository) {
        self.fileStore = fileStore
        self.repository = repository
        self.limitGB = UserDefaults.standard.object(forKey: Self.limitGBKey) as? Double ?? Self.defaultLimitGB
        self.autoDeleteEnabled = UserDefaults.standard.bool(forKey: Self.autoDeleteKey)
    }

    // MARK: - Check & Enforce

    func checkAndEnforce() {
        calculateUsage()

        usagePercentage = limitGB > 0 ? (currentUsageGB / limitGB) * 100 : 0
        isWarning = usagePercentage >= 90
        isExceeded = usagePercentage >= 100

        if isExceeded && autoDeleteEnabled {
            performAutoCleanup()
        }

        if isWarning {
            logger.warning("Storage usage at \(self.usagePercentage, format: .fixed(precision: 1))% (\(self.currentUsageGB, format: .fixed(precision: 2)) GB / \(self.limitGB, format: .fixed(precision: 1)) GB)")
        }
    }

    /// Returns true if there is sufficient space to continue recording.
    func hasCapacity() -> Bool {
        calculateUsage()
        return currentUsageGB < limitGB
    }

    // MARK: - Private

    private func calculateUsage() {
        let audioBytes = fileStore.totalAudioSize()
        let totalBytes = audioBytes // Primarily audio, DB is relatively small
        currentUsageGB = Double(totalBytes) / (1024 * 1024 * 1024)
    }

    private func performAutoCleanup() {
        logger.info("Auto-cleanup triggered: usage \(self.currentUsageGB, format: .fixed(precision: 2)) GB exceeds limit \(self.limitGB, format: .fixed(precision: 1)) GB")

        // Get sessions sorted by date (oldest first)
        let sessions = repository.fetchAllSessions()
            .filter { $0.audioKept }
            .sorted { ($0.createdAt ?? Date.distantFuture) < ($1.createdAt ?? Date.distantFuture) }

        for session in sessions {
            guard currentUsageGB > limitGB * 0.85 else { break } // Clean to 85%

            let sessionId = session.id ?? UUID()
            repository.deleteAudioKeepTranscript(sessionId: sessionId)
            logger.debug("Auto-deleted audio for session: \(sessionId.uuidString)")

            // Recalculate
            calculateUsage()
        }

        // Update state
        usagePercentage = limitGB > 0 ? (currentUsageGB / limitGB) * 100 : 0
        isWarning = usagePercentage >= 90
        isExceeded = usagePercentage >= 100

        logger.info("Auto-cleanup complete: usage now \(self.currentUsageGB, format: .fixed(precision: 2)) GB")
    }
}
