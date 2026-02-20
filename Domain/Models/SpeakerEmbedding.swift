import Accelerate
import Foundation

/// 130-dimensional speaker embedding derived from MFCC statistics.
///
/// All embeddings are L2-normalized at creation time, enabling fast cosine
/// similarity computation via a simple dot product.
struct SpeakerEmbedding: Codable, Equatable {

    /// L2-normalized 130-dimensional feature vector.
    let values: [Float]

    /// Creates an embedding and L2-normalizes it.
    ///
    /// Dimension breakdown (130 total):
    /// - 13 MFCC means
    /// - 13 MFCC standard deviations
    /// - 13 delta means
    /// - 13 delta-delta means
    /// - 78 upper-triangular correlation coefficients (13 choose 2)
    init(values: [Float]) {
        var normalized = values
        var norm: Float = 0
        vDSP_svesq(normalized, 1, &norm, vDSP_Length(normalized.count))
        norm = sqrt(norm)
        if norm > 1e-10 {
            var divisor = norm
            vDSP_vsdiv(normalized, 1, &divisor, &normalized, 1, vDSP_Length(normalized.count))
        }
        self.values = normalized
    }

    /// Creates an embedding from pre-normalized values (skips normalization).
    init(preNormalized values: [Float]) {
        self.values = values
    }

    /// Cosine similarity to another embedding (dot product of L2-normalized vectors).
    func cosineSimilarity(to other: SpeakerEmbedding) -> Float {
        guard values.count == other.values.count, !values.isEmpty else { return 0 }
        var result: Float = 0
        vDSP_dotpr(values, 1, other.values, 1, &result, vDSP_Length(values.count))
        return result
    }

    /// Cosine distance = 1 - cosineSimilarity.
    func cosineDistance(to other: SpeakerEmbedding) -> Float {
        1 - cosineSimilarity(to: other)
    }

    /// Computes the centroid (mean then re-normalize) of multiple embeddings.
    static func centroid(of embeddings: [SpeakerEmbedding]) -> SpeakerEmbedding? {
        guard let first = embeddings.first else { return nil }
        let dim = first.values.count
        guard dim > 0 else { return nil }

        var sum = [Float](repeating: 0, count: dim)
        for emb in embeddings {
            guard emb.values.count == dim else { continue }
            vDSP_vadd(sum, 1, emb.values, 1, &sum, 1, vDSP_Length(dim))
        }

        var count = Float(embeddings.count)
        vDSP_vsdiv(sum, 1, &count, &sum, 1, vDSP_Length(dim))

        return SpeakerEmbedding(values: sum)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case values
    }
}
