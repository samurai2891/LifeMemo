import Foundation
import NaturalLanguage

/// Extracts keywords, named entities, and topic clusters from text
/// using Apple's NaturalLanguage framework.
@MainActor
final class TopicExtractor {

    // MARK: - Types

    struct ExtractionResult: Equatable {
        let keywords: [Keyword]
        let namedEntities: [NamedEntity]
        let topicClusters: [TopicCluster]
        let processingTime: TimeInterval
    }

    struct Keyword: Equatable, Identifiable, Hashable {
        let id: UUID
        let word: String
        let count: Int
        let partOfSpeech: PartOfSpeech
        enum PartOfSpeech: String, Equatable, Hashable { case noun, verb, adjective, other }
    }

    struct NamedEntity: Equatable, Identifiable, Hashable {
        let id: UUID
        let text: String
        let type: EntityType
        let count: Int
        enum EntityType: String, Equatable, Hashable { case person, place, organization, other }
    }

    struct TopicCluster: Equatable, Identifiable {
        let id: UUID
        let label: String
        let keywords: [String]
        let weight: Double
    }

    // MARK: - Config

    var maxKeywords: Int = 20
    var maxEntities: Int = 15
    var maxTopics: Int = 5

    // MARK: - Stop Words

    // swiftlint:disable:next line_length
    private static let stopWords: Set<String> = ["the","a","an","is","was","are","were","be","been","have","has","had","do","does","did","will","would","could","should","may","might","can","shall","to","of","in","for","on","with","at","by","from","as","into","through","during","before","after","about","between","but","not","or","and","if","then","so","that","this","it","its","he","she","they","we","you","i","my","your","his","her","their","our","what","which","who","when","where","how","all","each","every","both","few","more","most","other","some","such","no","only","own","same","than","too","very","の","は","が","を","に","で","と","も","や","へ","から","まで","より","など","って","という","する","ある","いる","なる","できる","こと","もの","ため","よう","それ","これ","その","この"]

    // MARK: - Public API

    func extract(from text: String) -> ExtractionResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        guard !text.isEmpty else {
            return ExtractionResult(keywords: [], namedEntities: [], topicClusters: [], processingTime: 0)
        }
        let keywords = extractKeywords(text)
        let entities = extractNamedEntities(text)
        let topics = buildTopicClusters(from: text, keywords: keywords)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        return ExtractionResult(
            keywords: keywords, namedEntities: entities,
            topicClusters: topics, processingTime: elapsed
        )
    }

    // MARK: - Keyword Extraction

    private func extractKeywords(_ text: String) -> [Keyword] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var counts: [String: (count: Int, pos: Keyword.PartOfSpeech)] = [:]
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word, scheme: .lexicalClass, options: options
        ) { tag, range in
            let pos = Self.mapPartOfSpeech(tag)
            guard pos != .other else { return true }
            let token = String(text[range]).lowercased()
            guard token.count >= 2, !Self.stopWords.contains(token) else { return true }
            let existing = counts[token]
            counts[token] = (count: (existing?.count ?? 0) + 1, pos: existing?.pos ?? pos)
            return true
        }
        return counts
            .sorted { $0.value.count > $1.value.count }
            .prefix(maxKeywords)
            .map { Keyword(id: UUID(), word: $0.key, count: $0.value.count, partOfSpeech: $0.value.pos) }
    }

    private static func mapPartOfSpeech(_ tag: NLTag?) -> Keyword.PartOfSpeech {
        switch tag {
        case .noun: return .noun
        case .verb: return .verb
        case .adjective: return .adjective
        default: return .other
        }
    }

    // MARK: - Named Entity Extraction

    private func extractNamedEntities(_ text: String) -> [NamedEntity] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var counts: [String: (count: Int, type: NamedEntity.EntityType)] = [:]
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word, scheme: .nameType, options: options
        ) { tag, range in
            guard let entityType = Self.mapEntityType(tag) else { return true }
            let token = String(text[range])
            guard !token.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
            let existing = counts[token]
            counts[token] = (count: (existing?.count ?? 0) + 1, type: existing?.type ?? entityType)
            return true
        }
        return counts
            .sorted { $0.value.count > $1.value.count }
            .prefix(maxEntities)
            .map { NamedEntity(id: UUID(), text: $0.key, type: $0.value.type, count: $0.value.count) }
    }

    private static func mapEntityType(_ tag: NLTag?) -> NamedEntity.EntityType? {
        switch tag {
        case .personalName: return .person
        case .placeName: return .place
        case .organizationName: return .organization
        default: return nil
        }
    }

    // MARK: - Topic Clustering

    private func buildTopicClusters(from text: String, keywords: [Keyword]) -> [TopicCluster] {
        let keywordSet = Set(keywords.map(\.word))
        let words = tokenize(text).filter { keywordSet.contains($0) }
        guard !words.isEmpty else { return [] }

        let windowSize = 50
        var cooccurrence: [String: Set<String>] = [:]
        for i in 0..<words.count {
            let window = Set(words[i..<min(i + windowSize, words.count)])
            for w in window { cooccurrence[w, default: []].formUnion(window) }
        }

        let countMap = Dictionary(uniqueKeysWithValues: keywords.map { ($0.word, $0.count) })
        var used: Set<String> = []
        var clusters: [(label: String, members: [String], totalCount: Int)] = []
        for kw in keywords.sorted(by: { $0.count > $1.count }) {
            guard !used.contains(kw.word) else { continue }
            let members = cooccurrence[kw.word, default: []]
                .filter { !used.contains($0) }
                .sorted { (countMap[$0] ?? 0) > (countMap[$1] ?? 0) }
            guard !members.isEmpty else { continue }
            let total = members.reduce(0) { $0 + (countMap[$1] ?? 0) }
            clusters.append((label: kw.word, members: members, totalCount: total))
            used.formUnion(members)
        }

        let maxCount = clusters.map(\.totalCount).max() ?? 1
        return clusters.prefix(maxTopics).map { cluster in
            TopicCluster(
                id: UUID(), label: cluster.label,
                keywords: cluster.members,
                weight: Double(cluster.totalCount) / Double(max(maxCount, 1))
            )
        }
    }

    private func tokenize(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .map { String(text[$0]).lowercased() }
    }
}
