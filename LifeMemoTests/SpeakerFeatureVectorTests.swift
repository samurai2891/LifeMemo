import XCTest
@testable import LifeMemo

final class SpeakerFeatureVectorTests: XCTestCase {

    // MARK: - Distance Tests

    func testDistanceToSelfIsZero() {
        let vector = SpeakerFeatureVector(
            meanPitch: 150, pitchStdDev: 30, meanEnergy: 0.5,
            meanSpectralCentroid: 800, meanJitter: 0.02, meanShimmer: 0.04
        )
        XCTAssertEqual(vector.distance(to: vector), 0, accuracy: 0.001)
    }

    func testDistanceIsSymmetric() {
        let a = SpeakerFeatureVector(
            meanPitch: 120, pitchStdDev: 25, meanEnergy: 0.4,
            meanSpectralCentroid: 700, meanJitter: 0.01, meanShimmer: 0.03
        )
        let b = SpeakerFeatureVector(
            meanPitch: 200, pitchStdDev: 40, meanEnergy: 0.7,
            meanSpectralCentroid: 1200, meanJitter: 0.04, meanShimmer: 0.08
        )
        XCTAssertEqual(a.distance(to: b), b.distance(to: a), accuracy: 0.001)
    }

    func testDistanceIncreasesWithDifference() {
        let base = SpeakerFeatureVector(
            meanPitch: 150, pitchStdDev: 30, meanEnergy: 0.5,
            meanSpectralCentroid: 800, meanJitter: 0.02, meanShimmer: 0.04
        )
        let similar = SpeakerFeatureVector(
            meanPitch: 155, pitchStdDev: 32, meanEnergy: 0.52,
            meanSpectralCentroid: 810, meanJitter: 0.021, meanShimmer: 0.041
        )
        let different = SpeakerFeatureVector(
            meanPitch: 250, pitchStdDev: 60, meanEnergy: 0.9,
            meanSpectralCentroid: 1500, meanJitter: 0.06, meanShimmer: 0.09
        )

        let distSimilar = base.distance(to: similar)
        let distDifferent = base.distance(to: different)
        XCTAssertLessThan(distSimilar, distDifferent)
    }

    func testDistanceWeightsApplied() {
        // Only pitch differs — weighted at 2.0
        let a = SpeakerFeatureVector(
            meanPitch: 100, pitchStdDev: 30, meanEnergy: 0.5,
            meanSpectralCentroid: 800, meanJitter: 0.02, meanShimmer: 0.04
        )
        let b = SpeakerFeatureVector(
            meanPitch: 250, pitchStdDev: 30, meanEnergy: 0.5,
            meanSpectralCentroid: 800, meanJitter: 0.02, meanShimmer: 0.04
        )
        let dist = a.distance(to: b)
        XCTAssertGreaterThan(dist, 0)
    }

    // MARK: - Centroid Tests

    func testCentroidOfEmptyArrayIsNil() {
        XCTAssertNil(SpeakerFeatureVector.centroid(of: []))
    }

    func testCentroidOfSingleElementIsSameElement() {
        let vector = SpeakerFeatureVector(
            meanPitch: 150, pitchStdDev: 30, meanEnergy: 0.5,
            meanSpectralCentroid: 800, meanJitter: 0.02, meanShimmer: 0.04
        )
        let centroid = SpeakerFeatureVector.centroid(of: [vector])
        XCTAssertEqual(centroid, vector)
    }

    func testCentroidAveragesCorrectly() {
        let a = SpeakerFeatureVector(
            meanPitch: 100, pitchStdDev: 20, meanEnergy: 0.4,
            meanSpectralCentroid: 600, meanJitter: 0.01, meanShimmer: 0.02
        )
        let b = SpeakerFeatureVector(
            meanPitch: 200, pitchStdDev: 40, meanEnergy: 0.8,
            meanSpectralCentroid: 1000, meanJitter: 0.03, meanShimmer: 0.06
        )
        let centroid = SpeakerFeatureVector.centroid(of: [a, b])!

        XCTAssertEqual(centroid.meanPitch, 150, accuracy: 0.001)
        XCTAssertEqual(centroid.pitchStdDev, 30, accuracy: 0.001)
        XCTAssertEqual(centroid.meanEnergy, 0.6, accuracy: 0.001)
        XCTAssertEqual(centroid.meanSpectralCentroid, 800, accuracy: 0.001)
        XCTAssertEqual(centroid.meanJitter, 0.02, accuracy: 0.001)
        XCTAssertEqual(centroid.meanShimmer, 0.04, accuracy: 0.001)
    }

    // MARK: - Codable Tests

    func testCodableRoundTrip() throws {
        let vector = SpeakerFeatureVector(
            meanPitch: 175.5, pitchStdDev: 35.2, meanEnergy: 0.65,
            meanSpectralCentroid: 950.3, meanJitter: 0.025, meanShimmer: 0.045
        )
        let data = try JSONEncoder().encode(vector)
        let decoded = try JSONDecoder().decode(SpeakerFeatureVector.self, from: data)
        XCTAssertEqual(vector, decoded)
    }

    // MARK: - asArray Tests

    func testAsArrayOrder() {
        let vector = SpeakerFeatureVector(
            meanPitch: 1, pitchStdDev: 2, meanEnergy: 3,
            meanSpectralCentroid: 4, meanJitter: 5, meanShimmer: 6
        )
        XCTAssertEqual(vector.asArray, [1, 2, 3, 4, 5, 6])
    }
}
