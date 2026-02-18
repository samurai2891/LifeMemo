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

        // Custom store URL in Application Support
        if let description = container.persistentStoreDescriptions.first {
            let storeURL = Self.storeURL()
            description.url = storeURL
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }

        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Core Data failed to load: \(error.localizedDescription)")
            }
            // Set database file protection
            if let url = description.url {
                try? FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUnlessOpen],
                    ofItemAtPath: url.path
                )
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    static func storeURL() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let coreDataDir = appSupport
            .appendingPathComponent("LifeMemo", isDirectory: true)
            .appendingPathComponent("CoreData", isDirectory: true)
        try? fm.createDirectory(at: coreDataDir, withIntermediateDirectories: true)
        return coreDataDir.appendingPathComponent("LifeMemo.sqlite")
    }

    // MARK: - Programmatic Model

    /// Cached model to prevent duplicate `NSManagedObjectModel` registrations
    /// which cause "Failed to find a unique match" errors in Core Data.
    private static let cachedModel: NSManagedObjectModel = {
        let model = NSManagedObjectModel()

        let sessionEntity = makeSessionEntity()
        let chunkEntity = makeChunkEntity()
        let segmentEntity = makeSegmentEntity()
        let highlightEntity = makeHighlightEntity()
        let tagEntity = makeTagEntity()
        let folderEntity = makeFolderEntity()
        let editHistoryEntity = makeEditHistoryEntity()

        configureRelationships(
            session: sessionEntity,
            chunk: chunkEntity,
            segment: segmentEntity,
            highlight: highlightEntity,
            tag: tagEntity,
            folder: folderEntity,
            editHistory: editHistoryEntity
        )

        model.entities = [
            sessionEntity, chunkEntity, segmentEntity,
            highlightEntity, tagEntity, folderEntity,
            editHistoryEntity
        ]
        return model
    }()

    static func createManagedObjectModel() -> NSManagedObjectModel {
        cachedModel
    }

    /// Creates a fresh (non-cached) model for test use.
    /// Avoids entity-class registration conflicts with the host app's model.
    static func createTestModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let sessionEntity = makeSessionEntity()
        let chunkEntity = makeChunkEntity()
        let segmentEntity = makeSegmentEntity()
        let highlightEntity = makeHighlightEntity()
        let tagEntity = makeTagEntity()
        let folderEntity = makeFolderEntity()
        let editHistoryEntity = makeEditHistoryEntity()

        configureRelationships(
            session: sessionEntity,
            chunk: chunkEntity,
            segment: segmentEntity,
            highlight: highlightEntity,
            tag: tagEntity,
            folder: folderEntity,
            editHistory: editHistoryEntity
        )

        model.entities = [
            sessionEntity, chunkEntity, segmentEntity,
            highlightEntity, tagEntity, folderEntity,
            editHistoryEntity
        ]
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

        let bodyText = NSAttributeDescription()
        bodyText.name = "bodyText"
        bodyText.attributeType = .stringAttributeType
        bodyText.isOptional = true

        let latitude = NSAttributeDescription()
        latitude.name = "latitude"
        latitude.attributeType = .doubleAttributeType
        latitude.defaultValue = Double(0)

        let longitude = NSAttributeDescription()
        longitude.name = "longitude"
        longitude.attributeType = .doubleAttributeType
        longitude.defaultValue = Double(0)

        let placeName = NSAttributeDescription()
        placeName.name = "placeName"
        placeName.attributeType = .stringAttributeType
        placeName.isOptional = true

        entity.properties = [
            id, createdAt, startedAt, endedAt,
            title, languageModeRaw, statusRaw,
            audioKept, summary, bodyText,
            latitude, longitude, placeName
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

        let isUserEdited = NSAttributeDescription()
        isUserEdited.name = "isUserEdited"
        isUserEdited.attributeType = .booleanAttributeType
        isUserEdited.defaultValue = false

        let originalText = NSAttributeDescription()
        originalText.name = "originalText"
        originalText.attributeType = .stringAttributeType
        originalText.isOptional = true

        entity.properties = [id, startMs, endMs, text, createdAt, isUserEdited, originalText]
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

    private static func makeTagEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "TagEntity"
        entity.managedObjectClassName = "TagEntity"

        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .UUIDAttributeType

        let name = NSAttributeDescription()
        name.name = "name"
        name.attributeType = .stringAttributeType
        name.defaultValue = ""

        let colorHex = NSAttributeDescription()
        colorHex.name = "colorHex"
        colorHex.attributeType = .stringAttributeType
        colorHex.isOptional = true

        let createdAt = NSAttributeDescription()
        createdAt.name = "createdAt"
        createdAt.attributeType = .dateAttributeType

        entity.properties = [id, name, colorHex, createdAt]
        return entity
    }

    private static func makeFolderEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "FolderEntity"
        entity.managedObjectClassName = "FolderEntity"

        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .UUIDAttributeType

        let name = NSAttributeDescription()
        name.name = "name"
        name.attributeType = .stringAttributeType
        name.defaultValue = ""

        let sortOrder = NSAttributeDescription()
        sortOrder.name = "sortOrder"
        sortOrder.attributeType = .integer32AttributeType
        sortOrder.defaultValue = Int32(0)

        let createdAt = NSAttributeDescription()
        createdAt.name = "createdAt"
        createdAt.attributeType = .dateAttributeType

        entity.properties = [id, name, sortOrder, createdAt]
        return entity
    }

    private static func makeEditHistoryEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "EditHistoryEntity"
        entity.managedObjectClassName = "EditHistoryEntity"

        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .UUIDAttributeType

        let previousText = NSAttributeDescription()
        previousText.name = "previousText"
        previousText.attributeType = .stringAttributeType
        previousText.defaultValue = ""

        let newText = NSAttributeDescription()
        newText.name = "newText"
        newText.attributeType = .stringAttributeType
        newText.defaultValue = ""

        let editedAt = NSAttributeDescription()
        editedAt.name = "editedAt"
        editedAt.attributeType = .dateAttributeType

        let editIndex = NSAttributeDescription()
        editIndex.name = "editIndex"
        editIndex.attributeType = .integer16AttributeType
        editIndex.defaultValue = Int16(0)

        entity.properties = [id, previousText, newText, editedAt, editIndex]
        return entity
    }

    // MARK: - Relationships

    private static func configureRelationships(
        session: NSEntityDescription,
        chunk: NSEntityDescription,
        segment: NSEntityDescription,
        highlight: NSEntityDescription,
        tag: NSEntityDescription,
        folder: NSEntityDescription,
        editHistory: NSEntityDescription
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

        // Session <-> Tags (many-to-many)
        let sessionToTags = NSRelationshipDescription()
        sessionToTags.name = "tags"
        sessionToTags.destinationEntity = tag
        sessionToTags.deleteRule = .nullifyDeleteRule
        sessionToTags.isOptional = true

        let tagToSessions = NSRelationshipDescription()
        tagToSessions.name = "sessions"
        tagToSessions.destinationEntity = session
        tagToSessions.deleteRule = .nullifyDeleteRule
        tagToSessions.isOptional = true

        sessionToTags.inverseRelationship = tagToSessions
        tagToSessions.inverseRelationship = sessionToTags

        // Session <-> Folder (many-to-one)
        let sessionToFolder = NSRelationshipDescription()
        sessionToFolder.name = "folder"
        sessionToFolder.destinationEntity = folder
        sessionToFolder.deleteRule = .nullifyDeleteRule
        sessionToFolder.maxCount = 1
        sessionToFolder.isOptional = true

        let folderToSessions = NSRelationshipDescription()
        folderToSessions.name = "sessions"
        folderToSessions.destinationEntity = session
        folderToSessions.deleteRule = .nullifyDeleteRule
        folderToSessions.isOptional = true

        sessionToFolder.inverseRelationship = folderToSessions
        folderToSessions.inverseRelationship = sessionToFolder

        // Segment <-> EditHistory (one-to-many, cascade)
        let segmentToEditHistory = NSRelationshipDescription()
        segmentToEditHistory.name = "editHistory"
        segmentToEditHistory.destinationEntity = editHistory
        segmentToEditHistory.deleteRule = .cascadeDeleteRule
        segmentToEditHistory.isOptional = true

        let editHistoryToSegment = NSRelationshipDescription()
        editHistoryToSegment.name = "segment"
        editHistoryToSegment.destinationEntity = segment
        editHistoryToSegment.deleteRule = .nullifyDeleteRule
        editHistoryToSegment.maxCount = 1

        segmentToEditHistory.inverseRelationship = editHistoryToSegment
        editHistoryToSegment.inverseRelationship = segmentToEditHistory

        // Append relationship properties to entities
        session.properties += [
            sessionToChunks, sessionToSegments, sessionToHighlights,
            sessionToTags, sessionToFolder
        ]
        chunk.properties += [chunkToSession, chunkToSegments]
        segment.properties += [segmentToSession, segmentToChunk, segmentToEditHistory]
        highlight.properties += [highlightToSession]
        tag.properties += [tagToSessions]
        folder.properties += [folderToSessions]
        editHistory.properties += [editHistoryToSegment]
    }
}
