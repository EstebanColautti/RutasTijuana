import Foundation

struct TripService: Sendable {
    var id: String
    let name: String
    let direction: String?
    var stops: [TransitStop]
    var circular: Bool
    var geometry: [[GeoPoint]] = []
    var accessPositions: [String: Double] = [:]

    func section(through selected: [TransitStop]) -> [GeoPoint]? {
        if let first = selected.first, let last = selected.last,
           let start = accessPositions[first.id], let end = accessPositions[last.id], let points = geometry.first {
            let measure = RouteMeasure(points)
            if end > start { return measure.section(from: start, to: end) }
            if circular, let a = measure.section(from: start, to: measure.length), let b = measure.section(from: 0, to: end) {
                return a + b.dropFirst()
            }
            return nil
        }
        return JourneyScenario(schemaVersion: 1, name: name, coverageRadius: 1000,
            stops: stops, places: [], circular: circular, routeGeometry: geometry).mappedSection(for: selected)
    }
}

struct TripNetwork: Sendable {
    let version: String
    let services: [TripService]

    init(catalog: RouteCatalog) {
        version = catalog.version
        services = catalog.features.compactMap { feature in
            if let scenario = catalog.journeyScenario(for: feature) {
                return TripService(id: feature.id, name: feature.name, direction: scenario.direction,
                               stops: scenario.stops, circular: scenario.circular == true, geometry: scenario.routeGeometry ?? [])
            }
            guard catalog.readyForDistribution, feature.kind == .route, !feature.geometry.lines.isEmpty else { return nil }
            return TripService(id: feature.id, name: feature.name, direction: feature.routeDetails?.direction,
                stops: [], circular: feature.routeDetails?.circular == true, geometry: feature.geometry.lines.map { $0.map(\.point) })
        }.sorted { $0.id < $1.id }
    }

    init(version: String, services: [TripService]) {
        self.version = version
        self.services = services.sorted { $0.id < $1.id }
    }
}

enum TripCost {
    static let walkingSpeed = 1.3
    static let ridingSpeed = 6.0
    static let transferPenalty = 480.0
    static let extraTransferPenalty = 900.0
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

actor TripTransferCache {
    private struct Entry {
        let route: WalkingRoute
        let expires: ContinuousClock.Instant
    }

    private let clock = ContinuousClock()
    private var entries: [String: Entry] = [:]

    func route(for key: String) -> WalkingRoute? {
        guard let entry = entries[key] else { return nil }
        guard entry.expires > clock.now else {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.route
    }

    func store(_ route: WalkingRoute, for key: String) {
        if entries[key] == nil, entries.count >= 128,
           let oldest = entries.min(by: { $0.value.expires < $1.value.expires }) {
            entries.removeValue(forKey: oldest.key)
        }
        entries[key] = Entry(route: route, expires: clock.now.advanced(by: .seconds(900)))
    }
}

private struct TripPointIndex {
    private struct Cell: Hashable { let x: Int; let y: Int }
    private let scale: Double
    private var cells: [Cell: [Int]] = [:]
    init(_ points: [GeoPoint]) {
        scale = max(1, cos((points.first?.latitude ?? 0) * .pi / 180) * 111195)
        for (index, point) in points.enumerated() { cells[cell(point), default: []].append(index) }
    }
    private func cell(_ point: GeoPoint) -> Cell {
        .init(x: Int(floor(point.longitude * scale / 250)), y: Int(floor(point.latitude * 111195 / 250)))
    }
    func nearby(_ point: GeoPoint, radius: Double) -> [Int] {
        let center = cell(point), span = Int(ceil(radius / 250)) + 1
        var result: [Int] = []
        for x in center.x-span...center.x+span {
            for y in center.y-span...center.y+span { result += cells[.init(x: x, y: y)] ?? [] }
        }
        return result
    }
}

actor TripPlanner {
    private struct Visit: Hashable {
        let stop: Int
        let service: String?
    }

    private struct Label {
        var stop: Int
        var service: String?
        var legs: [TripLeg]
        var boardings: Int
        var walking: Double
        var riding: Double
        var excessWalking: Double
        var visited: Set<Visit>
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
        var excludedServices: Set<String> = []
        var radius = 800.0
        init(label: Label) { self.label = label; if let service = label.service { excludedServices.insert(service) } }
    }
    private typealias Entry = (label: Label, priority: [Double])

    private struct PreparedGraph {
        let stops: [TransitStop]
        let points: [GeoPoint]
        let pointIndex: TripPointIndex
        let unitVectors: [SIMD3<Double>]
        let distanceToDestination: [Double]
        let indices: [String: Int]
        let departures: [Int: [(service: TripService, position: Int)]]
    }

    private struct SearchProgress {
        var frontier: [Entry]
        var best: [String: Double]
    }

    private enum CachedWalk { case route(WalkingRoute), unavailable }
    private let network: TripNetwork
    private let provider: any TripWalkingProvider
    private let preferences: TripPreferences
    private let transferCache: TripTransferCache?
    private var walking: [String: CachedWalk] = [:]
    private var rideDistances: [String: Double] = [:]
    private var generation = UUID()
    private var queryOrigin: GeoPoint?
    private var queryDestination: GeoPoint?
    private var preparedGraph: PreparedGraph?
    private var progress: SearchProgress?

    init(network: TripNetwork, provider: any TripWalkingProvider, preferences: TripPreferences = .init(),
         transferCache: TripTransferCache? = nil) {
        self.network = network
        self.provider = provider
        self.preferences = preferences
        self.transferCache = transferCache
    }

    func cancel() async {
        generation = UUID()
        progress = nil
        await provider.cancel()
    }

    func search(from origin: GeoPoint, to destination: GeoPoint) async throws -> TripSearchResult {
        guard origin.latitude.isFinite, origin.longitude.isFinite, destination.latitude.isFinite, destination.longitude.isFinite,
              abs(origin.latitude) <= 90, abs(destination.latitude) <= 90, abs(origin.longitude) <= 180,
              abs(destination.longitude) <= 180, origin != destination, preferences.walkingMeters.isFinite, preferences.walkingMeters >= 0,
              preferences.transfers >= 0, preferences.requestsPerBatch > 0 else { throw TripPlanningError.invalidInput }
        if queryOrigin != origin || queryDestination != destination {
            walking.removeAll()
            rideDistances.removeAll()
            queryOrigin = origin
            queryDestination = destination
            preparedGraph = nil
            progress = nil
        }
        let token = UUID()
        generation = token
        if preparedGraph == nil {
            let source = network.services
            let preparation = Task.detached(priority: .userInitiated) {
                let services = try RouteAccess.services(source, origin: origin, destination: destination)
                return Self.prepareGraph(services, origin: origin, destination: destination)
            }
            let prepared = try await withTaskCancellationHandler(operation: { try await preparation.value }, onCancel: { preparation.cancel() })
            guard generation == token else { throw CancellationError() }
            preparedGraph = prepared
        }
        guard let graph = preparedGraph else { return .unavailable }
        let stops = graph.stops
        let points = graph.points
        let final = points.count - 1
        let pointIndex = graph.pointIndex
        let unitVectors = graph.unitVectors
        let distanceToDestination = graph.distanceToDestination
        let indices = graph.indices
        let departures = graph.departures
        func walkKey(_ from: GeoPoint, _ to: GeoPoint) -> String {
            func coordinate(_ point: GeoPoint) -> String {
                "\(point.latitude.bitPattern):\(point.longitude.bitPattern)"
            }
            return coordinate(from) + "|" + coordinate(to)
        }
        func valid(_ route: WalkingRoute, from: GeoPoint, to: GeoPoint) -> Bool {
            route.points.count >= 2 && route.length.isFinite && route.duration.isFinite && route.duration >= 0
                && route.points.allSatisfy { $0.latitude.isFinite && $0.longitude.isFinite && abs($0.latitude) <= 90 && abs($0.longitude) <= 180 }
                && route.points.first!.distance(to: from) <= 25 && route.points.last!.distance(to: to) <= 25
        }
        var requests = 0
        let previousProgress = progress
        progress = nil
        var best = previousProgress?.best ?? [:]
        let initial = Label(stop: 0, service: nil, legs: [], boardings: 0, walking: 0,
                            riding: 0, excessWalking: 0, visited: [Visit(stop: 0, service: nil)], tie: "", pendingWalk: nil)
        var frontier = previousProgress?.frontier ?? []
        var finished = false
        defer {
            if generation == token && !finished && !Task.isCancelled {
                progress = SearchProgress(frontier: frontier, best: best)
            }
        }
        let clock = ContinuousClock()
        var deadline = clock.now.advanced(by: .seconds(1))
        func score(_ label: Label) -> [Double] {
            let transfers = max(0, label.boardings - (label.service != nil || label.stop == final ? 1 : 0))
            let remaining = max(0, distanceToDestination[label.stop] - 50) / TripCost.ridingSpeed
            let cost = label.walking / TripCost.walkingSpeed + label.riding / TripCost.ridingSpeed + Double(transfers) * TripCost.transferPenalty
                + label.excessWalking / TripCost.walkingSpeed + Double(max(0, transfers - preferences.transfers)) * TripCost.extraTransferPenalty
            return [cost + remaining, remaining, Double(transfers), label.walking, label.riding]
        }
        func precedes(_ a: Entry, _ b: Entry) -> Bool {
            for (left, right) in zip(a.priority, b.priority) where left != right {
                return left < right
            }
            return a.label.tie < b.label.tie
        }
        func push(_ label: Label) {
            frontier.append((label, score(label)))
            var child = frontier.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard precedes(frontier[child], frontier[parent]) else { break }
                frontier.swapAt(child, parent)
                child = parent
            }
        }
        func pop() -> Entry {
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
            var selected: Int?
            while selected == nil {
                let candidates = source.radius >= 3200 ? Array(points.indices) : pointIndex.nearby(points[current.stop], radius: source.radius) + [final]
                var nearest: (target: Int, chordSquared: Double)?
                let startVector = unitVectors[current.stop]
                for target in candidates {
                    guard target != 0, target != current.stop else { continue }
                    let delta = startVector - unitVectors[target]
                    let chordSquared = delta.x * delta.x + delta.y * delta.y + delta.z * delta.z
                    if let nearest, chordSquared > nearest.chordSquared || (chordSquared == nearest.chordSquared && target >= nearest.target) {
                        continue
                    }
                    guard !source.excluded.contains(target), !current.visited.contains(Visit(stop: target, service: nil)) else { continue }
                    if target == final {
                        guard current.boardings > 0 else { continue }
                    } else {
                        guard (departures[target] ?? []).contains(where: { departure in
                            !source.excludedServices.contains(departure.service.id)
                                && (departure.position + 1 < departure.service.stops.count || departure.service.circular)
                        }) else { continue }
                        if current.stop > 0, chordSquared <= 1e-12,
                           stops[current.stop - 1].suggested || stops[target - 1].suggested,
                           points[current.stop].distance(to: points[target]) <= 2 { continue }
                    }
                    if case .unavailable = walking[walkKey(points[current.stop], points[target])] {
                        source.excluded.insert(target)
                        continue
                    }
                    nearest = (target, chordSquared)
                }
                guard let nearest, source.radius >= 3200 || points[current.stop].distance(to: points[nearest.target]) <= source.radius else {
                    if source.radius < 3200 { source.radius *= 2; continue }
                    return
                }
                selected = nearest.target
            }
            guard let target = selected else { return }
            source.excluded.insert(target)
            for departure in departures[target] ?? [] { source.excludedServices.insert(departure.service.id) }
            let estimate = max(0, points[current.stop].distance(to: points[target]) - 50)
            var next = current
            let state = "\(target)|"
            next.stop = target
            next.service = nil
            next.visited.insert(Visit(stop: target, service: nil))
            next.tie += state + ";"
            next.walking += estimate
            next.excessWalking += max(0, estimate - preferences.walkingMeters)
            next.pendingWalk = PendingWalk(from: current.stop, estimate: estimate, source: source)
            push(next)
        }
        if previousProgress == nil { push(initial) }
        while !frontier.isEmpty {
            if clock.now >= deadline { return .paused }
            try Task.checkCancellation()
            guard generation == token else { throw CancellationError() }
            let entry = pop()
            var current = entry.label
            if let pending = current.pendingWalk {
                enqueueWalk(from: pending.source)
                let key = walkKey(points[pending.from], points[current.stop])
                if pending.from > 0 && current.stop != final,
                   (stops[pending.from - 1].suggested || stops[current.stop - 1].suggested),
                   points[pending.from].distance(to: points[current.stop]) <= 2 { continue }
                if walking[key] == nil && (pending.from == 0 || current.stop == final)
                    && !(current.stop != final && stops[current.stop - 1].suggested)
                    && !(pending.from > 0 && stops[pending.from - 1].suggested)
                    && points[pending.from].distance(to: points[current.stop]) <= 1 {
                    walking[key] = .route(.init(points: [points[pending.from], points[current.stop]], steps: [], duration: 0))
                }
                let route: WalkingRoute
                let confirmed: Bool
                switch walking[key] {
                case .unavailable: continue
                case .route(let saved): route = saved; confirmed = true
                case nil:
                    route = .init(points: [points[pending.from], points[current.stop]], steps: [], duration: 0)
                    confirmed = false
                }
                current.pendingWalk = nil
                if confirmed {
                    current.walking += route.length - pending.estimate
                    current.excessWalking += max(0, route.length - preferences.walkingMeters)
                        - max(0, pending.estimate - preferences.walkingMeters)
                }
                if !confirmed || route.length > 1 {
                    current.legs.append(.walk(from: points[pending.from], to: points[current.stop], route: route))
                }
                push(current)
                continue
            }
            let stateKey = "\(current.stop)|\(current.service ?? "")|\(current.boardings)"
            let currentScore = entry.priority
            let cost = currentScore[0] - currentScore[1]
            if let previous = best[stateKey], previous <= cost + 0.000001 { continue }
            best[stateKey] = cost
            if current.stop == final && current.boardings > 0 {
                var candidateResolved = false
                defer {
                    if !candidateResolved {
                        best.removeValue(forKey: stateKey)
                        push(current)
                    }
                }
                var legs: [(index: Int, leg: TripLeg)] = []
                var meters = 0.0
                var exceeded = max(0, current.boardings - 1) > preferences.transfers
                var unavailable = false
                let validationOrder = Self.validationOrder(current.legs, origin: origin, destination: destination)
                for item in validationOrder {
                    let leg = current.legs[item.index]
                    guard case .walk(let from, let to, _) = leg else { legs.append((item.index, leg)); continue }
                    let key = walkKey(from, to)
                    if walking[key] == nil {
                        let reusable = from != origin && to != destination ? transferCache : nil
                        let cacheKey = network.version + "|" + key
                        let cached = await reusable?.route(for: cacheKey)
                        try Task.checkCancellation()
                        guard generation == token else { throw CancellationError() }
                        if let cached {
                            walking[key] = .route(cached)
                        } else {
                            guard requests < preferences.requestsPerBatch, clock.now < deadline else { return .paused }
                            requests += 1
                            let started = clock.now
                            let response = try await provider.route(from: from, to: to)
                            deadline = deadline.advanced(by: started.duration(to: clock.now))
                            try Task.checkCancellation()
                            guard generation == token else { throw CancellationError() }
                            if let response {
                                guard valid(response, from: from, to: to) else { throw TripPlanningError.tryAgainLater }
                                walking[key] = .route(response)
                                await reusable?.store(response, for: cacheKey)
                                try Task.checkCancellation()
                                guard generation == token else { throw CancellationError() }
                            } else {
                                walking[key] = .unavailable
                            }
                        }
                    }
                    guard case .route(let route) = walking[key] else { unavailable = true; break }
                    meters += route.length
                    exceeded = exceeded || route.length > preferences.walkingMeters
                    if route.length > 1 { legs.append((item.index, .walk(from: from, to: to, route: route))) }
                }
                candidateResolved = true
                if unavailable {
                    best.removeAll()
                    frontier.removeAll()
                    push(initial)
                    continue
                }
                finished = true
                return .found(PlannedTrip(catalogVersion: network.version, legs: legs.sorted { $0.index < $1.index }.map(\.leg),
                    transfers: max(0, current.boardings - 1), walkingMeters: meters, exceedsPreferences: exceeded))
            }
            for departure in departures[current.stop] ?? [] {
                let service = departure.service
                let position = departure.position
                let nextPosition = position + 1
                guard nextPosition < service.stops.count || service.circular else { continue }
                let nextStop = service.stops[nextPosition % service.stops.count]
                guard let nextIndex = indices[nextStop.id] else { continue }
                let key = "\(nextIndex)|\(service.id)"
                let visit = Visit(stop: nextIndex, service: service.id)
                guard !current.visited.contains(visit) else { continue }
                var next = current
                next.stop = nextIndex
                next.visited.insert(visit)
                next.tie += key + ";"
                let distanceKey = "\(service.id.count):\(service.id):\(position)"
                if rideDistances[distanceKey] == nil {
                    if let start = service.accessPositions[service.stops[position].id], let end = service.accessPositions[nextStop.id] {
                        let length = end > start ? end - start : (service.circular ? RouteMeasure(service.geometry[0]).length - start + end : .infinity)
                        rideDistances[distanceKey] = length
                    } else {
                        rideDistances[distanceKey] = service.section(through: [service.stops[position], nextStop]).map { path in
                            zip(path, path.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
                        } ?? service.stops[position].point.distance(to: nextStop.point)
                    }
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
        finished = true
        return .unavailable
    }

    private static func validationOrder(_ legs: [TripLeg], origin: GeoPoint, destination: GeoPoint) -> [(index: Int, transferDistance: Double)] {
        var ranked: [(index: Int, transferDistance: Double)] = []
        for (index, leg) in legs.enumerated() {
            var distance = -1.0
            if case .walk(let from, let to, _) = leg, from != origin, to != destination {
                distance = from.distance(to: to)
            }
            ranked.append((index, distance))
        }
        return ranked.sorted {
            if $0.transferDistance == $1.transferDistance { return $0.index < $1.index }
            return $0.transferDistance > $1.transferDistance
        }
    }

    private static func prepareGraph(_ services: [TripService], origin: GeoPoint, destination: GeoPoint) -> PreparedGraph {
        let stops = services.flatMap(\.stops).reduce(into: [String: TransitStop]()) { $0[$1.id] = $1 }
            .values.sorted { $0.id < $1.id }
        let points = [origin] + stops.map(\.point) + [destination]
        let pointIndex = TripPointIndex(points)
        let unitVectors = points.map { point -> SIMD3<Double> in
            let latitude = point.latitude * .pi / 180
            let longitude = point.longitude * .pi / 180
            return SIMD3(cos(latitude) * cos(longitude), cos(latitude) * sin(longitude), sin(latitude))
        }
        let distanceToDestination = points.map { $0.distance(to: destination) }
        let indices = Dictionary(uniqueKeysWithValues: stops.enumerated().map { ($0.element.id, $0.offset + 1) })
        var departures: [Int: [(service: TripService, position: Int)]] = [:]
        for service in services {
            for position in service.stops.indices {
                if let index = indices[service.stops[position].id] {
                    departures[index, default: []].append((service, position))
                }
            }
        }
        return PreparedGraph(stops: stops, points: points, pointIndex: pointIndex, unitVectors: unitVectors,
                             distanceToDestination: distanceToDestination, indices: indices, departures: departures)
    }
}
