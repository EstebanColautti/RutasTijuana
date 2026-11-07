import Foundation

struct TripService {
    let id: String
    let name: String
    let direction: String?
    let stops: [TransitStop]
    let circular: Bool
    var geometry: [[GeoPoint]] = []
}

struct TripNetwork {
    let version: String
    let services: [TripService]

    init(catalog: RouteCatalog) {
        version = catalog.version
        services = catalog.features.compactMap { feature in
            guard let scenario = catalog.journeyScenario(for: feature) else { return nil }
            return TripService(id: feature.id, name: feature.name, direction: scenario.direction,
                               stops: scenario.stops, circular: scenario.circular == true, geometry: scenario.routeGeometry ?? [])
        }.sorted { $0.id < $1.id }
    }

    init(version: String, services: [TripService]) {
        self.version = version
        self.services = services
    }
}

struct TripPreferences {
    var walkingMeters = 800.0
    var transfers = 2
    var requestsPerBatch = 24
}

enum TripLeg {
    case walk(from: GeoPoint, to: GeoPoint, route: WalkingRoute)
    case ride(service: TripService, stops: [TransitStop])
}

struct PlannedTrip {
    let catalogVersion: String
    let legs: [TripLeg]
    let transfers: Int
    let walkingMeters: Double
    let exceedsPreferences: Bool
}

enum TripPlanningError: Error { case invalidInput }

enum TripSearchResult {
    case found(PlannedTrip)
    case paused
    case unavailable
}

@MainActor protocol TripWalkingProvider {
    func route(from: GeoPoint, to: GeoPoint) async throws -> WalkingRoute?
}

@MainActor
final class TripPlanner {
    private struct Label {
        var stop: Int
        var service: String?
        var legs: [TripLeg]
        var boardings: Int
        var walking: Double
        var riding: Double
        var excessWalking: Double
        var visited: Set<String>
        var tie: String
        var pendingWalk: (from: Int, estimate: Double)?
    }
    private enum CachedWalk { case route(WalkingRoute), unavailable }
    private let network: TripNetwork
    private let provider: any TripWalkingProvider
    private let preferences: TripPreferences
    private var walking: [String: CachedWalk] = [:]
    private var generation = UUID()
    private var queryOrigin: GeoPoint?
    private var queryDestination: GeoPoint?

    init(network: TripNetwork, provider: any TripWalkingProvider, preferences: TripPreferences = .init()) {
        self.network = network
        self.provider = provider
        self.preferences = preferences
    }

    func cancel() { generation = UUID() }

    func search(from origin: GeoPoint, to destination: GeoPoint) async throws -> TripSearchResult {
        guard origin.latitude.isFinite, origin.longitude.isFinite, destination.latitude.isFinite, destination.longitude.isFinite,
              abs(origin.latitude) <= 90, abs(destination.latitude) <= 90, abs(origin.longitude) <= 180,
              abs(destination.longitude) <= 180, preferences.walkingMeters.isFinite, preferences.walkingMeters >= 0,
              preferences.transfers >= 0, preferences.requestsPerBatch > 0 else { throw TripPlanningError.invalidInput }
        if queryOrigin != origin || queryDestination != destination {
            walking.removeAll()
            queryOrigin = origin
            queryDestination = destination
        }
        let token = UUID()
        generation = token
        let stops = network.services.flatMap(\.stops).reduce(into: [String: TransitStop]()) { $0[$1.id] = $1 }
            .values.sorted { $0.id < $1.id }
        let points = [origin] + stops.map(\.point) + [destination]
        let final = points.count - 1
        let indices = Dictionary(uniqueKeysWithValues: stops.enumerated().map { ($0.element.id, $0.offset + 1) })
        var requests = 0
        var best: [String: [[Double]]] = [:]
        var frontier = [Label(stop: 0, service: nil, legs: [], boardings: 0, walking: 0,
                              riding: 0, excessWalking: 0, visited: ["0|"], tie: "", pendingWalk: nil)]
        func score(_ label: Label) -> [Double] {
            let transfers = max(0, label.boardings - 1)
            return [Double(max(0, transfers - preferences.transfers)) + (label.excessWalking > 0 ? 1 : 0),
                    label.excessWalking, Double(transfers), label.walking, label.riding]
        }
        while !frontier.isEmpty {
            try Task.checkCancellation()
            guard generation == token else { throw CancellationError() }
            frontier.sort {
                let a = score($0), b = score($1)
                return a == b ? $0.tie < $1.tie : a.lexicographicallyPrecedes(b)
            }
            var current = frontier.removeFirst()
            if let pending = current.pendingWalk {
                let key = "\(pending.from):\(current.stop)"
                if walking[key] == nil && points[pending.from].distance(to: points[current.stop]) <= 1 {
                    walking[key] = .route(.init(points: [points[pending.from], points[current.stop]], steps: [], duration: 0))
                }
                if walking[key] == nil {
                    guard requests < preferences.requestsPerBatch else { return .paused }
                    requests += 1
                    let route = try await provider.route(from: points[pending.from], to: points[current.stop])
                    try Task.checkCancellation()
                    guard generation == token else { throw CancellationError() }
                    if let route, route.points.count >= 2, route.length.isFinite,
                       route.points.first!.distance(to: points[pending.from]) <= 25,
                       route.points.last!.distance(to: points[current.stop]) <= 25 {
                        walking[key] = .route(route)
                    } else { walking[key] = .unavailable }
                }
                guard case .route(let route) = walking[key] else { continue }
                current.pendingWalk = nil
                current.walking += route.length - pending.estimate
                current.excessWalking += max(0, route.length - preferences.walkingMeters)
                    - max(0, pending.estimate - preferences.walkingMeters)
                if route.length > 1 {
                    current.legs.append(.walk(from: points[pending.from], to: points[current.stop], route: route))
                }
                frontier.append(current)
                continue
            }
            let stateKey = "\(current.stop)|\(current.service ?? "")"
            let cost = [Double(current.boardings), current.walking, current.riding, current.excessWalking]
            let previous = best[stateKey] ?? []
            if previous.contains(where: { zip($0, cost).allSatisfy { $0 <= $1 } }) { continue }
            best[stateKey] = previous.filter { !zip(cost, $0).allSatisfy { $0 <= $1 } } + [cost]
            if current.stop == final && current.boardings > 0 {
                return .found(PlannedTrip(catalogVersion: network.version, legs: current.legs,
                    transfers: max(0, current.boardings - 1), walkingMeters: current.walking,
                    exceedsPreferences: score(current)[0] > 0))
            }
            for service in network.services {
                for position in service.stops.indices where indices[service.stops[position].id] == current.stop {
                    let nextPosition = position + 1
                    guard nextPosition < service.stops.count || service.circular else { continue }
                    let nextStop = service.stops[nextPosition % service.stops.count]
                    guard let nextIndex = indices[nextStop.id] else { continue }
                    let key = "\(nextIndex)|\(service.id)"
                    guard !current.visited.contains(key) else { continue }
                    var next = current
                    next.stop = nextIndex
                    next.visited.insert(key)
                    next.tie += key + ";"
                    next.riding += points[current.stop].distance(to: nextStop.point)
                    if current.service == service.id, case .ride(_, let previousStops)? = next.legs.last {
                        next.legs.removeLast()
                        next.legs.append(.ride(service: service, stops: previousStops + [nextStop]))
                    } else {
                        next.boardings += 1
                        next.legs.append(.ride(service: service, stops: [service.stops[position], nextStop]))
                    }
                    next.service = service.id
                    frontier.append(next)
                }
            }
            guard current.service != nil || current.stop == 0 else { continue }
            for target in points.indices where target != 0 && target != current.stop {
                let state = "\(target)|"
                guard !current.visited.contains(state), target != final || current.boardings > 0 else { continue }
                let estimate = max(0, points[current.stop].distance(to: points[target]) - 50)
                var next = current
                next.stop = target
                next.service = nil
                next.visited.insert(state)
                next.tie += state + ";"
                next.walking += estimate
                next.excessWalking += max(0, estimate - preferences.walkingMeters)
                next.pendingWalk = (current.stop, estimate)
                frontier.append(next)
            }
        }
        return .unavailable
    }
}
