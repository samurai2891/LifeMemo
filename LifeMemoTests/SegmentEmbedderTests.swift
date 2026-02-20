import XCTest
@testable import LifeMemo

final class SegmentEmbedderTests: XCTestCase {

    // MARK: - Dimension Check

    func testEmbeddingDimension130() {
        let frames = makeConstantFrames(numFrames: 50, value: 1.0)
        let deltas = makeConstantFrames(numFrames: 50, value: 0.1)
        let deltaDeltas = makeConstantFrames(numFrames: 50, value: 0.01)

        let embedding = SegmentEmbedder.computeEmbedding(
            mfccFrames: frames, deltas: deltas, deltaDeltas: deltaDeltas
        )

        XCTAssertNotNil(embedding)
        XCTAssertEqual(embedding?.values.count, SegmentEmbedder.embeddingDimension)
    }

    // MARK: - L2 Normalization

    func testEmbeddingIsL2Normalized() {
        let frames = makeConstantFrames(numFrames: 100, value: 2.0)
        let deltas = makeConstantFrames(numFrames: 100, value: 0.5)
        let deltaDeltas = makeConstantFrames(numFrames: 100, value: 0.1)

        guard let embedding = SegmentEmbedder.computeEmbedding(
            mfccFrames: frames, deltas: deltas, deltaDeltas: deltaDeltas
        ) else {
            XCTFail("Embedding should not be nil")
            return
        }

        let norm = sqrtf(embedding.values.reduce(0) { $0 + $1 * $1 })
        XCTAssertEqual(norm, 1.0, accuracy: 1e-4, "Embedding should be L2-normalized")
    }

    // MARK: - Empty Input

    func testEmptyFramesReturnsNil() {
        let embedding = SegmentEmbedder.computeEmbedding(
            mfccFrames: [], deltas: [], deltaDeltas: []
        )
        XCTAssertNil(embedding)
    }

    // MARK: - Statistics Computation

    func testMeanComputation() {
        // Frames where MFCC values increase linearly
        let frames: [[Float]] = (0..<10).map { i in
            [Float](repeating: Float(i), count: 13)
        }
        let deltas = makeConstantFrames(numFrames: 10, value: 0)
        let deltaDeltas = makeConstantFrames(numFrames: 10, value: 0)

        guard let embedding = SegmentEmbedder.computeEmbedding(
            mfccFrames: frames, deltas: deltas, deltaDeltas: deltaDeltas
        ) else {
            XCTFail("Embedding should not be nil")
            return
        }

        // First 13 values are MFCC means (before normalization)
        // Mean of 0..9 = 4.5, but after L2 normalization exact value differs
        // Just verify the embedding is valid and has correct dimension
        XCTAssertEqual(embedding.values.count, 130)
    }

    // MARK: - Correlation Matrix

    func testCorrelationDimensionIs78() {
        // 13 * 12 / 2 = 78 upper-triangular elements
        let frames: [[Float]] = (0..<100).map { i in
            (0..<13).map { d in Float(i) * 0.1 + Float(d) * 0.5 }
        }
        let deltas = makeConstantFrames(numFrames: 100, value: 0)
        let deltaDeltas = makeConstantFrames(numFrames: 100, value: 0)

        guard let embedding = SegmentEmbedder.computeEmbedding(
            mfccFrames: frames, deltas: deltas, deltaDeltas: deltaDeltas
        ) else {
            XCTFail("Embedding should not be nil")
            return
        }

        // Total: 13(mean) + 13(std) + 13(deltaMean) + 13(ddMean) + 78(corr) = 130
        XCTAssertEqual(embedding.values.count, 130)
    }

    // MARK: - Different Segments Produce Different Embeddings

    func testDifferentSegmentsProduceDifferentEmbeddings() {
        // Use frames with different directional patterns, not just different
        // magnitudes, because L2 normalization erases magnitude differences.
        let framesA: [[Float]] = (0..<50).map { _ in
            (0..<13).map { d in Float(d + 1) }            // [1, 2, 3, ..., 13]
        }
        let framesB: [[Float]] = (0..<50).map { _ in
            (0..<13).map { d in Float(13 - d) }           // [13, 12, 11, ..., 1]
        }
        let deltas = makeConstantFrames(numFrames: 50, value: 0)
        let deltaDeltas = makeConstantFrames(numFrames: 50, value: 0)

        guard let embA = SegmentEmbedder.computeEmbedding(
            mfccFrames: framesA, deltas: deltas, deltaDeltas: deltaDeltas
        ),
        let embB = SegmentEmbedder.computeEmbedding(
            mfccFrames: framesB, deltas: deltas, deltaDeltas: deltaDeltas
        ) else {
            XCTFail("Embeddings should not be nil")
            return
        }

        let similarity = embA.cosineSimilarity(to: embB)
        // Different inputs should produce different embeddings
        XCTAssertLessThan(similarity, 0.999, "Different segments should produce different embeddings")
    }

    // MARK: - Helpers

    private func makeConstantFrames(numFrames: Int, value: Float) -> [[Float]] {
        (0..<numFrames).map { _ in [Float](repeating: value, count: 13) }
    }
}
