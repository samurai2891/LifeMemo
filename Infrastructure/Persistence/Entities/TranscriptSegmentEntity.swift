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
    @NSManaged public var session: SessionEntity?
    @NSManaged public var chunk: ChunkEntity?
}
