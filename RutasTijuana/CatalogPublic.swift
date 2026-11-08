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
        "fare": "Tarifa", "schedule": "Horario", "places": "Lugares", "updated-at": "Actualización",
        "stop-order": "Orden de paradas", "route-shape": "Tipo de recorrido", "notice": "Aviso", "service-role": "Servicio"]

    static func text(_ value: String) -> Bool {
        let lower = value.lowercased()
        return value.count <= 4000 && !["http:", "https:", "www.", "plugin://", "file://", "<", ">",
            "mymaps", "geojson", ".kml", ".pdf", "source_id", "xml_path", "google drive", "figma", "procedencia"].contains { lower.contains($0) }
    }

    static func information(_ value: CatalogInformation?, description: Bool = false) -> CatalogInformation? {
        guard let value else { return nil }
        var seen = Set<String>()
        let fields = value.fields.compactMap { field -> CatalogInformation.Field? in
            guard !field.inferred, let label = labels[field.category], text(field.value) else { return nil }
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
