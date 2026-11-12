import SwiftUI
import MapKit
import Accessibility

struct TripActionButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
    }
}

@MainActor final class AppleTripWalkingProvider: TripWalkingProvider {
    private let provider = AppleWalkingRouteProvider()
    private var generation = UUID()
    private var nextRequest = Date.distantPast
    private var failures = 0

    func cancel() async {
        generation = UUID()
        provider.cancel()
    }

    func route(from: GeoPoint, to: GeoPoint) async throws -> WalkingRoute? {
        guard Date() >= nextRequest else { throw TripPlanningError.tryAgainLater }
        let token = UUID()
        generation = token
        let deadline = Task {
            do { try await Task.sleep(nanoseconds: 30_000_000_000) }
            catch { return }
            if generation == token { provider.cancel() }
        }
        defer { deadline.cancel() }
        return try await withTaskCancellationHandler {
            do {
                let route = try await provider.route(from: from, to: .init(id: "walk", name: "Destino", point: to))
                failures = 0
                return route
            } catch let error as MKError where error.code == .directionsNotFound {
                failures = 0
                return nil
            } catch {
                if Task.isCancelled || generation != token { throw CancellationError() }
                nextRequest = Date().addingTimeInterval(WalkingPolicy.retryDelays[min(failures, 2)])
                failures += 1
                throw error
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, generation == token else { return }
                provider.cancel()
            }
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var textSize
    @StateObject private var location = LocationService()
    @State private var origin: GeoPoint?
    @State private var destination: GeoPoint?
    @State private var originName = ""
    @State private var destinationName = ""
    @State private var originReference: GeoPoint?
    @State private var destinationReference: GeoPoint?
    @State private var originReferenceUsesLocation = false
    @State private var requestingOriginLocation = false
    @State private var query = ""
    @State private var selectingOrigin = true
    @State private var places: [MKMapItem] = []
    @State private var message = ""
    @State private var transferCache = TripTransferCache()
    @State private var planner: TripPlanner?
    @State private var plannedVersion: String?
    @State private var trip: PlannedTrip?
    @State private var working = false
    @State private var paused = false
    @State private var task: Task<Void, Never>?
    @State private var search: MKLocalSearch?
    @State private var searchGeneration = UUID()
    @State private var travelling = false
    @FocusState private var searchFocused: Bool
    @AccessibilityFocusState private var resultFocused: Bool
    @State private var selectingOnMap = false
    @State private var mapPoint: GeoPoint?
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 32.53, longitude: -117),
        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)))

    init(catalog: RouteCatalog) {
        self.catalog = catalog
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--capture-catalog"),
           let line = catalog.features.first(where: { $0.kind == .route && !$0.geometry.lines.isEmpty })?.geometry.lines.first,
           line.count >= 2 {
            _origin = State(initialValue: line[Int((Double(line.count - 1) * 0.2).rounded())].point)
            _destination = State(initialValue: line[Int((Double(line.count - 1) * 0.6).rounded())].point)
            _originName = State(initialValue: "Origen de prueba")
            _destinationName = State(initialValue: "Destino de prueba")
            _planner = State(initialValue: TripPlanner(network: .init(catalog: catalog), provider: AppleTripWalkingProvider()))
            _plannedVersion = State(initialValue: catalog.version)
        } else if ProcessInfo.processInfo.arguments.contains("--trip-fixture") {
            _origin = State(initialValue: GeoPoint(latitude: 32.4991, longitude: -117))
            _destination = State(initialValue: GeoPoint(latitude: 32.5209, longitude: -117))
            _originName = State(initialValue: "Origen de ejemplo")
            _destinationName = State(initialValue: "Destino de ejemplo")
            _planner = State(initialValue: TripPlanner(network: .init(catalog: catalog), provider: FixtureTripWalkingProvider()))
            _plannedVersion = State(initialValue: catalog.version)
        }
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Map(position: $camera) { mapContents }
                    .frame(height: geometry.size.height * (textSize.isAccessibilitySize ? 0.26 : trip == nil ? 0.52 : 0.42))
                    .accessibilityLabel("Mapa de origen, destino e itinerario")
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("--trip-fixture") {
                            Text("Datos de evaluación").font(.footnote)
                        }
                        #endif
                        if trip == nil {
                        if selectingOrigin {
                            Text("Desde dónde sales").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                            Text(originName.isEmpty ? "Elige desde dónde sales" : originName)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                            TripActionButton("Usar mi ubicación") {
                                invalidate()
                                requestingOriginLocation = true
                                location.request()
                            }
                                .frame(minHeight: 44).disabled(location.isRequesting || working)
                        } else {
                            Label(originName.isEmpty ? "Origen" : "Origen: \(originName)", systemImage: "a.circle")
                            Text("A dónde vas").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                            Text(destinationName.isEmpty ? "Elige a dónde quieres llegar" : destinationName)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                        }
                        selectionMap
                        stopSuggestions
                        Text(selectingOrigin ? "Buscar origen" : "Buscar destino").font(.subheadline)
                        TextField(selectingOrigin ? "Buscar origen" : "Buscar destino", text: $query, prompt: Text(""))
                            .focused($searchFocused)
                            .accessibilityIdentifier("trip-place-search")
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .background(.background, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary))
                            .contentShape(Rectangle())
                            .onTapGesture { searchFocused = true }
                            .submitLabel(.search).onSubmit { findPlaces() }
                            .disabled(working)
                        TripActionButton("Buscar lugar") { findPlaces() }.frame(minHeight: 44).disabled(working)
                        ForEach(Array(places.enumerated()), id: \.offset) { row in
                            Button {
                                guard let coordinate = row.element.placemark.location?.coordinate else { return }
                                requestingOriginLocation = false
                                location.cancel()
                                invalidate()
                                let point = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
                                if selectingOrigin { origin = point; originName = row.element.name ?? "Origen"; originReference = point; originReferenceUsesLocation = false }
                                else { destination = point; destinationName = row.element.name ?? "Destino"; destinationReference = point }
                                places = []
                                query = ""
                                camera = .automatic
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(row.element.name ?? "Lugar")
                                    Text(row.element.placemark.title ?? "").font(.caption)
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                            }.accessibilityIdentifier("trip-place-\(row.offset)")
                        }
                        if let error = location.message { Text(error) }
                        if !message.isEmpty { Text(message).accessibilityIdentifier("trip-status") }
                        }
                        if let trip {
                            if let error = location.message { Text(error) }
                            if !message.isEmpty { Text(message).accessibilityIdentifier("trip-status") }
                            Text(primaryService?.name ?? "Ruta recomendada").font(.title2.bold())
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityFocused($resultFocused)
                                .accessibilityIdentifier("trip-result")
                                .onAppear { resultFocused = true }
                            if let direction = primaryService?.direction, !direction.isEmpty {
                                Text(direction).font(.subheadline)
                            }
                            Text("\(trip.transfers) \(trip.transfers == 1 ? "transbordo" : "transbordos") · \(WalkingFormat.distance(trip.walkingMeters)) a pie")
                            if trip.exceedsPreferences {
                                Text("Este viaje requiere ampliar la caminata o los transbordos preferidos.")
                            }
                            ForEach(Array(trip.legs.enumerated()), id: \.offset) { row in
                                legSummary(row.element)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                    .background(.background, in: RoundedRectangle(cornerRadius: 14))
                            }
                            Text("El seguimiento utiliza tu ubicación durante el viaje. Los avisos de bajada son opcionales.")
                                .font(.footnote)
                        }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                }
                .id("\(trip != nil)-\(selectingOrigin)")
                .scrollDismissesKeyboard(.interactively)
                .background(Color(uiColor: .secondarySystemBackground), in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    primaryAction
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .secondarySystemBackground))
                }
            }
        }
        .tint(colorScheme == .dark ? Color(red: 0.65, green: 0.81, blue: 1) : Color(red: 0.02, green: 0.29, blue: 0.57))
        .preferredColorScheme(testColorScheme)
        .navigationTitle(trip != nil ? "Tu trayecto" : selectingOrigin ? "Desde dónde sales" : "A dónde vas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if trip != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Editar") { invalidate() }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Cambiar origen o destino")
                        .accessibilityIdentifier("Cambiar origen o destino")
                }
            } else if !selectingOrigin {
                ToolbarItem(placement: .primaryAction) {
                    Button("Cambiar origen") { selectingOrigin = true }
                        .frame(minHeight: 44).disabled(working)
                }
            }
        }
        .sheet(isPresented: $selectingOnMap) { mapSelection }
        .fullScreenCover(isPresented: $travelling) {
            if let trip {
                TripTravelView(trip: trip, destinationName: destinationName, onReplan: { point in
                    invalidate()
                    origin = point
                    originName = "Tu ubicación"
                    originReference = nil
                    originReferenceUsesLocation = false
                    travelling = false
                    calculate()
                })
            }
        }
        .onChange(of: location.point) { _, point in
            guard selectingOrigin, requestingOriginLocation, let point else { return }
            requestingOriginLocation = false
            invalidate(); origin = point; originName = "Tu ubicación"
            if let accuracy = location.horizontalAccuracy, accuracy >= 0, accuracy <= 100 {
                originReference = point; originReferenceUsesLocation = true
            } else {
                originReference = nil; originReferenceUsesLocation = false
            }
        }
        .onChange(of: message) { _, text in
            if !text.isEmpty { AccessibilityNotification.Announcement(text).post() }
        }
        .onChange(of: selectingOrigin) { _, _ in
            requestingOriginLocation = false
            location.cancel()
            search?.cancel()
            searchGeneration = UUID()
            places = []
            query = ""
            message = ""
        }
        .onDisappear {
            searchGeneration = UUID()
            task?.cancel()
            let cancelledPlanner = planner
            Task { await cancelledPlanner?.cancel() }
            search?.cancel()
            location.cancel()
        }
    }

    @ViewBuilder private var primaryAction: some View {
        if trip != nil {
            Button { travelling = true } label: {
                Text("Iniciar ruta").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityIdentifier("trip-begin")
            .disabled(working)
            .buttonStyle(.borderedProminent)
        } else if selectingOrigin {
            Button { selectingOrigin = false } label: {
                Text("Continuar").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityIdentifier("trip-continue")
            .disabled(origin == nil || working)
            .buttonStyle(.borderedProminent)
        } else if working {
            HStack {
                ProgressView("Calculando itinerario")
                Spacer()
                TripActionButton("Cancelar") { invalidate() }.frame(minHeight: 44)
            }
        } else {
            Button(action: calculate) {
                Text(paused ? "Continuar búsqueda" : "Ver trayecto")
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityIdentifier("trip-calculate")
            .disabled(origin == nil || destination == nil)
            .buttonStyle(.borderedProminent)
        }
    }

    private var testColorScheme: ColorScheme? {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--trip-dark") ? .dark : nil
        #else
        return nil
        #endif
    }

    private var primaryService: TripService? {
        guard let trip else { return nil }
        for leg in trip.legs {
            if case .ride(let service, _) = leg { return service }
        }
        return nil
    }

    @MapContentBuilder private var mapContents: some MapContent {

        if let origin {
            Marker("Origen", systemImage: "a.circle.fill", coordinate: .init(latitude: origin.latitude, longitude: origin.longitude))
                .tint(.blue)
        }
        if let destination, !selectingOrigin || trip != nil {
            Marker("Destino", systemImage: "b.circle.fill", coordinate: .init(latitude: destination.latitude, longitude: destination.longitude))
                .tint(colorScheme == .dark ? .indigo : .black)
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
                        Marker("Sube en " + stop.name, systemImage: "a.circle.fill", coordinate: .init(latitude: stop.point.latitude, longitude: stop.point.longitude))
                            .tint(.blue)
                    }
                    if let stop = stops.last {
                        Marker("Baja en " + stop.name, systemImage: "b.circle.fill", coordinate: .init(latitude: stop.point.latitude, longitude: stop.point.longitude))
                            .tint(colorScheme == .dark ? .indigo : .black)
                    }
                }
            }
        }
    }

    private struct NearbyStop: Identifiable {
        let feature: CatalogFeature
        let distance: Double
        var id: String { feature.id }
    }

    private var catalogHasStops: Bool {
        catalog.features.contains { feature in
            guard feature.kind == .stop, case .point = feature.geometry else { return false }
            return true
        }
    }

    private var nearbyStops: [NearbyStop] {
        let reference = selectingOrigin ? originReference : destinationReference
        guard let reference, reference.latitude.isFinite, reference.longitude.isFinite,
              (-90...90).contains(reference.latitude), (-180...180).contains(reference.longitude) else { return [] }
        return catalog.features.compactMap { feature in
            guard feature.kind == .stop, case .point(let position) = feature.geometry else { return nil }
            let distance = position.point.distance(to: reference)
            guard distance.isFinite, distance <= 1_000 else { return nil }
            return NearbyStop(feature: feature, distance: distance)
        }.sorted { $0.distance == $1.distance ? $0.id < $1.id : $0.distance < $1.distance }.prefix(3).map { $0 }
    }

    private func isSelected(_ feature: CatalogFeature) -> Bool {
        guard case .point(let coordinate) = feature.geometry else { return false }
        return (selectingOrigin ? origin : destination) == coordinate.point
    }

    @ViewBuilder private var stopSuggestions: some View {
        if !catalogHasStops {
            Text("Puedes elegir un lugar o seleccionarlo en el mapa.")
                .font(.footnote)
        } else if (selectingOrigin ? originReference : destinationReference) == nil {
            Text("Elige un punto en el mapa o busca un lugar para ver paradas cercanas.")
                .font(.footnote)
        } else if nearbyStops.isEmpty {
            Text("No hay paradas cercanas a este punto. Puedes elegir otro lugar.")
                .font(.footnote)
        } else {
            Text("Paradas cercanas").font(.headline).accessibilityAddTraits(.isHeader)
            if selectingOrigin && originReferenceUsesLocation {
                Text("Al elegir una parada, el viaje comenzará desde ella; no se incluye la caminata desde tu ubicación.").font(.footnote)
            }
            ForEach(nearbyStops) { item in
                Button {
                    guard case .point(let coordinate) = item.feature.geometry else { return }
                    requestingOriginLocation = false
                    location.cancel()
                    search?.cancel()
                    searchGeneration = UUID()
                    invalidate()
                    if selectingOrigin {
                        origin = coordinate.point; originName = item.feature.name
                    } else {
                        destination = coordinate.point; destinationName = item.feature.name
                    }
                    places = []; query = ""; searchFocused = false; camera = .automatic
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bus.fill").accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.feature.name).fontWeight(.medium)
                            Text("A \(WalkingFormat.distance(item.distance)) en línea recta").font(.caption)
                        }
                        Spacer(minLength: 0)
                        if isSelected(item.feature) {
                            Image(systemName: "checkmark").accessibilityLabel("Seleccionada")
                        }
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(12).background(.background, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .accessibilityValue(isSelected(item.feature) ? "Seleccionada" : "")
                .accessibilityIdentifier("trip-stop-\(item.feature.id)")
            }
        }
    }

    private var selectionMap: some View {
        TripActionButton(selectingOrigin ? "Elegir origen en el mapa" : "Elegir destino en el mapa") {
            requestingOriginLocation = false
            location.cancel()
            mapPoint = selectingOrigin ? origin : destination
            selectingOnMap = true
        }.disabled(working)
    }

    private var mapSelection: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $camera) {
                    mapContents
                    if let mapPoint {
                        Marker("Punto seleccionado", coordinate: .init(latitude: mapPoint.latitude, longitude: mapPoint.longitude))
                    }
                }
                .onTapGesture { position in
                    guard let coordinate = proxy.convert(position, from: .local) else { return }
                    mapPoint = .init(latitude: coordinate.latitude, longitude: coordinate.longitude)
                }
            }
            .navigationTitle(selectingOrigin ? "Elegir origen" : "Elegir destino")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    TripActionButton("Cancelar") { selectingOnMap = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    TripActionButton("Usar punto") {
                        guard let mapPoint else { return }
                        invalidate()
                        search?.cancel()
                        searchGeneration = UUID()
                        places = []
                        query = ""
                        if selectingOrigin { origin = mapPoint; originName = "Origen en el mapa"; originReference = mapPoint; originReferenceUsesLocation = false }
                        else { destination = mapPoint; destinationName = "Destino en el mapa"; destinationReference = mapPoint }
                        camera = .automatic
                        selectingOnMap = false
                    }.disabled(mapPoint == nil)
                }
            }
        }
    }

    @ViewBuilder private func legSummary(_ leg: TripLeg) -> some View {
        switch leg {
        case .walk(_, _, let route):
            Label("Camina \(WalkingFormat.distance(route.length)) · \(WalkingFormat.duration(route.duration, arrived: false))", systemImage: "figure.walk")
        case .ride(let service, let stops):
            VStack(alignment: .leading) {
                Label(service.name, systemImage: "bus")
                Text(service.direction ?? "Sentido del recorrido")
                Text(stops.first?.suggested == true ? "Punto de subida sugerido" : "Sube en \(stops.first?.name ?? "")")
                Text(stops.last?.suggested == true ? "Punto de bajada sugerido" : "Baja en \(stops.last?.name ?? "")")
                if stops.contains(where: \.suggested) {
                    Text("Confirma con el conductor dónde puedes subir y bajar.").font(.footnote)
                }
                if service.section(through: stops) == nil {
                    Text("El seguimiento de esta etapa usa confirmación manual.").font(.footnote)
                }
            }
        }
    }

    private func invalidate() {
        task?.cancel()
        let cancelledPlanner = planner
        Task { await cancelledPlanner?.cancel() }
        planner = nil
        plannedVersion = nil
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
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { places = []; message = "Escribe el nombre de un lugar."; return }
        searchFocused = false
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--trip-fixture") {
            places = catalog.features.compactMap { feature in
                guard feature.kind == .stop, feature.name.localizedStandardContains(text),
                      case .point(let coordinate) = feature.geometry else { return nil }
                let item = MKMapItem(placemark: .init(coordinate: .init(latitude: coordinate.latitude, longitude: coordinate.longitude)))
                item.name = feature.name
                return item
            }
            message = places.isEmpty ? "No se encontraron lugares." : ""
            return
        }
        #endif
        request.naturalLanguageQuery = text
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
        guard !working else { return }
        guard let origin, let destination, origin != destination else {
            message = "Elige un destino distinto del origen."
            return
        }
        if planner == nil || (!paused && plannedVersion != catalog.version) {
            if plannedVersion != catalog.version { trip = nil }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--trip-fixture") {
                planner = TripPlanner(network: .init(catalog: catalog), provider: FixtureTripWalkingProvider())
            } else {
                planner = TripPlanner(network: .init(catalog: catalog), provider: AppleTripWalkingProvider(), transferCache: transferCache)
            }
            #else
            planner = TripPlanner(network: .init(catalog: catalog), provider: AppleTripWalkingProvider(), transferCache: transferCache)
            #endif
            plannedVersion = catalog.version
        }
        guard let activePlanner = planner else { return }
        working = true
        message = ""
        task = Task {
            do {
                try Task.checkCancellation()
                let result = try await activePlanner.search(from: origin, to: destination)
                guard !Task.isCancelled else { return }
                switch result {
                case .found(let result): trip = result; paused = false; camera = .automatic
                case .paused: paused = true; message = "La búsqueda necesita continuar."
                case .unavailable:
                    trip = nil
                    paused = false
                    message = "No se encontró una conexión con los recorridos disponibles."
                }
            } catch TripPlanningError.tryAgainLater {
                guard !Task.isCancelled else { return }
                message = "Espera un momento antes de volver a calcular."
            } catch {
                guard !Task.isCancelled else { return }
                message = "No se pudo calcular el viaje. Comprueba la conexión y vuelve a intentar."
            }
            working = false
        }
    }
}
