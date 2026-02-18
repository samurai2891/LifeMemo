import Foundation
import OSLog
import os.log

/// Exports recent app logs for support/debugging purposes.
///
/// Reads from OSLogStore for the current process, filtering to the last 24 hours.
/// Output includes timestamps, log levels, and categories but explicitly excludes
/// any memo content, transcripts, or audio data.
@MainActor
final class AppLogExporter {

    private let logger = Logger(subsystem: "com.lifememo.app", category: "LogExport")

    /// Exports the last 24 hours of app logs as a text file.
    ///
    /// - Returns: URL of the temporary log file, suitable for sharing via UIActivityViewController.
    func exportLogs() throws -> URL {
        let store = try OSLogStore(scope: .currentProcessIdentifier)

        let startDate = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
        let position = store.position(date: startDate)

        let entries = try store.getEntries(at: position)

        var lines: [String] = []
        lines.append("LifeMemo Diagnostic Logs")
        lines.append("Exported: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Device: \(deviceInfo())")
        lines.append("App Version: \(appVersion())")
        lines.append(String(repeating: "-", count: 60))
        lines.append("")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        for entry in entries {
            guard let logEntry = entry as? OSLogEntryLog else { continue }

            // Only include our app's logs
            guard logEntry.subsystem == "com.lifememo.app" else { continue }

            let timestamp = dateFormatter.string(from: logEntry.date)
            let level = levelString(logEntry.level)
            let category = logEntry.category
            let message = logEntry.composedMessage

            lines.append("[\(timestamp)] [\(level)] [\(category)] \(message)")
        }

        let content = lines.joined(separator: "\n")

        // Write to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "LifeMemo_Logs_\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")).txt"
        let fileURL = tempDir.appendingPathComponent(fileName)

        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        logger.info("Logs exported: \(lines.count) entries")
        return fileURL
    }

    // MARK: - Helpers

    private func levelString(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        @unknown default: return "UNKNOWN"
        }
    }

    private func deviceInfo() -> String {
        let device = ProcessInfo.processInfo
        return "\(device.operatingSystemVersionString)"
    }

    private func appVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
