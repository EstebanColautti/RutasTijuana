import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
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
