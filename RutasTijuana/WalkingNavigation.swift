import Foundation

struct WalkingDestination: Identifiable, Equatable {
    let id: String
    let name: String
    let point: GeoPoint
}

struct WalkingStep {
    let instruction: String
    let endDistance: Double
}

struct WalkingRoute {
    let points: [GeoPoint]
    let steps: [WalkingStep]
    let duration: TimeInterval
    var length: Double { zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) } }
}

struct WalkingFix {
    let point: GeoPoint
    let accuracy: Double
    let timestamp: Date
    var course: Double = -1
    var speed: Double = -1
    func isReliable(at now: Date) -> Bool {
        accuracy.isFinite && accuracy >= 0 && accuracy <= 50 &&
        timestamp.timeIntervalSince(now) <= 2 && now.timeIntervalSince(timestamp) < 10 &&
        point.latitude.isFinite && point.longitude.isFinite &&
        abs(point.latitude) <= 90 && abs(point.longitude) <= 180
    }
}

enum WalkingPolicy {
    static let maneuverDistance = 30.0
    static let idleTimeout: TimeInterval = 900
    static let sessionTimeout: TimeInterval = 7200
    static let retryDelays: [TimeInterval] = [30, 60, 120]
}

struct WalkingProgress {
    var traveled = 0.0
    var remaining = 0.0
    var stepIndex = 0
    var stepRemaining = 0.0
    var offRoute = false
    var arrived = false
}

struct WalkingProgressEngine {
    let route: WalkingRoute
    let destination: WalkingDestination
    private(set) var progress = WalkingProgress()
    private var previous: WalkingFix?
    private var offSince: Date?
    private var offCount = 0
    private var arrivalSince: Date?
    private var arrivalCount = 0
    private var pendingStep: Int?
    private var stepCount = 0

    init(route: WalkingRoute, destination: WalkingDestination) {
        self.route = route
        self.destination = destination
        progress.remaining = route.length
        progress.stepRemaining = route.steps.first?.endDistance ?? route.length
    }

    mutating func update(_ fix: WalkingFix, now: Date) -> WalkingProgress? {
        guard fix.isReliable(at: now), route.points.count >= 2 else {
            offSince = nil; offCount = 0; arrivalSince = nil; arrivalCount = 0
            pendingStep = nil; stepCount = 0
            return nil
        }
        if let previous {
            let dt = fix.timestamp.timeIntervalSince(previous.timestamp)
            guard dt > 0 else { return nil }
            guard fix.point.distance(to: previous.point) <= max(25, dt * 4 + fix.accuracy + previous.accuracy) else { return nil }
        }
        let projection = project(fix.point)
        let corridor = max(35, 2 * fix.accuracy)
        if projection.distance > corridor {
            if offSince == nil { offSince = now }
            offCount += 1
        } else {
            offSince = nil; offCount = 0
            let maxAdvance = previous.map { max(15, fix.timestamp.timeIntervalSince($0.timestamp) * 4 + fix.accuracy) } ?? 50
            if projection.along <= progress.traveled + maxAdvance {
                progress.traveled = max(progress.traveled, projection.along)
            }
        }
        previous = fix
        progress.remaining = max(0, route.length - progress.traveled)
        progress.offRoute = offCount >= 3 && now.timeIntervalSince(offSince ?? now) >= 8
        let next = route.steps.firstIndex { $0.endDistance > progress.traveled + 5 } ?? max(0, route.steps.count - 1)
        if next > progress.stepIndex {
            if pendingStep == next { stepCount += 1 } else { pendingStep = next; stepCount = 1 }
            if stepCount >= 3 { progress.stepIndex = min(progress.stepIndex + 1, next); pendingStep = nil; stepCount = 0 }
        } else { pendingStep = nil; stepCount = 0 }
        progress.stepRemaining = max(0, (route.steps.indices.contains(progress.stepIndex) ? route.steps[progress.stepIndex].endDistance : route.length) - progress.traveled)
        let endpointNear = route.points.last.map { $0.distance(to: destination.point) <= 25 } ?? false
        if endpointNear && !progress.offRoute && fix.accuracy <= 20 && fix.point.distance(to: destination.point) <= 25 && progress.remaining <= 40 {
            if arrivalSince == nil { arrivalSince = now }
            arrivalCount += 1
        } else { arrivalSince = nil; arrivalCount = 0 }
        progress.arrived = arrivalCount >= 3 && now.timeIntervalSince(arrivalSince ?? now) >= 5
        return progress
    }

    private func project(_ point: GeoPoint) -> (distance: Double, along: Double) {
        let scale = cos(point.latitude * .pi / 180)
        var cumulative = 0.0
        var candidates: [(distance: Double, along: Double)] = []
        for (a, b) in zip(route.points, route.points.dropFirst()) {
            let x = (b.longitude - a.longitude) * scale * 111_195
            let y = (b.latitude - a.latitude) * 111_195
            let px = (point.longitude - a.longitude) * scale * 111_195
            let py = (point.latitude - a.latitude) * 111_195
            let square = x*x + y*y
            let t = square > 0 ? min(1, max(0, (px*x + py*y) / square)) : 0
            let length = a.distance(to: b)
            candidates.append((hypot(px-t*x, py-t*y), cumulative + t*length))
            cumulative += length
        }
        let local = candidates.filter { $0.along >= progress.traveled - 30 && $0.along <= progress.traveled + 80 }
        return (local.min(by: { $0.distance < $1.distance }) ?? candidates.min(by: { $0.distance < $1.distance })) ?? (.infinity, 0)
    }
}

@MainActor protocol WalkingRouteProvider: AnyObject {
    func route(from: GeoPoint, to: WalkingDestination) async throws -> WalkingRoute
    func cancel()
}


enum WalkingPhase { case locating, calculating, preview, navigating, paused, arrived, ended }
enum WalkingLocationState { case acquiring, imprecise, ready }
enum WalkingCalculationError { case network, unavailable, timeout }
enum WalkingStartDecision: Equatable { case locate, recalculate, start }

struct WalkingSessionStatus {
    var location = WalkingLocationState.acquiring
    var connected = true
    var calculating = false
    var error: WalkingCalculationError?
    var endpointGap = 0.0
    var terminal: String?
    var waitingToStart = false

    func messages(hasRoute: Bool) -> [String] {
        if let terminal { return [terminal] }
        var result: [String] = []
        if location == .acquiring { result.append("Actualizando ubicación…") }
        if location == .imprecise { result.append("Ubicación imprecisa · Espera una señal más precisa") }
        if !connected { result.append(hasRoute ? "Sin conexión · No se puede recalcular" : "Sin conexión · Conéctate para calcular el camino") }
        if let error, connected || error != .network {
            switch error {
            case .network: result.append("No se pudo conectar. Vuelve a intentarlo.")
            case .unavailable: result.append("No se pudo obtener un camino a pie. Vuelve a intentarlo.")
            case .timeout: result.append("La consulta tardó demasiado. Vuelve a intentarlo.")
            }
        }
        if calculating { result.append(hasRoute ? "Recalculando…" : "Calculando camino…") }
        else if waitingToStart { result.append("Actualizando el punto de inicio…") }
        if endpointGap > 25 { result.append("El camino termina a \(WalkingFormat.distance(endpointGap)) de la parada.") }
        return result
    }
    func offersRetry(phase: WalkingPhase) -> Bool {
        phase != .ended && phase != .arrived && phase != .paused && !waitingToStart && !calculating && error != nil
    }
    static func startDecision(fix: WalkingFix?, origin: GeoPoint?, now: Date) -> WalkingStartDecision {
        guard let fix, fix.isReliable(at: now) else { return .locate }
        guard let origin, fix.point.distance(to: origin) <= 25 else { return .recalculate }
        return .start
    }
}

enum WalkingFormat {
    static func distance(_ meters: Double) -> String {
        guard meters.isFinite else { return "—" }
        let value = max(0, meters)
        if value < 1000 { return "\(Int(value.rounded())) m" }
        return String(format: "%.1f km", value / 1000).replacingOccurrences(of: ".", with: ",")
    }
    static func duration(_ seconds: Double, arrived: Bool = false) -> String {
        if arrived { return "Llegaste" }
        guard seconds.isFinite else { return "—" }
        if seconds < 60 { return "Menos de 1 min" }
        return "\(Int(ceil(seconds / 60))) min aprox."
    }
}
