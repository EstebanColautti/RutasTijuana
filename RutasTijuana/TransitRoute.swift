import Foundation

struct GeoPoint: Equatable, Codable {
    let latitude: Double
    let longitude: Double

    func distance(to other: GeoPoint) -> Double {
        let radians = Double.pi / 180
        let value = pow(sin((other.latitude - latitude) * radians / 2), 2)
            + cos(latitude * radians) * cos(other.latitude * radians)
            * pow(sin((other.longitude - longitude) * radians / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, value))))
    }
}

struct TransitStop: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let point: GeoPoint
}

struct NearbyStop: Identifiable {
    let stop: TransitStop
    let distance: Double
    var id: String { stop.id }
}

struct TransitRoute {
    let name: String
    let stops: [TransitStop]
    let coverageRadius: Double

    func nearbyStops(to point: GeoPoint) -> [NearbyStop] {
        let distances: [NearbyStop] = stops.map { stop in
            NearbyStop(stop: stop, distance: point.distance(to: stop.point))
        }
        let covered = distances.filter { $0.distance <= coverageRadius }
        let sorted = covered.sorted { first, second in
            if first.distance == second.distance { return first.id < second.id }
            return first.distance < second.distance
        }
        return Array(sorted.prefix(3))
    }

    func journey(from origin: String, to destination: String) -> [TransitStop]? {
        guard origin != destination,
              let start = stops.firstIndex(where: { $0.id == origin }),
              let end = stops.firstIndex(where: { $0.id == destination }) else { return nil }
        let count = (end - start + stops.count) % stops.count
        return (0...count).map { stops[(start + $0) % stops.count] }
    }

    static let demonstration = TransitRoute(
        name: "Ruta de demostración",
        stops: [
            TransitStop(id: "demo-1", name: "Parada 1", point: GeoPoint(latitude: 32.525, longitude: -117.020)),
            TransitStop(id: "demo-2", name: "Parada 2", point: GeoPoint(latitude: 32.531, longitude: -117.020)),
            TransitStop(id: "demo-3", name: "Parada 3", point: GeoPoint(latitude: 32.537, longitude: -117.015)),
            TransitStop(id: "demo-4", name: "Parada 4", point: GeoPoint(latitude: 32.537, longitude: -117.005)),
            TransitStop(id: "demo-5", name: "Parada 5", point: GeoPoint(latitude: 32.531, longitude: -117.005)),
            TransitStop(id: "demo-6", name: "Parada 6", point: GeoPoint(latitude: 32.525, longitude: -117.010))
        ],
        coverageRadius: 2_000
    )
}
