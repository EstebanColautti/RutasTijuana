#if os(iOS)
import CoreLocation
import Combine

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var point: GeoPoint?
    @Published private(set) var message: String?
    @Published private(set) var isRequesting = false
    private let manager = CLLocationManager()
    private var timeout: DispatchWorkItem?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        cancel()
        point = nil
        message = nil
        isRequesting = true
        let work = DispatchWorkItem { [weak self] in
            self?.fail("No pudimos obtener tu ubicación. Puedes elegir el origen en el mapa.")
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
        resolveAuthorization()
    }

    func cancel() {
        timeout?.cancel()
        timeout = nil
        isRequesting = false
        manager.stopUpdatingLocation()
    }

    private func resolveAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: fail("La ubicación no está disponible. Elige el origen en el mapa.")
        @unknown default: fail("Elige el origen en el mapa.")
        }
    }

    private func fail(_ text: String) {
        guard isRequesting else { return }
        cancel()
        message = text
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if isRequesting { resolveAuthorization() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRequesting, let location = locations.last,
              location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 60 else { return }
        cancel()
        point = GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        fail("No pudimos obtener tu ubicación. Puedes elegir el origen en el mapa.")
    }
}
#endif
