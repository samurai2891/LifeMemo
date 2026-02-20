import Accelerate
import Foundation

/// Shared utilities for covariance matrix computation and log-determinant calculation.
///
/// Uses LAPACK `spotrf_` (Cholesky decomposition) for numerically stable
/// log-determinant computation required by BIC segmentation.
enum CovarianceUtil {

    /// Computes the covariance matrix of a set of feature frames.
    ///
    /// - Parameter frames: Array of feature vectors, each of dimension `d`.
    /// - Returns: Column-major `d x d` covariance matrix with `1e-6` diagonal regularization.
    static func covarianceMatrix(frames: [[Float]]) -> [Float] {
        guard let first = frames.first else { return [] }
        let d = first.count
        let n = frames.count
        guard d > 0, n > 1 else {
            // Return identity-like matrix with regularization
            var result = [Float](repeating: 0, count: d * d)
            for i in 0..<d { result[i * d + i] = 1e-6 }
            return result
        }

        // Compute means
        var means = [Float](repeating: 0, count: d)
        for frame in frames {
            for j in 0..<d {
                means[j] += frame[j]
            }
        }
        let invN = 1.0 / Float(n)
        for j in 0..<d {
            means[j] *= invN
        }

        // Compute covariance (column-major for LAPACK compatibility)
        var cov = [Float](repeating: 0, count: d * d)
        for frame in frames {
            for i in 0..<d {
                let di = frame[i] - means[i]
                for j in i..<d {
                    let dj = frame[j] - means[j]
                    // Column-major: element (i, j) is at index j * d + i
                    cov[j * d + i] += di * dj
                }
            }
        }

        let invNm1 = 1.0 / Float(n - 1)
        for i in 0..<d {
            for j in i..<d {
                cov[j * d + i] *= invNm1
                if i != j {
                    cov[i * d + j] = cov[j * d + i] // Symmetric
                }
            }
        }

        // Regularization: add 1e-6 to diagonal
        for i in 0..<d {
            cov[i * d + i] += 1e-6
        }

        return cov
    }

    /// Computes the log-determinant of a symmetric positive-definite matrix
    /// using Cholesky decomposition (LAPACK `spotrf_`).
    ///
    /// - Parameters:
    ///   - matrix: Column-major `d x d` matrix.
    ///   - dimension: The dimension `d`.
    /// - Returns: `log(det(matrix))`, or `-Float.infinity` if decomposition fails.
    static func logDeterminant(matrix: [Float], dimension: Int) -> Float {
        guard dimension > 0, matrix.count == dimension * dimension else { return -.infinity }

        var work = matrix
        var n = Int32(dimension)
        var lda = Int32(dimension)
        var info: Int32 = 0
        var uplo: Int8 = Int8(UnicodeScalar("L").value)

        // Cholesky decomposition: A = L * L^T
        spotrf_(&uplo, &n, &work, &lda, &info)

        guard info == 0 else { return -.infinity }

        // log(det) = 2 * sum(log(diag(L)))
        var logDet: Float = 0
        for i in 0..<dimension {
            let diag = work[i * dimension + i]
            guard diag > 0 else { return -.infinity }
            logDet += logf(diag)
        }

        return 2 * logDet
    }
}
