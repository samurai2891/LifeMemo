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
    @NSManaged public var speakerNamesJSON: String?  // e.g. {"0":"Taro","1":"Hanako"}
    @NSManaged public var liveEditsJSON: String?
    @NSManaged public var speakerProfilesJSON: String?
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

    var liveEditRecords: [LiveEditRecord] {
        guard let json = liveEditsJSON,
              let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([LiveEditRecord].self, from: data)) ?? []
    }

    /// Decoded speaker name mapping (speakerIndex -> custom name).
    var speakerNames: [Int: String] {
        guard let json = speakerNamesJSON,
              let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        var result: [Int: String] = [:]
        for (key, value) in dict {
            if let index = Int(key) {
                result[index] = value
            }
        }
        return result
    }

    /// Decoded speaker profiles per chunk (chunkIndex -> profiles).
    var speakerProfiles: [Int: [SpeakerProfile]] {
        guard let json = speakerProfilesJSON,
              let data = json.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([Int: [SpeakerProfile]].self, from: data)) ?? [:]
    }

    /// Encodes and stores the speaker profiles mapping.
    func setSpeakerProfiles(_ profiles: [Int: [SpeakerProfile]]) {
        if let data = try? JSONEncoder().encode(profiles),
           let json = String(data: data, encoding: .utf8) {
            speakerProfilesJSON = json
        }
    }

    /// Encodes and stores the speaker name mapping.
    func setSpeakerNames(_ names: [Int: String]) {
        let stringKeyed = Dictionary(uniqueKeysWithValues: names.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyed),
           let json = String(data: data, encoding: .utf8) {
            speakerNamesJSON = json
        }
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
