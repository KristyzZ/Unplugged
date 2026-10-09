import CoreLocation
import Observation

/// Thin wrapper around CLLocationManager for "near me" sorting.
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private(set) var location: LatLng?
    private(set) var denied = false

    @ObservationIgnored private let manager = CLLocationManager()
    /// Last status the delegate reported. Reading `manager.authorizationStatus`
    /// on the main thread triggers a UI-responsiveness warning.
    @ObservationIgnored private var status: CLAuthorizationStatus = .notDetermined
    @ObservationIgnored private var wantsLocation = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        wantsLocation = true
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            denied = true
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            denied = false
            if wantsLocation { manager.requestLocation() }
        case .denied, .restricted:
            denied = true
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        location = LatLng(lat: l.coordinate.latitude, lng: l.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
