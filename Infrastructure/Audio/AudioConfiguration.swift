import Foundation
import AVFAudio

/// Configurable audio recording parameters for balancing quality vs battery.
///
/// The default profile is optimized for voice recording with good battery life.
/// Users can switch profiles to trade quality for longer battery life, or vice versa.
struct AudioConfiguration: Codable, Equatable {

    enum QualityProfile: String, CaseIterable, Identifiable, Codable {
        case low = "low"
        case standard = "standard"
        case high = "high"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .low: return String(localized: "Battery Saver")
            case .standard: return String(localized: "Standard")
            case .high: return String(localized: "High Quality")
            }
        }

        var description: String {
            switch self {
            case .low: return String(localized: "Lower quality, significantly less battery usage")
            case .standard: return String(localized: "Good quality voice recording, balanced battery")
            case .high: return String(localized: "Best quality, higher battery usage")
            }
        }
    }

    let sampleRate: Double
    let channels: Int
    let chunkDurationSeconds: TimeInterval
    let bitRate: Int
    let encoderQualityRawValue: Int

    /// Estimated relative battery impact (1.0 = baseline standard)
    var estimatedBatteryMultiplier: Double {
        let rateMultiplier = sampleRate / 16_000.0
        let channelMultiplier = Double(channels)
        return rateMultiplier * channelMultiplier
    }

    static let low = AudioConfiguration(
        sampleRate: 8_000,
        channels: 1,
        chunkDurationSeconds: 60,
        bitRate: 32_000,
        encoderQualityRawValue: AVAudioQuality.low.rawValue
    )

    static let standard = AudioConfiguration(
        sampleRate: 16_000,
        channels: 1,
        chunkDurationSeconds: 60,
        bitRate: 64_000,
        encoderQualityRawValue: AVAudioQuality.medium.rawValue
    )

    static let high = AudioConfiguration(
        sampleRate: 44_100,
        channels: 1,
        chunkDurationSeconds: 60,
        bitRate: 128_000,
        encoderQualityRawValue: AVAudioQuality.max.rawValue
    )

    static func from(profile: QualityProfile) -> AudioConfiguration {
        switch profile {
        case .low: return .low
        case .standard: return .standard
        case .high: return .high
        }
    }

    // MARK: - UserDefaults Persistence

    private static let storageKey = "audioQualityProfile"

    static func loadProfile() -> QualityProfile {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let profile = QualityProfile(rawValue: raw) else {
            return .standard
        }
        return profile
    }

    static func saveProfile(_ profile: QualityProfile) {
        UserDefaults.standard.set(profile.rawValue, forKey: storageKey)
    }

    static func current() -> AudioConfiguration {
        .from(profile: loadProfile())
    }

    // MARK: - Recorder Config Conversion

    func toRecorderConfig() -> ChunkedAudioRecorder.Config {
        ChunkedAudioRecorder.Config(
            chunkSeconds: chunkDurationSeconds,
            sampleRate: sampleRate,
            channels: channels,
            bitRate: bitRate,
            encoderQualityRawValue: encoderQualityRawValue
        )
    }
}
