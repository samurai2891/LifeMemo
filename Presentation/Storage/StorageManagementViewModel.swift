import Foundation
import Combine

/// ViewModel for the StorageManagementView.
///
/// Wraps StorageManager and CloudSyncManager to provide a unified interface
/// for storage visualization, cleanup operations, backup management,
/// and iCloud sync control.
@MainActor
final class StorageManagementViewModel: ObservableObject {

    // MARK: - Types

    enum CleanupPeriod: Int, CaseIterable, Identifiable {
        case sevenDays = 7
        case thirtyDays = 30
        case ninetyDays = 90
        case halfYear = 180

        var id: Int { rawValue }

        var displayText: String {
            switch self {
            case .sevenDays: return "7 days"
            case .thirtyDays: return "30 days"
            case .ninetyDays: return "90 days"
            case .halfYear: return "180 days"
            }
        }
    }

    enum AlertType: Identifiable {
        case deleteAudioConfirmation
        case deleteExportsConfirmation
        case deleteBackupConfirmation(URL)
        case backupSuccess(URL)
        case backupError(String)
        case cleanupResult(Int)
        case iCloudUnavailable(String)

        var id: String {
            switch self {
            case .deleteAudioConfirmation: return "deleteAudio"
            case .deleteExportsConfirmation: return "deleteExports"
            case .deleteBackupConfirmation: return "deleteBackup"
            case .backupSuccess: return "backupSuccess"
            case .backupError: return "backupError"
            case .cleanupResult: return "cleanupResult"
            case .iCloudUnavailable: return "iCloudUnavailable"
            }
        }
    }

    // MARK: - Published State

    @Published var selectedCleanupPeriod: CleanupPeriod = .thirtyDays
    @Published var activeAlert: AlertType?
    @Published private(set) var isCreatingBackup = false
    @Published private(set) var iCloudStatusText: String = ""

    // MARK: - Dependencies

    let storageManager: StorageManager
    let cloudSyncManager: CloudSyncManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(storageManager: StorageManager, cloudSyncManager: CloudSyncManager) {
        self.storageManager = storageManager
        self.cloudSyncManager = cloudSyncManager
    }

    // MARK: - Storage

    var breakdown: StorageManager.StorageBreakdown {
        storageManager.breakdown
    }

    var sessionStorageList: [StorageManager.SessionStorageInfo] {
        storageManager.sessionStorageList
    }

    var backups: [StorageManager.BackupInfo] {
        storageManager.backups
    }

    var isCalculating: Bool {
        storageManager.isCalculating
    }

    var deviceFreeSpaceGB: Double {
        storageManager.deviceFreeSpaceGB
    }

    func loadStorage() {
        storageManager.calculateStorage()
    }

    // MARK: - iCloud Sync

    var isSyncEnabled: Bool {
        get { cloudSyncManager.isSyncEnabled }
        set { cloudSyncManager.isSyncEnabled = newValue }
    }

    var syncState: CloudSyncManager.SyncState {
        cloudSyncManager.syncState
    }

    var lastSyncDisplayText: String {
        cloudSyncManager.lastSyncDisplayText
    }

    func toggleSync(enabled: Bool) {
        Task {
            if enabled {
                let available = await cloudSyncManager.checkiCloudAvailability()
                if available {
                    cloudSyncManager.isSyncEnabled = true
                } else {
                    let statusText = await cloudSyncManager.iCloudStatusDescription()
                    activeAlert = .iCloudUnavailable(statusText)
                }
            } else {
                cloudSyncManager.isSyncEnabled = false
            }
        }
    }

    func refreshiCloudStatus() {
        Task {
            iCloudStatusText = await cloudSyncManager.iCloudStatusDescription()
        }
    }

    // MARK: - Audio Cleanup

    func requestDeleteAudio() {
        activeAlert = .deleteAudioConfirmation
    }

    func confirmDeleteAudio() {
        let deletedCount = storageManager.deleteAudioOlderThan(
            days: selectedCleanupPeriod.rawValue
        )
        activeAlert = .cleanupResult(deletedCount)
    }

    // MARK: - Export Cleanup

    func requestDeleteExports() {
        activeAlert = .deleteExportsConfirmation
    }

    func confirmDeleteExports() {
        storageManager.deleteAllExports()
    }

    // MARK: - Backup

    func createBackup() {
        isCreatingBackup = true

        let result = storageManager.createBackup()
        switch result {
        case .success(let url):
            activeAlert = .backupSuccess(url)
        case .failure(let error):
            activeAlert = .backupError(error.localizedDescription)
        }

        isCreatingBackup = false
    }

    func requestDeleteBackup(at url: URL) {
        activeAlert = .deleteBackupConfirmation(url)
    }

    func confirmDeleteBackup(at url: URL) {
        storageManager.deleteBackup(at: url)
    }

    // MARK: - Formatting

    func formatBytes(_ bytes: Int64) -> String {
        StorageManager.formatBytes(bytes)
    }

    func formattedFreeSpace() -> String {
        String(format: "%.1f GB", deviceFreeSpaceGB)
    }
}
