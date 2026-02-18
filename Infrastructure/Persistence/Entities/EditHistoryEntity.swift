import Foundation
import CoreData

@objc(EditHistoryEntity)
public class EditHistoryEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var previousText: String?
    @NSManaged public var newText: String?
    @NSManaged public var editedAt: Date?
    @NSManaged public var editIndex: Int16
    @NSManaged public var segment: TranscriptSegmentEntity?
}

extension EditHistoryEntity {

    func toEntry(segmentId: UUID) -> EditHistoryEntry {
        EditHistoryEntry(
            id: id ?? UUID(),
            segmentId: segmentId,
            previousText: previousText ?? "",
            newText: newText ?? "",
            editedAt: editedAt ?? Date(),
            editIndex: Int(editIndex)
        )
    }
}
