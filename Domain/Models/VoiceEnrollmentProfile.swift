import Foundation

/// Identity labels assigned after speaker matching.
enum IdentityLabel: String, Codable, Equatable {
    case me
    case unknown
}

/// Quality metrics captured for one enrollment take.
struct EnrollmentSampleQuality: Codable, Equatable {
    let snrDb: Float
    let speechRatio: Float
    let clippingRatio: Float
    let durationSec: Double
    let accepted: Bool
    let rejectionReasons: [String]
}

/// Aggregated quality stats for a completed enrollment profile.
struct VoiceEnrollmentQualityStats: Codable, Equatable {
    let acceptedSamples: Int
    let averageSnrDb: Float
    let averageSpeechRatio: Float
    let averageClippingRatio: Float
}

/// Persisted voice enrollment profile used for "Me" speaker assignment.
struct VoiceEnrollmentProfile: Codable, Equatable, Identifiable {
    let id: UUID
    let displayName: String
    let referenceEmbedding: SpeakerEmbedding
    let referenceCentroid: SpeakerFeatureVector
    let version: Int
    let isActive: Bool
    let qualityStats: VoiceEnrollmentQualityStats
    let adaptationCount: Int
    let updatedAt: Date
}

/// Result returned by speaker identity matching.
struct SpeakerIdentityMatchResult: Equatable {
    let identity: IdentityLabel
    let distance: Float
    let confidence: Float
    let usedMFCC: Bool
    let decisionReason: String
}

/// Concrete mapping from a global speaker index to an identity result.
struct SpeakerIdentityAssignment: Equatable {
    let globalSpeakerIndex: Int
    let result: SpeakerIdentityMatchResult
}
