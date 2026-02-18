import Foundation

struct SessionSummary: Identifiable {
    let id: UUID
    let title: String
    let createdAt: Date
    let startedAt: Date
    let endedAt: Date?
    let status: SessionStatus
    let audioKept: Bool
    let languageMode: String
    let summary: String?
    let chunkCount: Int
    let transcriptPreview: String?
    let bodyText: String?
    let tags: [TagInfo]
    let folderName: String?
    let placeName: String?
}
