import Foundation
import CoreData

final class CoreDataStack {

    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    init(modelName: String) {
        let model = Self.createManagedObjectModel()
        container = NSPersistentContainer(name: modelName, managedObjectModel: model)
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data failed to load: \(error.localizedDescription)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Programmatic Model

    static func createManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let sessionEntity = makeSessionEntity()
        let chunkEntity = makeChunkEntity()
        let segmentEntity = makeSegmentEntity()
        let highlightEntity = makeHighlightEntity()

        configureRelationships(
            session: sessionEntity,
            chunk: chunkEntity,
            segment: segmentEntity,
            highlight: highlightEntity
        )

        model.entities = [sessionEntity, chunkEntity, segmentEntity, highlightEntity]
        return model
    }

    func saveContext() {
        let context = viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("CoreData save error: \(error.localizedDescription)")
        }
    }

    // MARK: - Entity Builders

    private static func makeSessionEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "SessionEntity"
        entity.managedObjectClassName = "SessionEntity"

        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .UUIDAttributeType

        let createdAt = NSAttributeDescription()
        createdAt.name = "createdAt"
        createdAt.attributeType = .dateAttributeType

        let startedAt = NSAttributeDescription()
        startedAt.name = "startedAt"
        startedAt.attributeType = .dateAttributeType

        let endedAt = NSAttributeDescription()
        endedAt.name = "endedAt"
        endedAt.attributeType = .dateAttributeType
        endedAt.isOptional = true

        let title = NSAttributeDescription()
        title.name = "title"
        title.attributeType = .stringAttributeType
        title.defaultValue = ""

        let languageModeRaw = NSAttributeDescription()
        languageModeRaw.name = "languageModeRaw"
        languageModeRaw.attributeType = .stringAttributeType
        languageModeRaw.defaultValue = "auto"

        let statusRaw = NSAttributeDescription()
        statusRaw.name = "statusRaw"
        statusRaw.attributeType = .integer16AttributeType
        statusRaw.defaultValue = Int16(0)

        let audioKept = NSAttributeDescription()
        audioKept.name = "audioKept"
        audioKept.attributeType = .booleanAttributeType
        audioKept.defaultValue = true

        let summary = NSAttributeDescription()
        summary.name = "summary"
        summary.attributeType = .stringAttributeType
        summary.isOptional = true

        entity.properties = [
            id, createdAt, startedAt, endedAt,
            title, languageModeRaw, statusRaw,
            audioKept, summary
        ]
        return entity
    }

    private static func makeChunkEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "ChunkEntity"
        entity.managedObjectClassName = "ChunkEntity"

        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .UUIDAttributeType

        let index = NSAttributeDescription()
        index.name = "index"
        index.attributeType = .integer32AttributeType
        index.defaultValue = Int32(0)

        let startAt = NSAttributeDescription()
        startAt.name = "startAt"
        startAt.attributeType = .dateAttributeType

        let endAt = NSAttributeDescription()
        endAt.name = "endAt"
        endAt.attributeType = .dateAttributeType
        endAt.isOptional = true

        let relativePath = NSAttributeDescription()
        relativePath.name = "relativePath"
        relativePath.attributeType = .stringAttributeType
        relativePath.isOptional = true

        let durationSec = NSAttributeDescription()
        durationSec.name = "durationSec"
        durationSec.attributeType = .doubleAttributeType
        durationSec.defaultValue = Double(0)

        let sizeBytes = NSAttributeDescription()
        sizeBytes.name = "sizeBytes"
        sizeBytes.attributeType = .integer64AttributeType
        sizeBytes.defaultValue = Int64(0)

        let transcriptionStatusRaw = NSAttributeDescription()
        transcriptionStatusRaw.name = "transcriptionStatusRaw"
        transcriptionStatusRaw.attributeType = .integer16AttributeType
        transcriptionStatusRaw.defaultValue = Int16(0)

        let audioDeleted = NSAttributeDescription()
        audioDeleted.name = "audioDeleted"
        audioDeleted.attributeType = .booleanAttributeType
        audioDeleted.defaultValue = false

        entity.properties = [
            id, index, startAt, endAt,
            relativePath, durationSec, sizeBytes,
            transcriptionStatusRaw, audioDeleted
        ]
        return entity
    }

    private static func makeSegmentEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "TranscriptSegmentEntity"
        entity.managedObjectClassName = "TranscriptSegmentEntity"

        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .UUIDAttributeType

        let startMs = NSAttributeDescription()
        startMs.name = "startMs"
        startMs.attributeType = .integer64AttributeType
        startMs.defaultValue = Int64(0)

        let endMs = NSAttributeDescription()
        endMs.name = "endMs"
        endMs.attributeType = .integer64AttributeType
        endMs.defaultValue = Int64(0)

        let text = NSAttributeDescription()
        text.name = "text"
        text.attributeType = .stringAttributeType
        text.defaultValue = ""

        let createdAt = NSAttributeDescription()
        createdAt.name = "createdAt"
        createdAt.attributeType = .dateAttributeType

        entity.properties = [id, startMs, endMs, text, createdAt]
        return entity
    }

    private static func makeHighlightEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "HighlightEntity"
        entity.managedObjectClassName = "HighlightEntity"

        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .UUIDAttributeType

        let atMs = NSAttributeDescription()
        atMs.name = "atMs"
        atMs.attributeType = .integer64AttributeType
        atMs.defaultValue = Int64(0)

        let label = NSAttributeDescription()
        label.name = "label"
        label.attributeType = .stringAttributeType
        label.isOptional = true

        let createdAt = NSAttributeDescription()
        createdAt.name = "createdAt"
        createdAt.attributeType = .dateAttributeType

        entity.properties = [id, atMs, label, createdAt]
        return entity
    }

    // MARK: - Relationships

    private static func configureRelationships(
        session: NSEntityDescription,
        chunk: NSEntityDescription,
        segment: NSEntityDescription,
        highlight: NSEntityDescription
    ) {
        // Session <-> Chunks (one-to-many, cascade)
        let sessionToChunks = NSRelationshipDescription()
        sessionToChunks.name = "chunks"
        sessionToChunks.destinationEntity = chunk
        sessionToChunks.deleteRule = .cascadeDeleteRule
        sessionToChunks.isOptional = true

        let chunkToSession = NSRelationshipDescription()
        chunkToSession.name = "session"
        chunkToSession.destinationEntity = session
        chunkToSession.deleteRule = .nullifyDeleteRule
        chunkToSession.maxCount = 1

        sessionToChunks.inverseRelationship = chunkToSession
        chunkToSession.inverseRelationship = sessionToChunks

        // Session <-> Segments (one-to-many, cascade)
        let sessionToSegments = NSRelationshipDescription()
        sessionToSegments.name = "segments"
        sessionToSegments.destinationEntity = segment
        sessionToSegments.deleteRule = .cascadeDeleteRule
        sessionToSegments.isOptional = true

        let segmentToSession = NSRelationshipDescription()
        segmentToSession.name = "session"
        segmentToSession.destinationEntity = session
        segmentToSession.deleteRule = .nullifyDeleteRule
        segmentToSession.maxCount = 1

        sessionToSegments.inverseRelationship = segmentToSession
        segmentToSession.inverseRelationship = sessionToSegments

        // Chunk <-> Segments (one-to-many, cascade)
        let chunkToSegments = NSRelationshipDescription()
        chunkToSegments.name = "segments"
        chunkToSegments.destinationEntity = segment
        chunkToSegments.deleteRule = .cascadeDeleteRule
        chunkToSegments.isOptional = true

        let segmentToChunk = NSRelationshipDescription()
        segmentToChunk.name = "chunk"
        segmentToChunk.destinationEntity = chunk
        segmentToChunk.deleteRule = .nullifyDeleteRule
        segmentToChunk.maxCount = 1
        segmentToChunk.isOptional = true

        chunkToSegments.inverseRelationship = segmentToChunk
        segmentToChunk.inverseRelationship = chunkToSegments

        // Session <-> Highlights (one-to-many, cascade)
        let sessionToHighlights = NSRelationshipDescription()
        sessionToHighlights.name = "highlights"
        sessionToHighlights.destinationEntity = highlight
        sessionToHighlights.deleteRule = .cascadeDeleteRule
        sessionToHighlights.isOptional = true

        let highlightToSession = NSRelationshipDescription()
        highlightToSession.name = "session"
        highlightToSession.destinationEntity = session
        highlightToSession.deleteRule = .nullifyDeleteRule
        highlightToSession.maxCount = 1

        sessionToHighlights.inverseRelationship = highlightToSession
        highlightToSession.inverseRelationship = sessionToHighlights

        // Append relationship properties to entities
        session.properties += [sessionToChunks, sessionToSegments, sessionToHighlights]
        chunk.properties += [chunkToSession, chunkToSegments]
        segment.properties += [segmentToSession, segmentToChunk]
        highlight.properties += [highlightToSession]
    }
}
