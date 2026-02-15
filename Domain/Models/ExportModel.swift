import Foundation

struct ExportModel {
    let title: String
    let startedAt: Date
    let endedAt: Date?
    let languageMode: String
    let audioKept: Bool
    let summaryMarkdown: String?
    let fullTranscript: String
    let highlights: [HighlightInfo]

    var safeFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        let dateStr = formatter.string(from: startedAt)
        let safe = title
            .replacingOccurrences(of: "[^a-zA-Z0-9_\\-]", with: "_", options: .regularExpression)
            .prefix(50)
        return "\(dateStr)_\(safe)"
    }
}
