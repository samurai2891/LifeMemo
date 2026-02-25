import XCTest
@testable import LifeMemo

final class AHCClustererTests: XCTestCase {

    // MARK: - Single Embedding

    func testSingleEmbeddingReturnsSingleCluster() {
        let emb = makeEmbedding(seed: 1)
        let result = AHCClusterer.cluster(embeddings: [emb])

        XCTAssertEqual(result.numClusters, 1)
        XCTAssertEqual(result.labels, [0])
    }

    // MARK: - Empty Input

    func testEmptyInputReturnsEmpty() {
        let result = AHCClusterer.cluster(embeddings: [])
        XCTAssertEqual(result.numClusters, 0)
        XCTAssertTrue(result.labels.isEmpty)
    }

    // MARK: - Two Distinct Clusters

    func testTwoDistinctClustersDetected() {
        // Group A: embeddings centered around one direction
        let groupA = (0..<5).map { _ in makeDirectionalEmbedding(direction: 0) }
        // Group B: embeddings centered around opposite direction
        let groupB = (0..<5).map { _ in makeDirectionalEmbedding(direction: 1) }

        let all = groupA + groupB
        let result = AHCClusterer.cluster(embeddings: all)

        XCTAssertEqual(result.numClusters, 2, "Should detect 2 distinct clusters")
        XCTAssertEqual(result.labels.count, 10)

        // All group A should have same label
        let groupALabels = Set(result.labels[0..<5])
        XCTAssertEqual(groupALabels.count, 1, "Group A should have uniform labels")

        // All group B should have same label
        let groupBLabels = Set(result.labels[5..<10])
        XCTAssertEqual(groupBLabels.count, 1, "Group B should have uniform labels")

        // Groups should have different labels
        XCTAssertNotEqual(groupALabels.first, groupBLabels.first,
            "Groups should have different cluster labels")
    }

    // MARK: - Very Similar Embeddings → Single Cluster

    func testSimilarEmbeddingsMergeToOne() {
        // All embeddings very similar (same direction, tiny perturbation)
        let embeddings = (0..<5).map { i -> SpeakerEmbedding in
            var values = [Float](repeating: 0, count: 130)
            values[0] = 1.0
            values[1] = Float(i) * 0.001  // Tiny variation
            return SpeakerEmbedding(values: values)
        }

        let result = AHCClusterer.cluster(embeddings: embeddings)
        XCTAssertEqual(result.numClusters, 1, "Very similar embeddings should form 1 cluster")
    }

    // MARK: - Three Clusters

    func testThreeDistinctClusters() {
        let group1 = (0..<3).map { _ in makeDirectionalEmbedding(direction: 0) }
        let group2 = (0..<3).map { _ in makeDirectionalEmbedding(direction: 1) }
        let group3 = (0..<3).map { _ in makeDirectionalEmbedding(direction: 2) }

        let all = group1 + group2 + group3
        let result = AHCClusterer.cluster(embeddings: all)

        XCTAssertGreaterThanOrEqual(result.numClusters, 2, "Should detect at least 2 clusters")
        XCTAssertLessThanOrEqual(result.numClusters, 3, "Should detect at most 3 clusters")
    }

    // MARK: - Labels Are Contiguous

    func testLabelsAreContiguous() {
        let embs = (0..<6).map { i in makeDirectionalEmbedding(direction: i % 2) }
        let result = AHCClusterer.cluster(embeddings: embs)

        let uniqueLabels = Set(result.labels).sorted()
        let expected = Array(0..<result.numClusters)
        XCTAssertEqual(uniqueLabels, expected, "Labels should be 0-indexed and contiguous")
    }

    // MARK: - Max Cluster Cap

    func testClusterCountDoesNotExceedConfiguredCap() {
        // Build 12 highly separated embeddings so distance-threshold alone
        // would otherwise keep many singleton clusters.
        let embeddings = (0..<12).map { i -> SpeakerEmbedding in
            var values = [Float](repeating: 0, count: 130)
            values[i] = 1.0
            return SpeakerEmbedding(values: values)
        }

        let result = AHCClusterer.cluster(embeddings: embeddings)

        XCTAssertLessThanOrEqual(
            result.numClusters,
            AHCClusterer.maxClusters,
            "Cluster count should be capped by maxClusters"
        )
        XCTAssertEqual(result.labels.count, embeddings.count)
    }

    // MARK: - Helpers

    private func makeEmbedding(seed: Int) -> SpeakerEmbedding {
        var values = [Float](repeating: 0, count: 130)
        for i in 0..<130 {
            values[i] = Float((seed * 131 + i * 7) % 1000) / 1000.0
        }
        return SpeakerEmbedding(values: values)
    }

    /// Creates an embedding pointing primarily in one of several orthogonal directions.
    private func makeDirectionalEmbedding(direction: Int) -> SpeakerEmbedding {
        var values = [Float](repeating: 0, count: 130)
        // Set a block of dimensions to high values based on direction
        let blockSize = 30
        let start = (direction * blockSize) % 130
        let end = min(start + blockSize, 130)
        for i in start..<end {
            values[i] = 1.0
        }
        return SpeakerEmbedding(values: values)
    }
}
