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
    typealias Phase = WalkingPhase
    @Published private(set) var phase = Phase.locating
    @Published private(set) var route: WalkingRoute?
    @Published private(set) var fix: WalkingFix?
    @Published private(set) var progress = WalkingProgress()
    @Published private(set) var status = WalkingSessionStatus()
    @Published private(set) var retryAvailable = true
    let destination: WalkingDestination
    private let provider: WalkingRouteProvider
    private let locations: NavigationLocationProvider
    private let now: () -> Date
    private var engine: WalkingProgressEngine?
    private var routeOrigin: GeoPoint?
    private var generation = UUID()
    private var request: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var started: Date?
    private var lastMovement: Date
    private var movementPoint: GeoPoint?
    private var nextRequest = Date.distantPast
    private var requestStarted: Date?
    private var awaitingRetry = false
    private var failures = 0
    private let activity = NavigationActivityController()

    init(destination: WalkingDestination, provider: WalkingRouteProvider? = nil, locations: NavigationLocationProvider? = nil, now: @escaping () -> Date = Date.init) {
        self.destination = destination
        self.provider = provider ?? AppleWalkingRouteProvider()
        self.locations = locations ?? AppleNavigationLocationProvider()
        self.now = now
        lastMovement = now()
        self.locations.onFix = { [weak self] in self?.receive($0) }
        self.locations.onDenied = { [weak self] in
            self?.finish()
            self?.status.terminal = "Habilita la ubicación en Ajustes para iniciar la guía."
        }
        self.locations.onError = { [weak self] _ in
            self?.status.location = .acquiring
            self?.activityUpdate()
        }
    }
    var message: String { status.messages(hasRoute: route != nil).joined(separator: "\n") }
    var isLocationCurrent: Bool { status.location == .ready && fix?.isReliable(at: now()) == true }
    var offersRetry: Bool { status.offersRetry(phase: phase) }
    var instruction: String {
        guard let route, route.steps.indices.contains(progress.stepIndex) else { return "Continúa por el camino marcado" }
        return route.steps[progress.stepIndex].instruction
    }
    var secondsRemaining: Double {
        guard let route, route.length > 0 else { return 0 }
        return route.duration * progress.remaining / route.length
    }
    func prepare() {
        guard ticker == nil, phase != .ended, phase != .arrived else { return }
        locations.start()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }
    func start() {
        guard status.offersStart(phase: phase), route != nil, request == nil else { return }
        status.waitingToStart = true
        continueStart()
    }
    private func continueStart() {
        guard status.waitingToStart, request == nil else { return }
        switch WalkingSessionStatus.startDecision(fix: isLocationCurrent ? fix : nil, origin: routeOrigin, now: now()) {
        case .locate:
            status.location = .acquiring
            locations.start()
        case .recalculate:
            if now() >= nextRequest, let fix, status.connected { calculate(fix) }
        case .start:
            guard let route, let fix else { return }
            engine = WalkingProgressEngine(route: route, destination: destination)
            progress = engine?.update(fix, now: now()) ?? engine!.progress
            phase = .navigating
            started = now(); lastMovement = now()
            status.waitingToStart = false
            locations.enableBackground()
            activityUpdate()
        }
    }
    func resume() {
        guard phase == .paused else { return }
        phase = .locating; engine = nil; route = nil; fix = nil; routeOrigin = nil; awaitingRetry = false
        let connected = status.connected
        status = WalkingSessionStatus()
        status.connected = connected
        nextRequest = .distantPast; failures = 0
        started = nil; lastMovement = now(); movementPoint = nil
        prepare()
    }
    private func cancelRequest() {
        generation = UUID(); provider.cancel(); request?.cancel(); request = nil; requestStarted = nil
        status.calculating = false
    }
    func finish(arrived: Bool = false) {
        cancelRequest(); awaitingRetry = false
        locations.stop(); ticker?.cancel(); ticker = nil
        phase = arrived ? .arrived : .ended
        status.waitingToStart = false
        status.terminal = arrived ? "Llegaste a la parada" : "Guía finalizada"
        activity.end(message: status.terminal!)
    }
    func connectivityChanged(_ connected: Bool) {
        guard phase != .ended, phase != .arrived else { return }
        let recovered = !status.connected && connected
        status.connected = connected
        if recovered {
            if status.waitingToStart { continueStart() }
            else if progress.offRoute, isLocationCurrent, now() >= nextRequest, let fix { calculate(fix) }
        }
        activityUpdate()
    }
    func retry() {
        guard offersRetry, request == nil, status.connected, now() >= nextRequest else { return }
        guard isLocationCurrent, let fix else { awaitingRetry = true; status.location = .acquiring; locations.start(); return }
        calculate(fix)
    }
    private func receive(_ value: WalkingFix) {
        guard phase != .ended, phase != .arrived, phase != .paused else { return }
        guard value.isReliable(at: now()) else {
            status.location = .imprecise
            _ = engine?.update(value, now: now()); activityUpdate(); return
        }
        if let fix, value.timestamp <= fix.timestamp { return }
        guard value.isPlausible(after: fix) else { status.location = .imprecise; activityUpdate(); return }
        fix = value; status.location = .ready
        if movementPoint == nil || movementPoint!.distance(to: value.point) >= max(10, value.accuracy) {
            movementPoint = value.point; lastMovement = now()
        }
        if awaitingRetry, request == nil, status.connected, now() >= nextRequest {
            awaitingRetry = false; calculate(value); return
        }
        if status.waitingToStart { continueStart(); return }
        if route == nil {
            if request == nil, now() >= nextRequest, status.error == nil { calculate(value) }
            return
        }
        guard phase == .navigating else { return }
        if let updated = engine?.update(value, now: now()) {
            progress = updated
            if updated.arrived { finish(arrived: true); return }
            if updated.offRoute, request == nil, now() >= nextRequest { calculate(value) }
            activityUpdate()
        }
    }
    private func failed(_ error: WalkingCalculationError) {
        nextRequest = now().addingTimeInterval(WalkingPolicy.retryDelays[min(failures, 2)])
        failures += 1; retryAvailable = false
        status.error = error
        status.waitingToStart = false
        if phase != .navigating { phase = route == nil ? .locating : .preview }
    }
    private func calculate(_ value: WalkingFix) {
        guard request == nil, status.connected else { return }
        let token = UUID(); generation = token
        let navigating = phase == .navigating
        if !navigating { phase = .calculating }
        status.calculating = true
        status.error = nil
        requestStarted = now(); nextRequest = now().addingTimeInterval(30); retryAvailable = false
        request = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await provider.route(from: value.point, to: destination)
                guard !Task.isCancelled, generation == token else { return }
                guard result.points.count >= 2, result.length.isFinite, result.length > 0, result.duration.isFinite, result.duration >= 0 else { throw URLError(.cannotParseResponse) }
                route = result; routeOrigin = value.point
                engine = WalkingProgressEngine(route: result, destination: destination)
                progress = engine!.progress
                phase = navigating ? .navigating : .preview
                failures = 0; status.error = nil
                status.endpointGap = result.points.last!.distance(to: destination.point)
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                let ns = error as NSError
                failed(!status.connected || ns.domain == NSURLErrorDomain ? .network : .unavailable)
            }
            request = nil; requestStarted = nil; status.calculating = false
            if status.waitingToStart { continueStart() }
            activityUpdate()
        }
    }
    private func tick() {
        guard phase != .ended, phase != .arrived, phase != .paused else { return }
        retryAvailable = now() >= nextRequest
        if request != nil, let requestStarted, now().timeIntervalSince(requestStarted) >= 30 {
            cancelRequest(); failed(.timeout); activityUpdate()
        }
        if let started, now().timeIntervalSince(started) >= WalkingPolicy.sessionTimeout { finish(); return }
        if now().timeIntervalSince(lastMovement) >= WalkingPolicy.idleTimeout {
            cancelRequest(); locations.stop(); phase = .paused
            status.waitingToStart = false; status.terminal = "Guía pausada. Abre la app para reanudar."
            activity.end(message: status.terminal!); ticker?.cancel(); ticker = nil
            return
        }
        if fix == nil || !fix!.isReliable(at: now()) { status.location = .acquiring }
        if status.waitingToStart, status.location == .ready, retryAvailable { continueStart() }
        else if phase == .navigating, progress.offRoute, isLocationCurrent, retryAvailable, let fix { calculate(fix) }
        activityUpdate()
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
        let arguments = ProcessInfo.processInfo.arguments
        let endpoint = arguments.contains("--walking-gap") ? GeoPoint(latitude: destination.point.latitude - 0.0005, longitude: destination.point.longitude) : destination.point
        let length = from.distance(to: endpoint)
        let instruction = arguments.contains("--walking-long") ? "Continúa por la calle hasta el siguiente cruce peatonal y gira a la derecha para acercarte a la parada indicada en el mapa." : "Continúa hasta la parada"
        return WalkingRoute(points: [from, endpoint], steps: [WalkingStep(instruction: instruction, endDistance: length)], duration: 90)
    }
}
@MainActor final class FixtureNavigationLocationProvider: NavigationLocationProvider {
    var onFix: ((WalkingFix) -> Void)?
    var onError: ((String) -> Void)?
    var onDenied: (() -> Void)?
    let destination: WalkingDestination
    private var updates: Task<Void, Never>?
    init(destination: WalkingDestination) { self.destination = destination }
    private func emit() {
        onFix?(WalkingFix(point: GeoPoint(latitude: destination.point.latitude - 0.001, longitude: destination.point.longitude), accuracy: 5, timestamp: Date()))
    }
    func start() {
        emit()
        guard updates == nil else { return }
        updates = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                self?.emit()
            }
        }
    }
    func enableBackground() {}
    func stop() { updates?.cancel(); updates = nil }
}
#endif
