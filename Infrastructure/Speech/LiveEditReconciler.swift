import Foundation

/// Matches live edit records against final transcription segments using
/// text similarity (Jaccard coefficient on word sets).
///
/// After recording stops and final transcription completes, each live edit
/// is reconciled with the persistent segments. Edits whose original text
/// exceeds the similarity threshold are applied to the best-matching segment.
struct LiveEditReconciler {

    struct Match: Equatable {
        let segmentId: UUID
        let editedText: String
        let confidence: Double
    }

    func reconcile(
        editRecords: [LiveEditRecord],
        finalSegments: [(id: UUID, text: String)],
        threshold: Double = 0.3
    ) -> [Match] {
        guard !editRecords.isEmpty, !finalSegments.isEmpty else { return [] }

        var usedIndices = Set<Int>()
        var matches: [Match] = []

        for record in editRecords {
            var bestIndex: Int?
            var bestScore: Double = 0

            for (index, segment) in finalSegments.enumerated() {
                guard !usedIndices.contains(index) else { continue }
                let score = textSimilarity(record.originalText, segment.text)
                if score > bestScore {
                    bestScore = score
                    bestIndex = index
                }
            }

            if let index = bestIndex, bestScore >= threshold {
                usedIndices.insert(index)
                matches.append(Match(
                    segmentId: finalSegments[index].id,
                    editedText: record.editedText,
                    confidence: bestScore
                ))
            }
        }

        return matches
    }

    func textSimilarity(_ a: String, _ b: String) -> Double {
        let wordsA = wordSet(a)
        let wordsB = wordSet(b)
        guard !wordsA.isEmpty || !wordsB.isEmpty else { return 0 }
        let intersection = wordsA.intersection(wordsB).count
        let union = wordsA.union(wordsB).count
        return Double(intersection) / Double(union)
    }

    /// Extracts a normalized word set, stripping punctuation for robust matching
    /// against speech recognizer output (which may include commas, periods, etc.).
    private func wordSet(_ text: String) -> Set<String> {
        let punctuation = CharacterSet.punctuationCharacters.union(.symbols)
        return Set(
            text.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: punctuation) }
                .filter { !$0.isEmpty }
        )
    }
}
