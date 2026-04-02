import Combine
import CoreLocation
import Foundation

/// Provides the device's location for astronomical calculations.
/// Requests a single one-shot location update and caches it across launches.
@MainActor
final class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()

    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager = CLLocationManager()

    // UserDefaults keys for cross-launch caching
    private let latKey = "locationCachedLatitude"
    private let lonKey = "locationCachedLongitude"

    private override init() {
        authorizationStatus = manager.authorizationStatus

        // Restore last known coordinate so calculations work immediately on relaunch
        let lat = UserDefaults.standard.double(forKey: "locationCachedLatitude")
        let lon = UserDefaults.standard.double(forKey: "locationCachedLongitude")
        if lat != 0 || lon != 0 {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Requests location access if not yet determined; fetches a fresh fix if already authorized.
    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    var hasPermission: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.coordinate = location.coordinate
            UserDefaults.standard.set(location.coordinate.latitude, forKey: self.latKey)
            UserDefaults.standard.set(location.coordinate.longitude, forKey: self.lonKey)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silently ignore — cached coordinate (if any) remains valid
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if self.hasPermission {
                manager.requestLocation()
            }
        }
    }
}
