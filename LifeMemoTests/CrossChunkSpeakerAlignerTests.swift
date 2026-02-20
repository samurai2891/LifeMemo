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
            makeProfile(speakerIndex: 0, pitch: 120, energy: 0.4, centroid: 600),
            makeProfile(speakerIndex: 1, pitch: 220, energy: 0.7, centroid: 1200),
        ]

        let chunk = CrossChunkSpeakerAligner.ChunkSpeakers(chunkIndex: 0, profiles: profiles)
        let result = CrossChunkSpeakerAligner.align(chunkSpeakers: [chunk])

        XCTAssertEqual(result.map[0]?[0], 0)
        XCTAssertEqual(result.map[0]?[1], 1)
        XCTAssertEqual(result.globalProfiles.count, 2)
    }

    // MARK: - Two Chunks Alignment (Legacy Centroid)

    func testTwoChunksMatchingSpeakersLegacy() {
        let chunk0 = CrossChunkSpeakerAligner.ChunkSpeakers(
            chunkIndex: 0,
            profiles: [
                makeProfile(speakerIndex: 0, pitch: 120, energy: 0.4, centroid: 600),
                makeProfile(speakerIndex: 1, pitch: 220, energy: 0.7, centroid: 1200),
            ]
        )

        // Chunk 1 has same speakers but indices swapped
        let chunk1 = CrossChunkSpeakerAligner.ChunkSpeakers(
            chunkIndex: 1,
            profiles: [
                makeProfile(speakerIndex: 0, pitch: 225, energy: 0.72, centroid: 1210),
                makeProfile(speakerIndex: 1, pitch: 118, energy: 0.42, centroid: 610),
            ]
        )

        let result = CrossChunkSpeakerAligner.align(chunkSpeakers: [chunk0, chunk1])

        XCTAssertEqual(result.map[1]?[0], 1)
        XCTAssertEqual(result.map[1]?[1], 0)
    }

    // MARK: - Two Chunks Alignment (MFCC Embedding)

    func testTwoChunksMatchingSpeakersMFCC() {
        let embA = makeDirectionalEmbedding(direction: 0)
        let embB = makeDirectionalEmbedding(direction: 1)

        let chunk0 = CrossChunkSpeakerAligner.ChunkSpeakers(
            chunkIndex: 0,
            profiles: [
                makeProfileWithMFCC(speakerIndex: 0, embedding: embA),
                makeProfileWithMFCC(speakerIndex: 1, embedding: embB),
            ]
        )

        // Chunk 1 has same speakers but indices swapped
        let chunk1 = CrossChunkSpeakerAligner.ChunkSpeakers(
            chunkIndex: 1,
            profiles: [
                makeProfileWithMFCC(speakerIndex: 0, embedding: embB), // matches global 1
                makeProfileWithMFCC(speakerIndex: 1, embedding: embA), // matches global 0
            ]
        )

        let result = CrossChunkSpeakerAligner.align(chunkSpeakers: [chunk0, chunk1])

        XCTAssertEqual(result.map[1]?[0], 1, "Local 0 (embB) should map to global 1")
        XCTAssertEqual(result.map[1]?[1], 0, "Local 1 (embA) should map to global 0")
    }

    // MARK: - Unmatched Speaker

    func testUnmatchedSpeakerGetsNewGlobalIndex() {
        let embA = makeDirectionalEmbedding(direction: 0)
        let embC = makeDirectionalEmbedding(direction: 2) // Very different

        let chunk0 = CrossChunkSpeakerAligner.ChunkSpeakers(
            chunkIndex: 0,
            profiles: [
                makeProfileWithMFCC(speakerIndex: 0, embedding: embA),
            ]
        )

        let chunk1 = CrossChunkSpeakerAligner.ChunkSpeakers(
            chunkIndex: 1,
            profiles: [
                makeProfileWithMFCC(speakerIndex: 0, embedding: embC),
            ]
        )

        let result = CrossChunkSpeakerAligner.align(chunkSpeakers: [chunk0, chunk1])

        let globalIdx = result.map[1]?[0]
        XCTAssertNotNil(globalIdx)
        XCTAssertNotEqual(globalIdx, 0, "New speaker should get a new global index")
        XCTAssertEqual(result.globalProfiles.count, 2)
    }

    // MARK: - MFCC Embedding Preserved in Global Profiles

    func testGlobalProfilesPreserveMFCCEmbedding() {
        let emb = makeDirectionalEmbedding(direction: 0)
        let chunk = CrossChunkSpeakerAligner.ChunkSpeakers(
            chunkIndex: 0,
            profiles: [makeProfileWithMFCC(speakerIndex: 0, embedding: emb)]
        )

        let result = CrossChunkSpeakerAligner.align(chunkSpeakers: [chunk])
        XCTAssertNotNil(result.globalProfiles.first?.mfccEmbedding)
    }

    // MARK: - Backward Compatibility: No MFCC Falls Back to Centroid

    func testFallbackToCentroidWhenNoMFCC() {
        let chunk0 = CrossChunkSpeakerAligner.ChunkSpeakers(
            chunkIndex: 0,
            profiles: [makeProfile(speakerIndex: 0, pitch: 120, energy: 0.4, centroid: 600)]
        )

        let chunk1 = CrossChunkSpeakerAligner.ChunkSpeakers(
            chunkIndex: 1,
            profiles: [makeProfile(speakerIndex: 0, pitch: 122, energy: 0.42, centroid: 610)]
        )

        let result = CrossChunkSpeakerAligner.align(chunkSpeakers: [chunk0, chunk1])

        // Should match using legacy centroid distance
        XCTAssertEqual(result.map[1]?[0], 0, "Similar centroid should match to global 0")
    }

    // MARK: - Helpers

    private func makeProfile(
        speakerIndex: Int,
        pitch: Float,
        energy: Float,
        centroid: Float
    ) -> SpeakerProfile {
        SpeakerProfile(
            id: UUID(),
            speakerIndex: speakerIndex,
            centroid: SpeakerFeatureVector(
                meanPitch: pitch,
                pitchStdDev: pitch * 0.15,
                meanEnergy: energy,
                meanSpectralCentroid: centroid,
                meanJitter: 0.02,
                meanShimmer: 0.04
            ),
            sampleCount: 5
        )
    }

    private func makeProfileWithMFCC(
        speakerIndex: Int,
        embedding: SpeakerEmbedding
    ) -> SpeakerProfile {
        SpeakerProfile(
            id: UUID(),
            speakerIndex: speakerIndex,
            centroid: SpeakerFeatureVector(
                meanPitch: 0, pitchStdDev: 0, meanEnergy: 0,
                meanSpectralCentroid: 0, meanJitter: 0, meanShimmer: 0
            ),
            sampleCount: 5,
            mfccEmbedding: embedding
        )
    }

    private func makeDirectionalEmbedding(direction: Int) -> SpeakerEmbedding {
        var values = [Float](repeating: 0, count: 130)
        let blockSize = 30
        let start = (direction * blockSize) % 130
        let end = min(start + blockSize, 130)
        for i in start..<end {
            values[i] = 1.0
        }
        return SpeakerEmbedding(values: values)
    }
}
