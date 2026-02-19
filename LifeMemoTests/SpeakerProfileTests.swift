import XCTest
@testable import LifeMemo

final class SpeakerProfileTests: XCTestCase {

    // MARK: - Merging Tests

    func testMergingUpdatesWeightedCentroid() {
        let original = SpeakerProfile(
            id: UUID(),
            speakerIndex: 0,
            centroid: SpeakerFeatureVector(
                meanPitch: 100, pitchStdDev: 20, meanEnergy: 0.4,
                meanSpectralCentroid: 600, meanJitter: 0.01, meanShimmer: 0.02
            ),
            sampleCount: 3
        )

        let newCentroid = SpeakerFeatureVector(
            meanPitch: 200, pitchStdDev: 40, meanEnergy: 0.8,
            meanSpectralCentroid: 1000, meanJitter: 0.03, meanShimmer: 0.06
        )

        let merged = original.merging(newCentroid: newCentroid, newSampleCount: 1)

        // 3/(3+1) * 100 + 1/(3+1) * 200 = 75 + 50 = 125
        XCTAssertEqual(merged.centroid.meanPitch, 125, accuracy: 0.01)
        XCTAssertEqual(merged.sampleCount, 4)
        XCTAssertEqual(merged.speakerIndex, 0)
        XCTAssertEqual(merged.id, original.id)
    }

    func testMergingWithEqualWeights() {
        let profile = SpeakerProfile(
            id: UUID(),
            speakerIndex: 1,
            centroid: SpeakerFeatureVector(
                meanPitch: 100, pitchStdDev: 20, meanEnergy: 0.4,
                meanSpectralCentroid: 600, meanJitter: 0.01, meanShimmer: 0.02
            ),
            sampleCount: 1
        )

        let newCentroid = SpeakerFeatureVector(
            meanPitch: 200, pitchStdDev: 40, meanEnergy: 0.8,
            meanSpectralCentroid: 1000, meanJitter: 0.03, meanShimmer: 0.06
        )

        let merged = profile.merging(newCentroid: newCentroid, newSampleCount: 1)

        // 1/2 * 100 + 1/2 * 200 = 150
        XCTAssertEqual(merged.centroid.meanPitch, 150, accuracy: 0.01)
        XCTAssertEqual(merged.sampleCount, 2)
    }

    func testMergingWithZeroNewSamples() {
        let profile = SpeakerProfile(
            id: UUID(),
            speakerIndex: 0,
            centroid: SpeakerFeatureVector(
                meanPitch: 150, pitchStdDev: 30, meanEnergy: 0.5,
                meanSpectralCentroid: 800, meanJitter: 0.02, meanShimmer: 0.04
            ),
            sampleCount: 5
        )

        let dummy = SpeakerFeatureVector(
            meanPitch: 0, pitchStdDev: 0, meanEnergy: 0,
            meanSpectralCentroid: 0, meanJitter: 0, meanShimmer: 0
        )

        let merged = profile.merging(newCentroid: dummy, newSampleCount: 0)

        // Original centroid should remain unchanged (5/5 weight)
        XCTAssertEqual(merged.centroid.meanPitch, 150, accuracy: 0.01)
        XCTAssertEqual(merged.sampleCount, 5)
    }

    // MARK: - Codable Round Trip

    func testCodableRoundTrip() throws {
        let profile = SpeakerProfile(
            id: UUID(),
            speakerIndex: 2,
            centroid: SpeakerFeatureVector(
                meanPitch: 175, pitchStdDev: 35, meanEnergy: 0.6,
                meanSpectralCentroid: 900, meanJitter: 0.025, meanShimmer: 0.05
            ),
            sampleCount: 10
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(SpeakerProfile.self, from: data)

        XCTAssertEqual(decoded.id, profile.id)
        XCTAssertEqual(decoded.speakerIndex, profile.speakerIndex)
        XCTAssertEqual(decoded.centroid, profile.centroid)
        XCTAssertEqual(decoded.sampleCount, profile.sampleCount)
    }

    // MARK: - Equatable

    func testEquality() {
        let id = UUID()
        let centroid = SpeakerFeatureVector(
            meanPitch: 150, pitchStdDev: 30, meanEnergy: 0.5,
            meanSpectralCentroid: 800, meanJitter: 0.02, meanShimmer: 0.04
        )
        let a = SpeakerProfile(id: id, speakerIndex: 0, centroid: centroid, sampleCount: 5)
        let b = SpeakerProfile(id: id, speakerIndex: 0, centroid: centroid, sampleCount: 5)
        XCTAssertEqual(a, b)
    }
}
