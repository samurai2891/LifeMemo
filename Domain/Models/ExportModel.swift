import Foundation

/// A speaker-attributed segment for export purposes.
///
/// Represents a contiguous run of text from a single speaker with
/// timing information, used by all export formats.
struct ExportSegment {
    let speakerIndex: Int
    let speakerName: String?
    let text: String
    let startMs: Int64
    let endMs: Int64
}

struct ExportModel {
    let title: String
    let startedAt: Date
    let endedAt: Date?
    let languageMode: String
    let audioKept: Bool
    let summaryMarkdown: String?
    let fullTranscript: String
    let highlights: [HighlightInfo]
    let bodyText: String?
    let tags: [String]
    let folderName: String?
    let locationName: String?
    let speakerSegments: [ExportSegment]

    /// Backward-compatible initializer without speakerSegments.
    init(
        title: String,
        startedAt: Date,
        endedAt: Date?,
        languageMode: String,
        audioKept: Bool,
        summaryMarkdown: String?,
        fullTranscript: String,
        highlights: [HighlightInfo],
        bodyText: String?,
        tags: [String],
        folderName: String?,
        locationName: String?
    ) {
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.languageMode = languageMode
        self.audioKept = audioKept
        self.summaryMarkdown = summaryMarkdown
        self.fullTranscript = fullTranscript
        self.highlights = highlights
        self.bodyText = bodyText
        self.tags = tags
        self.folderName = folderName
        self.locationName = locationName
        self.speakerSegments = []
    }

    /// Full initializer with speaker segments.
    init(
        title: String,
        startedAt: Date,
        endedAt: Date?,
        languageMode: String,
        audioKept: Bool,
        summaryMarkdown: String?,
        fullTranscript: String,
        highlights: [HighlightInfo],
        bodyText: String?,
        tags: [String],
        folderName: String?,
        locationName: String?,
        speakerSegments: [ExportSegment]
    ) {
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.languageMode = languageMode
        self.audioKept = audioKept
        self.summaryMarkdown = summaryMarkdown
        self.fullTranscript = fullTranscript
        self.highlights = highlights
        self.bodyText = bodyText
        self.tags = tags
        self.folderName = folderName
        self.locationName = locationName
        self.speakerSegments = speakerSegments
    }

    var safeFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        let dateStr = formatter.string(from: startedAt)
        let safe = title
            .replacingOccurrences(of: "[^a-zA-Z0-9_\\-]", with: "_", options: .regularExpression)
            .prefix(50)
        return "\(dateStr)_\(safe)"
    }

    /// Whether meaningful speaker diarization data is available for export.
    var hasSpeakerSegments: Bool {
        !speakerSegments.isEmpty && speakerSegments.contains { $0.speakerIndex >= 0 }
    }
}
