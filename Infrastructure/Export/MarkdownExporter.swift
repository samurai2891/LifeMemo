import Foundation

enum MarkdownExporter {

    static func make(model: ExportModel) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        var md = "# \(model.title)\n\n"
        md += "- **Started**: \(formatter.string(from: model.startedAt))\n"
        if let ended = model.endedAt {
            md += "- **Ended**: \(formatter.string(from: ended))\n"
        }
        md += "- **Language**: \(model.languageMode)\n"
        md += "- **Audio**: \(model.audioKept ? "kept" : "deleted")\n\n"

        if let summary = model.summaryMarkdown, !summary.isEmpty {
            md += summary
            md += "\n\n"
        }

        if !model.highlights.isEmpty {
            md += "## Highlights\n\n"
            for h in model.highlights {
                let sec = h.atMs / 1000
                let min = sec / 60
                let remSec = sec % 60
                let label = h.label.map { " - \($0)" } ?? ""
                md += "- `\(String(format: "%02d:%02d", min, remSec))`\(label)\n"
            }
            md += "\n"
        }

        md += "## Transcript\n\n"

        if model.hasSpeakerSegments {
            for segment in model.speakerSegments {
                let name = segment.speakerName ?? "Speaker \(segment.speakerIndex + 1)"
                let timestamp = formatTimestamp(ms: segment.startMs)
                md += "**\(name)** [\(timestamp)]: \(segment.text)\n\n"
            }
        } else {
            md += model.fullTranscript
            md += "\n"
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
