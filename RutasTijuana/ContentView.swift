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
    @State private var scenario = JourneyScenario.sample
    private var route: TransitRoute { scenario.route }
    @State private var search = ""
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
    @State private var camera = MapCameraPosition.region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 32.531, longitude: -117.012),
        span: MKCoordinateSpan(latitudeDelta: 0.024, longitudeDelta: 0.024)
    ))
    #if os(iOS)
    @StateObject private var location = LocationService()
    #endif

    private var title: String {
        switch stage {
        case .home: return ""
        case .origin: return "Desde dónde sales"
        case .destination: return "A dónde vas"
        case .journey: return "Tu trayecto"
        }
    }

    private var trip: [TransitStop] {
        guard let originID, let destinationID else { return [] }
        return route.journey(from: originID, to: destinationID) ?? []
    }

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
                                    Label(stage == .destination ? "Cambiar origen" : "Regresar", systemImage: "chevron.left")
                                }
                            }
                        }
                }
                .presentationDetents([.medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .interactiveDismissDisabled()
                .presentationDragIndicator(.visible)
                .alert("Destino no válido", isPresented: $invalidDestination) {
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
        .frame(minWidth: 320, minHeight: 560)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Image(systemName: "bus.fill")
                .font(.system(size: 44)).foregroundStyle(.blue).padding(20)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
            Text("Rutas Tijuana").font(.largeTitle.bold())
            Text("Consulta cómo llegar de un punto A a un punto B en transporte público.")
                .foregroundStyle(.secondary)
            demoNotice
            #if DEBUG
            Button("Abrir datos de evaluación") { importing = true }
                .buttonStyle(.bordered)
            #endif
            Spacer()
            NavigationLink { CatalogView() } label: {
                Label("Explorar recorridos", systemImage: "map").frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.bordered).controlSize(.large)
            .accessibilityIdentifier("Explorar recorridos")
            Text("Puedes elegir tu ubicación manualmente. No se guarda.")
                .font(.footnote).foregroundStyle(.secondary)
            primaryButton("Elegir ubicación inicial") { stage = .origin; search = "" }
        }
        .padding(24)
    }

    private var routeMap: some View {
        MapReader { proxy in
            Map(position: $camera, selection: $selectedStop) {
                MapPolyline(coordinates: (route.stops + [route.stops[0]]).map { $0.point.coordinate })
                    .stroke(.gray.opacity(0.5), lineWidth: 4)
                if stage == .journey {
                    MapPolyline(coordinates: trip.map { $0.point.coordinate }).stroke(.blue, lineWidth: 7)
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
            .onTapGesture { position in
                guard !invalidDestination, stage != .journey, let point = proxy.convert(position, from: .local) else { return }
                select(GeoPoint(latitude: point.latitude, longitude: point.longitude))
            }
            .overlay(alignment: .topLeading) {
                Text("Recorrido de evaluación").font(.caption.weight(.medium)).padding(8)
                    .background(.regularMaterial, in: Capsule()).padding(12).allowsHitTesting(false)
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
                if stage == .origin { originPanel }
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
            }
            .disabled(location.isRequesting)
            if let message = location.message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            #endif
            searchField
            if search.isEmpty && !scenario.places.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Array(Set(scenario.places.map(\.category))).sorted(), id: \.self) { category in
                            Button(categoryTitle(category)) { search = category }.buttonStyle(.bordered)
                        }
                    }
                }
            }
            choices(point: origin, selectedID: originID, isOrigin: true)
            primaryButton("Continuar", disabled: originID == nil) {
                cancelLocation()
                search = ""
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
            if search.isEmpty && !scenario.places.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Array(Set(scenario.places.map(\.category))).sorted(), id: \.self) { category in
                            Button(categoryTitle(category)) { search = category }.buttonStyle(.bordered)
                        }
                    }
                }
            }
            choices(point: destination, selectedID: destinationID, isOrigin: false)
            primaryButton("Ver trayecto", disabled: destinationID == nil) {
                if originID == destinationID {
                    destination = nil
                    destinationID = nil
                    selectedStop = nil
                    invalidDestination = true
                }
                else {
                    selectedStop = nil
                    stage = .journey
                    camera = .automatic
                }
            }
        }
    }

    private var journeyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(route.name).font(.title3.bold())
            Text("Simulación en sentido único · \(max(0, trip.count - 1)) tramos")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Horario y frecuencia: dato no disponible").font(.footnote)
            if let first = trip.first, let last = trip.last {
                Label("Acércate al origen · Camino peatonal no disponible", systemImage: "figure.walk")
                    .font(.footnote).foregroundStyle(.secondary)
                journeyRow("Sube en \(first.name)", point: origin, stop: first, symbol: "a.circle.fill")
                journeyRow("Bájate en \(last.name)", point: destination, stop: last, symbol: "b.circle.fill")
                Label("Continúa al destino · Camino peatonal no disponible", systemImage: "figure.walk")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let stop = route.stops.first(where: { $0.id == selectedStop }) {
                Label(stop.name, systemImage: "bus").font(.subheadline)
            }
            Text("El mapa muestra una simulación. No indica un servicio real ni un camino peatonal.")
                .font(.footnote).foregroundStyle(.secondary)
            primaryButton("Nueva consulta", action: reset)
        }
    }

    @ViewBuilder
    private func choices(point: GeoPoint?, selectedID: String?, isOrigin: Bool) -> some View {
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let stops = scenario.matchingStops(search)
            let places = scenario.matchingPlaces(search)
            if stops.isEmpty && places.isEmpty { Text("Sin coincidencias").foregroundStyle(.secondary) }
            ForEach(places) { place in
                if let stop = route.stops.first(where: { $0.id == place.stopID }) {
                    Button { selectStop(stop, isOrigin: isOrigin) } label: {
                        VStack(alignment: .leading) {
                            Label(place.name, systemImage: place.symbol)
                            Text("Referencia de evaluación · \(stop.name)").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
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
                Button(stop.name) { select(stop.point) }.frame(minHeight: 44)
                    .accessibilityIdentifier("stop-\(stop.id)")
            }
        }
    }

    private var demoNotice: some View {
        Label("Datos de evaluación", systemImage: "info.circle")
            .font(.caption).foregroundStyle(.secondary)
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
        Button(action: action) { Text(title).frame(maxWidth: .infinity, minHeight: 32) }
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
        search = ""
        selectedStop = nil
        switch stage {
        case .home: break
        case .origin: stage = .home
        case .destination: stage = .origin
        case .journey: stage = .destination
        }
    }

    private func reset() {
        cancelLocation()
        search = ""
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
