import SwiftUI
import MapKit

@MainActor final class AppleTripWalkingProvider: TripWalkingProvider {
    private let provider = AppleWalkingRouteProvider()
    func route(from: GeoPoint, to: GeoPoint) async throws -> WalkingRoute? {
        do {
            return try await provider.route(from: from, to: .init(id: "walk", name: "Destino", point: to))
        } catch let error as MKError where error.code == .directionsNotFound {
            return nil
        }
    }
}

#if DEBUG
@MainActor final class FixtureTripWalkingProvider: TripWalkingProvider {
    func route(from: GeoPoint, to: GeoPoint) async throws -> WalkingRoute? {
        guard from.distance(to: to) <= 150 else { return nil }
        return .init(points: [from, to], steps: [.init(instruction: "Continúa", endDistance: from.distance(to: to))],
                     duration: from.distance(to: to) / 1.2)
    }
}

extension RouteCatalog {
    static var tripSample: RouteCatalog {
        let stops = (0..<3).map { index in
            CatalogFeature(id: "trip-stop-\(index)", name: "Parada \(index + 1)", groupID: "g", kind: .stop,
                color: "#164B85", verified: false,
                geometry: .point(.init(longitude: -117, latitude: 32.5 + Double(index) * 0.01)))
        }
        let routes = (0..<2).map { index in
            CatalogFeature(id: "trip-route-\(index)", name: "Recorrido \(index + 1)", groupID: "g", kind: .route,
                color: "#164B85", verified: false,
                geometry: .line([.init(longitude: -117, latitude: 32.5 + Double(index) * 0.01),
                                       .init(longitude: -117, latitude: 32.5 + Double(index + 1) * 0.01)]),
                itinerary: .init(stopIDs: ["trip-stop-\(index)", "trip-stop-\(index + 1)"],
                                 circular: false, direction: "Sentido de ejemplo", updatedAt: "2026-11-07"))
        }
        return .init(schemaVersion: 1, version: "trip-example", publishable: true, licenseStatus: "published",
                     groups: [.init(id: "g", name: "Ejemplo")], features: stops + routes)
    }
}
#endif

struct TripPlannerView: View {
    let catalog: RouteCatalog
    @StateObject private var location = LocationService()
    @State private var origin: GeoPoint?
    @State private var destination: GeoPoint?
    @State private var originName = ""
    @State private var destinationName = ""
    @State private var query = ""
    @State private var selectingOrigin = false
    @State private var places: [MKMapItem] = []
    @State private var message = ""
    @State private var planner: TripPlanner?
    @State private var trip: PlannedTrip?
    @State private var working = false
    @State private var paused = false
    @State private var task: Task<Void, Never>?
    @State private var search: MKLocalSearch?
    @State private var searchGeneration = UUID()
    @State private var travelling = false
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 32.53, longitude: -117),
        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)))

    init(catalog: RouteCatalog) {
        self.catalog = catalog
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--trip-fixture") {
            _origin = State(initialValue: GeoPoint(latitude: 32.4991, longitude: -117))
            _destination = State(initialValue: GeoPoint(latitude: 32.5209, longitude: -117))
            _originName = State(initialValue: "Origen de ejemplo")
            _destinationName = State(initialValue: "Destino de ejemplo")
            _planner = State(initialValue: TripPlanner(network: .init(catalog: catalog), provider: FixtureTripWalkingProvider()))
        }
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--trip-fixture") {
                    Text("Datos de evaluación").font(.footnote)
                }
                #endif
                Text("Origen").font(.headline)
                Text(originName.isEmpty ? "Elige desde dónde sales" : originName)
                Button("Usar mi ubicación") { invalidate(); location.request() }
                    .frame(minHeight: 44).disabled(location.isRequesting || working)
                Toggle("Buscar un origen", isOn: $selectingOrigin).disabled(working)
                selectionMap
                Text("Destino").font(.headline)
                Text(destinationName.isEmpty ? "Elige a dónde quieres llegar" : destinationName)
                TextField(selectingOrigin ? "Buscar origen" : "Buscar destino", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search).onSubmit { findPlaces() }
                    .disabled(working)
                Button("Buscar lugar") { findPlaces() }.frame(minHeight: 44).disabled(working)
                ForEach(Array(places.enumerated()), id: \.offset) { row in
                    Button {
                        guard let coordinate = row.element.placemark.location?.coordinate else { return }
                        invalidate()
                        let point = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
                        if selectingOrigin { origin = point; originName = row.element.name ?? "Origen"; selectingOrigin = false }
                        else { destination = point; destinationName = row.element.name ?? "Destino" }
                        places = []
                        query = ""
                    } label: {
                        VStack(alignment: .leading) {
                            Text(row.element.name ?? "Lugar")
                            Text(row.element.placemark.title ?? "").font(.caption)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
                if let error = location.message { Text(error) }
                if !message.isEmpty { Text(message).accessibilityIdentifier("trip-status") }
                if working {
                    ProgressView("Calculando itinerario")
                    Button("Cancelar") { invalidate() }.frame(minHeight: 44)
                } else {
                    Button(paused ? "Continuar búsqueda" : "Calcular viaje") { calculate() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("trip-calculate")
                        .disabled(origin == nil || destination == nil)
                        .frame(minHeight: 44)
                }
                if let trip {
                    Text("Ruta recomendada").font(.title2.bold()).accessibilityIdentifier("trip-result")
                    Text("\(trip.transfers) transbordos · \(WalkingFormat.distance(trip.walkingMeters)) a pie")
                    if trip.exceedsPreferences {
                        Text("Este viaje requiere ampliar la caminata o los transbordos preferidos.")
                    }
                    ForEach(Array(trip.legs.enumerated()), id: \.offset) { row in
                        legSummary(row.element)
                    }
                    Button("Iniciar viaje") { travelling = true }
                        .accessibilityIdentifier("trip-begin")
                        .buttonStyle(.borderedProminent).frame(minHeight: 44)
                }
            }.padding()
        }
        .navigationTitle("Planear viaje")
        .fullScreenCover(isPresented: $travelling) {
            if let trip {
                TripTravelView(trip: trip, onReplan: { point in
                    invalidate()
                    origin = point
                    originName = "Tu ubicación"
                    travelling = false
                    calculate()
                })
            }
        }
        .onChange(of: location.point) { _, point in
            if let point { invalidate(); origin = point; originName = "Tu ubicación" }
        }
        .onChange(of: selectingOrigin) { _, _ in
            search?.cancel()
            searchGeneration = UUID()
            places = []
        }
        .onDisappear {
            task?.cancel()
            let cancelledPlanner = planner
            Task { await cancelledPlanner?.cancel() }
            search?.cancel()
            location.cancel()
        }
    }

    @ViewBuilder private var selectionMap: some View {
                MapReader { proxy in
                    Map(position: $camera) {
                        if let origin {
                            Marker("Origen", coordinate: .init(latitude: origin.latitude, longitude: origin.longitude))
                        }
                        if let destination {
                            Marker("Destino", coordinate: .init(latitude: destination.latitude, longitude: destination.longitude))
                        }
                        if let trip {
                            ForEach(Array(trip.legs.enumerated()), id: \.offset) { row in
                                switch row.element {
                                case .walk(_, _, let route):
                                    MapPolyline(coordinates: route.points.map { .init(latitude: $0.latitude, longitude: $0.longitude) })
                                        .stroke(.blue, style: StrokeStyle(lineWidth: 4, dash: [6, 4]))
                                case .ride(let service, let stops):
                                    if let path = service.section(through: stops) {
                                        MapPolyline(coordinates: path.map { .init(latitude: $0.latitude, longitude: $0.longitude) })
                                            .stroke(.indigo, lineWidth: 5)
                                    } else {
                                        ForEach(Array(service.geometry.enumerated()), id: \.offset) { part in
                                            MapPolyline(coordinates: part.element.map { .init(latitude: $0.latitude, longitude: $0.longitude) })
                                                .stroke(.gray, lineWidth: 3)
                                        }
                                    }
                                    if let stop = stops.first {
                                        Marker("Sube en " + stop.name, coordinate: .init(latitude: stop.point.latitude, longitude: stop.point.longitude))
                                    }
                                    if let stop = stops.last {
                                        Marker("Baja en " + stop.name, coordinate: .init(latitude: stop.point.latitude, longitude: stop.point.longitude))
                                    }
                                }
                            }
                        }
                    }
                    .onTapGesture { position in
                        guard !working, let coordinate = proxy.convert(position, from: .local) else { return }
                        invalidate()
                        let point = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
                        if selectingOrigin { origin = point; originName = "Origen en el mapa"; selectingOrigin = false }
                        else { destination = point; destinationName = "Destino en el mapa" }
                    }
                }.frame(height: 240)
                .accessibilityLabel("Mapa de origen y destino")
                .accessibilityHint("También puedes buscar ambos lugares usando el buscador.")
                Text(selectingOrigin ? "Toca el mapa para elegir el origen." : "Toca el mapa para elegir el destino.")
                    .font(.footnote)
    }

    @ViewBuilder private func legSummary(_ leg: TripLeg) -> some View {
        switch leg {
        case .walk(_, _, let route):
            Label("Camina \(WalkingFormat.distance(route.length)) · \(WalkingFormat.duration(route.duration, arrived: false))", systemImage: "figure.walk")
        case .ride(let service, let stops):
            VStack(alignment: .leading) {
                Label(service.name, systemImage: "bus")
                Text(service.direction ?? "Sentido según el orden de paradas")
                Text("Sube en \(stops.first?.name ?? "")")
                Text("Baja en \(stops.last?.name ?? "")")
            }
        }
    }

    private func invalidate() {
        task?.cancel()
        let cancelledPlanner = planner
        Task { await cancelledPlanner?.cancel() }
        planner = nil
        trip = nil
        paused = false
        working = false
        message = ""
    }

    private func findPlaces() {
        search?.cancel()
        let token = UUID()
        searchGeneration = token
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 32.53, longitude: -117),
                                            span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3))
        let operation = MKLocalSearch(request: request)
        search = operation
        operation.start { response, error in
            guard searchGeneration == token else { return }
            places = response?.mapItems ?? []
            message = error == nil ? (places.isEmpty ? "No se encontraron lugares." : "") : "No se pudo buscar. Intenta de nuevo."
        }
    }

    private func calculate() {
        guard let origin, let destination, origin != destination else {
            message = "Elige un destino distinto del origen."
            return
        }
        if planner == nil { planner = TripPlanner(network: .init(catalog: catalog), provider: AppleTripWalkingProvider()) }
        working = true
        message = ""
        task = Task {
            do {
                let result = try await planner!.search(from: origin, to: destination)
                guard !Task.isCancelled else { return }
                switch result {
                case .found(let result): trip = result; paused = false; camera = .automatic
                case .paused: paused = true; message = "La búsqueda necesita continuar."
                case .unavailable: message = "No se encontró una conexión con los recorridos disponibles."
                }
            } catch {
                guard !Task.isCancelled else { return }
                message = "No se pudo calcular el viaje. Comprueba la conexión y vuelve a intentar."
            }
            working = false
        }
    }
}
