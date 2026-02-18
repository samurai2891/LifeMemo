import Foundation
import CoreData

@objc(TranscriptSegmentEntity)
public class TranscriptSegmentEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var startMs: Int64
    @NSManaged public var endMs: Int64
    @NSManaged public var text: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var isUserEdited: Bool
    @NSManaged public var originalText: String?
    @NSManaged public var speakerIndex: Int16  // -1 = undiarized (legacy), 0+ = speaker
    @NSManaged public var session: SessionEntity?
    @NSManaged public var chunk: ChunkEntity?
    @NSManaged public var editHistory: NSSet?
}

extension TranscriptSegmentEntity {

    /// Edit history entries sorted by editIndex ascending.
    var editHistoryArray: [EditHistoryEntity] {
        let set = editHistory as? Set<EditHistoryEntity> ?? []
        return set.sorted { $0.editIndex < $1.editIndex }
    }
}
