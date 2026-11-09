import Foundation

struct RouteMeasure: Sendable {
    let points: [GeoPoint]
    let cumulative: [Double]
    var length: Double { cumulative.last ?? 0 }
    init(_ points: [GeoPoint]) {
        self.points = points
        var values = [0.0]
        for (a, b) in zip(points, points.dropFirst()) { values.append(values.last! + a.distance(to: b)) }
        cumulative = values
    }
    func point(at distance: Double) -> GeoPoint {
        guard points.count > 1 else { return points[0] }
        let distance = min(length, max(0, distance))
        var low = 1, high = points.count - 1
        while low < high { let middle = (low + high) / 2; if cumulative[middle] < distance { low = middle + 1 } else { high = middle } }
        let start = points[low - 1], end = points[low]
        let span = cumulative[low] - cumulative[low - 1]
        let t = span > 0 ? (distance - cumulative[low - 1]) / span : 0
        return .init(latitude: start.latitude + t * (end.latitude - start.latitude), longitude: start.longitude + t * (end.longitude - start.longitude))
    }
    func section(from start: Double, to end: Double) -> [GeoPoint]? {
        guard points.count > 1, start >= 0, end <= length + 0.01, end > start else { return nil }
        var result = [point(at: start)]
        for index in points.indices where cumulative[index] > start && cumulative[index] < end { result.append(points[index]) }
        let last = point(at: end)
        if result.last != last { result.append(last) }
        return result.count > 1 ? result : nil
    }
    func projection(_ point: GeoPoint, segment index: Int) -> (along: Double, meters: Double) {
        let a = points[index], b = points[index + 1], scale = cos(point.latitude * .pi / 180)
        let x = (b.longitude - a.longitude) * scale, y = b.latitude - a.latitude
        let px = (point.longitude - a.longitude) * scale, py = point.latitude - a.latitude
        let squared = x*x + y*y
        let t = squared > 0 ? min(1, max(0, (px*x + py*y) / squared)) : 0
        let projected = GeoPoint(latitude: a.latitude + t * (b.latitude - a.latitude), longitude: a.longitude + t * (b.longitude - a.longitude))
        return (cumulative[index] + t * (cumulative[index + 1] - cumulative[index]), point.distance(to: projected))
    }
    func nearest(_ point: GeoPoint, limit: Int = 4) -> [Double] {
        let candidates = (0..<max(0, points.count - 1)).map { projection(point, segment: $0) }.sorted { $0.meters < $1.meters }
        var selected: [Double] = []
        for candidate in candidates where candidate.meters <= (candidates.first?.meters ?? 0) + 15 {
            if selected.allSatisfy({ abs($0 - candidate.along) > 50 }) { selected.append(candidate.along) }
            if selected.count == limit { break }
        }
        return selected
    }
}

enum RouteAccess {
    private struct Path {
        var service: TripService
        let measure: RouteMeasure
        var positions: Set<Int> = []
        var anchors: Set<Int> = []
    }
    private struct Cell: Hashable { let x: Int; let y: Int }
    private struct Segment { let path: Int; let index: Int }

    static func services(_ source: [TripService], origin: GeoPoint, destination: GeoPoint) throws -> [TripService] {
        let documented = source.filter { !$0.stops.isEmpty }
        var paths = source.filter { $0.stops.isEmpty }.flatMap { service in
            service.geometry.enumerated().compactMap { index, points -> Path? in
                let measure = RouteMeasure(points)
                guard points.count > 1, measure.length > 1 else { return nil }
                var part = service
                part.id = service.id + ":part:\(index)"
                part.geometry = [points]
                part.circular = service.circular && points.first == points.last
                return Path(service: part, measure: measure)
            }
        }
        guard !paths.isEmpty else { return documented }
        let reference = paths.flatMap { $0.measure.points }.reduce(0) { $0 + $1.latitude }
            / Double(paths.reduce(0) { $0 + $1.measure.points.count })
        let scale = cos(reference * .pi / 180) * 111195
        func cell(_ point: GeoPoint) -> Cell { .init(x: Int(floor(point.longitude * scale / 200)), y: Int(floor(point.latitude * 111195 / 200))) }
        func add(_ path: Int, _ along: Double, offsets: Bool) {
            for offset in offsets ? [-25.0, 0, 25] : [0.0] {
                let value = min(paths[path].measure.length, max(0, along + offset))
                paths[path].positions.insert(Int((value * 100).rounded()))
            }
        }
        var grid: [Cell: [Segment]] = [:]
        for index in paths.indices {
            try Task.checkCancellation()
            let measure = paths[index].measure
            add(index, 0, offsets: false); add(index, measure.length, offsets: false)
            for point in [origin, destination] {
                for along in measure.nearest(point) { add(index, along, offsets: true) }
            }
            paths[index].anchors = paths[index].positions
            for segment in 0..<measure.points.count - 1 {
                let a = cell(measure.points[segment]), b = cell(measure.points[segment + 1])
                guard abs(a.x - b.x) <= 200 && abs(a.y - b.y) <= 200 else { continue }
                for x in min(a.x, b.x)...max(a.x, b.x) {
                    for y in min(a.y, b.y)...max(a.y, b.y) { grid[.init(x: x, y: y), default: []].append(.init(path: index, index: segment)) }
                }
            }
        }
        func connections(at point: GeoPoint, excluding: Int?) -> [Int: (along: Double, meters: Double)] {
            let center = cell(point)
            var best: [Int: (along: Double, meters: Double)] = [:]
            var visited = Set<String>()
            for x in center.x-2...center.x+2 {
                for y in center.y-2...center.y+2 {
                    for segment in grid[.init(x: x, y: y)] ?? [] where segment.path != excluding {
                        guard visited.insert("\(segment.path):\(segment.index)").inserted else { continue }
                        let projected = paths[segment.path].measure.projection(point, segment: segment.index)
                        if projected.meters <= 350, projected.meters < (best[segment.path]?.meters ?? .infinity) {
                            best[segment.path] = projected
                        }
                    }
                }
            }
            return best
        }
        for service in documented {
            for stop in service.stops {
                for (path, projection) in connections(at: stop.point, excluding: nil) { add(path, projection.along, offsets: true) }
            }
        }
        var meetings: [String: (a: Int, from: Double, b: Int, to: Double, meters: Double)] = [:]
        for index in paths.indices {
            try Task.checkCancellation()
            let measure = paths[index].measure
            let count = max(1, Int(ceil(measure.length / 250)))
            for sample in 0...count {
                if sample % 32 == 0 { try Task.checkCancellation() }
                let along = measure.length * Double(sample) / Double(count)
                let point = measure.point(at: along)
                for (other, projection) in connections(at: point, excluding: index) where other > index {
                    let key = "\(index):\(other)"
                    if projection.meters < (meetings[key]?.meters ?? .infinity) {
                        meetings[key] = (index, along, other, projection.along, projection.meters)
                    }
                }
            }
        }
        for meeting in meetings.values { add(meeting.a, meeting.from, offsets: meeting.meters <= 2); add(meeting.b, meeting.to, offsets: meeting.meters <= 2) }
        return documented + paths.map { path in
            var service = path.service
            var selected = path.anchors.sorted()
            for position in path.positions.sorted() where !path.anchors.contains(position) {
                if selected.allSatisfy({ abs($0 - position) >= 7500 }) { selected.append(position) }
            }
            for position in selected.sorted() {
                let along = min(path.measure.length, Double(position) / 100)
                if service.circular && along >= path.measure.length - 0.01 { continue }
                let id = "access:\(service.id):\(position)"
                service.stops.append(.init(id: id, name: "Punto sugerido", point: path.measure.point(at: along), suggested: true))
                service.accessPositions[id] = along
            }
            return service
        }
    }
}
