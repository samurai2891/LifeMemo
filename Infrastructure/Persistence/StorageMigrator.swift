import Foundation
import os.log

/// One-time migration from Documents/AppData/ to Library/Application Support/LifeMemo/
enum StorageMigrator {

    private static let migrationKey = "v1_storageMigrationComplete"
    private static let logger = Logger(subsystem: "com.lifememo.app", category: "Migration")

    static func migrateIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let fm = FileManager.default

        // Source: Documents/AppData/
        guard let documentsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let sourceDir = documentsURL.appendingPathComponent("AppData", isDirectory: true)

        // If source doesn't exist, this is a fresh install - just mark complete
        guard fm.fileExists(atPath: sourceDir.path) else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            logger.info("No legacy data found, marking migration complete")
            return
        }

        // Destination: Library/Application Support/LifeMemo/
        guard let appSupportURL = fm.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }
        let destDir = appSupportURL.appendingPathComponent("LifeMemo", isDirectory: true)

        do {
            // Create destination if needed
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

            // Move subdirectories: Audio, FTS, Export, Backup
            let subdirs = ["Audio", "FTS", "Export", "Backup"]
            for subdir in subdirs {
                let src = sourceDir.appendingPathComponent(subdir, isDirectory: true)
                let dst = destDir.appendingPathComponent(subdir, isDirectory: true)
                guard fm.fileExists(atPath: src.path) else { continue }
                if fm.fileExists(atPath: dst.path) {
                    // Merge: enumerate and move individual items
                    try mergeDirectory(from: src, to: dst, fileManager: fm)
                } else {
                    try fm.moveItem(at: src, to: dst)
                }
            }

            // Move CoreData store files to CoreData subdirectory
            let coreDataDir = destDir.appendingPathComponent("CoreData", isDirectory: true)
            try fm.createDirectory(at: coreDataDir, withIntermediateDirectories: true)

            // Legacy store was at Documents/LifeMemo.sqlite (parent of AppData)
            let legacyStore = documentsURL.appendingPathComponent("LifeMemo.sqlite")
            let newStore = coreDataDir.appendingPathComponent("LifeMemo.sqlite")
            if fm.fileExists(atPath: legacyStore.path) && !fm.fileExists(atPath: newStore.path) {
                try fm.moveItem(at: legacyStore, to: newStore)
                // Also move WAL and SHM
                for suffix in ["-wal", "-shm"] {
                    let src = URL(fileURLWithPath: legacyStore.path + suffix)
                    let dst = URL(fileURLWithPath: newStore.path + suffix)
                    if fm.fileExists(atPath: src.path) && !fm.fileExists(atPath: dst.path) {
                        try fm.moveItem(at: src, to: dst)
                    }
                }
            }

            // Create remaining directories
            let additionalDirs = ["Exports", "Backups"]
            for dir in additionalDirs {
                let url = destDir.appendingPathComponent(dir, isDirectory: true)
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            }

            // Exclude all from iCloud backup
            excludeFromBackup(url: destDir)

            // Only mark complete after all moves succeed
            UserDefaults.standard.set(true, forKey: migrationKey)
            logger.info("Storage migration completed successfully")

            // Clean up empty source directory
            try? fm.removeItem(at: sourceDir)

        } catch {
            logger.error("Storage migration failed: \(error.localizedDescription)")
            // Do NOT mark complete - will retry next launch
        }
    }

    // MARK: - Private Helpers

    private static func mergeDirectory(
        from src: URL,
        to dst: URL,
        fileManager fm: FileManager
    ) throws {
        guard let items = try? fm.contentsOfDirectory(
            at: src,
            includingPropertiesForKeys: nil
        ) else { return }

        for item in items {
            let target = dst.appendingPathComponent(item.lastPathComponent)
            if !fm.fileExists(atPath: target.path) {
                try fm.moveItem(at: item, to: target)
            }
        }
    }

    private static func excludeFromBackup(url: URL) {
        var mutableURL = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? mutableURL.setResourceValues(resourceValues)

        // Also exclude subdirectories
        let fm = FileManager.default
        if let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            for case let fileURL as URL in enumerator {
                let isDir = (try? fileURL.resourceValues(
                    forKeys: [.isDirectoryKey]
                ).isDirectory) ?? false
                if isDir {
                    var dirURL = fileURL
                    var values = URLResourceValues()
                    values.isExcludedFromBackup = true
                    try? dirURL.setResourceValues(values)
                }
            }
        }
    }
}
