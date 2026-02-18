import Foundation

/// Lightweight value type representing a tag.
struct TagInfo: Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let colorHex: String?
}
