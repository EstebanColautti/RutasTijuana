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

struct CatalogInformation: Codable, Equatable, Sendable {
    struct Field: Codable, Equatable, Sendable {
        let category: String
        let label: String
        let value: String
        let evidence: String
        let inferred: Bool
    }
    let description: String
    let fields: [Field]

    var searchableText: String {
        ([description] + fields.map { "\($0.label) \($0.value)" }).joined(separator: " ")
    }
}

struct CatalogFeature: Codable, Identifiable, Equatable, Sendable {
    struct Itinerary: Codable, Equatable, Sendable {
        let stopIDs: [String]
        let circular: Bool
        let direction: String?
        let updatedAt: String?
    }
    enum Kind: String, Codable, Sendable { case route, area, reference, stop }
    let id: String
    let name: String
    let groupID: String
    let kind: Kind
    let color: String
    let verified: Bool
    let geometry: CatalogGeometry
    var information: CatalogInformation? = nil
    var itinerary: Itinerary?

    func publishedValues(for category: String) -> [String] {
        information?.fields.compactMap { field in
            guard field.category == category, !field.inferred else { return nil }
            let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        } ?? []
    }

    var orderedItinerary: Itinerary? {
        if let itinerary { return itinerary }
        let order = publishedValues(for: "stop-order")
        let shape = publishedValues(for: "route-shape")
        guard order.count == 1, shape.count == 1, ["linear", "circular"].contains(shape[0]),
              let ids = try? JSONDecoder().decode([String].self, from: Data(order[0].utf8)) else { return nil }
        return Itinerary(stopIDs: ids, circular: shape[0] == "circular",
                         direction: publishedValues(for: "direction").first,
                         updatedAt: publishedValues(for: "updated-at").first)
    }

    func distance(to point: GeoPoint) -> Double? {
        guard point.latitude.isFinite, point.longitude.isFinite,
              (-90...90).contains(point.latitude), (-180...180).contains(point.longitude) else { return nil }
        if kind == .stop, case .point(let position) = geometry {
            return position.point.distance(to: point)
        }
        guard kind == .route else { return nil }
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

enum CatalogFilter: String, CaseIterable, Identifiable {
    case all, routes, stops, areas
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Todos"
        case .routes: return "Recorridos"
        case .stops: return "Paradas"
        case .areas: return "Áreas y referencias"
        }
    }
    var supportsProximity: Bool { self == .routes || self == .stops }
    func includes(_ kind: CatalogFeature.Kind) -> Bool {
        switch self {
        case .all: return true
        case .routes: return kind == .route
        case .stops: return kind == .stop
        case .areas: return kind == .area || kind == .reference
        }
    }
}

struct RouteCatalog: Codable, Sendable {
    struct ServiceInformation: Codable, Sendable {
        let notices: [String]?
        let contact: URL?
    }
    let schemaVersion: Int
    let version: String
    let publishable: Bool
    let licenseStatus: String
    let groups: [CatalogGroup]
    let features: [CatalogFeature]
    var serviceInformation: ServiceInformation?

    var serviceNotices: [String] {
        guard readyForDistribution else { return [] }
        return serviceInformation?.notices
            ?? features.filter { $0.kind == .reference }.flatMap { $0.publishedValues(for: "notice") }
    }

    var serviceContact: URL? {
        guard readyForDistribution else { return nil }
        let links = features.filter { $0.kind == .reference }.flatMap { $0.publishedValues(for: "contact") }
            .compactMap { URL(string: $0) }
        let configured = serviceInformation?.contact.map { [$0] } ?? []
        return (configured + links).first {
            $0.scheme?.lowercased() == "https" && $0.host != nil && $0.user == nil && $0.password == nil
        }
    }

    func journeyScenario(for feature: CatalogFeature) -> JourneyScenario? {
        guard feature.kind == .route, let itinerary = feature.orderedItinerary,
              itinerary.stopIDs.count >= 2,
              Set(itinerary.stopIDs).count == itinerary.stopIDs.count else { return nil }
        let byID = Dictionary(features.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let stops = itinerary.stopIDs.compactMap { id -> TransitStop? in
            guard let stop = byID[id], stop.kind == .stop,
                  case .point(let location) = stop.geometry else { return nil }
            return TransitStop(id: id, name: stop.name, point: location.point)
        }
        guard stops.count == itinerary.stopIDs.count else { return nil }
        let schedule = feature.publishedValues(for: "schedule")
        return JourneyScenario(schemaVersion: 1, name: feature.name, coverageRadius: 2_000,
                               stops: stops, places: [], updatedAt: itinerary.updatedAt,
                               circular: itinerary.circular, direction: itinerary.direction,
                               routeID: feature.id, schedules: schedule)
    }

    var readyForDistribution: Bool { publishable && ["verified", "published"].contains(licenseStatus) }

    static func decode(_ data: Data, allowPrivate: Bool) throws -> RouteCatalog {
        guard data.count <= 16 * 1024 * 1024 else { throw CatalogError.tooLarge }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == 1 else { throw CatalogError.unsupportedVersion }
        guard allowPrivate || (value.publishable && value.licenseStatus == "verified") else { throw CatalogError.privateDataset }
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
        matching(query, groupID: groupID, filter: routesOnly ? .routes : .all)
    }

    func matching(_ query: String, groupID: String? = nil, filter: CatalogFilter) -> [CatalogFeature] {
        let terms = Self.fold(query).split(whereSeparator: \.isWhitespace)
        let names = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.name) })
        return features.filter { feature in
            let text = Self.fold(feature.name + " " + (names[feature.groupID] ?? "") + " " + (feature.information?.searchableText ?? ""))
            return filter.includes(feature.kind) && (groupID == nil || feature.groupID == groupID)
                && terms.allSatisfy { text.contains($0) }
        }.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_MX"))
    }

    static var informationSample: RouteCatalog {
        let base = sample
        var feature = base.features[0]
        feature.information = CatalogInformation(description: "Descripción de ejemplo",
            fields: [.init(category: "schedule", label: "Horario mencionado", value: "06:00–20:00",
                           evidence: "Horario: 06:00–20:00", inferred: false)])
        return RouteCatalog(schemaVersion: 1, version: "sample", publishable: true, licenseStatus: "verified",
                            groups: base.groups, features: [feature])
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
