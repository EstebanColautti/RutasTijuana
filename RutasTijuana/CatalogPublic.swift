import Foundation

struct CatalogRouteDetails: Codable, Equatable, Sendable {
    var code: String?
    var direction: String?
    var circular: Bool?
}

struct CatalogAsset: Codable, Equatable, Sendable {
    let id: String
    let bytes: Int
    let sha256: String
    let mimeType: String
    let downloadURL: URL
    var width: Int?
    var height: Int?

    var isValid: Bool {
        id == sha256 && id.count == 64 && id.allSatisfy { $0.isHexDigit && !$0.isUppercase }
            && bytes > 0 && bytes <= 2 * 1024 * 1024 && mimeType == "image/jpeg"
            && (width.map { $0 > 0 && $0 <= 4096 } ?? true)
            && (height.map { $0 > 0 && $0 <= 4096 } ?? true)
    }
}

enum CatalogPublic {
    static let labels = ["code": "Código", "direction": "Sentido", "circuit": "Circuito",
        "fare": "Tarifa", "schedule": "Horario", "contact": "Contacto", "places": "Lugares", "updated-at": "Actualización",
        "stop-order": "Orden de paradas", "route-shape": "Tipo de recorrido", "notice": "Aviso", "service-role": "Servicio"]

    static func validatePayload(_ data: Data) throws {
        func object(_ value: Any?, keys: Set<String>) throws -> [String: Any] {
            guard let object = value as? [String: Any], Set(object.keys).isSubset(of: keys) else { throw CatalogSyncError.format }
            return object
        }
        let document = try object(JSONSerialization.jsonObject(with: data), keys: ["schemaVersion", "version", "groups", "features", "serviceInformation"])
        guard let groups = document["groups"] as? [Any], let features = document["features"] as? [Any] else { throw CatalogSyncError.format }
        for group in groups { _ = try object(group, keys: ["id", "name"]) }
        for value in features {
            let feature = try object(value, keys: ["id", "name", "groupID", "kind", "color", "geometry", "information", "itinerary", "routeDetails", "media"])
            _ = try object(feature["geometry"], keys: ["type", "coordinates"])
            let information = try object(feature["information"], keys: ["description", "fields"])
            guard let fields = information["fields"] as? [Any] else { throw CatalogSyncError.format }
            for field in fields { _ = try object(field, keys: ["category", "label", "value"]) }
            if let details = feature["routeDetails"], !(details is NSNull) { _ = try object(details, keys: ["code", "direction", "circular"]) }
            if let itinerary = feature["itinerary"], !(itinerary is NSNull) { _ = try object(itinerary, keys: ["stopIDs", "circular", "direction", "updatedAt"]) }
        }
        if let service = document["serviceInformation"], !(service is NSNull) { _ = try object(service, keys: ["notices", "contact"]) }
    }

    static func text(_ value: String) -> Bool {
        let lower = value.lowercased()
        return value.count <= 4000 && !["http:", "https:", "www.", "plugin://", "file://", "<", ">",
            "mymaps", "geojson", ".kml", ".pdf", "source_id", "xml_path", "google drive", "figma", "procedencia"].contains { lower.contains($0) }
    }

    static func information(_ value: CatalogInformation?, description: Bool = false) -> CatalogInformation? {
        guard let value else { return nil }
        var seen = Set<String>()
        let fields = value.fields.compactMap { field -> CatalogInformation.Field? in
            guard !field.inferred, let label = labels[field.category] else { return nil }
            if field.category == "contact" {
                guard let url = URL(string: field.value), url.scheme == "https", url.host != nil,
                      url.user == nil, url.password == nil, field.value.count <= 4000 else { return nil }
            } else if !text(field.value) { return nil }
            let trimmed = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(field.category + "|" + trimmed).inserted else { return nil }
            return .init(category: field.category, label: label, value: trimmed, evidence: "", inferred: false)
        }
        return .init(description: description && text(value.description) ? value.description : "", fields: fields)
    }

    static func catalog(_ value: RouteCatalog, description: Bool = false) -> RouteCatalog {
        let features = value.features.map { feature in
            var feature = feature
            feature.information = information(feature.information, description: description)
            return feature
        }
        return RouteCatalog(schemaVersion: value.schemaVersion, version: value.version, publishable: value.publishable,
            licenseStatus: value.licenseStatus, groups: value.groups, features: features, serviceInformation: value.serviceInformation)
    }
}
