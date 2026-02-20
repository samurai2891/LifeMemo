import Foundation

/// Aligns speaker indices across independently-processed 60-second audio chunks.
///
/// Each chunk's diarization produces local speaker indices (0, 1, 2...) that may
/// not correspond to the same physical speakers across chunks. This aligner builds
/// a global speaker map by greedily matching local speaker profiles to global
/// profiles using cosine distance on MFCC embeddings (with legacy centroid fallback).
///
/// ## Algorithm
/// 1. Chunk 0's speakers become the initial global reference profiles.
/// 2. For each subsequent chunk, compute a distance matrix (local x global).
/// 3. Greedily match pairs in ascending distance order (threshold ≤ 0.4 for MFCC).
/// 4. Unmatched local speakers are assigned new global indices.
/// 5. Matched global profiles are updated with weighted averaging.
enum CrossChunkSpeakerAligner {

    // MARK: - Types

    struct ChunkSpeakers {
        let chunkIndex: Int
        let profiles: [SpeakerProfile]
    }

    /// Maps chunkIndex -> (localSpeakerIndex -> globalSpeakerIndex)
    typealias AlignmentMap = [Int: [Int: Int]]

    // MARK: - Configuration

    /// Distance threshold for MFCC embedding matching (cosine distance).
    private static let mfccMatchThreshold: Float = 0.4

    /// Legacy distance threshold for centroid-based matching.
    private static let legacyMatchThreshold: Float = 2.0

    // MARK: - Public API

    /// Aligns speakers across multiple chunks and returns a mapping plus updated global profiles.
    ///
    /// - Parameter chunkSpeakers: Speaker profiles from each chunk, ordered by chunk index.
    /// - Returns: Tuple of (alignment map, global speaker profiles).
    static func align(
        chunkSpeakers: [ChunkSpeakers]
    ) -> (map: AlignmentMap, globalProfiles: [SpeakerProfile]) {
        guard !chunkSpeakers.isEmpty else {
            return (map: [:], globalProfiles: [])
        }

        let sorted = chunkSpeakers.sorted { $0.chunkIndex < $1.chunkIndex }

        // Initialize from first chunk
        var globalProfiles = sorted[0].profiles.enumerated().map { idx, profile in
            SpeakerProfile(
                id: profile.id,
                speakerIndex: idx,
                centroid: profile.centroid,
                sampleCount: profile.sampleCount,
                mfccEmbedding: profile.mfccEmbedding
            )
        }

        var alignmentMap: AlignmentMap = [:]

        // First chunk: identity mapping
        var firstMap: [Int: Int] = [:]
        for profile in sorted[0].profiles {
            firstMap[profile.speakerIndex] = profile.speakerIndex
        }
        alignmentMap[sorted[0].chunkIndex] = firstMap

        // Process subsequent chunks
        for chunkIdx in 1..<sorted.count {
            let chunk = sorted[chunkIdx]
            let (localMap, updatedProfiles) = matchChunkToGlobal(
                localProfiles: chunk.profiles,
                globalProfiles: globalProfiles
            )
            globalProfiles = updatedProfiles
            alignmentMap[chunk.chunkIndex] = localMap
        }

        return (map: alignmentMap, globalProfiles: globalProfiles)
    }

    // MARK: - Private

    /// Computes distance between two speaker profiles, preferring MFCC embedding.
    private static func computeDistance(
        local: SpeakerProfile,
        global: SpeakerProfile
    ) -> (distance: Float, usedMFCC: Bool) {
        if let localMFCC = local.mfccEmbedding, let globalMFCC = global.mfccEmbedding {
            return (distance: localMFCC.cosineDistance(to: globalMFCC), usedMFCC: true)
        }
        return (distance: local.centroid.distance(to: global.centroid), usedMFCC: false)
    }

    /// Matches local speakers from a chunk to existing global speakers using greedy assignment.
    private static func matchChunkToGlobal(
        localProfiles: [SpeakerProfile],
        globalProfiles: [SpeakerProfile]
    ) -> (localToGlobal: [Int: Int], updatedGlobal: [SpeakerProfile]) {
        guard !localProfiles.isEmpty else {
            return (localToGlobal: [:], updatedGlobal: globalProfiles)
        }

        // Build distance matrix
        var distances: [(localIdx: Int, globalIdx: Int, distance: Float, usedMFCC: Bool)] = []
        for local in localProfiles {
            for global in globalProfiles {
                let (dist, usedMFCC) = computeDistance(local: local, global: global)
                distances.append((
                    localIdx: local.speakerIndex,
                    globalIdx: global.speakerIndex,
                    distance: dist,
                    usedMFCC: usedMFCC
                ))
            }
        }

        // Sort by distance ascending for greedy matching
        distances.sort { $0.distance < $1.distance }

        var localToGlobal: [Int: Int] = [:]
        var matchedLocal = Set<Int>()
        var matchedGlobal = Set<Int>()
        var updatedProfiles = globalProfiles

        // Greedy matching
        for entry in distances {
            guard !matchedLocal.contains(entry.localIdx),
                  !matchedGlobal.contains(entry.globalIdx) else { continue }

            let threshold = entry.usedMFCC ? mfccMatchThreshold : legacyMatchThreshold
            guard entry.distance <= threshold else { continue }

            localToGlobal[entry.localIdx] = entry.globalIdx
            matchedLocal.insert(entry.localIdx)
            matchedGlobal.insert(entry.globalIdx)

            // Update global profile with weighted merge
            if let globalProfileIdx = updatedProfiles.firstIndex(where: { $0.speakerIndex == entry.globalIdx }),
               let localProfile = localProfiles.first(where: { $0.speakerIndex == entry.localIdx }) {

                var merged = updatedProfiles[globalProfileIdx].merging(
                    newCentroid: localProfile.centroid,
                    newSampleCount: localProfile.sampleCount
                )

                // Also merge MFCC embedding if available
                if let localMFCC = localProfile.mfccEmbedding {
                    merged = merged.merging(
                        newMFCCEmbedding: localMFCC,
                        newSampleCount: localProfile.sampleCount
                    )
                }

                updatedProfiles[globalProfileIdx] = merged
            }
        }

        // Unmatched local speakers become new global speakers
        for local in localProfiles where !matchedLocal.contains(local.speakerIndex) {
            let newGlobalIndex = (updatedProfiles.map(\.speakerIndex).max() ?? -1) + 1
            localToGlobal[local.speakerIndex] = newGlobalIndex
            updatedProfiles.append(SpeakerProfile(
                id: UUID(),
                speakerIndex: newGlobalIndex,
                centroid: local.centroid,
                sampleCount: local.sampleCount,
                mfccEmbedding: local.mfccEmbedding
            ))
        }

        return (localToGlobal: localToGlobal, updatedGlobal: updatedProfiles)
    }
}
