import Foundation

final class FileStore {

    // MARK: - Directory Helpers

    func appDataDir() throws -> URL {
        let doc = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = doc.appendingPathComponent("AppData", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Audio File Paths

    func ensureAudioFileURL(relativePath: String) throws -> URL {
        let base = try appDataDir()
        let url = base.appendingPathComponent(relativePath)
        let parentDir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: parentDir.path
        )
        return url
    }

    func resolveAbsoluteURL(relativePath: String) -> URL? {
        guard let base = try? appDataDir() else { return nil }
        let url = base.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func makeChunkRelativePath(sessionId: UUID, index: Int, ext: String) -> String {
        let name = String(format: "%04d.%@", index, ext)
        return "Audio/\(sessionId.uuidString)/\(name)"
    }

    // MARK: - Deletion

    func deleteFile(relativePath: String) {
        guard let base = try? appDataDir() else { return }
        let url = base.appendingPathComponent(relativePath)
        try? FileManager.default.removeItem(at: url)
    }

    func deleteSessionAudioDir(sessionId: UUID) {
        guard let base = try? appDataDir() else { return }
        let dir = base.appendingPathComponent("Audio/\(sessionId.uuidString)", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Export

    func writeExport(text: String, ext: String, suggestedName: String) throws -> URL {
        let base = try appDataDir()
        let exportDir = base.appendingPathComponent("Export", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        let file = exportDir.appendingPathComponent("\(suggestedName).\(ext)")
        try text.data(using: .utf8)?.write(to: file, options: [.atomic])
        return file
    }

    // MARK: - Size Calculation

    func totalAudioSize() -> Int64 {
        guard let base = try? appDataDir() else { return 0 }
        let audioDir = base.appendingPathComponent("Audio", isDirectory: true)
        return directorySize(url: audioDir)
    }

    private func directorySize(url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
