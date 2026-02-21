import Foundation

/// Stage 7: User-learned corrections from edit history.
///
/// When the user manually edits transcribed text, the diff is stored as a
/// correction rule. On subsequent transcriptions, matching patterns are
/// auto-corrected. Context-aware: stores the preceding word for disambiguation.
///
/// Stored in UserDefaults as JSON. Max 500 entries; least-frequent entries
/// are evicted when the limit is reached.
final class AdaptiveDictionary: TextCorrectionStage, @unchecked Sendable {
    let name = "AdaptiveDictionary"

    private let storageKey: String
    private let maxEntries: Int
    private let storage: UserDefaults
    private let lock = NSLock()
    private var cache: [CorrectionEntry]?

    // MARK: - Persisted entry

    struct CorrectionEntry: Codable, Equatable, Sendable {
        let original: String
        let replacement: String
        let precedingWord: String?
        var frequency: Int
    }

    // MARK: - Init

    init(
        storage: UserDefaults = .standard,
        storageKey: String = "com.lifememo.adaptiveDictionary",
        maxEntries: Int = 500
    ) {
        self.storage = storage
        self.storageKey = storageKey
        self.maxEntries = maxEntries
    }

    // MARK: - TextCorrectionStage

    func apply(_ text: String) -> String {
        let entries = loadEntries()
        guard !entries.isEmpty else { return text }

        var result = text
        // Apply most-frequent corrections first
        let sorted = entries.sorted { $0.frequency > $1.frequency }
        for entry in sorted {
            if let context = entry.precedingWord {
                let pattern = "\(context)\(entry.original)"
                let replacement = "\(context)\(entry.replacement)"
                result = result.replacingOccurrences(of: pattern, with: replacement)
            } else {
                result = result.replacingOccurrences(
                    of: entry.original, with: entry.replacement
                )
            }
        }
        return result
    }

    // MARK: - Learning

    /// Record a user correction for future auto-application.
    func learn(original: String, replacement: String, precedingWord: String?) {
        guard original != replacement, !original.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        var entries = loadEntriesUnsafe()

        if let index = entries.firstIndex(where: {
            $0.original == original
                && $0.replacement == replacement
                && $0.precedingWord == precedingWord
        }) {
            let updated = CorrectionEntry(
                original: entries[index].original,
                replacement: entries[index].replacement,
                precedingWord: entries[index].precedingWord,
                frequency: entries[index].frequency + 1
            )
            entries = entries.enumerated().map { i, entry in
                i == index ? updated : entry
            }
        } else {
            let entry = CorrectionEntry(
                original: original,
                replacement: replacement,
                precedingWord: precedingWord,
                frequency: 1
            )
            entries = entries + [entry]
        }

        // Evict least-frequent entries if over limit
        if entries.count > maxEntries {
            entries = Array(
                entries.sorted { $0.frequency > $1.frequency }
                    .prefix(maxEntries)
            )
        }

        saveEntries(entries)
    }

    /// Remove a specific learned correction.
    func forget(original: String, replacement: String, precedingWord: String?) {
        lock.lock()
        defer { lock.unlock() }

        let entries = loadEntriesUnsafe().filter {
            !($0.original == original
                && $0.replacement == replacement
                && $0.precedingWord == precedingWord)
        }
        saveEntries(entries)
    }

    /// Remove all learned corrections.
    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeObject(forKey: storageKey)
        cache = nil
    }

    /// Current number of stored entries.
    var entryCount: Int {
        loadEntries().count
    }

    // MARK: - Persistence

    private func loadEntries() -> [CorrectionEntry] {
        lock.lock()
        defer { lock.unlock() }
        return loadEntriesUnsafe()
    }

    /// Must be called while holding `lock`.
    private func loadEntriesUnsafe() -> [CorrectionEntry] {
        if let cached = cache { return cached }
        guard let data = storage.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode(
                  [CorrectionEntry].self, from: data
              )
        else {
            return []
        }
        cache = entries
        return entries
    }

    /// Must be called while holding `lock`.
    private func saveEntries(_ entries: [CorrectionEntry]) {
        cache = entries
        guard let data = try? JSONEncoder().encode(entries) else { return }
        storage.set(data, forKey: storageKey)
    }
}
