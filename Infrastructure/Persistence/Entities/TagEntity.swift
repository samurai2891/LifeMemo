import Foundation
import CoreData

@objc(TagEntity)
public class TagEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var colorHex: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var sessions: NSSet?
}

extension TagEntity {
    var sessionsArray: [SessionEntity] {
        let set = sessions as? Set<SessionEntity> ?? []
        return set.sorted { ($0.createdAt ?? Date.distantPast) > ($1.createdAt ?? Date.distantPast) }
    }

    func toInfo() -> TagInfo {
        TagInfo(
            id: id ?? UUID(),
            name: name ?? "",
            colorHex: colorHex
        )
    }
}
