import Foundation

/// Enhanced export service supporting multiple formats with configurable options.
///
/// Extends the original ExportService with PDF support and content selection.
/// Each export call produces an immutable output file at a new URL.
@MainActor
final class EnhancedExportService {

    // MARK: - Dependencies

    private let repository: SessionRepository
    private let fileStore: FileStore

    // MARK: - Init

    init(repository: SessionRepository, fileStore: FileStore) {
        self.repository = repository
        self.fileStore = fileStore
    }

    // MARK: - Export

    func export(sessionId: UUID, options: ExportOptions) throws -> URL {
        let model = repository.getSessionExportModel(sessionId: sessionId)

        switch options.format {
        case .markdown:
            let text = FilteredMarkdownExporter.make(model: model, options: options)
            return try fileStore.writeExport(
                text: text,
                ext: "md",
                suggestedName: model.safeFileName
            )

        case .text:
            let text = FilteredTextExporter.make(model: model, options: options)
            return try fileStore.writeExport(
                text: text,
                ext: "txt",
                suggestedName: model.safeFileName
            )

        case .pdf:
            let data = PDFExporter.make(model: model, options: options)
            return try writePDFExport(data: data, suggestedName: model.safeFileName)
        }
    }

    // MARK: - Private

    private func writePDFExport(data: Data, suggestedName: String) throws -> URL {
        let base = try fileStore.appDataDir()
        let exportDir = base.appendingPathComponent("Export", isDirectory: true)
        try FileManager.default.createDirectory(
            at: exportDir,
            withIntermediateDirectories: true
        )
        let file = exportDir.appendingPathComponent("\(suggestedName).pdf")
        try data.write(to: file, options: [.atomic])
        return file
    }
}

// MARK: - Filtered Markdown Exporter

/// Markdown exporter that respects export options for selective content inclusion.
enum FilteredMarkdownExporter {

    static func make(model: ExportModel, options: ExportOptions) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        var md = "# \(model.title)\n\n"

        if options.includeMetadata {
            md += "- **Started**: \(formatter.string(from: model.startedAt))\n"
            if let ended = model.endedAt {
                md += "- **Ended**: \(formatter.string(from: ended))\n"
            }
            md += "- **Language**: \(model.languageMode)\n"
            md += "- **Audio**: \(model.audioKept ? "kept" : "deleted")\n\n"
        }

        if options.includeSummary, let summary = model.summaryMarkdown, !summary.isEmpty {
            md += summary + "\n\n"
        }

        if options.includeHighlights, !model.highlights.isEmpty {
            md += "## Highlights\n\n"
            for h in model.highlights {
                let label = h.label.map { " - \($0)" } ?? ""
                md += "- `\(formatTimestamp(ms: h.atMs))`\(label)\n"
            }
            md += "\n"
        }

        if options.includeTranscript, !model.fullTranscript.isEmpty {
            md += "## Transcript\n\n"
            md += model.fullTranscript + "\n"
        }

        return md
    }

    private static func formatTimestamp(ms: Int64) -> String {
        let sec = ms / 1000
        let min = sec / 60
        let remSec = sec % 60
        return String(format: "%02d:%02d", min, remSec)
    }
}

// MARK: - Filtered Text Exporter

/// Text exporter that respects export options for selective content inclusion.
enum FilteredTextExporter {

    static func make(model: ExportModel, options: ExportOptions) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        var lines: [String] = []
        lines.append(model.title)
        lines.append(String(repeating: "=", count: model.title.count))
        lines.append("")

        if options.includeMetadata {
            lines.append("Started: \(formatter.string(from: model.startedAt))")
            if let ended = model.endedAt {
                lines.append("Ended: \(formatter.string(from: ended))")
            }
            lines.append("Language: \(model.languageMode)")
            lines.append("Audio: \(model.audioKept ? "kept" : "deleted")")
            lines.append("")
        }

        if options.includeSummary, let summary = model.summaryMarkdown, !summary.isEmpty {
            lines.append("--- Summary ---")
            let plain = stripMarkdown(summary)
            lines.append(plain)
            lines.append("")
        }

        if options.includeHighlights, !model.highlights.isEmpty {
            lines.append("--- Highlights ---")
            for h in model.highlights {
                let label = h.label ?? ""
                lines.append("  [\(formatTimestamp(ms: h.atMs))] \(label)")
            }
            lines.append("")
        }

        if options.includeTranscript, !model.fullTranscript.isEmpty {
            lines.append("--- Transcript ---")
            lines.append(model.fullTranscript)
        }

        return lines.joined(separator: "\n")
    }

    private static func stripMarkdown(_ text: String) -> String {
        text
            .replacingOccurrences(of: "# ", with: "")
            .replacingOccurrences(of: "## ", with: "")
            .replacingOccurrences(of: "- ", with: "  * ")
    }

    private static func formatTimestamp(ms: Int64) -> String {
        let sec = ms / 1000
        let min = sec / 60
        let remSec = sec % 60
        return String(format: "%02d:%02d", min, remSec)
    }
}
