#if os(iOS)
import MapKit
import CoreLocation
import Combine

@MainActor final class AppleWalkingRouteProvider: WalkingRouteProvider {
    private var request: MKDirections?
    func cancel() { request?.cancel(); request = nil }
    func route(from: GeoPoint, to destination: WalkingDestination) async throws -> WalkingRoute {
        cancel()
        let query = MKDirections.Request()
        query.source = MKMapItem(placemark: MKPlacemark(coordinate: from.walkingCoordinate))
        query.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.point.walkingCoordinate))
        query.transportType = .walking
        query.requestsAlternateRoutes = false
        let directions = MKDirections(request: query)
        request = directions
        let result = try await directions.calculate()
        guard let route = result.routes.first, route.polyline.pointCount >= 2 else { throw URLError(.resourceUnavailable) }
        let points = route.polyline.walkingPoints
        var distance = 0.0
        let steps = route.steps.compactMap { step -> WalkingStep? in
            distance += step.distance
            guard step.distance > 0 else { return nil }
            return WalkingStep(instruction: step.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Continúa por el camino marcado" : step.instructions, endDistance: distance)
        }
        let length = zip(points, points.dropFirst()).reduce(0.0) { $0 + $1.0.distance(to: $1.1) }
        let ratio = distance > 0 ? length / distance : 1
        return WalkingRoute(points: points, steps: steps.enumerated().map { index, step in WalkingStep(instruction: index + 1 < steps.count ? steps[index + 1].instruction : "Continúa hasta la parada", endDistance: step.endDistance * ratio) }, duration: route.expectedTravelTime)
    }
}

extension GeoPoint {
    var walkingCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
extension MKPolyline {
    var walkingPoints: [GeoPoint] {
        var coordinates = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates.map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude) }
    }
}

@MainActor protocol NavigationLocationProvider: AnyObject {
    var onFix: ((WalkingFix) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var onDenied: (() -> Void)? { get set }
    func start()
    func enableBackground()
    func stop()
}

@MainActor final class AppleNavigationLocationProvider: NSObject, NavigationLocationProvider, @preconcurrency CLLocationManagerDelegate {
    var onFix: ((WalkingFix) -> Void)?
    var onError: ((String) -> Void)?
    var onDenied: (() -> Void)?
    private let manager = CLLocationManager()
    private var background: CLBackgroundActivitySession?
    private var active = false
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
    }
    func start() {
        active = true
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else { authorize() }
    }
    private func authorize() {
        guard active else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if manager.accuracyAuthorization == .reducedAccuracy {
                manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "WalkingNavigation")
            }
            manager.startUpdatingLocation()
        case .denied, .restricted:
            stop(); onDenied?()
        default: break
        }
    }
    func enableBackground() {
        guard active else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        background = CLBackgroundActivitySession()
    }
    func stop() {
        active = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        background?.invalidate(); background = nil
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { authorize() }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard active, let fix = locations.last else { return }
        onFix?(WalkingFix(point: GeoPoint(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude), accuracy: fix.horizontalAccuracy, timestamp: fix.timestamp, course: fix.course, speed: fix.speed))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onError?("Actualizando ubicación…")
    }
}

@MainActor final class WalkingNavigationCoordinator: ObservableObject {
    enum Phase { case locating, calculating, preview, navigating, paused, arrived, ended }
    @Published private(set) var phase = Phase.locating
    @Published private(set) var route: WalkingRoute?
    @Published private(set) var fix: WalkingFix?
    @Published private(set) var progress = WalkingProgress()
    @Published private(set) var message = "Obteniendo ubicación…"
    let destination: WalkingDestination
    private let provider: WalkingRouteProvider
    private let locations: NavigationLocationProvider
    private let now: () -> Date
    private var engine: WalkingProgressEngine?
    private var generation = UUID()
    private var request: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var started: Date?
    private var lastMovement: Date
    private var movementPoint: GeoPoint?
    private var nextRequest = Date.distantPast
    private var requestStarted: Date?
    private var failures = 0
    private var connected = true
    private let activity = NavigationActivityController()

    init(destination: WalkingDestination, provider: WalkingRouteProvider? = nil, locations: NavigationLocationProvider? = nil, now: @escaping () -> Date = Date.init) {
        self.destination = destination; self.provider = provider ?? AppleWalkingRouteProvider(); self.locations = locations ?? AppleNavigationLocationProvider(); self.now = now
        lastMovement = now()
        self.locations.onFix = { [weak self] in self?.receive($0) }
        self.locations.onDenied = { [weak self] in
            guard let self else { return }
            self.finish()
            self.message = "Habilita la ubicación en Ajustes para iniciar la guía."
        }
        self.locations.onError = { [weak self] text in
            guard let self else { return }
            self.message = text
            self.activityUpdate()
        }
    }
    var instruction: String {
        guard let route, route.steps.indices.contains(progress.stepIndex) else { return "Continúa por el camino marcado" }
        return route.steps[progress.stepIndex].instruction
    }
    var secondsRemaining: Double { guard let route, route.length > 0 else { return 0 }; return route.duration * progress.remaining / route.length }
    func prepare() {
        locations.start()
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }
    func start() {
        guard phase == .preview, let route else { return }
        engine = WalkingProgressEngine(route: route, destination: destination)
        progress = engine!.progress
        phase = .navigating; started = now(); lastMovement = now()
        locations.enableBackground()
        message = ""
        activityUpdate()
    }
    func resume() {
        guard phase == .paused else { return }
        phase = .locating; engine = nil; route = nil; fix = nil
        prepare()
    }
    func finish(arrived: Bool = false) {
        generation = UUID(); provider.cancel(); request?.cancel(); request = nil
        locations.stop(); ticker?.cancel(); ticker = nil
        phase = arrived ? .arrived : .ended
        message = arrived ? "Llegaste a la parada" : "Guía finalizada"
        activity.end(message: message)
    }
    func connectivityChanged(_ connected: Bool) {
        self.connected = connected
        if !connected { message = "Sin conexión · El camino actual sigue disponible"; activityUpdate() }
    }
    func retry() {
        guard phase != .ended && phase != .arrived else { return }
        guard let fix, fix.isReliable(at: now()) else { locations.start(); message = "Obteniendo ubicación…"; return }
        guard now() >= nextRequest else { return }
        calculate(fix)
    }
    private func receive(_ value: WalkingFix) {
        guard phase != .ended && phase != .arrived && phase != .paused else { return }
        guard value.isReliable(at: now()) else { message = "Ubicación imprecisa"; _ = engine?.update(value, now: now()); activityUpdate(); return }
        fix = value
        if movementPoint == nil || movementPoint!.distance(to: value.point) >= max(10, value.accuracy) {
            movementPoint = value.point; lastMovement = now()
        }
        if route == nil { if request == nil && now() >= nextRequest { calculate(value) }; return }
        guard phase == .navigating else { return }
        if let updated = engine?.update(value, now: now()) {
            progress = updated
            if updated.arrived { finish(arrived: true); return }
            message = !connected ? "Sin conexión · No se puede recalcular" : request == nil ? "" : "Recalculando…"
            if updated.offRoute && request == nil && now() >= nextRequest { calculate(value) }
            activityUpdate()
        }
    }
    private func calculate(_ value: WalkingFix) {
        guard request == nil, connected else { return }
        let token = UUID(); generation = token
        let navigating = phase == .navigating
        if !navigating { phase = .calculating }
        message = navigating ? "Recalculando…" : "Calculando camino…"
        requestStarted = now()
        nextRequest = now().addingTimeInterval(30)
        request = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await provider.route(from: value.point, to: destination)
                guard !Task.isCancelled, generation == token else { return }
                guard result.points.count >= 2, result.length.isFinite, result.length > 0, result.duration.isFinite, result.duration >= 0 else { throw URLError(.cannotParseResponse) }
                route = result; engine = WalkingProgressEngine(route: result, destination: destination); progress = engine!.progress
                phase = navigating ? .navigating : .preview
                failures = 0
                let gap = result.points.last!.distance(to: destination.point)
                message = gap > 25 ? "El camino termina a \(Int(gap)) m de la parada." : ""
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                nextRequest = now().addingTimeInterval(WalkingPolicy.retryDelays[min(failures, 2)])
                failures += 1
                if !navigating { phase = .locating }
                message = "No se pudo obtener el camino. Comprueba tu conexión y vuelve a intentarlo."
            }
            request = nil; requestStarted = nil; activityUpdate()
        }
    }
    private func tick() {
        if request != nil, let requestStarted, now().timeIntervalSince(requestStarted) >= 30 {
            generation = UUID(); provider.cancel(); request?.cancel(); request = nil; self.requestStarted = nil
            nextRequest = now().addingTimeInterval(WalkingPolicy.retryDelays[min(failures, 2)]); failures += 1
            if route == nil { phase = .locating }
            message = "No se pudo obtener el camino. Vuelve a intentarlo."
            activityUpdate()
        }
        if let started, now().timeIntervalSince(started) >= WalkingPolicy.sessionTimeout { finish(); return }
        if now().timeIntervalSince(lastMovement) >= WalkingPolicy.idleTimeout {
            generation = UUID(); provider.cancel(); request?.cancel(); request = nil
            locations.stop(); phase = .paused; message = "Guía pausada. Abre la app para reanudar."
            activity.end(message: message); ticker?.cancel(); ticker = nil
            return
        }
        if fix == nil || !fix!.isReliable(at: now()) { message = "Actualizando ubicación…"; activityUpdate() }
    }
    private func activityUpdate() {
        guard phase == .navigating else { return }
        activity.update(destination: destination.name, instruction: instruction, meters: Int(progress.stepRemaining), status: message)
    }
}
#endif
#if DEBUG
@MainActor final class FixtureWalkingRouteProvider: WalkingRouteProvider {
    func cancel() {}
    func route(from: GeoPoint, to destination: WalkingDestination) async throws -> WalkingRoute {
        if ProcessInfo.processInfo.arguments.contains("--walking-error") { throw URLError(.notConnectedToInternet) }
        let length = from.distance(to: destination.point)
        return WalkingRoute(points: [from, destination.point], steps: [WalkingStep(instruction: "Continúa hasta la parada", endDistance: length)], duration: 90)
    }
}
@MainActor final class FixtureNavigationLocationProvider: NavigationLocationProvider {
    var onFix: ((WalkingFix) -> Void)?
    var onError: ((String) -> Void)?
    var onDenied: (() -> Void)?
    let destination: WalkingDestination
    init(destination: WalkingDestination) { self.destination = destination }
    func start() {
        onFix?(WalkingFix(point: GeoPoint(latitude: destination.point.latitude - 0.001, longitude: destination.point.longitude), accuracy: 5, timestamp: Date()))
    }
    func enableBackground() {}
    func stop() {}
}
#endif
