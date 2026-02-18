import Foundation

/// Lightweight value type representing a folder.
struct FolderInfo: Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let sortOrder: Int
}
