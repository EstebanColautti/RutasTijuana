import SwiftUI
import MapKit
import UniformTypeIdentifiers

struct CatalogView: View {
    @FocusState private var searchFocused: Bool
    @ObservedObject private var repository = CatalogRepository.shared
    @State private var privateCatalog: RouteCatalog?
    private var catalog: RouteCatalog? { privateCatalog ?? repository.catalog }
    @State private var query = ""
    @State private var groupID: String?
    @State private var filter = CatalogFilter.routes
    @State private var selectedID: String?
    @State private var reference: GeoPoint?
    @State private var walkingDestination: WalkingDestination?
    @State private var importing = false
    @State private var loading = false
    @State private var showingInformation = false
    @State private var showingServices = false
    private struct PlannedRoute: Identifiable {
        let id: String
        let scenario: JourneyScenario
    }
    @State private var plannedRoute: PlannedRoute?
    @State private var errorMessage: String?
    @State private var camera: MapCameraPosition = .automatic

    private var matches: [CatalogFeature] {
        let rows = catalog?.matching(query, groupID: groupID, filter: filter) ?? []
        guard let reference else { return rows }
        return rows.compactMap { feature -> (CatalogFeature, Double)? in
            guard let distance = feature.distance(to: reference), distance <= 1_000 else { return nil }
            return (feature, distance)
        }.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 < $1.1 }.map { $0.0 }
    }

    private var selection: CatalogFeature? { matches.first { $0.id == selectedID } }

    private var mapFeatures: [CatalogFeature] {
        var features = matches
        if let index = features.firstIndex(where: { $0.id == selectedID }) {
            features.append(features.remove(at: index))
        }
        return features
    }

    var body: some View {
        VStack(spacing: 0) {
            if let catalog {
                if !catalog.readyForDistribution {
                    Label("Catálogo local", systemImage: "info.circle")
                        .font(.caption).padding(10).frame(maxWidth: .infinity)
                        .background(.orange.opacity(0.1))
                }
                map.frame(minHeight: 180, maxHeight: 310)
                filters
                if let selection { detail(selection) }
                featureList
            } else {
                ContentUnavailableView {
                    Label("Recorridos", systemImage: "map")
                } description: {
                    Text("Descarga el catálogo para consultar sus recorridos y referencias.")
                } actions: {
                    Button("Descargar catálogo") { Task { await repository.update(force: true) } }.buttonStyle(.borderedProminent).disabled(repository.isUpdating)
                }
            }
            if loading || repository.isUpdating { ProgressView("Actualizando catálogo…").padding() }
            if let message = repository.message { Text(message).font(.footnote).foregroundStyle(.primary).padding(10) }
        }
        .sheet(isPresented: $showingInformation) {
            if let selection { informationSheet(selection) }
        }
        .sheet(isPresented: $showingServices) {
            NavigationStack { services }
        }
        .fullScreenCover(item: $plannedRoute) { route in
            ContentView(scenario: route.scenario)
        }
        .fullScreenCover(item: $walkingDestination) { WalkingNavigationView(destination: $0) }
        .navigationTitle("Recorridos")
        .preferredColorScheme(catalogTestColorScheme)
        .toolbar {
            ToolbarItem {
                Button("Servicios", systemImage: "info.circle") { showingServices = true }
            }
            ToolbarItem { Button("Actualizar ahora", systemImage: "arrow.clockwise") {
                privateCatalog = nil
                Task { await repository.update(force: true) }
            }.disabled(repository.isUpdating) }
            #if DEBUG
            ToolbarItem { Button("Abrir catálogo", systemImage: "folder") { importing = true }.disabled(loading) }
            #endif
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): load(url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .alert("No se pudo abrir el catálogo", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("Aceptar") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
        .task {
            await repository.open()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--catalog-sample") { privateCatalog = .sample }
            if ProcessInfo.processInfo.arguments.contains("--catalog-pale-sample") {
                let sample = RouteCatalog.sample
                let feature = sample.features[0]
                privateCatalog = RouteCatalog(schemaVersion: sample.schemaVersion, version: sample.version,
                    publishable: sample.publishable, licenseStatus: sample.licenseStatus, groups: sample.groups,
                    features: [CatalogFeature(id: feature.id, name: feature.name, groupID: feature.groupID,
                        kind: feature.kind, color: "#FFFF99", verified: false, geometry: feature.geometry)])
            }
            if ProcessInfo.processInfo.arguments.contains("--catalog-info-sample") { privateCatalog = .informationSample }
            if ProcessInfo.processInfo.arguments.contains("--catalog-services-sample") {
                let sample = RouteCatalog.informationSample
                privateCatalog = RouteCatalog(schemaVersion: sample.schemaVersion, version: sample.version,
                    publishable: true, licenseStatus: "published", groups: sample.groups, features: sample.features,
                    serviceInformation: .init(notices: ["Aviso de ejemplo · Cambio de horario"], contact: nil))
            }
            #endif
        }
        .onChange(of: query) { _, _ in selectedID = nil }
        .onChange(of: groupID) { _, _ in selectedID = nil; camera = .automatic }
        .onChange(of: filter) { _, _ in selectedID = nil; reference = nil; camera = .automatic }
    }

    private var services: some View {
        List {
            Section("Avisos") {
                let notices = catalog?.serviceNotices.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
                if notices.isEmpty { Text("No hay avisos disponibles") }
                ForEach(Array(notices.enumerated()), id: \.offset) { item in Text(item.element) }
            }
            Section("Atención") {
                if let contact = catalog?.serviceContact {
                    Link("Abrir contacto oficial", destination: contact).frame(minHeight: 44)
                } else {
                    Text("Contacto no disponible")
                }
            }
        }
        .navigationTitle("Servicios")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { showingServices = false } } }
    }

    private var featureList: some View {
        List(matches) { row($0) }
            .listStyle(.plain)
            .overlay {
                if matches.isEmpty { emptySearch }
            }
    }

    private var emptySearch: some View {
        let description = "No hay resultados en " + filter.title.lowercased() + ". Cambia la búsqueda, el grupo o el punto de referencia."
        return ContentUnavailableView("Sin coincidencias", systemImage: "magnifyingglass", description: Text(description))
    }

    private func distanceCaption(_ feature: CatalogFeature, meters: Double) -> String {
        "A " + WalkingFormat.distance(meters) + (feature.kind == .stop ? " de la parada" : " del trazado")
    }

    private func row(_ feature: CatalogFeature) -> some View {
        Button {
            selectedID = feature.id
            fit(feature)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: feature.kind == .route ? "point.topleft.down.curvedto.point.bottomright.up" : feature.kind == .stop ? "bus.fill" : "square.dashed")
                    .foregroundStyle(color(feature.color))
                VStack(alignment: .leading, spacing: 4) {
                    Text(feature.name).fontWeight(.medium)
                    Text(groupName(feature.groupID)).font(.caption).foregroundStyle(.primary)
                    if let reference, let distance = feature.distance(to: reference) {
                        Text(distanceCaption(feature, meters: distance))
                            .font(.caption).foregroundStyle(.primary)
                    }
                }
                Spacer(minLength: 0)
                if selectedID == feature.id { Image(systemName: "checkmark") }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("catalog-\(feature.id)")
    }

    private var filters: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Buscar nombre, grupo o información").font(.subheadline)
                TextField("Buscar nombre, grupo o información", text: $query, prompt: Text(""))
                    .focused($searchFocused)
                    .accessibilityLabel("Buscar nombre, grupo o información")
                    .accessibilityIdentifier("catalog-search")
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary))
                    .contentShape(Rectangle())
                    .onTapGesture { searchFocused = true }
            }
            HStack {
                Picker("Grupo", selection: $groupID) {
                    Text("Todos los grupos").tag(String?.none)
                    ForEach(catalog?.groups ?? []) { group in Text(group.name).tag(Optional(group.id)) }
                }
                .labelsHidden()
                Picker("Contenido", selection: $filter) {
                    ForEach(CatalogFilter.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("catalog-filter")
            }
            HStack {
                Text("Resultados: \(matches.count)").font(.caption).foregroundStyle(.primary)
                Spacer()
                if reference != nil {
                    Button("Quitar cercanía") { reference = nil; selectedID = nil; camera = .automatic }
                        .font(.caption)
                }
            }
        }.padding(12)
    }

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera) {
                ForEach(mapFeatures) { feature in
                    ForEach(Array(feature.geometry.lines.enumerated()), id: \.offset) { part in
                        MapPolyline(coordinates: part.element.map(\.coordinate))
                            .stroke(.white, lineWidth: selectedID == feature.id ? 11 : 7)
                        MapPolyline(coordinates: part.element.map(\.coordinate))
                            .stroke(.black, lineWidth: selectedID == feature.id ? 9 : 5)
                        MapPolyline(coordinates: part.element.map(\.coordinate))
                            .stroke(selectedID == feature.id ? .pink : color(feature.color),
                                    lineWidth: selectedID == feature.id ? 7 : 3)
                    }
                    ForEach(Array(feature.geometry.polygons.enumerated()), id: \.offset) { area in
                        MapPolygon(polygon(area.element))
                            .foregroundStyle(color(feature.color).opacity(0.18))
                            .stroke(selectedID == feature.id ? .pink : color(feature.color), lineWidth: 2)
                    }
                    if case .point(let point) = feature.geometry {
                        Annotation(feature.name, coordinate: point.coordinate) {
                            Image(systemName: feature.kind == .stop ? "bus.fill" : "mappin.circle").foregroundStyle(color(feature.color))
                        }
                    }
                }
                if let reference {
                    Annotation("Referencia", coordinate: CLLocationCoordinate2D(latitude: reference.latitude, longitude: reference.longitude)) {
                        Image(systemName: "scope").foregroundStyle(.blue)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .onTapGesture { position in
                guard filter.supportsProximity, let point = proxy.convert(position, from: .local) else { return }
                selectedID = nil
                reference = GeoPoint(latitude: point.latitude, longitude: point.longitude)
            }
            .overlay(alignment: .topLeading) {
                Text(filter.supportsProximity ? "Toca el mapa para consultar a 1 km" : filter.title)
                    .font(.caption).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(10).allowsHitTesting(false)
            }
        }
    }

    private func detail(_ feature: CatalogFeature) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(feature.name).font(.headline)
                Spacer()
                Button("Cerrar", systemImage: "xmark") { selectedID = nil }.labelStyle(.iconOnly)
            }
            Text(feature.kind == .route ? "Recorrido" : feature.kind == .stop ? "Parada" : "Área de referencia")
                .font(.caption).foregroundStyle(.primary)
            if feature.kind == .stop, case .point(let point) = feature.geometry {
                Button("Ir a la parada") { walkingDestination = WalkingDestination(id: feature.id, name: feature.name, point: GeoPoint(latitude: point.latitude, longitude: point.longitude)) }
            }
            if feature.kind == .route {
                if let catalog, catalog.readyForDistribution, let scenario = catalog.journeyScenario(for: feature) {
                    Button("Planear este recorrido") {
                        plannedRoute = PlannedRoute(id: feature.id, scenario: scenario)
                    }.frame(minHeight: 44)
                }
                if feature.information?.fields.contains(where: { $0.category == "schedule" && !$0.inferred && !$0.value.isEmpty }) != true {
                    Text("Horario y frecuencia: dato no disponible").font(.caption)
                }
                Text("Distancia al trazado en línea recta.")
                    .font(.caption).foregroundStyle(.primary)
            }
            if feature.information != nil {
                Button("Ver información disponible") { showingInformation = true }
                    .accessibilityIdentifier("catalog-information")
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial)
    }

    private func informationSheet(_ feature: CatalogFeature) -> some View {
        NavigationStack {
            List {
                Section {
                    Text("Información del catálogo y detalles geométricos.")
                        .font(.footnote).foregroundStyle(.primary)
                }
                if let media = feature.media?.first {
                    Section("Fotografía") { CatalogPhoto(id: media) }
                }
                if let information = CatalogPublic.information(feature.information, description: true) {
                    if !information.description.isEmpty {
                        Section("Descripción disponible") { Text(information.description).textSelection(.enabled) }
                    }
                    ForEach(Array(information.fields.enumerated()), id: \.offset) { item in
                        Section {
                            Text(item.element.value).textSelection(.enabled)
                        } header: {
                            Text(item.element.label)
                                .textCase(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle(feature.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { showingInformation = false }.accessibilityIdentifier("catalog-information-close") } }
        }
    }

    private func load(_ url: URL) {
        loading = true
        Task { @MainActor in
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() }; loading = false }
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                guard (values.fileSize ?? Int.max) <= 16 * 1024 * 1024 else { throw CatalogError.tooLarge }
                let data = try Data(contentsOf: url)
                #if DEBUG
                let allowPrivate = true
                #else
                let allowPrivate = false
                #endif
                let decoded = try await Task.detached(priority: .userInitiated) {
                    try RouteCatalog.decode(data, allowPrivate: allowPrivate)
                }.value
                privateCatalog = CatalogPublic.catalog(decoded); selectedID = nil; query = ""; groupID = nil; reference = nil; camera = .automatic
            } catch let error as CatalogError { errorMessage = error.localizedDescription }
            catch is DecodingError { errorMessage = "El archivo no tiene un formato de catálogo válido." }
            catch { errorMessage = "No se pudo leer el archivo seleccionado." }
        }
    }

    private func groupName(_ id: String) -> String { catalog?.groups.first { $0.id == id }?.name ?? "" }

    private var catalogTestColorScheme: ColorScheme? {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--catalog-dark") ? .dark : nil
        #else
        return nil
        #endif
    }

    private func fit(_ feature: CatalogFeature) {
        let points = feature.geometry.positions
        guard let minLat = points.map(\.latitude).min(), let maxLat = points.map(\.latitude).max(),
              let minLon = points.map(\.longitude).min(), let maxLon = points.map(\.longitude).max() else { return }
        camera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(0.005, (maxLat - minLat) * 1.25),
                                  longitudeDelta: max(0.005, (maxLon - minLon) * 1.25))))
    }

    private func polygon(_ rings: [[CatalogPosition]]) -> MKPolygon {
        let holes = rings.dropFirst().map { MKPolygon(coordinates: $0.map(\.coordinate), count: $0.count) }
        let outer = rings.first ?? []
        return MKPolygon(coordinates: outer.map(\.coordinate), count: outer.count, interiorPolygons: holes)
    }

    private func color(_ value: String) -> Color {
        let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let number = UInt32(hex, radix: 16) else { return .blue }
        return Color(red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255,
                     blue: Double(number & 255) / 255)
    }
}

private extension CatalogPosition {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
