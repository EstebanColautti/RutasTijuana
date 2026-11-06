import Foundation

struct JourneyPlace: Identifiable, Codable {
    let id: String
    let name: String
    let subtitle: String
    let category: String
    let stopID: String
    let keywords: [String]

    var symbol: String {
        switch category {
        case "hospital": return "cross.case.fill"
        case "culture": return "building.columns.fill"
        case "shopping": return "bag.fill"
        case "park": return "leaf.fill"
        case "sport": return "sportscourt.fill"
        default: return "mappin.circle.fill"
        }
    }
}

enum ScenarioError: Error { case invalid, evaluationOnly }

struct JourneyScenario: Codable {
    let schemaVersion: Int
    let name: String
    let coverageRadius: Double
    let stops: [TransitStop]
    let places: [JourneyPlace]
    var updatedAt: String?
    var circular: Bool?
    var direction: String?
    var fixedOriginID: String?
    var routeID: String?
    var schedules: [String]?
    var routeGeometry: [[GeoPoint]]?

    var updateDate: String? {
        guard let date = updatedAt?.trimmingCharacters(in: .whitespacesAndNewlines), !date.isEmpty else { return nil }
        return date
    }

    var route: TransitRoute {
        TransitRoute(name: name, stops: stops, coverageRadius: coverageRadius, isCircular: circular == true)
    }

    static var sample: JourneyScenario {
        JourneyScenario(schemaVersion: 1, name: TransitRoute.demonstration.name,
            coverageRadius: TransitRoute.demonstration.coverageRadius,
            stops: TransitRoute.demonstration.stops, places: [], circular: true)
    }

    #if DEBUG
    static var evaluation: JourneyScenario {
        var scenario = sample
        scenario.updatedAt = "21/10/2026"
        scenario.fixedOriginID = scenario.stops.first?.id
        return scenario
    }
    #endif

    static func decode(_ data: Data, allowEvaluation: Bool) throws -> JourneyScenario {
        guard allowEvaluation else { throw ScenarioError.evaluationOnly }
        guard data.count <= 2_000_000 else { throw ScenarioError.invalid }
        var value = try JSONDecoder().decode(Self.self, from: data)
        value.routeID = nil
        value.routeGeometry = nil
        if value.circular == nil { value.circular = true }
        let ids = Set(value.stops.map(\.id))
        guard value.schemaVersion == 1, !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.stops.count >= 2, value.stops.count <= 1_000, ids.count == value.stops.count,
              value.fixedOriginID.map({ ids.contains($0) }) ?? true,
              value.coverageRadius.isFinite, value.coverageRadius > 0, value.coverageRadius <= 10_000,
              value.stops.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty &&
                  $0.point.latitude.isFinite && $0.point.longitude.isFinite &&
                  (-90...90).contains($0.point.latitude) && (-180...180).contains($0.point.longitude) }),
              value.places.count <= 5_000, Set(value.places.map(\.id)).count == value.places.count,
              value.places.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && ids.contains($0.stopID) })
        else { throw ScenarioError.invalid }
        return value
    }

    func mappedSection(for journey: [TransitStop]) -> [GeoPoint]? {
        guard journey.count >= 2, let routeGeometry else { return nil }
        let matches = routeGeometry.compactMap { section(on: $0, through: journey) }
        return matches.count == 1 ? matches[0] : nil
    }

    private func section(on path: [GeoPoint], through journey: [TransitStop]) -> [GeoPoint]? {
        guard path.count >= 2 else { return nil }
        var lengths: [Double] = [0]
        for index in 1..<path.count {
            lengths.append(lengths[index - 1] + path[index - 1].distance(to: path[index]))
        }
        guard let total = lengths.last, total > 0 else { return nil }
        let canWrap = circular == true && path.first == path.last

        func locate(_ stop: GeoPoint) -> (along: Double, point: GeoPoint)? {
            let scale = cos(stop.latitude * .pi / 180)
            var candidates: [(along: Double, point: GeoPoint, distance: Double)] = []
            for index in 1..<path.count where lengths[index] > lengths[index - 1] {
                let a = path[index - 1], b = path[index]
                let x = (b.longitude - a.longitude) * scale
                let y = b.latitude - a.latitude
                let squared = x * x + y * y
                guard squared > 0 else { continue }
                let t = min(1, max(0, ((stop.longitude - a.longitude) * scale * x + (stop.latitude - a.latitude) * y) / squared))
                let point = GeoPoint(latitude: a.latitude + t * (b.latitude - a.latitude),
                                     longitude: a.longitude + t * (b.longitude - a.longitude))
                let distance = stop.distance(to: point)
                if distance <= 40 {
                    candidates.append((lengths[index - 1] + t * (lengths[index] - lengths[index - 1]), point, distance))
                }
            }
            guard let best = candidates.min(by: { $0.distance < $1.distance }) else { return nil }
            let ambiguous = candidates.contains {
                let gap = abs(best.along - $0.along)
                return $0.distance <= best.distance + 5 && (canWrap ? min(gap, total - gap) : gap) > 20
            }
            return ambiguous ? nil : (best.along, best.point)
        }

        let locations = journey.compactMap { locate($0.point) }
        guard locations.count == journey.count, let first = locations.first, let last = locations.last else { return nil }
        var end = first.along
        for location in locations.dropFirst() {
            var along = location.along
            if along <= end && canWrap { along += total }
            guard along > end, along - first.along <= total && (!canWrap || along - first.along < total) else { return nil }
            end = along
        }
        var result = [first.point]
        for offset in end > total ? [0.0, total] : [0.0] {
            for index in path.indices where lengths[index] + offset > first.along && lengths[index] + offset < end {
                if result.last != path[index] { result.append(path[index]) }
            }
        }
        if result.last != last.point { result.append(last.point) }
        return result.count >= 2 ? result : nil
    }

    func matchingStops(_ query: String) -> [TransitStop] {
        stops.filter { matches(query, in: "\($0.name) \($0.id)") }
    }

    func matchingPlaces(_ query: String) -> [JourneyPlace] {
        places.filter { matches(query, in: "\($0.name) \($0.subtitle) \($0.category) \($0.keywords.joined(separator: " "))") }
    }

    private func matches(_ query: String, in text: String) -> Bool {
        let locale = Locale(identifier: "es_MX")
        let value = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale)
        return query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale)
            .split(whereSeparator: { $0.isWhitespace }).allSatisfy { value.contains($0) }
    }
}

struct RecentJourney: Codable, Equatable {
    let routeID: String?
    let originID: String
    let destinationID: String
}

enum RouteValidation: Equatable {
    case accepted
    case rejected
    case invalid

    var title: String {
        switch self {
        case .accepted: return "Ruta aceptada"
        case .rejected: return "Ruta rechazada"
        case .invalid: return "Dato inválido"
        }
    }
}

func validarRuta(origen: String, destino: String, paradasPrincipales: Int, fechaActualizacion: String?) -> RouteValidation {
    let origin = origen.trimmingCharacters(in: .whitespacesAndNewlines)
    let destination = destino.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !origin.isEmpty, !destination.isEmpty, origin != destination, paradasPrincipales >= 0 else {
        return .invalid
    }
    let date = fechaActualizacion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return paradasPrincipales >= 2 && !date.isEmpty ? .accepted : .rejected
}
