import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}

let route = TransitRoute.demonstration
check(Set(route.stops.map(\.id)).count == route.stops.count, "Identificadores duplicados")
check(route.journey(from: "demo-1", to: "demo-4")?.map(\.id) == ["demo-1", "demo-2", "demo-3", "demo-4"], "Orden del recorrido")
check(route.journey(from: "demo-5", to: "demo-2")?.map(\.id) == ["demo-5", "demo-6", "demo-1", "demo-2"], "Continuidad al cerrar el circuito")
check(route.journey(from: "demo-1", to: "demo-1") == nil, "Origen y destino iguales")
check(route.journey(from: "missing", to: "demo-2") == nil, "Parada inexistente")
let empty = TransitRoute(name: "Vacía", stops: [], coverageRadius: 2_000)
check(empty.journey(from: "a", to: "b") == nil, "Recorrido vacío")
check(empty.nearbyStops(to: route.stops[0].point).isEmpty, "Catálogo vacío")
let nearby = route.nearbyStops(to: route.stops[0].point)
check(nearby.count == 3 && nearby.first?.id == "demo-1", "Paradas cercanas")
check(zip(nearby, nearby.dropFirst()).allSatisfy { $0.0.distance <= $0.1.distance }, "Distancias ordenadas")
check(route.nearbyStops(to: GeoPoint(latitude: 0, longitude: 0)).isEmpty, "Punto fuera de cobertura")
let equator = GeoPoint(latitude: 0, longitude: 0)
let distance = equator.distance(to: GeoPoint(latitude: 0, longitude: 1))
check(abs(distance - 111_195) < 2, "Conversión de distancia a metros")
check(equator.distance(to: equator) == 0, "Distancia del mismo punto")
print("Pruebas de trayectos correctas")

func rejects(_ data: Data, allowPrivate: Bool = true) -> Bool {
    do { _ = try RouteCatalog.decode(data, allowPrivate: allowPrivate); return false }
    catch { return true }
}

let sampleData = try JSONEncoder().encode(RouteCatalog.sample)
let sample = try RouteCatalog.decode(sampleData, allowPrivate: false)
check(sample.features.count == 1, "Carga de catálogo")
check(sample.matching("recórrido EJEMPLO").count == 1, "Búsqueda sin distinción de acentos")
check(sample.matching("inexistente").isEmpty, "Búsqueda sin coincidencias")
check(sample.matching("", groupID: "missing").isEmpty, "Filtro de grupo")
var sampleObject = try JSONSerialization.jsonObject(with: sampleData) as! [String: Any]
sampleObject["publishable"] = false
sampleObject["licenseStatus"] = "pending_review"
let privateData = try JSONSerialization.data(withJSONObject: sampleObject)
check(rejects(privateData, allowPrivate: false), "El catálogo privado no se permite en distribución")
check(try RouteCatalog.decode(privateData, allowPrivate: true).features.count == 1, "Carga interna de catálogo privado")
sampleObject["publishable"] = true
check(rejects(try JSONSerialization.data(withJSONObject: sampleObject), allowPrivate: false), "La licencia pendiente no se habilita cambiando una bandera")
sampleObject["schemaVersion"] = 99
check(rejects(try JSONSerialization.data(withJSONObject: sampleObject)), "Versión no compatible")
sampleObject["schemaVersion"] = 1
var sampleFeatures = sampleObject["features"] as! [[String: Any]]
sampleObject["features"] = sampleFeatures + sampleFeatures
check(rejects(try JSONSerialization.data(withJSONObject: sampleObject)), "Identificadores duplicados")
sampleFeatures[0]["groupID"] = "missing"
sampleObject["features"] = sampleFeatures
check(rejects(try JSONSerialization.data(withJSONObject: sampleObject)), "Referencias de grupo inválidas")
sampleFeatures[0]["groupID"] = "sample"
sampleFeatures[0]["geometry"] = ["type": "LineString", "coordinates": [[32.5, -117.0], [32.6, -117.1]]]
sampleObject["features"] = sampleFeatures
check(rejects(try JSONSerialization.data(withJSONObject: sampleObject)), "Coordenadas invertidas fuera del intervalo de latitud")
sampleFeatures[0]["geometry"] = ["type": "LineString", "coordinates": [[-117, 32.5]]]
sampleObject["features"] = sampleFeatures
check(rejects(try JSONSerialization.data(withJSONObject: sampleObject)), "Línea con un solo vértice")
let line = CatalogFeature(id: "line", name: "Ejemplo", groupID: "sample", kind: .route,
                          color: "#2476E8", verified: false,
                          geometry: .line([CatalogPosition(longitude: 0, latitude: 0), CatalogPosition(longitude: 2, latitude: 0)]))
check(abs(line.distance(to: GeoPoint(latitude: 1, longitude: 1))! - 111_195) < 2, "Distancia al segmento y no solo a sus vértices")
check(line.distance(to: GeoPoint(latitude: 0, longitude: 1))! < 0.01, "Punto sobre un trazado")
check(abs(line.distance(to: GeoPoint(latitude: 0, longitude: 3))! - 111_195) < 2, "Extremo más próximo fuera del segmento")
let ring = [CatalogPosition(longitude: -117, latitude: 32.5), CatalogPosition(longitude: -117.01, latitude: 32.5),
            CatalogPosition(longitude: -117.01, latitude: 32.51), CatalogPosition(longitude: -117, latitude: 32.5)]
let area = CatalogFeature(id: "area", name: "Área", groupID: "sample", kind: .area, color: "#2476E8",
                          verified: false, geometry: .polygon([ring, ring]))
check(area.distance(to: GeoPoint(latitude: 32.5, longitude: -117)) == nil, "Las áreas no se ofrecen como recorridos cercanos")
let areaCatalog = RouteCatalog(schemaVersion: 1, version: "sample", publishable: true, licenseStatus: "verified",
                               groups: sample.groups, features: sample.features + [area])
let decodedArea = try RouteCatalog.decode(JSONEncoder().encode(areaCatalog), allowPrivate: false)
check(decodedArea.features[1].geometry.polygons[0].count == 2, "Conservación de los anillos interiores")
check(decodedArea.matching("").count == 1 && decodedArea.matching("", routesOnly: false).count == 2, "Separación de recorridos y áreas")
if let path = ProcessInfo.processInfo.environment["CATALOG_TEST_FILE"] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let local = try RouteCatalog.decode(data, allowPrivate: true)
    let original = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let originals = original["features"] as! [[String: Any]]
    func vertexCount(_ value: Any) -> Int {
        guard let array = value as? [Any], !array.isEmpty else { return 0 }
        if array.first is NSNumber { return 1 }
        return array.reduce(0) { $0 + vertexCount($1) }
    }
    let originalVertices = originals.reduce(0) { sum, row in
        sum + vertexCount((row["geometry"] as! [String: Any])["coordinates"]!)
    }
    check(local.features.count == originals.count, "Recuento completo del catálogo local")
    check(local.features.reduce(0) { $0 + $1.geometry.positions.count } == originalVertices, "Conservación de los vértices del catálogo local")
    check(local.features.filter { $0.kind == .route }.count == originals.filter { $0["kind"] as? String == "route" }.count, "Recuento de recorridos del catálogo local")
}
print("Pruebas de catálogo correctas")
