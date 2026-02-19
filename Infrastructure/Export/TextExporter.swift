import Foundation

enum TextExporter {

    static func make(model: ExportModel) -> String {
        var lines: [String] = []

        lines.append(model.title)
        lines.append(String(repeating: "=", count: model.title.count))
        lines.append("")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        lines.append("Started: \(formatter.string(from: model.startedAt))")
        if let ended = model.endedAt {
            lines.append("Ended: \(formatter.string(from: ended))")
        }
        lines.append("Language: \(model.languageMode)")
        lines.append("Audio: \(model.audioKept ? "kept" : "deleted")")
        lines.append("")

        if let summary = model.summaryMarkdown, !summary.isEmpty {
            let plain = summary
                .replacingOccurrences(of: "# ", with: "")
                .replacingOccurrences(of: "## ", with: "")
                .replacingOccurrences(of: "- ", with: "  * ")
            lines.append("--- Summary ---")
            lines.append(plain)
            lines.append("")
        }

        if !model.highlights.isEmpty {
            lines.append("--- Highlights ---")
            for h in model.highlights {
                let sec = h.atMs / 1000
                let min = sec / 60
                let remSec = sec % 60
                let label = h.label ?? ""
                lines.append("  [\(String(format: "%02d:%02d", min, remSec))] \(label)")
            }
            lines.append("")
        }

        lines.append("--- Transcript ---")

        if model.hasSpeakerSegments {
            for segment in model.speakerSegments {
                let name = segment.speakerName ?? "Speaker \(segment.speakerIndex + 1)"
                let timestamp = formatTimestamp(ms: segment.startMs)
                lines.append("[\(name)] [\(timestamp)] \(segment.text)")
            }
        } else {
            lines.append(model.fullTranscript)
        }

        return lines.joined(separator: "\n")
    }

    private static func formatTimestamp(ms: Int64) -> String {
        let sec = ms / 1000
        let min = sec / 60
        let remSec = sec % 60
        return String(format: "%02d:%02d", min, remSec)
    }
}
