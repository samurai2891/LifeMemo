import XCTest
@testable import LifeMemo

final class SpeakerEmbeddingTests: XCTestCase {

    // MARK: - L2 Normalization

    func testInitializationNormalizesValues() {
        let raw = [Float](repeating: 2.0, count: 130)
        let embedding = SpeakerEmbedding(values: raw)

        let norm = sqrtf(embedding.values.reduce(0) { $0 + $1 * $1 })
        XCTAssertEqual(norm, 1.0, accuracy: 1e-4)
    }

    func testPreNormalizedSkipsNormalization() {
        var values = [Float](repeating: 0, count: 130)
        values[0] = 0.5
        values[1] = 0.5

        let embedding = SpeakerEmbedding(preNormalized: values)
        XCTAssertEqual(embedding.values[0], 0.5)
        XCTAssertEqual(embedding.values[1], 0.5)
    }

    func testZeroValuesDoNotCrash() {
        let embedding = SpeakerEmbedding(values: [Float](repeating: 0, count: 130))
        // Should handle gracefully (all zeros remain)
        XCTAssertEqual(embedding.values.count, 130)
    }

    // MARK: - Cosine Similarity

    func testSelfSimilarityIsOne() {
        let embedding = SpeakerEmbedding(values: makeValues(seed: 1))
        let sim = embedding.cosineSimilarity(to: embedding)
        XCTAssertEqual(sim, 1.0, accuracy: 1e-4)
    }

    func testSimilaritySymmetric() {
        let a = SpeakerEmbedding(values: makeValues(seed: 1))
        let b = SpeakerEmbedding(values: makeValues(seed: 2))
        XCTAssertEqual(
            a.cosineSimilarity(to: b),
            b.cosineSimilarity(to: a),
            accuracy: 1e-6
        )
    }

    func testOrthogonalEmbeddingsHaveZeroSimilarity() {
        var valuesA = [Float](repeating: 0, count: 130)
        valuesA[0] = 1.0
        var valuesB = [Float](repeating: 0, count: 130)
        valuesB[1] = 1.0

        let a = SpeakerEmbedding(values: valuesA)
        let b = SpeakerEmbedding(values: valuesB)

        XCTAssertEqual(a.cosineSimilarity(to: b), 0.0, accuracy: 1e-4)
    }

    // MARK: - Cosine Distance

    func testSelfDistanceIsZero() {
        let embedding = SpeakerEmbedding(values: makeValues(seed: 3))
        XCTAssertEqual(embedding.cosineDistance(to: embedding), 0, accuracy: 1e-4)
    }

    func testOrthogonalDistanceIsOne() {
        var valuesA = [Float](repeating: 0, count: 130)
        valuesA[0] = 1.0
        var valuesB = [Float](repeating: 0, count: 130)
        valuesB[1] = 1.0

        let a = SpeakerEmbedding(values: valuesA)
        let b = SpeakerEmbedding(values: valuesB)

        XCTAssertEqual(a.cosineDistance(to: b), 1.0, accuracy: 1e-4)
    }

    // MARK: - Centroid

    func testCentroidOfSingleEmbedding() {
        let emb = SpeakerEmbedding(values: makeValues(seed: 5))
        let centroid = SpeakerEmbedding.centroid(of: [emb])

        XCTAssertNotNil(centroid)
        // Centroid of single embedding = that embedding (re-normalized)
        let sim = emb.cosineSimilarity(to: centroid!)
        XCTAssertEqual(sim, 1.0, accuracy: 1e-3)
    }

    func testCentroidOfEmptyIsNil() {
        XCTAssertNil(SpeakerEmbedding.centroid(of: []))
    }

    func testCentroidOfIdenticalEmbeddings() {
        let emb = SpeakerEmbedding(values: makeValues(seed: 7))
        let centroid = SpeakerEmbedding.centroid(of: [emb, emb, emb])

        XCTAssertNotNil(centroid)
        let sim = emb.cosineSimilarity(to: centroid!)
        XCTAssertEqual(sim, 1.0, accuracy: 1e-3)
    }

    // MARK: - Codable Round Trip

    func testCodableRoundTrip() throws {
        let original = SpeakerEmbedding(values: makeValues(seed: 10))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpeakerEmbedding.self, from: data)

        XCTAssertEqual(original.values.count, decoded.values.count)
        for i in 0..<original.values.count {
            XCTAssertEqual(original.values[i], decoded.values[i], accuracy: 1e-6)
        }
    }

    // MARK: - Equatable

    func testEquatable() {
        let a = SpeakerEmbedding(values: makeValues(seed: 1))
        let b = SpeakerEmbedding(values: makeValues(seed: 1))
        XCTAssertEqual(a, b)
    }

    // MARK: - Helpers

    private func makeValues(seed: Int) -> [Float] {
        (0..<130).map { i in
            Float((seed * 131 + i * 7) % 1000) / 1000.0
        }
    }
}
