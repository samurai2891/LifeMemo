import Foundation
import CoreData
import CloudKit
import Combine
import os.log

/// Manages iCloud sync for Core Data using NSPersistentCloudKitContainer.
///
/// Provides sync status monitoring, conflict resolution, and manual sync triggers.
/// Audio files are NOT synced (too large) - only metadata and transcripts sync.
@MainActor
final class CloudSyncManager: ObservableObject {

    // MARK: - Types

    enum SyncState: Equatable {
        case disabled
        case idle
        case syncing
        case error(String)

        var displayText: String {
            switch self {
            case .disabled:
                return "Disabled"
            case .idle:
                return "Up to date"
            case .syncing:
                return "Syncing..."
            case .error(let message):
                return "Error: \(message)"
            }
        }

        var isError: Bool {
            if case .error = self { return true }
            return false
        }
    }

    // MARK: - Constants

    private static let syncEnabledKey = "iCloudSyncEnabled"
    private static let lastSyncDateKey = "lastCloudSyncDate"
    private static let cloudKitContainerID = "iCloud.com.lifememo.app"

    // MARK: - Published State

    @Published private(set) var syncState: SyncState = .disabled
    @Published private(set) var lastSyncDate: Date?
    @Published var isSyncEnabled: Bool {
        didSet {
            guard oldValue != isSyncEnabled else { return }
            UserDefaults.standard.set(isSyncEnabled, forKey: Self.syncEnabledKey)
            if isSyncEnabled {
                enableSync()
            } else {
                disableSync()
            }
        }
    }

    // MARK: - Private Properties

    private let logger = Logger(subsystem: "com.lifememo.app", category: "CloudSync")
    private var cancellables = Set<AnyCancellable>()
    private var eventObserver: NSObjectProtocol?

    // MARK: - Init

    init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.syncEnabledKey)
        self.isSyncEnabled = enabled

        if let savedDate = UserDefaults.standard.object(forKey: Self.lastSyncDateKey) as? Date {
            self.lastSyncDate = savedDate
        }

        if enabled {
            setupEventObserver()
            syncState = .idle
        }
    }

    deinit {
        if let observer = eventObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Sync Control

    private func enableSync() {
        syncState = .idle
        setupEventObserver()
        logger.info("iCloud sync enabled")
    }

    private func disableSync() {
        syncState = .disabled
        removeEventObserver()
        logger.info("iCloud sync disabled")
    }

    // MARK: - Event Observation

    private func setupEventObserver() {
        removeEventObserver()

        eventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else {
                return
            }

            Task { @MainActor in
                self?.handleSyncEvent(event)
            }
        }
    }

    private func removeEventObserver() {
        if let observer = eventObserver {
            NotificationCenter.default.removeObserver(observer)
            eventObserver = nil
        }
    }

    private func handleSyncEvent(_ event: NSPersistentCloudKitContainer.Event) {
        if event.endDate == nil {
            // Event is in progress
            syncState = .syncing
            logger.debug("Sync event started: \(event.type.rawValue)")
        } else if let error = event.error {
            let message = Self.userFriendlyErrorMessage(error)
            syncState = .error(message)
            logger.error("Sync error: \(error.localizedDescription)")
        } else {
            syncState = .idle
            let completedDate = event.endDate ?? Date()
            lastSyncDate = completedDate
            UserDefaults.standard.set(completedDate, forKey: Self.lastSyncDateKey)
            logger.info("Sync completed successfully")
        }
    }

    // MARK: - iCloud Availability

    func checkiCloudAvailability() async -> Bool {
        let container = CKContainer(identifier: Self.cloudKitContainerID)
        do {
            let status = try await container.accountStatus()
            let available = status == .available
            if !available {
                logger.warning("iCloud not available. Status: \(String(describing: status))")
            }
            return available
        } catch {
            logger.error("iCloud availability check failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Returns a user-readable description of the current iCloud account status.
    func iCloudStatusDescription() async -> String {
        let container = CKContainer(identifier: Self.cloudKitContainerID)
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                return "iCloud is available"
            case .noAccount:
                return "No iCloud account configured"
            case .restricted:
                return "iCloud access is restricted"
            case .couldNotDetermine:
                return "Could not determine iCloud status"
            case .temporarilyUnavailable:
                return "iCloud temporarily unavailable"
            @unknown default:
                return "Unknown iCloud status"
            }
        } catch {
            return "Unable to check iCloud: \(error.localizedDescription)"
        }
    }

    // MARK: - CloudKit Container Factory

    /// Creates a CloudKit-enabled persistent container.
    ///
    /// Call this instead of a regular NSPersistentContainer when sync is enabled.
    /// Audio files are excluded from sync due to their large size.
    static func createCloudContainer(
        modelName: String,
        model: NSManagedObjectModel
    ) -> NSPersistentCloudKitContainer {
        let container = NSPersistentCloudKitContainer(
            name: modelName,
            managedObjectModel: model
        )

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("No persistent store description found")
        }

        // Configure CloudKit sync
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: cloudKitContainerID
        )

        // Enable persistent history tracking (required for CloudKit sync)
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentHistoryTrackingKey
        )
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )

        return container
    }

    // MARK: - Formatting

    /// Formats the last sync date for display.
    var lastSyncDisplayText: String {
        guard let date = lastSyncDate else {
            return "Never"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Error Helpers

    private static func userFriendlyErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError

        switch nsError.code {
        case CKError.networkUnavailable.rawValue,
             CKError.networkFailure.rawValue:
            return "No network connection"
        case CKError.notAuthenticated.rawValue:
            return "Not signed in to iCloud"
        case CKError.quotaExceeded.rawValue:
            return "iCloud storage full"
        case CKError.serverResponseLost.rawValue:
            return "Connection to iCloud lost"
        default:
            // Truncate overly long error messages
            let message = error.localizedDescription
            if message.count > 100 {
                return String(message.prefix(97)) + "..."
            }
            return message
        }
    }
}
