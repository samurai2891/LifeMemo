import XCTest
@testable import LifeMemo

final class CrossChunkSpeakerAlignerTests: XCTestCase {

    // MARK: - Empty Input

    func testAlignEmptyChunks() {
        let result = CrossChunkSpeakerAligner.align(chunkSpeakers: [])
        XCTAssertTrue(result.map.isEmpty)
        XCTAssertTrue(result.globalProfiles.isEmpty)
    }

    // MARK: - Single Chunk

    func testSingleChunkIdentityMapping() {
        let profiles = [
            SpeakerProfile(
                id: UUID(), speakerIndex: 0,
                centroid: makeVector(pitch: 120, energy: 0.4, centroid: 600),
                sampleCount: 5
            ),
            SpeakerProfile(
                id: UUID(), speakerIndex: 1,
                centroid: makeVector(pitch: 220, energy: 0.7, centroid: 1200),
                sampleCount: 3
            ),
        ]

        let chunk = CrossChunkSpeakerAligner.ChunkSpeakers(chunkIndex: 0, profiles: profiles)
        let result = CrossChunkSpeakerAligner.align(chunkSpeakers: [chunk])

        XCTAssertEqual(result.map[0]?[0], 0)
        XCTAssertEqual(result.map[0]?[1], 1)
        XCTAssertEqual(result.globalProfiles.count, 2)
    }

    // MARK: - Two Chunks Alignment

    func testTwoChunksMatchingSpeakers() {
        let chunk0 = CrossChunkSpeakerAligner.ChunkSpeakers(
            chunkIndex: 0,
            profiles: [
                SpeakerProfile(
                    id: UUID(), speakerIndex: 0,
                    centroid: makeVector(pitch: 120, energy: 0.4, centroid: 600),
                    sampleCount: 5
                ),
                SpeakerProfile(
                    id: UUID(), speakerIndex: 1,
                    centroid: makeVector(pitch: 220, energy: 0.7, centroid: 1200),
                    sampleCount: 3
                ),
            ]
        )

        // Chunk 1 has same speakers but indices might be swapped
        let chunk1 = CrossChunkSpeakerAligner.ChunkSpeakers(
            chunkIndex: 1,
            profiles: [
                SpeakerProfile(
                    id: UUID(), speakerIndex: 0,
                    centroid: makeVector(pitch: 225, energy: 0.72, centroid: 1210), // matches global speaker 1
                    sampleCount: 4
                ),
                SpeakerProfile(
                    id: UUID(), speakerIndex: 1,
                    centroid: makeVector(pitch: 118, energy: 0.42, centroid: 610), // matches global speaker 0
                    sampleCount: 4
                ),
            ]
        )

        let result = CrossChunkSpeakerAligner.align(chunkSpeakers: [chunk0, chunk1])

        // Chunk 1's local speaker 0 (high pitch) should map to global speaker 1
        XCTAssertEqual(result.map[1]?[0], 1)
        // Chunk 1's local speaker 1 (low pitch) should map to global speaker 0
        XCTAssertEqual(result.map[1]?[1], 0)
    }

    // MARK: - Unmatched Speaker

    func testUnmatchedSpeakerGetsNewGlobalIndex() {
        let chunk0 = CrossChunkSpeakerAligner.ChunkSpeakers(
            chunkIndex: 0,
            profiles: [
                SpeakerProfile(
                    id: UUID(), speakerIndex: 0,
                    centroid: makeVector(pitch: 120, energy: 0.4, centroid: 600),
                    sampleCount: 5
                ),
            ]
        )

        // Chunk 1 has a very different speaker
        let chunk1 = CrossChunkSpeakerAligner.ChunkSpeakers(
            chunkIndex: 1,
            profiles: [
                SpeakerProfile(
                    id: UUID(), speakerIndex: 0,
                    centroid: makeVector(pitch: 300, energy: 0.9, centroid: 2000),
                    sampleCount: 3
                ),
            ]
        )

        let result = CrossChunkSpeakerAligner.align(chunkSpeakers: [chunk0, chunk1])

        // The new speaker should get a new global index (not 0)
        let globalIdx = result.map[1]?[0]
        XCTAssertNotNil(globalIdx)
        XCTAssertNotEqual(globalIdx, 0)
        XCTAssertEqual(result.globalProfiles.count, 2)
    }

    // MARK: - Helpers

    private func makeVector(
        pitch: Float,
        energy: Float,
        centroid: Float
    ) -> SpeakerFeatureVector {
        SpeakerFeatureVector(
            meanPitch: pitch,
            pitchStdDev: pitch * 0.15,
            meanEnergy: energy,
            meanSpectralCentroid: centroid,
            meanJitter: 0.02,
            meanShimmer: 0.04
        )
    }
}
