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
check(rejects(try JSONSerialization.data(withJSONObject: sampleObject), allowPrivate: false), "La política de distribución comprueba ambos campos")
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

let scenario = JourneyScenario.sample
let scenarioData = try JSONEncoder().encode(scenario)
let decodedScenario = try JourneyScenario.decode(scenarioData, allowEvaluation: true)
check(decodedScenario.stops.count == 6, "Escenario de evaluación")
check(decodedScenario.matchingStops("PARADA 1").count == 1, "Búsqueda de paradas")
check(decodedScenario.matchingStops("inexistente").isEmpty, "Sin coincidencias")
do {
    _ = try JourneyScenario.decode(scenarioData, allowEvaluation: false)
    fatalError("Release debe rechazar escenarios de evaluación")
} catch ScenarioError.evaluationOnly { }
let malformedScenario = JourneyScenario(schemaVersion: 1, name: "Ejemplo", coverageRadius: 100,
    stops: scenario.stops, places: [JourneyPlace(id: "1", name: "Referencia", subtitle: "",
        category: "culture", stopID: "missing", keywords: [])])
do {
    _ = try JourneyScenario.decode(JSONEncoder().encode(malformedScenario), allowEvaluation: true)
    fatalError("Debe rechazar referencias sin parada")
} catch ScenarioError.invalid { }
let searchScenario = JourneyScenario(schemaVersion: 1, name: "Ejemplo", coverageRadius: 100,
    stops: scenario.stops, places: [JourneyPlace(id: "1", name: "Lugar de prueba", subtitle: "Cultura",
        category: "culture", stopID: scenario.stops[0].id, keywords: ["música"])])
check(searchScenario.matchingPlaces("MUSICA cultura").count == 1, "Búsqueda por palabras y acentos")
if let path = ProcessInfo.processInfo.environment["SCENARIO_TEST_FILE"] {
    let local = try JourneyScenario.decode(Data(contentsOf: URL(fileURLWithPath: path)), allowEvaluation: true)
    check(!local.stops.isEmpty && !local.places.isEmpty, "Escenario local")
}
print("Pruebas de escenarios correctas")

var enriched = RouteCatalog.sample
var enrichedFeature = enriched.features[0]
enrichedFeature.information = CatalogInformation(description: "Salida desde Lugar de ejemplo",
    fields: [.init(category: "fare", label: "Tarifa", value: "$9", evidence: "Tarifa: $9", inferred: false)])
let enrichedCatalog = RouteCatalog(schemaVersion: 1, version: "test", publishable: true,
    licenseStatus: "verified", groups: enriched.groups, features: [enrichedFeature])
let informationRoundTrip = try RouteCatalog.decode(JSONEncoder().encode(enrichedCatalog), allowPrivate: true)
check(informationRoundTrip.features[0].information == enrichedFeature.information, "Información completa de ida y vuelta")
check(informationRoundTrip.matching("lugar $9").count == 1, "Búsqueda en descripción y campos")

final class MemoryCatalogCache: CatalogCache {
    var snapshot: CatalogSnapshot?
    var attempted: Date?
    var failWrites = false
    func current() throws -> CatalogSnapshot? { snapshot }
    func replace(_ snapshot: CatalogSnapshot) throws {
        if failWrites { throw CatalogSyncError.storage }
        self.snapshot = snapshot
    }
    func lastAttempt() throws -> Date? { attempted }
    func recordAttempt(_ date: Date) throws { attempted = date }
}
final class FixtureCatalogTransport: CatalogTransport {
    var values: [URL: Data] = [:]
    var calls = 0
    func fetch(_ url: URL, limit: Int) async throws -> Data {
        calls += 1
        guard let value = values[url] else { throw CatalogSyncError.response }
        return value
    }
}
let syncEndpoint = URL(string: "https://example.test/functions/v1/catalog")!
let snapshotURL = URL(string: "https://example.test/functions/v1/catalog?version=one")!
let publishedData = Data("""
{"schemaVersion":2,"version":"one","groups":[{"id":"g","name":"Ejemplo"}],"features":[{"id":"r","name":"Recorrido","groupID":"g","kind":"route","color":"#2476E8","geometry":{"type":"LineString","coordinates":[[-117,32.5],[-117.01,32.51]]},"information":{"description":"Texto público","fields":[]}}]}
""".utf8)
#if canImport(CryptoKit)
import CryptoKit
func fixtureDigest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format:"%02x",$0) }.joined() }
#else
func fixtureDigest(_ data: Data) -> String { String(repeating: data == publishedData ? "a" : "b", count:64) }
#endif
let syncCache = MemoryCatalogCache()
let syncTransport = FixtureCatalogTransport()
let validManifest = CatalogManifest(version:"one",schemaVersion:2,bytes:publishedData.count,sha256:fixtureDigest(publishedData),downloadURL:snapshotURL)
syncTransport.values[syncEndpoint] = try JSONEncoder().encode(validManifest)
syncTransport.values[snapshotURL] = publishedData
let synchronizer = CatalogSynchronizer(transport:syncTransport,cache:syncCache,digest:fixtureDigest,allowLoopbackHTTP:false)
let firstSync = try await synchronizer.update(from:syncEndpoint,force:false,now:Date(timeIntervalSince1970:1000))
check(firstSync?.features.count == 1, "Descarga del catálogo")
check(syncCache.snapshot?.data == publishedData, "Contenido conservado sin cambios")
_ = try await synchronizer.update(from:syncEndpoint,force:false,now:Date(timeIntervalSince1970:1100))
check(syncTransport.calls == 2, "Intervalo de actualización")
_ = try await synchronizer.update(from:syncEndpoint,force:true,now:Date(timeIntervalSince1970:1200))
check(syncTransport.calls == 3, "La misma versión no se vuelve a descargar")
let hostileManifest = CatalogManifest(version:"two",schemaVersion:2,bytes:publishedData.count,sha256:fixtureDigest(publishedData),downloadURL:URL(string:"https://other.test/catalog")!)
syncTransport.values[syncEndpoint] = try JSONEncoder().encode(hostileManifest)
do { _ = try await synchronizer.update(from:syncEndpoint,force:true); fatalError("Debe rechazar otro origen") } catch CatalogSyncError.address { }
check(syncCache.snapshot?.version == "one", "Conserva el catálogo ante un origen incorrecto")
let corruptManifest = CatalogManifest(version:"two",schemaVersion:2,bytes:publishedData.count,sha256:String(repeating:"0",count:64),downloadURL:snapshotURL)
syncTransport.values[syncEndpoint] = try JSONEncoder().encode(corruptManifest)
do { _ = try await synchronizer.update(from:syncEndpoint,force:true); fatalError("Debe rechazar contenido alterado") } catch CatalogSyncError.integrity { }
check(syncCache.snapshot?.version == "one", "Conserva el catálogo ante un fallo de integridad")
syncTransport.values.removeAll()
do { _ = try await synchronizer.update(from:syncEndpoint,force:true); fatalError("Debe informar la falta de conexión") } catch CatalogSyncError.response { }
check(syncCache.snapshot?.version == "one", "Conserva la copia sin conexión")
do { try CatalogSynchronizer.checkAddress(URL(string:"http://example.test/catalog")!,allowLoopbackHTTP:true); fatalError("No debe aceptar HTTP externo") } catch CatalogSyncError.address { }
try CatalogSynchronizer.checkAddress(URL(string:"http://127.0.0.1:54321/functions/v1/catalog")!,allowLoopbackHTTP:true)
let relativeCache = MemoryCatalogCache()
let relativeTransport = FixtureCatalogTransport()
relativeTransport.values[syncEndpoint] = try JSONEncoder().encode(CatalogManifest(version:"one",schemaVersion:2,bytes:publishedData.count,sha256:fixtureDigest(publishedData),downloadURL:URL(string:"?version=one")!))
relativeTransport.values[snapshotURL] = publishedData
let relativeSync = CatalogSynchronizer(transport:relativeTransport,cache:relativeCache,digest:fixtureDigest,allowLoopbackHTTP:false)
check(try await relativeSync.update(from:syncEndpoint,force:true)?.features.count == 1, "Dirección de descarga relativa")
let tooBig = CatalogManifest(version:"two",schemaVersion:2,bytes:CatalogSynchronizer.maximumBytes+1,sha256:fixtureDigest(publishedData),downloadURL:snapshotURL)
relativeTransport.values[syncEndpoint] = try JSONEncoder().encode(tooBig)
do { _ = try await relativeSync.update(from:syncEndpoint,force:true); fatalError("Debe limitar el tamaño del manifiesto") } catch CatalogSyncError.format { }
check(relativeCache.snapshot?.version == "one", "Un archivo demasiado grande no sustituye la copia")
if let address = ProcessInfo.processInfo.environment["CATALOG_HTTP_TEST_URL"], let base = URL(string:address) {
    let transport = NetworkCatalogTransport()
    let bytes = try await transport.fetch(base.appendingPathComponent("ok"),limit:1024)
    check(String(data:bytes,encoding:.utf8) == "{}", "Descarga HTTP acotada")
    for path in ["large","stream","redirect","error"] {
        do { _ = try await transport.fetch(base.appendingPathComponent(path),limit:1024); fatalError("Debe rechazar \(path)") }
        catch { }
    }
}
#if canImport(SQLite3)
import SQLite3
let cacheDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let cacheURL = cacheDirectory.appendingPathComponent("catalog.sqlite")
let nativeCache = try SQLiteCatalogCache(url:cacheURL)
try nativeCache.replace(.init(version:"one",sha256:fixtureDigest(publishedData),data:publishedData))
let reopenedCache = try SQLiteCatalogCache(url:cacheURL)
check(try reopenedCache.current()?.data == publishedData, "SQLite conserva los datos al reabrir")
var database: OpaquePointer?
check(sqlite3_open(cacheURL.path,&database) == SQLITE_OK, "Abrir base de prueba")
check(sqlite3_exec(database,"CREATE TRIGGER reject_snapshot BEFORE INSERT ON snapshots WHEN NEW.version='broken' BEGIN SELECT RAISE(ABORT,'test'); END",nil,nil,nil) == SQLITE_OK, "Preparar fallo transaccional")
sqlite3_close(database)
do { try nativeCache.replace(.init(version:"broken",sha256:"broken",data:publishedData)); fatalError("Debe revertir la transacción") } catch CatalogSyncError.storage { }
check(try nativeCache.current()?.version == "one", "SQLite revierte el reemplazo fallido")
#endif
print("Pruebas de actualización correctas")
