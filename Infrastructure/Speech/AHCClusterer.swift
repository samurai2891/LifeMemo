import Accelerate
import Foundation

/// Agglomerative Hierarchical Clustering (AHC) with average linkage.
///
/// Clusters speaker segment embeddings by iteratively merging the closest pair
/// until a stopping criterion is met (BIC-based or distance threshold).
///
/// ## Stopping Criteria
/// 1. While cluster count is above `maxClusters`, merging continues regardless of distance.
/// 2. Once cluster count is `<= maxClusters`, stop when minimum cosine distance
///    exceeds `maxDistanceThreshold`.
enum AHCClusterer {

    /// Result of hierarchical clustering.
    struct ClusterResult: Equatable {
        let labels: [Int]     // Cluster label per input embedding
        let numClusters: Int
    }

    // MARK: - Configuration

    /// Maximum cosine distance threshold for merging (higher = more aggressive merging).
    static let maxDistanceThreshold: Float = 0.6

    /// Upper bound on number of clusters.
    static let maxClusters = 10

    // MARK: - Public API

    /// Clusters speaker embeddings using agglomerative hierarchical clustering.
    ///
    /// - Parameter embeddings: L2-normalized speaker embeddings.
    /// - Returns: Cluster labels (0-indexed, contiguous) and total cluster count.
    static func cluster(embeddings: [SpeakerEmbedding]) -> ClusterResult {
        let n = embeddings.count
        let targetClusters = max(1, maxClusters)

        guard n > 1 else {
            return ClusterResult(labels: n == 1 ? [0] : [], numClusters: n)
        }

        // Initialize: each embedding is its own cluster
        var clusterMembers: [[Int]] = (0..<n).map { [$0] }
        var activeClusters = Set(0..<n)

        // Compute initial cosine distance matrix (upper triangle)
        var distanceMatrix = [Float](repeating: Float.infinity, count: n * n)
        for i in 0..<n {
            distanceMatrix[i * n + i] = 0
            for j in (i + 1)..<n {
                let dist = embeddings[i].cosineDistance(to: embeddings[j])
                distanceMatrix[i * n + j] = dist
                distanceMatrix[j * n + i] = dist
            }
        }

        // Merge loop
        while activeClusters.count > 1 {
            // Find minimum distance pair among active clusters
            var minDist: Float = .infinity
            var mergeI = -1
            var mergeJ = -1

            let sorted = activeClusters.sorted()
            for (ai, i) in sorted.enumerated() {
                for j in sorted[(ai + 1)...] {
                    if distanceMatrix[i * n + j] < minDist {
                        minDist = distanceMatrix[i * n + j]
                        mergeI = i
                        mergeJ = j
                    }
                }
            }

            // Check stopping criteria
            guard mergeI >= 0 else { break }
            // Enforce the cluster cap first; only apply distance threshold
            // once we are already at or below the cap.
            if activeClusters.count <= targetClusters, minDist > maxDistanceThreshold {
                break
            }
            if activeClusters.count <= 1 { break }

            // Merge cluster j into cluster i
            let membersI = clusterMembers[mergeI]
            let membersJ = clusterMembers[mergeJ]
            let mergedMembers = membersI + membersJ

            clusterMembers[mergeI] = mergedMembers
            activeClusters.remove(mergeJ)

            // Update distances using average linkage
            let sizeI = Float(membersI.count)
            let sizeJ = Float(membersJ.count)
            let totalSize = sizeI + sizeJ

            for k in activeClusters where k != mergeI {
                let distIK = distanceMatrix[mergeI * n + k]
                let distJK = distanceMatrix[mergeJ * n + k]

                // Average linkage: weighted average of distances
                let newDist = (sizeI * distIK + sizeJ * distJK) / totalSize
                distanceMatrix[mergeI * n + k] = newDist
                distanceMatrix[k * n + mergeI] = newDist
            }

        }

        // Build labels array
        var labels = [Int](repeating: 0, count: n)
        let finalClusters = activeClusters.sorted()

        for (clusterLabel, clusterIdx) in finalClusters.enumerated() {
            for memberIdx in clusterMembers[clusterIdx] {
                labels[memberIdx] = clusterLabel
            }
        }

        return ClusterResult(labels: labels, numClusters: finalClusters.count)
    }
}
