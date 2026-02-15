import Foundation

struct HighlightInfo: Identifiable {
    let id: UUID
    let atMs: Int64
    let label: String?
    let createdAt: Date
}
