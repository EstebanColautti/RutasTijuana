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
        let value = try JSONDecoder().decode(Self.self, from: data)
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
