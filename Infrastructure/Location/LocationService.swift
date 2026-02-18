import Foundation
import CoreLocation

// MARK: - LocationService

/// Captures approximate location when a recording starts.
/// All location data stays on-device. Disabled by default (privacy first).
@MainActor
final class LocationService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var lastPlaceName: String?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    // MARK: - UserDefaults Persisted

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "locationCaptureEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "locationCaptureEnabled") }
    }

    // MARK: - Private

    private let locationManager = CLLocationManager()

    // MARK: - Init

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Public Methods

    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Capture current location (one-shot). Call when recording starts.
    func captureCurrentLocation() {
        guard isEnabled else { return }
        guard authorizationStatus == .authorizedWhenInUse
            || authorizationStatus == .authorizedAlways
        else {
            requestPermission()
            return
        }
        locationManager.requestLocation()
    }

    /// Reverse geocode to get a human-readable place name.
    /// Requires network. Only call if the user has explicitly enabled reverse geocoding.
    func reverseGeocode(location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                return [placemark.locality, placemark.administrativeArea]
                    .compactMap { $0 }
                    .joined(separator: ", ")
            }
        } catch {
            // Geocoding failed - not critical, return nil
        }
        return nil
    }

    /// Clear captured location state between recordings.
    func reset() {
        lastLocation = nil
        lastPlaceName = nil
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor in
            lastLocation = locations.last
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // Location capture failed - not critical for app functionality
    }

    nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
        }
    }
}
