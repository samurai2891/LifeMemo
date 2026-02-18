import Foundation
import CoreData

@objc(SessionEntity)
public class SessionEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var startedAt: Date?
    @NSManaged public var endedAt: Date?
    @NSManaged public var title: String?
    @NSManaged public var languageModeRaw: String?
    @NSManaged public var statusRaw: Int16
    @NSManaged public var audioKept: Bool
    @NSManaged public var summary: String?
    @NSManaged public var bodyText: String?
    @NSManaged public var latitude: Double
    @NSManaged public var longitude: Double
    @NSManaged public var placeName: String?
    @NSManaged public var chunks: NSSet?
    @NSManaged public var segments: NSSet?
    @NSManaged public var highlights: NSSet?
    @NSManaged public var tags: NSSet?
    @NSManaged public var folder: FolderEntity?
}

extension SessionEntity {

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .idle }
        set { statusRaw = newValue.rawValue }
    }

    var languageMode: LanguageMode {
        get { LanguageMode(rawValue: languageModeRaw ?? "auto") ?? .auto }
        set { languageModeRaw = newValue.rawValue }
    }

    var chunksArray: [ChunkEntity] {
        let set = chunks as? Set<ChunkEntity> ?? []
        return set.sorted { $0.index < $1.index }
    }

    var segmentsArray: [TranscriptSegmentEntity] {
        let set = segments as? Set<TranscriptSegmentEntity> ?? []
        return set.sorted { $0.startMs < $1.startMs }
    }

    var highlightsArray: [HighlightEntity] {
        let set = highlights as? Set<HighlightEntity> ?? []
        return set.sorted { $0.atMs < $1.atMs }
    }

    var tagsArray: [TagEntity] {
        let set = tags as? Set<TagEntity> ?? []
        return set.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    var hasLocation: Bool {
        latitude != 0 || longitude != 0
    }

    func toSummary() -> SessionSummary {
        let preview = segmentsArray
            .prefix(3)
            .map { $0.text ?? "" }
            .joined(separator: " ")

        return SessionSummary(
            id: id ?? UUID(),
            title: title ?? "",
            createdAt: createdAt ?? Date(),
            startedAt: startedAt ?? Date(),
            endedAt: endedAt,
            status: status,
            audioKept: audioKept,
            languageMode: languageModeRaw ?? "auto",
            summary: summary,
            chunkCount: chunksArray.count,
            transcriptPreview: preview.isEmpty ? nil : String(preview.prefix(200)),
            bodyText: bodyText,
            tags: tagsArray.map { $0.toInfo() },
            folderName: folder?.name,
            placeName: placeName
        )
    }
}
