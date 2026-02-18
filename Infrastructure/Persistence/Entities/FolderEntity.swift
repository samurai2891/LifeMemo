import Foundation
import CoreData

@objc(FolderEntity)
public class FolderEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var sortOrder: Int32
    @NSManaged public var createdAt: Date?
    @NSManaged public var sessions: NSSet?
}

extension FolderEntity {
    var sessionsArray: [SessionEntity] {
        let set = sessions as? Set<SessionEntity> ?? []
        return set.sorted { ($0.createdAt ?? Date.distantPast) > ($1.createdAt ?? Date.distantPast) }
    }

    func toInfo() -> FolderInfo {
        FolderInfo(
            id: id ?? UUID(),
            name: name ?? "",
            sortOrder: Int(sortOrder)
        )
    }
}
