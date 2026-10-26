import SwiftUI
import MapKit
import UniformTypeIdentifiers

struct CatalogView: View {
    @ObservedObject private var repository = CatalogRepository.shared
    @State private var privateCatalog: RouteCatalog?
    private var catalog: RouteCatalog? { privateCatalog ?? repository.catalog }
    @State private var query = ""
    @State private var groupID: String?
    @State private var routesOnly = true
    @State private var selectedID: String?
    @State private var reference: GeoPoint?
    @State private var importing = false
    @State private var loading = false
    @State private var showingInformation = false
    @State private var errorMessage: String?
    @State private var camera: MapCameraPosition = .automatic

    private var matches: [CatalogFeature] {
        let rows = catalog?.matching(query, groupID: groupID, routesOnly: routesOnly) ?? []
        guard let reference else { return rows }
        return rows.compactMap { feature -> (CatalogFeature, Double)? in
            guard let distance = feature.distance(to: reference), distance <= 1_000 else { return nil }
            return (feature, distance)
        }.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 < $1.1 }.map { $0.0 }
    }

    private var selection: CatalogFeature? { matches.first { $0.id == selectedID } }

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
                List(matches) { feature in
                    Button {
                        selectedID = feature.id
                        fit(feature)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: feature.kind == .route ? "point.topleft.down.curvedto.point.bottomright.up" : "square.dashed")
                                .foregroundStyle(color(feature.color))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(feature.name).fontWeight(.medium)
                                Text(groupName(feature.groupID)).font(.caption).foregroundStyle(.secondary)
                                if let reference, let distance = feature.distance(to: reference) {
                                    Text("A \(Int(distance.rounded())) m del trazado")
                                        .font(.caption).foregroundStyle(.secondary)
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
                .listStyle(.plain)
                .overlay {
                    if matches.isEmpty {
                        ContentUnavailableView("Sin coincidencias", systemImage: "magnifyingglass",
                                               description: Text("Cambia la búsqueda, el grupo o el punto de referencia."))
                    }
                }
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
            if let message = repository.message { Text(message).font(.footnote).foregroundStyle(.secondary).padding(10) }
        }
        .sheet(isPresented: $showingInformation) {
            if let selection { informationSheet(selection) }
        }
        .navigationTitle("Recorridos")
        .toolbar {
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
            if ProcessInfo.processInfo.arguments.contains("--catalog-info-sample") { privateCatalog = .informationSample }
            #endif
        }
        .onChange(of: query) { _, _ in selectedID = nil }
        .onChange(of: groupID) { _, _ in selectedID = nil; camera = .automatic }
        .onChange(of: routesOnly) { _, _ in selectedID = nil; reference = nil; camera = .automatic }
    }

    private var filters: some View {
        VStack(spacing: 10) {
            TextField("Buscar recorrido o grupo", text: $query)
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("catalog-search")
            HStack {
                Picker("Grupo", selection: $groupID) {
                    Text("Todos los grupos").tag(String?.none)
                    ForEach(catalog?.groups ?? []) { group in Text(group.name).tag(Optional(group.id)) }
                }
                .labelsHidden()
                Toggle("Solo recorridos", isOn: $routesOnly).font(.caption)
            }
            HStack {
                Text("Resultados: \(matches.count)").font(.caption).foregroundStyle(.secondary)
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
                ForEach(matches) { feature in
                    ForEach(Array(feature.geometry.lines.enumerated()), id: \.offset) { part in
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
                            Image(systemName: "mappin.circle").foregroundStyle(color(feature.color))
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
                guard routesOnly, let point = proxy.convert(position, from: .local) else { return }
                selectedID = nil
                reference = GeoPoint(latitude: point.latitude, longitude: point.longitude)
            }
            .overlay(alignment: .topLeading) {
                Text(routesOnly ? "Toca el mapa para consultar trazados a 1 km" : "Áreas y referencias")
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
            Text(feature.kind == .route ? "Recorrido" : "Área de referencia")
                .font(.caption).foregroundStyle(.secondary)
            if feature.kind == .route {
                if feature.information == nil {
                    Text("Horario y frecuencia: dato no disponible").font(.caption)
                }
                Text("Distancia al trazado en línea recta.")
                    .font(.caption).foregroundStyle(.secondary)
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
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let information = feature.information {
                    if !information.description.isEmpty {
                        Section("Descripción disponible") { Text(information.description).textSelection(.enabled) }
                    }
                    ForEach(Array(information.fields.enumerated()), id: \.offset) { item in
                        Section(item.element.label) {
                            Text(item.element.value).textSelection(.enabled)
                            if item.element.inferred {
                                Text("Cálculo o referencia deducida").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Texto disponible").font(.caption).foregroundStyle(.secondary)
                            }
                            if !item.element.evidence.isEmpty && item.element.evidence != item.element.value {
                                Text("Texto: \(item.element.evidence)").font(.caption).textSelection(.enabled)
                            }
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
                privateCatalog = decoded; selectedID = nil; query = ""; groupID = nil; reference = nil; camera = .automatic
            } catch let error as CatalogError { errorMessage = error.localizedDescription }
            catch is DecodingError { errorMessage = "El archivo no tiene un formato de catálogo válido." }
            catch { errorMessage = "No se pudo leer el archivo seleccionado." }
        }
    }

    private func groupName(_ id: String) -> String { catalog?.groups.first { $0.id == id }?.name ?? "" }

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
