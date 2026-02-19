import Foundation

/// Controls whether speech recognition uses on-device processing only
/// or allows server-based processing for higher accuracy.
enum RecognitionMode: String, CaseIterable, Identifiable, Codable {
    /// Privacy-first: all recognition happens on-device. No audio sent to servers.
    case onDevice = "onDevice"
    /// Quality-first: allows server recognition when available for better accuracy,
    /// especially with mixed languages. Falls back to on-device when offline.
    case serverAllowed = "serverAllowed"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onDevice: return "On-Device (Privacy)"
        case .serverAllowed: return "Server Allowed (Quality)"
        }
    }

    var description: String {
        switch self {
        case .onDevice:
            return "Audio never leaves the device. Best for privacy."
        case .serverAllowed:
            return "Better accuracy for mixed languages. Audio may be sent to Apple."
        }
    }

    var requiresOnDevice: Bool {
        self == .onDevice
    }

    // MARK: - UserDefaults

    private static let key = "recognitionMode"

    static func load(defaults: UserDefaults = .standard) -> RecognitionMode {
        let raw = defaults.string(forKey: key) ?? "onDevice"
        return RecognitionMode(rawValue: raw) ?? .onDevice
    }

    static func save(_ mode: RecognitionMode, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: key)
    }
}
