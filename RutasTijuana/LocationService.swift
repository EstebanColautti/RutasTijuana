#if os(iOS)
import CoreLocation
import Combine

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var point: GeoPoint?
    @Published private(set) var horizontalAccuracy: CLLocationAccuracy?
    @Published private(set) var message: String?
    @Published private(set) var isRequesting = false
    private let manager = CLLocationManager()
    private var tracking = false
    private var timeout: DispatchWorkItem?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request(continuously: Bool = false) {
        cancel()
        tracking = continuously
        horizontalAccuracy = nil
        point = nil
        message = nil
        isRequesting = true
        resolveAuthorization()
    }

    func cancel() {
        timeout?.cancel()
        timeout = nil
        isRequesting = false
        tracking = false
        manager.stopUpdatingLocation()
    }

    private func resolveAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            guard timeout == nil, isRequesting else { return }
            let work = DispatchWorkItem { [weak self] in
                self?.fail("No pudimos obtener tu ubicación. Puedes elegir el origen en el mapa.")
            }
            timeout = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
            if tracking { manager.startUpdatingLocation() } else { manager.requestLocation() }
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
        if isRequesting || tracking {
            if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                point = nil
                horizontalAccuracy = nil
                cancel()
                message = "La ubicación no está disponible. Puedes elegir tu origen."
            } else {
                resolveAuthorization()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRequesting || tracking, let location = locations.last,
              location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 60 else { return }
        if tracking {
            timeout?.cancel()
            timeout = nil
            isRequesting = false
            message = nil
        } else { cancel() }
        horizontalAccuracy = location.horizontalAccuracy
        point = GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if tracking, (error as? CLError)?.code == .locationUnknown { return }
        fail("No pudimos obtener tu ubicación. Puedes elegir el origen en el mapa.")
    }
}
#endif
