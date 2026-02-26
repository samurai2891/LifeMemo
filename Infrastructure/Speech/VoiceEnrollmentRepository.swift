import Foundation

/// Storage abstraction for voice enrollment profiles.
protocol VoiceEnrollmentProfileStoring: AnyObject {
    func activeProfile() -> VoiceEnrollmentProfile?
    func saveActiveProfile(_ profile: VoiceEnrollmentProfile)
    func deactivateProfile()
}

/// UserDefaults-backed enrollment profile storage.
final class VoiceEnrollmentRepository: VoiceEnrollmentProfileStoring {

    private let defaults: UserDefaults
    private let profileKey = "lifememo.voiceEnrollment.activeProfile.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func activeProfile() -> VoiceEnrollmentProfile? {
        guard let data = defaults.data(forKey: profileKey) else { return nil }
        return try? JSONDecoder().decode(VoiceEnrollmentProfile.self, from: data)
    }

    func saveActiveProfile(_ profile: VoiceEnrollmentProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: profileKey)
    }

    func deactivateProfile() {
        defaults.removeObject(forKey: profileKey)
    }
}
