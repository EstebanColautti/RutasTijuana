import SwiftUI
import MapKit
import UniformTypeIdentifiers

private extension GeoPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct ContentView: View {
    private enum Stage { case home, origin, destination, journey }
    @State private var scenario: JourneyScenario
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var catalogRepository = CatalogRepository.shared
    private var route: TransitRoute { scenario.route }
    @State private var search = ""
    @State private var walkingDestination: WalkingDestination?
    @State private var importing = false
    @State private var importError: String?
    @State private var detent: PresentationDetent = .medium
    @StateObject private var connectivity = ConnectivityMonitor()
    @State private var stage = Stage.home
    @State private var origin: GeoPoint?
    @State private var destination: GeoPoint?
    @State private var originID: String?
    @State private var destinationID: String?
    @State private var selectedStop: String?
    @State private var invalidDestination = false
    @State private var validation: RouteValidation = .invalid
    @State private var simulationStep: Int?
    @State private var categoryFilter: String?
    @AppStorage("journey-recent") private var recentData = Data()
    @AccessibilityFocusState private var resultFocused: Bool
    private var evaluation: Bool { scenario.fixedOriginID != nil }
    private var isDemo: Bool { scenario.routeID == nil }

    init(scenario: JourneyScenario = .sample, recent: RecentJourney? = nil) {
        _scenario = State(initialValue: scenario)
        if let recent, let start = scenario.stops.first(where: { $0.id == recent.originID }),
           let end = scenario.stops.first(where: { $0.id == recent.destinationID }) {
            _origin = State(initialValue: start.point)
            _destination = State(initialValue: end.point)
            _originID = State(initialValue: start.id)
            _destinationID = State(initialValue: end.id)
            _validation = State(initialValue: .accepted)
            _stage = State(initialValue: .journey)
        }
    }
    @State private var camera = MapCameraPosition.region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 32.531, longitude: -117.012),
        span: MKCoordinateSpan(latitudeDelta: 0.024, longitudeDelta: 0.024)
    ))
    #if os(iOS)
    @StateObject private var location = LocationService()
    #endif

    private var title: String {
        if let step = simulationStep {
            return step >= trip.count ? "Viaje finalizado" : "Trayecto en curso"
        }
        switch stage {
        case .home: return ""
        case .origin: return "Desde dónde sales"
        case .destination: return evaluation ? "¿Dónde bajas?" : "A dónde vas"
        case .journey: return "Tu trayecto"
        }
    }

    private var trip: [TransitStop] {
        guard let originID, let destinationID else { return [] }
        return route.journey(from: originID, to: destinationID) ?? []
    }

    private var mappedTrip: [GeoPoint]? { scenario.mappedSection(for: trip) }

    var body: some View {
        NavigationStack {
            Group {
                if stage == .home { welcome }
                else {
                    routeMap
                        .overlay(alignment: .top) {
                            if !connectivity.isConnected {
                                Label("Sin conexión · Puedes elegir de la lista", systemImage: "wifi.slash")
                                    .font(.caption).padding(10).background(.regularMaterial, in: Capsule()).padding()
                            }
                        }
                }
            }
            .sheet(isPresented: Binding(get: { stage != .home }, set: { _ in })) {
                NavigationStack {
                    panel
                        .navigationTitle(title)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(action: back) {
                                    Label(stage == .destination && !evaluation ? "Cambiar origen" : "Regresar", systemImage: "chevron.left")
                                }
                            }
                        }
                }
                .fullScreenCover(item: $walkingDestination) { WalkingNavigationView(destination: $0) }
                .presentationDetents([.medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .interactiveDismissDisabled()
                .presentationDragIndicator(.visible)
                .alert(evaluation ? "Dato inválido" : "Destino no válido", isPresented: $invalidDestination) {
                    Button("Cambiar destino", role: .cancel) { }
                } message: {
                    Text("Elige una parada de bajada distinta de la parada de origen.")
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                importScenario(result)
            }
            .alert("No se pudo abrir", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("Aceptar", role: .cancel) { importError = nil }
            } message: { Text(importError ?? "") }
            .navigationTitle(stage == .home ? "" : title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onChange(of: selectedStop) { _, id in
                guard !invalidDestination, stage != .journey,
                      let stop = route.stops.first(where: { $0.id == id }) else { return }
                select(stop.point)
            }
            #if os(iOS)
            .onChange(of: location.point) { _, point in
                if stage == .origin, let point { select(point) }
            }
            #endif
        }
    }

    private var welcome: some View {
        GeometryReader { geometry in
            ScrollView {
                welcomeContent.frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .leading)
            }
        }
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Image(systemName: "bus.fill")
                .font(.system(size: 44)).foregroundStyle(.blue).padding(20)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                .accessibilityHidden(true)
            Text("Rutas Tijuana").font(.largeTitle.bold())
            Text("Consulta cómo llegar de un punto A a un punto B en transporte público.")
                .foregroundStyle(.secondary)
            demoNotice
            #if DEBUG
            if isDemo {
                Button("Abrir datos de evaluación") { importing = true }
                    .buttonStyle(.bordered)
                Button("Evaluar consulta") {
                    scenario = .evaluation
                    if ProcessInfo.processInfo.arguments.contains("--evaluation-no-date") {
                        scenario.updatedAt = nil
                    }
                    reset()
                }.buttonStyle(.bordered).frame(minHeight: 44)
            }
            #endif
            Spacer()
            if let id = scenario.routeID {
                Button("Volver a recorridos") { dismiss() }.frame(minHeight: 44)
                Text(scenario.name).font(.headline).accessibilityIdentifier(id)
            } else {
                NavigationLink { CatalogView() } label: {
                    Label("Explorar recorridos", systemImage: "map").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered).controlSize(.large)
                .accessibilityIdentifier("Explorar recorridos")
            }
            NavigationLink { recentView } label: {
                Text("Consultas recientes").frame(minHeight: 44)
            }
            Text("Puedes elegir tu ubicación manualmente. No se guarda.")
                .font(.footnote).foregroundStyle(.secondary)
            primaryButton(evaluation ? "Planear mi ruta" : "Elegir ubicación inicial") { begin() }
        }
        .padding(24)
    }

    private var routeMap: some View {
        MapReader { proxy in
            Map(position: $camera, selection: $selectedStop) {
                if let geometry = scenario.routeGeometry, !geometry.isEmpty {
                    ForEach(Array(geometry.enumerated()), id: \.offset) { part in
                        MapPolyline(coordinates: part.element.map { $0.coordinate })
                            .stroke(.gray.opacity(0.6), lineWidth: 4)
                    }
                } else if isDemo {
                    MapPolyline(coordinates: route.mapStops.map { $0.point.coordinate })
                        .stroke(.gray.opacity(0.5), lineWidth: 4)
                }
                if stage == .journey && validation == .accepted {
                    if let section = isDemo ? trip.map(\.point) : mappedTrip {
                        MapPolyline(coordinates: section.map { $0.coordinate }).stroke(.blue, lineWidth: 7)
                    }
                    if let step = simulationStep, trip.indices.contains(step) {
                        MapPolyline(coordinates: trip.prefix(step + 1).map { $0.point.coordinate })
                            .stroke(.secondary, style: StrokeStyle(lineWidth: 7, dash: [7, 5]))
                        Marker("Parada actual simulada", systemImage: "bus.fill", coordinate: trip[step].point.coordinate)
                    }
                }
                ForEach(route.stops) { stop in
                    Marker(stop.name, systemImage: "bus", coordinate: stop.point.coordinate)
                        .tint(.gray).tag(stop.id)
                }
                if let origin {
                    Annotation("Origen A", coordinate: origin.coordinate) { pin("A", color: .blue) }
                }
                if let destination {
                    Annotation("Destino B", coordinate: destination.coordinate) { pin("B", color: .indigo) }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .accessibilityLabel(isDemo ? "Mapa esquemático del recorrido" : "Mapa del recorrido y sus paradas")
            .accessibilityHint("Las paradas y el resumen del trayecto también están en la lista.")
            .onTapGesture { position in
                guard !invalidDestination, stage != .journey, let point = proxy.convert(position, from: .local) else { return }
                select(GeoPoint(latitude: point.latitude, longitude: point.longitude))
            }
            .overlay(alignment: .topLeading) {
                if isDemo {
                    Text("Recorrido de evaluación").font(.caption.weight(.medium)).padding(8)
                        .background(.regularMaterial, in: Capsule()).padding(12).allowsHitTesting(false)
                }
            }
        }
    }

    private var panel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                demoNotice
                if !connectivity.isConnected {
                    Label("Sin conexión · Puedes elegir de la lista", systemImage: "wifi.slash")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let step = simulationStep { simulationPanel(step) }
                else if stage == .origin { originPanel }
                else if stage == .destination { destinationPanel }
                else { journeyPanel }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity).background(.regularMaterial)
    }

    private var originPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(origin == nil ? "Tu ubicación" : "Paradas cercanas").font(.title3.bold())
            Text("Toca el mapa o elige una parada. Las distancias son en línea recta.")
                .font(.subheadline).foregroundStyle(.secondary)
            #if os(iOS)
            Button { location.request() } label: {
                Label(location.isRequesting ? "Obteniendo ubicación…" : "Usar mi ubicación", systemImage: "location")
                    .frame(minHeight: 44)
            }
            .disabled(location.isRequesting)
            if let message = location.message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            #endif
            searchField
            categoryFilters
            choices(point: origin, selectedID: originID, isOrigin: true)
            primaryButton("Continuar", disabled: originID == nil) {
                cancelLocation()
                search = ""
                categoryFilter = nil
                stage = .destination
                selectedStop = nil
            }
        }
    }

    private var destinationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let stop = route.stops.first(where: { $0.id == originID }) {
                Label("Origen: \(stop.name)", systemImage: "a.circle")
            }
            Text("Dónde te bajas").font(.title3.bold())
            Text("Toca el mapa o elige una parada para marcar el destino.")
                .font(.subheadline).foregroundStyle(.secondary)
            searchField
            categoryFilters
            choices(point: destination, selectedID: destinationID, isOrigin: false)
            primaryButton(evaluation ? "Elegir destino" : "Ver trayecto", disabled: destinationID == nil) {
                let result = evaluarConsulta()
                if result == .invalid {
                    destination = nil
                    destinationID = nil
                    selectedStop = nil
                    invalidDestination = true
                } else {
                    validation = result
                    if result == .accepted && !isDemo { saveRecent() }
                    selectedStop = nil
                    stage = .journey
                    camera = .automatic
                }
            }
        }
    }

    private var journeyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(validation.title, systemImage: validation == .accepted ? "checkmark.circle" : "exclamationmark.circle")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($resultFocused)
            Text(route.name).font(.title3.bold())
            if isDemo {
                Text("Mapa esquemático entre paradas").font(.footnote).foregroundStyle(.secondary)
            } else if validation == .accepted && mappedTrip == nil {
                Text("El mapa muestra el recorrido completo y sus paradas.").font(.footnote).foregroundStyle(.secondary)
            }
            if let start = route.stops.first(where: { $0.id == originID }) { Text("Origen: \(start.name)") }
            if let end = route.stops.first(where: { $0.id == destinationID }) { Text("Destino: \(end.name)") }
            Text("Sentido: \(scenario.direction ?? "No disponible")")
                .font(.subheadline).foregroundStyle(.secondary)
            if let date = scenario.updateDate { Text("Actualización: \(date)") }
            else { Text("Fecha no disponible") }
            if let schedules = scenario.schedules, !schedules.isEmpty {
                ForEach(Array(schedules.enumerated()), id: \.offset) { item in Text(item.element).font(.footnote) }
            } else {
                Text("Horario no disponible").font(.footnote)
            }
            if validation == .accepted, let first = trip.first, let last = trip.last {
                Label("Camina hasta la parada de subida", systemImage: "figure.walk")
                    .font(.footnote).foregroundStyle(.secondary)
                journeyRow("Sube en \(first.name)", point: origin, stop: first, symbol: "a.circle.fill")
                Button("Ir a la parada") { walkingDestination = WalkingDestination(id: first.id, name: first.name, point: first.point) }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("walking-start")
                journeyRow("Bájate en \(last.name)", point: destination, stop: last, symbol: "b.circle.fill")
                Label("Continúa al destino · Camino peatonal no disponible", systemImage: "figure.walk")
                    .font(.footnote).foregroundStyle(.secondary)
                DisclosureGroup("Paradas principales (\(trip.count))") {
                    ForEach(trip) { stop in Text(stop.name) }
                }
                #if DEBUG
                if evaluation {
                    primaryButton("Trayecto simulado") { simulationStep = 0 }
                }
                #endif
            } else {
                Text(trip.isEmpty ? "No hay un recorrido en ese sentido. Elige otra parada." : "La ruta de evaluación requiere dos paradas y una fecha de actualización.")
                primaryButton("Cambiar destino", action: back)
            }
            if let stop = route.stops.first(where: { $0.id == selectedStop }) {
                Label(stop.name, systemImage: "bus").font(.subheadline)
            }
            if isDemo {
                Text("El trayecto de transporte es una simulación. La guía a pie se abre por separado.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            primaryButton("Nueva consulta", action: reset)
        }
        .onAppear { resultFocused = true }
    }

    @ViewBuilder
    private func choices(point: GeoPoint?, selectedID: String?, isOrigin: Bool) -> some View {
        if categoryFilter != nil || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let stops = categoryFilter == nil ? scenario.matchingStops(search) : []
            let places = scenario.matchingPlaces(search).filter { categoryFilter == nil || $0.category == categoryFilter }
            if stops.isEmpty && places.isEmpty { Text("Sin coincidencias").foregroundStyle(.secondary) }
            ForEach(places) { place in
                if let stop = route.stops.first(where: { $0.id == place.stopID }) {
                    Button { selectStop(stop, isOrigin: isOrigin) } label: {
                        VStack(alignment: .leading) {
                            Label(place.name, systemImage: place.symbol)
                            Text("Referencia de evaluación · \(stop.name)").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 10)
                    }.buttonStyle(.plain).accessibilityIdentifier("place-\(place.id)")
                }
            }
            ForEach(stops) { stop in
                Button(stop.name) { selectStop(stop, isOrigin: isOrigin) }
                    .frame(minHeight: 44).accessibilityIdentifier("stop-\(stop.id)")
            }
        } else if let point {
            let nearby = route.nearbyStops(to: point)
            if nearby.isEmpty {
                Text("No hay paradas de evaluación dentro del área de consulta. Elige otra en la lista.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(nearby) { option in
                Button {
                    if isOrigin { originID = option.id; destination = nil; destinationID = nil } else { destinationID = option.id }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(option.stop.name).fontWeight(.medium)
                            Text(distanceText(option.distance)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedID == option.id { Image(systemName: "checkmark").foregroundStyle(.blue) }
                    }
                    .padding(12).frame(minHeight: 52)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stop-\(option.id)")
                .accessibilityAddTraits(selectedID == option.id ? .isSelected : [])
            }
        } else {
            ForEach(route.stops) { stop in
                Button(stop.name) { selectStop(stop, isOrigin: isOrigin) }.frame(minHeight: 44)
                    .accessibilityIdentifier("stop-\(stop.id)")
            }
        }
    }

    private var demoNotice: some View {
        Group {
            if isDemo {
                Label("Datos de evaluación", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func categoryTitle(_ category: String) -> String {
        switch category {
        case "hospital": return "Salud"
        case "culture": return "Cultura"
        case "shopping": return "Comercio"
        case "park": return "Parques"
        case "sport": return "Deportes"
        default: return "Transporte"
        }
    }

    @ViewBuilder private var categoryFilters: some View {
        let categories = Array(Set(scenario.places.map(\.category))).sorted()
        if !categories.isEmpty {
            Picker("Categoría", selection: $categoryFilter) {
                Text("Todas").tag(nil as String?)
                ForEach(categories, id: \.self) { category in
                    Text(categoryTitle(category)).tag(Optional(category))
                }
            }.frame(minHeight: 44)
        }
    }

    private func begin() {
        search = ""
        categoryFilter = nil
        if let stop = route.stops.first(where: { $0.id == scenario.fixedOriginID }) {
            selectStop(stop, isOrigin: true)
            stage = .destination
        } else {
            stage = .origin
        }
    }

    private func evaluarConsulta() -> RouteValidation {
        guard let originID, let destinationID, originID != destinationID else { return .invalid }
        if evaluation {
            return validarRuta(origen: originID, destino: destinationID, paradasPrincipales: trip.count,
                              fechaActualizacion: scenario.updateDate)
        }
        return trip.isEmpty ? .rejected : .accepted
    }

    private func simulationPanel(_ step: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let finished = step >= trip.count
            Label(finished ? "Viaje finalizado" : "Trayecto en curso", systemImage: finished ? "checkmark.circle" : "bus")
                .font(.title3.bold())
            Text("Progreso simulado · Tiempo de llegada no disponible")
            if !finished {
                Text(trip[step].name)
                ProgressView(value: Double(step + 1), total: Double(trip.count))
                    .accessibilityLabel("Progreso del trayecto simulado")
                Text("Faltan \(trip.count - step - 1) paradas")
                if step + 1 < trip.count {
                    primaryButton("Avanzar una parada") { simulationStep = step + 1 }
                }
                primaryButton("Finalizar trayecto") { simulationStep = trip.count }
            }
            primaryButton("Volver al resultado") { simulationStep = nil }
            if finished { primaryButton("Nueva consulta", action: reset) }
        }
    }

    private var recents: [RecentJourney] {
        ((try? JSONDecoder().decode([RecentJourney].self, from: recentData)) ?? []).filter { $0.routeID != nil }
    }

    private func saveRecent() {
        guard let routeID = scenario.routeID, let originID, let destinationID else { return }
        let entry = RecentJourney(routeID: routeID, originID: originID, destinationID: destinationID)
        storeRecents(Array(([entry] + recents.filter { $0 != entry }).prefix(12)))
    }

    private func storeRecents(_ entries: [RecentJourney]) {
        recentData = (try? JSONEncoder().encode(entries)) ?? Data()
    }

    private var recentView: some View {
        List {
            if recents.isEmpty { Text("No hay consultas recientes") }
            ForEach(Array(recents.enumerated()), id: \.offset) { row in
                if let catalog = catalogRepository.catalog,
                   let feature = catalog.features.first(where: { $0.id == row.element.routeID }),
                   let match = catalog.journeyScenario(for: feature),
                   let trip = match.route.journey(from: row.element.originID, to: row.element.destinationID),
                   let start = trip.first, let end = trip.last {
                    NavigationLink {
                        ContentView(scenario: match, recent: row.element)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(match.name)
                            Text("\(start.name) → \(end.name)").foregroundStyle(.secondary)
                        }
                    }
                } else {
                    VStack(alignment: .leading) {
                        Text("Consulta no disponible")
                        Button("Quitar consulta", role: .destructive) {
                            storeRecents(recents.filter { $0 != row.element })
                        }
                    }
                }
            }
            if !recents.isEmpty {
                Button("Borrar recientes", role: .destructive) { storeRecents([]) }
            }
        }.navigationTitle("Consultas recientes").onAppear { storeRecents(recents) }
    }

    private var searchField: some View {
        TextField("Buscar parada o lugar", text: $search)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .accessibilityIdentifier("journey-search")
    }

    private func selectStop(_ stop: TransitStop, isOrigin: Bool) {
        cancelLocation()
        if isOrigin { origin = stop.point; originID = stop.id; destination = nil; destinationID = nil }
        else { destination = stop.point; destinationID = stop.id }
        search = ""
        categoryFilter = nil
        camera = .region(MKCoordinateRegion(center: stop.point.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.024, longitudeDelta: 0.024)))
    }

    private func importScenario(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2_000_000 else {
                throw ScenarioError.invalid
            }
            #if DEBUG
            scenario = try JourneyScenario.decode(Data(contentsOf: url), allowEvaluation: true)
            #else
            scenario = try JourneyScenario.decode(Data(contentsOf: url), allowEvaluation: false)
            #endif
            reset()
            camera = .automatic
        } catch { importError = "El archivo no es compatible o no está autorizado para esta versión." }
    }

    private func primaryButton(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity, minHeight: 44) }
            .buttonStyle(.borderedProminent).controlSize(.large).disabled(disabled)
            .accessibilityIdentifier(title)
    }

    private func pin(_ text: String, color: Color) -> some View {
        Text(text).font(.headline).foregroundStyle(.white).frame(width: 32, height: 32)
            .background(color, in: Circle()).accessibilityLabel(text == "A" ? "Origen" : "Destino")
    }

    private func journeyRow(_ title: String, point: GeoPoint?, stop: TransitStop, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading) {
                Text(title).fontWeight(.medium)
                if let point { Text(distanceText(point.distance(to: stop.point))).font(.caption).foregroundStyle(.secondary) }
            }
        } icon: { Image(systemName: symbol).foregroundStyle(.blue) }
    }

    private func distanceText(_ distance: Double) -> String { "A \(Int(distance.rounded())) m en línea recta" }

    private func select(_ point: GeoPoint) {
        cancelLocation()
        let closest = route.nearbyStops(to: point).first?.id
        if stage == .origin { origin = point; originID = closest; destination = nil; destinationID = nil }
        else if stage == .destination { destination = point; destinationID = closest }
    }

    private func back() {
        cancelLocation()
        if simulationStep != nil { simulationStep = nil; return }
        search = ""
        categoryFilter = nil
        selectedStop = nil
        switch stage {
        case .home: break
        case .origin: stage = .home
        case .destination: if evaluation { reset() } else { stage = .origin }
        case .journey: stage = .destination
        }
    }

    private func reset() {
        cancelLocation()
        search = ""
        categoryFilter = nil
        simulationStep = nil
        validation = .invalid
        origin = nil
        destination = nil
        originID = nil
        destinationID = nil
        selectedStop = nil
        stage = .home
        camera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 32.531, longitude: -117.012),
            span: MKCoordinateSpan(latitudeDelta: 0.024, longitudeDelta: 0.024)
        ))
    }

    private func cancelLocation() {
        #if os(iOS)
        location.cancel()
        #endif
    }
}

#Preview {
    ContentView()
}
