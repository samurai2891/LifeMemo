import Foundation
import CoreData

@objc(ChunkEntity)
public class ChunkEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var index: Int32
    @NSManaged public var startAt: Date?
    @NSManaged public var endAt: Date?
    @NSManaged public var relativePath: String?
    @NSManaged public var durationSec: Double
    @NSManaged public var sizeBytes: Int64
    @NSManaged public var transcriptionStatusRaw: Int16
    @NSManaged public var audioDeleted: Bool
    @NSManaged public var session: SessionEntity?
    @NSManaged public var segments: NSSet?
}

extension ChunkEntity {

    var transcriptionStatus: TranscriptionStatus {
        get { TranscriptionStatus(rawValue: transcriptionStatusRaw) ?? .pending }
        set { transcriptionStatusRaw = newValue.rawValue }
    }
}
