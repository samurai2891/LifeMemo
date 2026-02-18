import Foundation

/// Performs speaker diarization by combining pause detection with pitch-based clustering.
///
/// Given word-level timing and optional pitch data from the speech recognizer,
/// this class identifies speaker change points and groups words into speaker turns.
/// When `voiceAnalytics` pitch data is unavailable, it falls back to
/// `AudioPitchAnalyzer` for raw audio pitch estimation.
final class SpeakerDiarizer {

    // MARK: - Configuration

    private let pauseThresholdSec: TimeInterval = 0.5
    private let pitchChangeRatio: Float = 0.20           // 20% relative change
    private let pitchMatchThresholdHz: Float = 25.0       // Hz within centroid
    private let maxSpeakers: Int = 8

    // MARK: - Public API

    /// Diarizes word segments into speaker-attributed turns.
    ///
    /// - Parameters:
    ///   - audioURL: File URL of the audio chunk (used for fallback pitch analysis).
    ///   - wordSegments: Word-level data from the transcriber.
    /// - Returns: A `DiarizationResult` with speaker-labelled segments.
    func diarize(audioURL: URL, wordSegments: [WordSegmentInfo]) -> DiarizationResult {
        guard wordSegments.count > 1 else {
            return makeSingleSpeakerResult(wordSegments: wordSegments)
        }

        // Step 1: Ensure pitch data is available
        let enriched = enrichWithPitch(audioURL: audioURL, wordSegments: wordSegments)

        // Step 2: Detect speaker change points
        let changePoints = detectChangePoints(words: enriched)

        // Step 3: Split into groups at change points
        let groups = splitIntoGroups(words: enriched, changePoints: changePoints)

        // Step 4: Cluster groups by average pitch → assign speaker indices
        let labelledGroups = clusterBySpeaker(groups: groups)

        // Step 5: Merge consecutive groups with the same speaker
        let merged = mergeConsecutiveSameSpeaker(groups: labelledGroups)

        // Step 6: Build result
        let speakerIndices = Set(merged.map(\.speakerIndex))

        // If only one speaker detected, return as undiarized single segment
        if speakerIndices.count <= 1 {
            return makeSingleSpeakerResult(wordSegments: wordSegments)
        }

        let segments = merged.map { group in
            DiarizedSegment(
                id: UUID(),
                speakerIndex: group.speakerIndex,
                text: group.words.map(\.substring).joined(separator: " "),
                startOffsetMs: Int64(group.words.first!.timestamp * 1000),
                endOffsetMs: Int64(
                    (group.words.last!.timestamp + group.words.last!.duration) * 1000
                )
            )
        }

        return DiarizationResult(
            segments: segments,
            speakerCount: speakerIndices.count
        )
    }

    // MARK: - Pitch Enrichment

    private func enrichWithPitch(
        audioURL: URL,
        wordSegments: [WordSegmentInfo]
    ) -> [WordSegmentInfo] {
        // Check how many words already have pitch data
        let pitchCount = wordSegments.filter { $0.averagePitch != nil }.count
        let hasSufficientPitch = Double(pitchCount) / Double(wordSegments.count) >= 0.5

        if hasSufficientPitch {
            return wordSegments
        }

        // Fallback: estimate pitch from raw audio
        let windows = wordSegments.map { word in
            (startSec: word.timestamp, durationSec: max(word.duration, 0.03))
        }
        let pitches = AudioPitchAnalyzer.estimatePitches(url: audioURL, windows: windows)

        return zip(wordSegments, pitches).map { word, estimatedPitch in
            if word.averagePitch != nil {
                return word
            }
            return WordSegmentInfo(
                substring: word.substring,
                timestamp: word.timestamp,
                duration: word.duration,
                confidence: word.confidence,
                averagePitch: estimatedPitch
            )
        }
    }

    // MARK: - Change Point Detection

    private func detectChangePoints(words: [WordSegmentInfo]) -> Set<Int> {
        var changePoints = Set<Int>()

        for i in 1..<words.count {
            let prev = words[i - 1]
            let curr = words[i]

            // Pause detection
            let gap = curr.timestamp - (prev.timestamp + prev.duration)
            let hasPause = gap >= pauseThresholdSec

            // Pitch change detection
            let hasPitchChange = detectPitchChange(prev: prev, curr: curr)

            // Both pause AND pitch change → strong signal
            // Either alone → weak signal; we require both for robustness
            if hasPause && hasPitchChange {
                changePoints.insert(i)
            }
        }

        return changePoints
    }

    private func detectPitchChange(prev: WordSegmentInfo, curr: WordSegmentInfo) -> Bool {
        guard let prevPitch = prev.averagePitch,
              let currPitch = curr.averagePitch,
              prevPitch > 0 else {
            return false
        }
        let relativeChange = abs(currPitch - prevPitch) / prevPitch
        return relativeChange >= pitchChangeRatio
    }

    // MARK: - Grouping

    private struct WordGroup {
        let words: [WordSegmentInfo]
        let averagePitch: Float?
        var speakerIndex: Int
    }

    private func splitIntoGroups(
        words: [WordSegmentInfo],
        changePoints: Set<Int>
    ) -> [WordGroup] {
        var groups: [WordGroup] = []
        var currentWords: [WordSegmentInfo] = []

        for (index, word) in words.enumerated() {
            if changePoints.contains(index), !currentWords.isEmpty {
                groups.append(makeGroup(from: currentWords))
                currentWords = []
            }
            currentWords.append(word)
        }

        if !currentWords.isEmpty {
            groups.append(makeGroup(from: currentWords))
        }

        return groups
    }

    private func makeGroup(from words: [WordSegmentInfo]) -> WordGroup {
        let pitches = words.compactMap(\.averagePitch)
        let avgPitch: Float? = pitches.isEmpty
            ? nil
            : pitches.reduce(0, +) / Float(pitches.count)
        return WordGroup(words: words, averagePitch: avgPitch, speakerIndex: -1)
    }

    // MARK: - Centroid Clustering

    private func clusterBySpeaker(groups: [WordGroup]) -> [WordGroup] {
        var centroids: [Float] = []
        var result: [WordGroup] = []

        for group in groups {
            guard let groupPitch = group.averagePitch else {
                // No pitch → assign to most recent speaker or speaker 0
                let speakerIdx = centroids.isEmpty ? 0 : result.last?.speakerIndex ?? 0
                var updated = group
                updated.speakerIndex = speakerIdx
                result.append(updated)
                continue
            }

            // Find closest existing centroid
            var bestIdx = -1
            var bestDistance: Float = .infinity

            for (idx, centroid) in centroids.enumerated() {
                let distance = abs(groupPitch - centroid)
                if distance < bestDistance {
                    bestDistance = distance
                    bestIdx = idx
                }
            }

            if bestIdx >= 0 && bestDistance <= pitchMatchThresholdHz {
                // Match existing speaker → update centroid (running average)
                var updated = group
                updated.speakerIndex = bestIdx
                result.append(updated)

                // Update centroid with exponential moving average
                centroids[bestIdx] = centroids[bestIdx] * 0.7 + groupPitch * 0.3
            } else if centroids.count < maxSpeakers {
                // New speaker
                let newIdx = centroids.count
                centroids.append(groupPitch)
                var updated = group
                updated.speakerIndex = newIdx
                result.append(updated)
            } else {
                // Max speakers reached → assign to closest
                var updated = group
                updated.speakerIndex = max(0, bestIdx)
                result.append(updated)
            }
        }

        return result
    }

    // MARK: - Merging

    private func mergeConsecutiveSameSpeaker(groups: [WordGroup]) -> [WordGroup] {
        guard !groups.isEmpty else { return [] }

        var merged: [WordGroup] = [groups[0]]

        for i in 1..<groups.count {
            let current = groups[i]
            let lastIndex = merged.count - 1

            if merged[lastIndex].speakerIndex == current.speakerIndex {
                // Merge words into the last group
                let combinedWords = merged[lastIndex].words + current.words
                merged[lastIndex] = makeGroup(from: combinedWords)
                merged[lastIndex].speakerIndex = current.speakerIndex
            } else {
                merged.append(current)
            }
        }

        return merged
    }

    // MARK: - Fallback

    private func makeSingleSpeakerResult(
        wordSegments: [WordSegmentInfo]
    ) -> DiarizationResult {
        guard !wordSegments.isEmpty else {
            return DiarizationResult(segments: [], speakerCount: 0)
        }

        let text = wordSegments.map(\.substring).joined(separator: " ")
        let start = Int64(wordSegments.first!.timestamp * 1000)
        let lastWord = wordSegments.last!
        let end = Int64((lastWord.timestamp + lastWord.duration) * 1000)

        let segment = DiarizedSegment(
            id: UUID(),
            speakerIndex: 0,
            text: text,
            startOffsetMs: start,
            endOffsetMs: end
        )

        return DiarizationResult(segments: [segment], speakerCount: 1)
    }
}
