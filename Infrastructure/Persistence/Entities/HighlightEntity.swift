import Foundation
import CoreData

@objc(HighlightEntity)
public class HighlightEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var atMs: Int64
    @NSManaged public var label: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var session: SessionEntity?
}

extension HighlightEntity {

    func toInfo() -> HighlightInfo {
        HighlightInfo(
            id: id ?? UUID(),
            atMs: atMs,
            label: label,
            createdAt: createdAt ?? Date()
        )
    }
}
