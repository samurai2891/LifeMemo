import Foundation
import Combine

/// ViewModel for the StorageManagementView.
///
/// Wraps StorageManager to provide a unified interface
/// for storage visualization, cleanup operations, and backup management.
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

        var id: String {
            switch self {
            case .deleteAudioConfirmation: return "deleteAudio"
            case .deleteExportsConfirmation: return "deleteExports"
            case .deleteBackupConfirmation: return "deleteBackup"
            case .backupSuccess: return "backupSuccess"
            case .backupError: return "backupError"
            case .cleanupResult: return "cleanupResult"
            }
        }
    }

    // MARK: - Constants

    private static let storageLimitGBKey = "storageLimitGB"
    private static let autoDeleteEnabledKey = "autoDeleteEnabled"
    private static let defaultStorageLimitGB = 10

    // MARK: - Published State

    @Published var selectedCleanupPeriod: CleanupPeriod = .thirtyDays
    @Published var activeAlert: AlertType?
    @Published private(set) var isCreatingBackup = false

    @Published var storageLimitGB: Int {
        didSet {
            guard oldValue != storageLimitGB else { return }
            UserDefaults.standard.set(storageLimitGB, forKey: Self.storageLimitGBKey)
        }
    }

    @Published var autoDeleteEnabled: Bool {
        didSet {
            guard oldValue != autoDeleteEnabled else { return }
            UserDefaults.standard.set(autoDeleteEnabled, forKey: Self.autoDeleteEnabledKey)
        }
    }

    // MARK: - Dependencies

    let storageManager: StorageManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(storageManager: StorageManager) {
        self.storageManager = storageManager

        let savedLimit = UserDefaults.standard.integer(forKey: Self.storageLimitGBKey)
        self.storageLimitGB = savedLimit > 0 ? savedLimit : Self.defaultStorageLimitGB
        self.autoDeleteEnabled = UserDefaults.standard.bool(forKey: Self.autoDeleteEnabledKey)
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
