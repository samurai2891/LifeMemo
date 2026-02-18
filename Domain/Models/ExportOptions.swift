import Foundation

/// Options controlling what content is included in an export.
struct ExportOptions: Equatable {

    var includeMetadata: Bool = true
    var includeSummary: Bool = true
    var includeKeywords: Bool = true
    var includeHighlights: Bool = true
    var includeTranscript: Bool = true
    var includeTimestamps: Bool = false

    enum ExportFormat: String, CaseIterable, Identifiable {
        case markdown = "Markdown"
        case text = "Text"
        case pdf = "PDF"
        case json = "JSON"

        var id: String { rawValue }

        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .text: return "txt"
            case .pdf: return "pdf"
            case .json: return "json"
            }
        }

        var icon: String {
            switch self {
            case .markdown: return "doc.text"
            case .text: return "doc.plaintext"
            case .pdf: return "doc.richtext"
            case .json: return "curlybraces"
            }
        }
    }

    var format: ExportFormat = .markdown

    static let full = ExportOptions()

    static let minimal = ExportOptions(
        includeMetadata: true,
        includeSummary: false,
        includeKeywords: false,
        includeHighlights: false,
        includeTranscript: true,
        includeTimestamps: false,
        format: .text
    )
}
