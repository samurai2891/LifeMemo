import Foundation
import CoreLocation

/// Persists user preferences for location capture via UserDefaults.
/// All location data stays on-device. Reverse geocoding is off by default
/// because it requires a network call (CLGeocoder).
struct LocationPreference {

    // MARK: - Keys
    
    private static let enabledKey = "lifememo.location.enabled"
    private static let accuracyKey = "lifememo.location.accuracy"
    private static let timingKey = "lifememo.location.timing"
    private static let reverseGeocodeKey = "lifememo.location.reverseGeocode"

    // MARK: - Accuracy Levels
    
    enum Accuracy: String, CaseIterable, Identifiable {
        case approximate = "approximate"   // ~3km (kCLLocationAccuracyThreeKilometers)
        case balanced = "balanced"         // ~100m (kCLLocationAccuracyHundredMeters)  - DEFAULT
        case precise = "precise"           // ~10m (kCLLocationAccuracyNearestTenMeters)
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .approximate: return String(localized: "Approximate (~3km)")
            case .balanced: return String(localized: "Balanced (~100m)")
            case .precise: return String(localized: "Precise (~10m)")
            }
        }
        
        var clAccuracy: CLLocationAccuracy {
            switch self {
            case .approximate: return kCLLocationAccuracyThreeKilometers
            case .balanced: return kCLLocationAccuracyHundredMeters
            case .precise: return kCLLocationAccuracyNearestTenMeters
            }
        }
    }
    
    // MARK: - Capture Timing
    
    enum CaptureTiming: String, CaseIterable, Identifiable {
        case onStart = "start"       // Capture when recording starts - DEFAULT
        case onStop = "stop"         // Capture when recording stops
        case both = "both"           // Capture on both start and stop
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .onStart: return String(localized: "Recording Start")
            case .onStop: return String(localized: "Recording Stop")
            case .both: return String(localized: "Start & Stop")
            }
        }
    }
    
    // MARK: - Properties
    
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
    
    static var accuracy: Accuracy {
        get {
            guard let raw = UserDefaults.standard.string(forKey: accuracyKey),
                  let value = Accuracy(rawValue: raw) else { return .balanced }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: accuracyKey) }
    }
    
    static var captureTiming: CaptureTiming {
        get {
            guard let raw = UserDefaults.standard.string(forKey: timingKey),
                  let value = CaptureTiming(rawValue: raw) else { return .onStart }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: timingKey) }
    }
    
    static var reverseGeocodeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: reverseGeocodeKey) }
        set { UserDefaults.standard.set(newValue, forKey: reverseGeocodeKey) }
    }
}
