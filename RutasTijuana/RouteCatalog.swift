import Foundation

struct CatalogPosition: Codable, Equatable, Sendable {
    let longitude: Double
    let latitude: Double
    let altitude: Double?

    init(longitude: Double, latitude: Double, altitude: Double? = nil) {
        self.longitude = longitude
        self.latitude = latitude
        self.altitude = altitude
    }

    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        longitude = try values.decode(Double.self)
        latitude = try values.decode(Double.self)
        altitude = values.isAtEnd ? nil : try values.decode(Double.self)
        guard values.isAtEnd, longitude.isFinite, latitude.isFinite,
              (-180...180).contains(longitude), (-90...90).contains(latitude),
              altitude == nil || altitude!.isFinite else { throw CatalogError.invalidCoordinates }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(longitude)
        try values.encode(latitude)
        if let altitude { try values.encode(altitude) }
    }

    var point: GeoPoint { GeoPoint(latitude: latitude, longitude: longitude) }
}

enum CatalogGeometry: Codable, Equatable, Sendable {
    case point(CatalogPosition)
    case line([CatalogPosition])
    case multiLine([[CatalogPosition]])
    case polygon([[CatalogPosition]])
    case multiPolygon([[[CatalogPosition]]])

    private enum Keys: String, CodingKey { case type, coordinates }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        switch try values.decode(String.self, forKey: .type) {
        case "Point": self = .point(try values.decode(CatalogPosition.self, forKey: .coordinates))
        case "LineString": self = .line(try values.decode([CatalogPosition].self, forKey: .coordinates))
        case "MultiLineString": self = .multiLine(try values.decode([[CatalogPosition]].self, forKey: .coordinates))
        case "Polygon": self = .polygon(try values.decode([[CatalogPosition]].self, forKey: .coordinates))
        case "MultiPolygon": self = .multiPolygon(try values.decode([[[CatalogPosition]]].self, forKey: .coordinates))
        default: throw CatalogError.unsupportedGeometry
        }
        guard !positions.isEmpty, lines.allSatisfy({ $0.count >= 2 }),
              polygons.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.count >= 4 && $0.first == $0.last } })
        else { throw CatalogError.invalidCoordinates }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: Keys.self)
        switch self {
        case .point(let coordinates):
            try values.encode("Point", forKey: .type); try values.encode(coordinates, forKey: .coordinates)
        case .line(let coordinates):
            try values.encode("LineString", forKey: .type); try values.encode(coordinates, forKey: .coordinates)
        case .multiLine(let coordinates):
            try values.encode("MultiLineString", forKey: .type); try values.encode(coordinates, forKey: .coordinates)
        case .polygon(let coordinates):
            try values.encode("Polygon", forKey: .type); try values.encode(coordinates, forKey: .coordinates)
        case .multiPolygon(let coordinates):
            try values.encode("MultiPolygon", forKey: .type); try values.encode(coordinates, forKey: .coordinates)
        }
    }

    var lines: [[CatalogPosition]] {
        switch self {
        case .line(let value): return [value]
        case .multiLine(let value): return value
        default: return []
        }
    }

    var polygons: [[[CatalogPosition]]] {
        switch self {
        case .polygon(let value): return [value]
        case .multiPolygon(let value): return value
        default: return []
        }
    }

    var positions: [CatalogPosition] {
        if case .point(let value) = self { return [value] }
        return lines.flatMap { $0 } + polygons.flatMap { $0.flatMap { $0 } }
    }
}

struct CatalogGroup: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

struct CatalogFeature: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case route, area, reference }
    let id: String
    let name: String
    let groupID: String
    let kind: Kind
    let color: String
    let verified: Bool
    let geometry: CatalogGeometry

    func distance(to point: GeoPoint) -> Double? {
        guard kind == .route, point.latitude.isFinite, point.longitude.isFinite,
              (-90...90).contains(point.latitude), (-180...180).contains(point.longitude) else { return nil }
        return geometry.lines.flatMap { line in
            zip(line, line.dropFirst()).map { Self.segmentDistance(point, $0.point, $1.point) }
        }.min()
    }

    private static func segmentDistance(_ point: GeoPoint, _ start: GeoPoint, _ end: GeoPoint) -> Double {
        let radius = 6_371_000.0
        let length = start.distance(to: end) / radius
        guard length > 1e-12 else { return start.distance(to: point) }
        func bearing(_ a: GeoPoint, _ b: GeoPoint) -> Double {
            let scale = Double.pi / 180
            let delta = (b.longitude - a.longitude) * scale
            return atan2(sin(delta) * cos(b.latitude * scale),
                         cos(a.latitude * scale) * sin(b.latitude * scale)
                         - sin(a.latitude * scale) * cos(b.latitude * scale) * cos(delta))
        }
        let angular = start.distance(to: point) / radius
        let difference = bearing(start, point) - bearing(start, end)
        let along = atan2(sin(angular) * cos(difference), cos(angular))
        guard along >= 0, along <= length else { return min(start.distance(to: point), end.distance(to: point)) }
        return abs(asin(max(-1, min(1, sin(angular) * sin(difference))))) * radius
    }
}

struct RouteCatalog: Codable, Sendable {
    let schemaVersion: Int
    let version: String
    let publishable: Bool
    let licenseStatus: String
    let groups: [CatalogGroup]
    let features: [CatalogFeature]

    var readyForDistribution: Bool { publishable && licenseStatus == "verified" }

    static func decode(_ data: Data, allowPrivate: Bool) throws -> RouteCatalog {
        guard data.count <= 16 * 1024 * 1024 else { throw CatalogError.tooLarge }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == 1 else { throw CatalogError.unsupportedVersion }
        guard allowPrivate || value.readyForDistribution else { throw CatalogError.privateDataset }
        let groupIDs = Set(value.groups.map(\.id))
        guard groupIDs.count == value.groups.count,
              value.groups.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty }),
              Set(value.features.map(\.id)).count == value.features.count,
              value.features.count <= 10_000,
              value.features.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && groupIDs.contains($0.groupID)
                  && ($0.kind != .route || !$0.geometry.lines.isEmpty) }) else { throw CatalogError.invalidCatalog }
        return value
    }

    func matching(_ query: String, groupID: String? = nil, routesOnly: Bool = true) -> [CatalogFeature] {
        let terms = Self.fold(query).split(whereSeparator: \.isWhitespace)
        let names = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.name) })
        return features.filter { feature in
            let text = Self.fold(feature.name + " " + (names[feature.groupID] ?? ""))
            return (!routesOnly || feature.kind == .route) && (groupID == nil || feature.groupID == groupID)
                && terms.allSatisfy { text.contains($0) }
        }.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_MX"))
    }

    static var sample: RouteCatalog {
        RouteCatalog(schemaVersion: 1, version: "sample", publishable: true, licenseStatus: "verified",
                     groups: [CatalogGroup(id: "sample", name: "Ejemplo")],
                     features: [CatalogFeature(id: "sample-route", name: "Recorrido de ejemplo", groupID: "sample",
                                               kind: .route, color: "#2476E8", verified: false,
                                               geometry: .line([CatalogPosition(longitude: -117.02, latitude: 32.525),
                                                                CatalogPosition(longitude: -117.015, latitude: 32.537)]))])
    }
}

enum CatalogError: LocalizedError {
    case invalidCoordinates, unsupportedGeometry, unsupportedVersion, privateDataset, invalidCatalog, tooLarge

    var errorDescription: String? {
        switch self {
        case .invalidCoordinates: return "El catálogo contiene una geometría no válida."
        case .unsupportedGeometry: return "El tipo de geometría no es compatible."
        case .unsupportedVersion: return "La versión del catálogo no es compatible."
        case .privateDataset: return "Este catálogo solo puede abrirse en una compilación de desarrollo."
        case .invalidCatalog: return "El catálogo contiene referencias o identificadores no válidos."
        case .tooLarge: return "El catálogo supera el tamaño permitido."
        }
    }
}
