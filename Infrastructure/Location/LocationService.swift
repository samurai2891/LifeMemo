import Foundation
import CoreLocation
import os.log

/// Captures approximate location when a recording starts.
/// All location data stays on-device. Disabled by default (privacy first).
/// Reads configuration from LocationPreference (accuracy, timing, reverse geocode).
@MainActor
final class LocationService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var lastPlaceName: String?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    // MARK: - Private

    private let locationManager = CLLocationManager()
    private let logger = Logger(subsystem: "com.lifememo.app", category: "Location")

    // MARK: - Init

    override init() {
        super.init()
        locationManager.delegate = self
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Public Methods

    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Capture current location (one-shot). Reads accuracy from LocationPreference.
    func captureCurrentLocation() {
        guard LocationPreference.isEnabled else { return }
        guard authorizationStatus == .authorizedWhenInUse
            || authorizationStatus == .authorizedAlways
        else {
            requestPermission()
            return
        }
        locationManager.desiredAccuracy = LocationPreference.accuracy.clAccuracy
        logger.debug("Requesting location with accuracy: \(LocationPreference.accuracy.rawValue)")
        locationManager.requestLocation()
    }

    /// Reverse geocode to get a human-readable place name.
    /// Only called when LocationPreference.reverseGeocodeEnabled is true.
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
            logger.warning("Reverse geocoding failed: \(error.localizedDescription)")
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
            guard let location = locations.last else { return }
            lastLocation = location
            logger.info("Location captured: \(location.coordinate.latitude), \(location.coordinate.longitude)")

            if LocationPreference.reverseGeocodeEnabled {
                lastPlaceName = await reverseGeocode(location: location)
                if let name = lastPlaceName {
                    logger.info("Reverse geocoded: \(name)")
                }
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        let desc = error.localizedDescription
        Task { @MainActor in
            logger.warning("Location capture failed: \(desc)")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
        }
    }
}
