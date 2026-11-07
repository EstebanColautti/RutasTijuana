import Foundation

struct TripService: Sendable {
    let id: String
    let name: String
    let direction: String?
    let stops: [TransitStop]
    let circular: Bool
    var geometry: [[GeoPoint]] = []

    func section(through selected: [TransitStop]) -> [GeoPoint]? {
        JourneyScenario(schemaVersion: 1, name: name, coverageRadius: 1000,
            stops: stops, places: [], circular: circular, routeGeometry: geometry).mappedSection(for: selected)
    }
}

struct TripNetwork: Sendable {
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
        self.services = services.sorted { $0.id < $1.id }
    }
}

struct TripPreferences: Sendable {
    var walkingMeters = 800.0
    var transfers = 2
    var requestsPerBatch = 24
}

enum TripLeg: Sendable {
    case walk(from: GeoPoint, to: GeoPoint, route: WalkingRoute)
    case ride(service: TripService, stops: [TransitStop])
}

struct PlannedTrip: Sendable {
    let catalogVersion: String
    let legs: [TripLeg]
    let transfers: Int
    let walkingMeters: Double
    let exceedsPreferences: Bool
}

enum TripPlanningError: Error, Sendable { case invalidInput, tryAgainLater }

enum TripSearchResult: Sendable {
    case found(PlannedTrip)
    case paused
    case unavailable
}

protocol TripWalkingProvider: AnyObject, Sendable {
    func route(from: GeoPoint, to: GeoPoint) async throws -> WalkingRoute?
    func cancel() async
}

extension TripWalkingProvider {
    func cancel() async {}
}

actor TripPlanner {
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
        var pendingWalk: PendingWalk?
    }
    private struct PendingWalk {
        let from: Int
        let estimate: Double
        let source: WalkSource
    }
    private final class WalkSource {
        let label: Label
        var excluded: Set<Int> = []
        init(label: Label) { self.label = label }
    }
    private enum CachedWalk { case route(WalkingRoute), unavailable }
    private let network: TripNetwork
    private let provider: any TripWalkingProvider
    private let preferences: TripPreferences
    private var walking: [String: CachedWalk] = [:]
    private var rideDistances: [String: Double] = [:]
    private var generation = UUID()
    private var queryOrigin: GeoPoint?
    private var queryDestination: GeoPoint?

    init(network: TripNetwork, provider: any TripWalkingProvider, preferences: TripPreferences = .init()) {
        self.network = network
        self.provider = provider
        self.preferences = preferences
    }

    func cancel() async {
        generation = UUID()
        await provider.cancel()
    }

    func search(from origin: GeoPoint, to destination: GeoPoint) async throws -> TripSearchResult {
        guard origin.latitude.isFinite, origin.longitude.isFinite, destination.latitude.isFinite, destination.longitude.isFinite,
              abs(origin.latitude) <= 90, abs(destination.latitude) <= 90, abs(origin.longitude) <= 180,
              abs(destination.longitude) <= 180, origin != destination, preferences.walkingMeters.isFinite, preferences.walkingMeters >= 0,
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
        var departures: [Int: [(service: TripService, position: Int)]] = [:]
        for service in network.services {
            for position in service.stops.indices {
                if let index = indices[service.stops[position].id] {
                    departures[index, default: []].append((service, position))
                }
            }
        }
        var requests = 0
        var best: [String: [[Double]]] = [:]
        var frontier = [Label(stop: 0, service: nil, legs: [], boardings: 0, walking: 0,
                              riding: 0, excessWalking: 0, visited: ["0|"], tie: "", pendingWalk: nil)]
        func score(_ label: Label) -> [Double] {
            let transfers = max(0, label.boardings - 1)
            return [Double(max(0, transfers - preferences.transfers)) + (label.excessWalking > 0 ? 1 : 0),
                    label.excessWalking, Double(transfers), label.walking, label.riding]
        }
        func precedes(_ a: Label, _ b: Label) -> Bool {
            let left = score(a), right = score(b)
            return left == right ? a.tie < b.tie : left.lexicographicallyPrecedes(right)
        }
        func push(_ label: Label) {
            frontier.append(label)
            var child = frontier.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard precedes(frontier[child], frontier[parent]) else { break }
                frontier.swapAt(child, parent)
                child = parent
            }
        }
        func pop() -> Label {
            frontier.swapAt(0, frontier.count - 1)
            let result = frontier.removeLast()
            var parent = 0
            while parent * 2 + 1 < frontier.count {
                let left = parent * 2 + 1
                let right = left + 1
                let child = right < frontier.count && precedes(frontier[right], frontier[left]) ? right : left
                guard precedes(frontier[child], frontier[parent]) else { break }
                frontier.swapAt(parent, child)
                parent = child
            }
            return result
        }
        func enqueueWalk(from source: WalkSource) {
            let current = source.label
            let eligible = points.indices.filter { target in
                target != 0 && target != current.stop && !source.excluded.contains(target)
                    && !current.visited.contains("\(target)|") && (target != final || current.boardings > 0)
            }
            guard let target = eligible.min(by: {
                let a = points[current.stop].distance(to: points[$0])
                let b = points[current.stop].distance(to: points[$1])
                return a == b ? $0 < $1 : a < b
            }) else { return }
            source.excluded.insert(target)
            let estimate = max(0, points[current.stop].distance(to: points[target]) - 50)
            var next = current
            let state = "\(target)|"
            next.stop = target
            next.service = nil
            next.visited.insert(state)
            next.tie += state + ";"
            next.walking += estimate
            next.excessWalking += max(0, estimate - preferences.walkingMeters)
            next.pendingWalk = PendingWalk(from: current.stop, estimate: estimate, source: source)
            push(next)
        }
        while !frontier.isEmpty {
            try Task.checkCancellation()
            guard generation == token else { throw CancellationError() }
            var current = pop()
            if let pending = current.pendingWalk {
                enqueueWalk(from: pending.source)
                let key = "\(pending.from):\(current.stop)"
                if walking[key] == nil && (pending.from == 0 || current.stop == final)
                    && points[pending.from].distance(to: points[current.stop]) <= 1 {
                    walking[key] = .route(.init(points: [points[pending.from], points[current.stop]], steps: [], duration: 0))
                }
                if walking[key] == nil {
                    guard requests < preferences.requestsPerBatch else { return .paused }
                    requests += 1
                    let route = try await provider.route(from: points[pending.from], to: points[current.stop])
                    try Task.checkCancellation()
                    guard generation == token else { throw CancellationError() }
                    if let route, route.points.count >= 2, route.length.isFinite, route.duration.isFinite, route.duration >= 0,
                       route.points.allSatisfy({ $0.latitude.isFinite && $0.longitude.isFinite && abs($0.latitude) <= 90 && abs($0.longitude) <= 180 }),
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
                push(current)
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
            for departure in departures[current.stop] ?? [] {
                    let service = departure.service
                    let position = departure.position
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
                    let distanceKey = "\(service.id.count):\(service.id):\(position)"
                    if rideDistances[distanceKey] == nil {
                        rideDistances[distanceKey] = service.section(through: [service.stops[position], nextStop]).map { path in
                            zip(path, path.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
                        } ?? .infinity
                    }
                    next.riding += rideDistances[distanceKey]!
                    if current.service == service.id, case .ride(_, let previousStops)? = next.legs.last {
                        next.legs.removeLast()
                        next.legs.append(.ride(service: service, stops: previousStops + [nextStop]))
                    } else {
                        next.boardings += 1
                        next.legs.append(.ride(service: service, stops: [service.stops[position], nextStop]))
                    }
                    next.service = service.id
                    push(next)
            }
            guard current.service != nil || current.stop == 0 else { continue }
            enqueueWalk(from: WalkSource(label: current))
        }
        return .unavailable
    }
}
