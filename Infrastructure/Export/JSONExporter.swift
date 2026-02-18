import Foundation

/// Exports session data as a structured JSON document.
enum JSONExporter {

    struct ExportEnvelope: Codable {
        let version: Int
        let exportedAt: String
        let session: SessionExport
    }

    struct SessionExport: Codable {
        let title: String
        let startedAt: String
        let endedAt: String?
        let languageMode: String
        let audioKept: Bool
        let summary: String?
        let bodyText: String?
        let tags: [String]
        let folderName: String?
        let locationName: String?
        let transcript: String
        let highlights: [HighlightExport]
    }

    struct HighlightExport: Codable {
        let atMs: Int64
        let label: String?
    }

    static func make(model: ExportModel, options: ExportOptions) -> String {
        let dateFormatter = ISO8601DateFormatter()

        let highlights = options.includeHighlights
            ? model.highlights.map { HighlightExport(atMs: $0.atMs, label: $0.label) }
            : []

        let session = SessionExport(
            title: model.title,
            startedAt: dateFormatter.string(from: model.startedAt),
            endedAt: model.endedAt.map { dateFormatter.string(from: $0) },
            languageMode: model.languageMode,
            audioKept: model.audioKept,
            summary: options.includeSummary ? model.summaryMarkdown : nil,
            bodyText: model.bodyText,
            tags: model.tags,
            folderName: model.folderName,
            locationName: model.locationName,
            transcript: options.includeTranscript ? model.fullTranscript : "",
            highlights: highlights
        )

        let envelope = ExportEnvelope(
            version: 1,
            exportedAt: dateFormatter.string(from: Date()),
            session: session
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(envelope),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return json
    }
}
