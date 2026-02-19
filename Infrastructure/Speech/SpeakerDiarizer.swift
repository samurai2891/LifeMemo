import Foundation

/// Performs speaker diarization using multi-feature analysis and two-pass refinement.
///
/// Replaces the original pitch-only diarizer with a 6-step pipeline:
/// 1. Feature enrichment via `AudioFeatureExtractor`
/// 2. Score-based change point detection (weighted sum of pause, pitch, energy, spectral scores)
/// 3. Group splitting at change points with `SpeakerFeatureVector` computation
/// 4. Pass 1: Forward assignment to centroids or new speakers
/// 5. Pass 2: Re-assignment refinement with updated centroids
/// 6. Pass 3: Similar speaker merge (distance < mergeThreshold)
final class SpeakerDiarizer {

    // MARK: - Configuration

    private let changePointThreshold: Float = 2.0
    private let newSpeakerThreshold: Float = 1.5
    private let mergeThreshold: Float = 0.8
    private let maxSpeakers: Int = 8

    // MARK: - Internal Types

    private struct WordGroup {
        let words: [WordSegmentInfo]
        let featureVector: SpeakerFeatureVector?
        var speakerIndex: Int
    }

    // MARK: - Public API

    /// Diarizes word segments into speaker-attributed turns.
    ///
    /// - Parameters:
    ///   - audioURL: File URL of the audio chunk.
    ///   - wordSegments: Word-level data from the transcriber.
    /// - Returns: A `DiarizationResult` with speaker-labelled segments and profiles.
    func diarize(audioURL: URL, wordSegments: [WordSegmentInfo]) -> DiarizationResult {
        guard wordSegments.count > 1 else {
            return makeSingleSpeakerResult(wordSegments: wordSegments)
        }

        // Step 1: Enrich with all 6 features
        let enriched = enrichWithFeatures(audioURL: audioURL, wordSegments: wordSegments)

        // Step 2: Score-based change point detection
        let changePoints = detectChangePoints(words: enriched)

        // Step 3: Split into groups
        let groups = splitIntoGroups(words: enriched, changePoints: changePoints)

        // Step 4: Pass 1 — forward assignment
        let pass1 = forwardAssignment(groups: groups)

        // Step 5: Pass 2 — re-assignment refinement
        let pass2 = reassignmentRefinement(groups: pass1)

        // Step 6: Pass 3 — merge similar speakers
        let pass3 = mergeSimilarSpeakers(groups: pass2)

        // Merge consecutive same-speaker groups
        let merged = mergeConsecutiveSameSpeaker(groups: pass3)

        // Check if diarization produced multiple speakers
        let speakerIndices = Set(merged.map(\.speakerIndex))
        if speakerIndices.count <= 1 {
            return makeSingleSpeakerResult(wordSegments: wordSegments)
        }

        // Build profiles
        let profiles = buildSpeakerProfiles(groups: merged)

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
            speakerCount: speakerIndices.count,
            speakerProfiles: profiles
        )
    }

    // MARK: - Step 1: Feature Enrichment

    private func enrichWithFeatures(
        audioURL: URL,
        wordSegments: [WordSegmentInfo]
    ) -> [WordSegmentInfo] {
        let windows = wordSegments.map { word in
            (startSec: word.timestamp, durationSec: max(word.duration, 0.03))
        }
        let features = AudioFeatureExtractor.extractFeatures(url: audioURL, windows: windows)

        return zip(wordSegments, features).map { word, feat in
            WordSegmentInfo(
                substring: word.substring,
                timestamp: word.timestamp,
                duration: word.duration,
                confidence: word.confidence,
                averagePitch: word.averagePitch ?? feat.meanPitch,
                pitchStdDev: word.pitchStdDev ?? feat.pitchStdDev,
                averageEnergy: word.averageEnergy ?? feat.meanEnergy,
                averageSpectralCentroid: word.averageSpectralCentroid ?? feat.meanSpectralCentroid,
                averageJitter: word.averageJitter ?? feat.jitter,
                averageShimmer: word.averageShimmer ?? feat.shimmer
            )
        }
    }

    // MARK: - Step 2: Score-Based Change Point Detection

    private func detectChangePoints(words: [WordSegmentInfo]) -> Set<Int> {
        var changePoints = Set<Int>()

        for i in 1..<words.count {
            let prev = words[i - 1]
            let curr = words[i]

            let score = computeChangeScore(prev: prev, curr: curr)
            if score >= changePointThreshold {
                changePoints.insert(i)
            }
        }

        return changePoints
    }

    private func computeChangeScore(prev: WordSegmentInfo, curr: WordSegmentInfo) -> Float {
        // Pause score
        let gap = Float(curr.timestamp - (prev.timestamp + prev.duration))
        let pauseScore: Float
        if gap < 0.3 {
            pauseScore = 0
        } else if gap < 0.5 {
            pauseScore = 0.5
        } else if gap < 1.0 {
            pauseScore = 1.0
        } else {
            pauseScore = 1.5
        }

        // Pitch score
        let pitchScore: Float = {
            guard let prevP = prev.averagePitch, let currP = curr.averagePitch,
                  prevP > 0 else { return 0 }
            let avgP = (prevP + currP) / 2
            guard avgP > 0 else { return 0 }
            return min(abs(currP - prevP) / avgP * 5.0, 2.0)
        }()

        // Energy score
        let energyScore: Float = {
            guard let prevE = prev.averageEnergy, let currE = curr.averageEnergy else { return 0 }
            let avgE = (prevE + currE) / 2
            guard avgE > 0 else { return 0 }
            return min(abs(currE - prevE) / avgE * 3.0, 1.5)
        }()

        // Spectral centroid score
        let spectralScore: Float = {
            guard let prevS = prev.averageSpectralCentroid,
                  let currS = curr.averageSpectralCentroid else { return 0 }
            let avgS = (prevS + currS) / 2
            guard avgS > 0 else { return 0 }
            return min(abs(currS - prevS) / avgS * 2.0, 1.0)
        }()

        return pauseScore + pitchScore + energyScore + spectralScore
    }

    // MARK: - Step 3: Group Splitting

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
        let vector = computeFeatureVector(words: words)
        return WordGroup(words: words, featureVector: vector, speakerIndex: -1)
    }

    private func computeFeatureVector(words: [WordSegmentInfo]) -> SpeakerFeatureVector? {
        let pitches = words.compactMap(\.averagePitch)
        guard !pitches.isEmpty else { return nil }

        let meanPitch = pitches.reduce(0, +) / Float(pitches.count)
        let pitchVariance = pitches.reduce(Float(0)) { $0 + ($1 - meanPitch) * ($1 - meanPitch) }
        let pitchStd = sqrt(pitchVariance / Float(pitches.count))

        let energies = words.compactMap(\.averageEnergy)
        let meanEnergy = energies.isEmpty ? Float(0) : energies.reduce(0, +) / Float(energies.count)

        let centroids = words.compactMap(\.averageSpectralCentroid)
        let meanCentroid = centroids.isEmpty ? Float(0) : centroids.reduce(0, +) / Float(centroids.count)

        let jitters = words.compactMap(\.averageJitter)
        let meanJitter = jitters.isEmpty ? Float(0) : jitters.reduce(0, +) / Float(jitters.count)

        let shimmers = words.compactMap(\.averageShimmer)
        let meanShimmer = shimmers.isEmpty ? Float(0) : shimmers.reduce(0, +) / Float(shimmers.count)

        return SpeakerFeatureVector(
            meanPitch: meanPitch,
            pitchStdDev: pitchStd,
            meanEnergy: meanEnergy,
            meanSpectralCentroid: meanCentroid,
            meanJitter: meanJitter,
            meanShimmer: meanShimmer
        )
    }

    // MARK: - Step 4: Forward Assignment

    private func forwardAssignment(groups: [WordGroup]) -> [WordGroup] {
        var centroids: [SpeakerFeatureVector] = []
        var centroidCounts: [Int] = []
        var result: [WordGroup] = []

        for group in groups {
            guard let vector = group.featureVector else {
                let speakerIdx = result.last?.speakerIndex ?? 0
                result.append(WordGroup(
                    words: group.words,
                    featureVector: group.featureVector,
                    speakerIndex: speakerIdx
                ))
                continue
            }

            // Find closest centroid
            var bestIdx = -1
            var bestDistance: Float = .infinity
            for (idx, centroid) in centroids.enumerated() {
                let dist = vector.distance(to: centroid)
                if dist < bestDistance {
                    bestDistance = dist
                    bestIdx = idx
                }
            }

            if bestIdx >= 0 && bestDistance <= newSpeakerThreshold {
                // Match existing speaker
                result.append(WordGroup(
                    words: group.words,
                    featureVector: group.featureVector,
                    speakerIndex: bestIdx
                ))
                // Update centroid with exponential moving average
                let oldWeight = Float(centroidCounts[bestIdx])
                let newWeight = Float(1)
                let total = oldWeight + newWeight
                let oldC = centroids[bestIdx]
                centroids[bestIdx] = SpeakerFeatureVector(
                    meanPitch: (oldC.meanPitch * oldWeight + vector.meanPitch * newWeight) / total,
                    pitchStdDev: (oldC.pitchStdDev * oldWeight + vector.pitchStdDev * newWeight) / total,
                    meanEnergy: (oldC.meanEnergy * oldWeight + vector.meanEnergy * newWeight) / total,
                    meanSpectralCentroid: (oldC.meanSpectralCentroid * oldWeight + vector.meanSpectralCentroid * newWeight) / total,
                    meanJitter: (oldC.meanJitter * oldWeight + vector.meanJitter * newWeight) / total,
                    meanShimmer: (oldC.meanShimmer * oldWeight + vector.meanShimmer * newWeight) / total
                )
                centroidCounts[bestIdx] += 1
            } else if centroids.count < maxSpeakers {
                // New speaker
                let newIdx = centroids.count
                centroids.append(vector)
                centroidCounts.append(1)
                result.append(WordGroup(
                    words: group.words,
                    featureVector: group.featureVector,
                    speakerIndex: newIdx
                ))
            } else {
                // Max speakers reached — assign to closest
                result.append(WordGroup(
                    words: group.words,
                    featureVector: group.featureVector,
                    speakerIndex: max(0, bestIdx)
                ))
            }
        }

        return result
    }

    // MARK: - Step 5: Re-assignment Refinement

    private func reassignmentRefinement(groups: [WordGroup]) -> [WordGroup] {
        // Recompute centroids from current assignments
        let speakerIndices = Set(groups.map(\.speakerIndex))
        var centroids: [Int: SpeakerFeatureVector] = [:]

        for idx in speakerIndices {
            let vectors = groups
                .filter { $0.speakerIndex == idx }
                .compactMap(\.featureVector)
            if let centroid = SpeakerFeatureVector.centroid(of: vectors) {
                centroids[idx] = centroid
            }
        }

        guard !centroids.isEmpty else { return groups }

        // Re-assign each group to nearest centroid
        return groups.map { group in
            guard let vector = group.featureVector else { return group }

            var bestIdx = group.speakerIndex
            var bestDist: Float = .infinity

            for (idx, centroid) in centroids {
                let dist = vector.distance(to: centroid)
                if dist < bestDist {
                    bestDist = dist
                    bestIdx = idx
                }
            }

            return WordGroup(
                words: group.words,
                featureVector: group.featureVector,
                speakerIndex: bestIdx
            )
        }
    }

    // MARK: - Step 6: Merge Similar Speakers

    private func mergeSimilarSpeakers(groups: [WordGroup]) -> [WordGroup] {
        let speakerIndices = Array(Set(groups.map(\.speakerIndex))).sorted()
        guard speakerIndices.count > 1 else { return groups }

        // Compute centroids
        var centroids: [Int: SpeakerFeatureVector] = [:]
        for idx in speakerIndices {
            let vectors = groups
                .filter { $0.speakerIndex == idx }
                .compactMap(\.featureVector)
            if let centroid = SpeakerFeatureVector.centroid(of: vectors) {
                centroids[idx] = centroid
            }
        }

        // Find merge pairs (distance < mergeThreshold)
        var mergeMap: [Int: Int] = [:]  // oldIndex -> canonical index
        for idx in speakerIndices {
            mergeMap[idx] = idx
        }

        for i in 0..<speakerIndices.count {
            for j in (i + 1)..<speakerIndices.count {
                let idxA = speakerIndices[i]
                let idxB = speakerIndices[j]

                // Follow existing merges
                let canonA = resolveCanonical(mergeMap: mergeMap, index: idxA)
                let canonB = resolveCanonical(mergeMap: mergeMap, index: idxB)
                guard canonA != canonB else { continue }

                guard let centA = centroids[idxA], let centB = centroids[idxB] else { continue }
                if centA.distance(to: centB) < mergeThreshold {
                    // Merge B into A (keep lower index)
                    mergeMap[canonB] = canonA
                }
            }
        }

        // Apply merge map
        let merged = groups.map { group in
            let canonical = resolveCanonical(mergeMap: mergeMap, index: group.speakerIndex)
            return WordGroup(
                words: group.words,
                featureVector: group.featureVector,
                speakerIndex: canonical
            )
        }

        // Re-index speakers to be contiguous (0, 1, 2...)
        return reindexSpeakers(groups: merged)
    }

    private func resolveCanonical(mergeMap: [Int: Int], index: Int) -> Int {
        var current = index
        while let next = mergeMap[current], next != current {
            current = next
        }
        return current
    }

    private func reindexSpeakers(groups: [WordGroup]) -> [WordGroup] {
        let uniqueSpeakers = Array(Set(groups.map(\.speakerIndex))).sorted()
        var indexMap: [Int: Int] = [:]
        for (newIdx, oldIdx) in uniqueSpeakers.enumerated() {
            indexMap[oldIdx] = newIdx
        }

        return groups.map { group in
            WordGroup(
                words: group.words,
                featureVector: group.featureVector,
                speakerIndex: indexMap[group.speakerIndex] ?? group.speakerIndex
            )
        }
    }

    // MARK: - Consecutive Merge

    private func mergeConsecutiveSameSpeaker(groups: [WordGroup]) -> [WordGroup] {
        guard !groups.isEmpty else { return [] }

        var merged: [WordGroup] = [groups[0]]

        for i in 1..<groups.count {
            let current = groups[i]
            let lastIndex = merged.count - 1

            if merged[lastIndex].speakerIndex == current.speakerIndex {
                let combinedWords = merged[lastIndex].words + current.words
                let combinedVector = computeFeatureVector(words: combinedWords)
                merged[lastIndex] = WordGroup(
                    words: combinedWords,
                    featureVector: combinedVector,
                    speakerIndex: current.speakerIndex
                )
            } else {
                merged.append(current)
            }
        }

        return merged
    }

    // MARK: - Profile Building

    private func buildSpeakerProfiles(groups: [WordGroup]) -> [SpeakerProfile] {
        let speakerIndices = Array(Set(groups.map(\.speakerIndex))).sorted()

        return speakerIndices.compactMap { idx in
            let vectors = groups
                .filter { $0.speakerIndex == idx }
                .compactMap(\.featureVector)
            guard let centroid = SpeakerFeatureVector.centroid(of: vectors) else { return nil }

            return SpeakerProfile(
                id: UUID(),
                speakerIndex: idx,
                centroid: centroid,
                sampleCount: vectors.count
            )
        }
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
