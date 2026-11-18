import SwiftUI
import MapKit
import UniformTypeIdentifiers
import Accessibility

struct CatalogView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @ObservedObject private var repository = CatalogRepository.shared
    @AppStorage("favorite-routes") private var favoriteData = Data()
    @AppStorage("route-lists") private var listData = Data()
    @State private var grouped = true
    @State private var showingLists = false
    @State private var savingToLists = false
    @State private var listName = ""
    @State private var activeListID: UUID?
    @State private var routeToUse: String?
    private let routesTab: Bool
    private let favoritesOnly: Bool

    private struct SavedList: Codable, Identifiable {
        var id = UUID()
        var name: String
        var routes: [String] = []
    }

    private var savedLists: [SavedList] {
        get { (try? JSONDecoder().decode([SavedList].self, from: listData)) ?? [] }
        nonmutating set { if let data = try? JSONEncoder().encode(newValue) { listData = data } }
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    private let knownZones = ["5 y 10", "Centro", "Otay", "Playas", "La Gloria"]

    private func zones(_ feature: CatalogFeature) -> [String] {
        let text = normalized(feature.routeDetails?.direction ?? feature.name)
        return knownZones.filter { text.contains(normalized($0)) }
            .sorted { text.range(of: normalized($0))!.lowerBound < text.range(of: normalized($1))!.lowerBound }
    }

    private func zone(_ feature: CatalogFeature) -> String { zones(feature).first ?? "Otras rutas" }

    private func routeColor(_ feature: CatalogFeature) -> Color {
        switch zone(feature) {
        case "5 y 10": return .blue
        case "Centro": return .purple
        case "Otay": return .teal
        case "Playas": return .orange
        case "La Gloria": return .green
        default: return .gray
        }
    }
    @State private var privateCatalog: RouteCatalog?
    private var catalog: RouteCatalog? { privateCatalog ?? repository.catalog }
    @State private var query = ""
    @State private var groupID: String?
    @State private var filter = CatalogFilter.routes
    @State private var selectedID: String?
    @State private var favoritePulse = 0
    @State private var favoriteNotice = ""
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

    init(initialFilter: CatalogFilter = .routes, favoritesOnly: Bool = false, routesTab: Bool = false) {
        self.routesTab = routesTab
        _filter = State(initialValue: initialFilter)
        self.favoritesOnly = favoritesOnly
    }

    private var matches: [CatalogFeature] {
        let all = catalog?.matching(routesTab ? "" : query, groupID: groupID, filter: filter) ?? []
        if routesTab {
            let term = normalized(query)
            return all.filter { feature in
                term.isEmpty || normalized(([feature.name, feature.routeDetails?.code ?? "",
                    feature.routeDetails?.direction ?? "", zone(feature)] + zones(feature)).joined(separator: " ")).contains(term)
            }.sorted {
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
        }
        let rows = favoritesOnly ? all.filter { $0.kind == .route && FavoriteRoutes.decode(favoriteData).contains($0.id) } : all
        guard let reference else { return rows }
        return rows.compactMap { feature -> (CatalogFeature, Double)? in
            guard let distance = feature.distance(to: reference), distance <= 1_000 else { return nil }
            return (feature, distance)
        }.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 < $1.1 }.map { $0.0 }
    }

    private var selection: CatalogFeature? { matches.first { $0.id == selectedID } }

    private var mapFeatures: [CatalogFeature] {
        if routesTab, let selection { return [selection] }
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
                if routesTab {
                    ZStack {
                        VStack(spacing: 0) {
                            filters
                            Picker("Organización", selection: $grouped) {
                                Text("Por zona").tag(true)
                                Text("Todas").tag(false)
                            }.pickerStyle(.segmented).padding(.horizontal)
                            Button("Mis listas", systemImage: "bookmark") {
                                activeListID = nil
                                listName = ""
                                showingLists = true
                            }.frame(minHeight: 44)
                            featureList
                        }
                        .opacity(selection == nil ? 1 : 0)
                        .accessibilityHidden(selection != nil)
                        .allowsHitTesting(selection == nil)
                        if let selection {
                            ScrollView {
                                VStack(spacing: 0) {
                                    map.frame(height: 220)
                                    detail(selection)
                                }
                            }
                            .background(Color(uiColor: .systemBackground))
                        }
                    }
                } else {
                    map.frame(minHeight: 180, maxHeight: 310)
                    filters
                    if favoritesOnly && matches.isEmpty {
                        NavigationLink("Explorar recorridos") { CatalogView() }
                            .frame(minHeight: 44)
                    }
                    Group {
                        if let selection { detail(selection).transition(reduceMotion ? .identity : .opacity) }
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: selectedID)
                    featureList
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
            if !favoriteNotice.isEmpty {
                Text(favoriteNotice).font(.footnote).padding(10)
                    .accessibilityIdentifier("favorite-notice")
                    .task(id: favoriteNotice) {
                        do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
                        favoriteNotice = ""
                    }
            }
            if let message = repository.message { Text(message).font(.footnote).foregroundStyle(.primary).padding(10) }
        }
        .tint(colorScheme == .dark ? Color(red: 0.65, green: 0.81, blue: 1) : Color(red: 0.02, green: 0.29, blue: 0.57))
        .sheet(isPresented: $savingToLists) { if let selection { listEditor(routeID: selection.id) } }
        .sheet(isPresented: $showingLists, onDismiss: {
            if let id = routeToUse, let feature = catalog?.features.first(where: { $0.id == id }) {
                query = ""
                groupID = nil
                Task { @MainActor in
                    await Task.yield()
                    selectedID = id
                    fit(feature)
                }
            }
            routeToUse = nil
        }) { listEditor(routeID: nil) }
        .sheet(isPresented: $showingInformation) {
            if let selection { informationSheet(selection).tint(.blue) }
        }
        .sheet(isPresented: $showingServices) {
            NavigationStack { services }.tint(.blue)
        }
        .fullScreenCover(item: $plannedRoute) { route in
            ContentView(scenario: route.scenario)
        }
        .fullScreenCover(item: $walkingDestination) { WalkingNavigationView(destination: $0) }
        .navigationTitle(favoritesOnly ? "Favoritos" : routesTab ? "Rutas" : filter == .stops ? "Paradas" : "Recorridos")
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .tint(.white)
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { searchFocused = false }
                    .foregroundStyle(colorScheme == .dark ? Color(red: 0.65, green: 0.81, blue: 1) : Color(red: 0.02, green: 0.29, blue: 0.57))
            }
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
        List {
            if routesTab && grouped {
                let sections = Dictionary(grouping: matches, by: zone)
                ForEach(sections.keys.sorted {
                    if $0 == "Otras rutas" { return false }
                    if $1 == "Otras rutas" { return true }
                    return $0.localizedStandardCompare($1) == .orderedAscending
                }, id: \.self) { name in
                    Section(name) { ForEach(sections[name] ?? []) { row($0) } }
                }
            } else {
                ForEach(matches) { row($0) }
            }
        }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if matches.isEmpty { emptySearch }
            }
    }

    private var emptySearch: some View {
        if favoritesOnly {
            if !FavoriteRoutes.decode(favoriteData).isEmpty && (!query.isEmpty || groupID != nil || reference != nil) {
                return ContentUnavailableView("Sin coincidencias", systemImage: "magnifyingglass", description: Text("Cambia la búsqueda o los filtros."))
            }
            return ContentUnavailableView("Sin favoritos", systemImage: "star", description: Text("Guarda recorridos desde el catálogo para verlos aquí."))
        }
        let description = "No hay resultados en " + filter.title.lowercased() + ". Cambia la búsqueda, el grupo o el punto de referencia."
        return ContentUnavailableView("Sin coincidencias", systemImage: "magnifyingglass", description: Text(description))
    }

    private func distanceCaption(_ feature: CatalogFeature, meters: Double) -> String {
        "A " + WalkingFormat.distance(meters) + (feature.kind == .stop ? " de la parada" : " del trazado")
    }

    private func row(_ feature: CatalogFeature) -> some View {
        Button {
            searchFocused = false
            selectedID = feature.id
            fit(feature)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: feature.kind == .route ? "point.topleft.down.curvedto.point.bottomright.up" : feature.kind == .stop ? "bus.fill" : "square.dashed")
                    .foregroundStyle(feature.kind == .route ? routeColor(feature) : color(feature.color))
                VStack(alignment: .leading, spacing: 4) {
                    Text(feature.name).fontWeight(.medium)
                    Text(routesTab ? zone(feature) : groupName(feature.groupID)).font(.caption).foregroundStyle(.primary)
                    if routesTab, let direction = feature.routeDetails?.direction, direction != feature.name {
                        Text(direction).font(.caption).foregroundStyle(.secondary)
                    }
                    if let reference, let distance = feature.distance(to: reference) {
                        Text(distanceCaption(feature, meters: distance))
                            .font(.caption).foregroundStyle(.primary)
                    }
                }
                Spacer(minLength: 0)
                if feature.kind == .route && FavoriteRoutes.decode(favoriteData).contains(feature.id) {
                    Image(systemName: "star.fill").accessibilityHidden(true)
                }
                if selectedID == feature.id { Image(systemName: "checkmark") }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityValue([
            selectedID == feature.id ? "Seleccionado" : nil,
            feature.kind == .route && FavoriteRoutes.decode(favoriteData).contains(feature.id) ? "Favorito" : nil
        ].compactMap { $0 }.joined(separator: ", "))
        .accessibilityIdentifier("catalog-\(feature.id)")
    }

    private var filters: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Buscar nombre, grupo o información").font(.subheadline)
                TextField("Buscar nombre, grupo o información", text: $query, prompt: Text(""))
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { searchFocused = false }
                    .accessibilityLabel("Buscar nombre, grupo o información")
                    .accessibilityIdentifier("catalog-search")
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary))
                    .contentShape(Rectangle())
            }
            HStack {
                Picker("Grupo", selection: $groupID) {
                    Text("Todos los grupos").tag(String?.none)
                    ForEach(catalog?.groups ?? []) { group in Text(group.name).tag(Optional(group.id)) }
                }
                .labelsHidden()
                if !favoritesOnly && !routesTab {
                    Picker("Contenido", selection: $filter) {
                        ForEach(CatalogFilter.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("catalog-filter")
                }
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
                            .stroke(feature.kind == .route ? routeColor(feature) : color(feature.color),
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
                if feature.kind == .route && privateCatalog == nil {
                    let saved = FavoriteRoutes.decode(favoriteData).contains(feature.id)
                    Button {
                        favoriteData = FavoriteRoutes.toggle(feature.id, in: favoriteData)
                        favoriteNotice = saved ? "Quitado de favoritos" : "Guardado en favoritos"
                        AccessibilityNotification.Announcement(favoriteNotice).post()
                        if !reduceMotion { favoritePulse += 1 }
                    } label: {
                        Label(saved ? "Quitar de favoritos" : "Guardar en favoritos", systemImage: saved ? "star.fill" : "star")
                            .symbolEffect(.bounce, value: favoritePulse)
                    }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("favorite-toggle")
                }
                if feature.kind == .route {
                    let saved = savedLists.contains { $0.routes.contains(feature.id) }
                    Button("Guardar en listas", systemImage: saved ? "bookmark.fill" : "bookmark") {
                        listName = ""
                        savingToLists = true
                    }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityValue(saved ? "Guardado en listas" : "Sin guardar")
                }
                Button("Cerrar", systemImage: "xmark") { selectedID = nil }
                    .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            }
            Text(feature.kind == .route ? "Recorrido" : feature.kind == .stop ? "Parada" : "Área de referencia")
                .font(.caption).foregroundStyle(.primary)
            if feature.kind == .stop, case .point(let point) = feature.geometry {
                Button("Ir a la parada") { walkingDestination = WalkingDestination(id: feature.id, name: feature.name, point: GeoPoint(latitude: point.latitude, longitude: point.longitude)) }
            }
            if feature.kind == .route {
                if routesTab {
                    Text("Zona: " + zone(feature)).font(.caption)
                    if let direction = feature.routeDetails?.direction { Text("Sentido: " + direction).font(.caption) }
                    Button("Volver a encuadrar", systemImage: "arrow.up.left.and.arrow.down.right") {
                        fit(feature)
                    }.frame(minHeight: 44)
                }
                if routesTab, let catalog, catalog.readyForDistribution {
                    NavigationLink("Usar esta ruta") {
                        TripPlannerView(catalog: catalog, requiredRouteID: feature.id)
                    }.frame(minHeight: 44)
                } else if let catalog, catalog.readyForDistribution, let scenario = catalog.journeyScenario(for: feature) {
                    Button("Planear este recorrido") {
                        plannedRoute = PlannedRoute(id: feature.id, scenario: scenario)
                    }.frame(minHeight: 44)
                }
                Text("Distancia al trazado en línea recta.")
                    .font(.caption).foregroundStyle(.primary)
            }
            if feature.information != nil || feature.routeDetails != nil || !(feature.media ?? []).isEmpty {
                Button("Ver información disponible") { showingInformation = true }
                    .accessibilityIdentifier("catalog-information")
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func listEditor(routeID: String?) -> some View {
        NavigationStack {
            List {
                if let activeListID, let list = savedLists.first(where: { $0.id == activeListID }), routeID == nil {
                    TextField("Nombre de la lista", text: $listName)
                    Button("Renombrar") {
                        let name = listName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty, !savedLists.contains(where: { $0.id != list.id && normalized($0.name) == normalized(name) }) else { return }
                        savedLists = savedLists.map { item in
                            var changed = item
                            if changed.id == list.id { changed.name = name }
                            return changed
                        }
                    }
                    ForEach(list.routes, id: \.self) { id in
                        if let feature = catalog?.features.first(where: { $0.id == id }) {
                            Button(feature.name) { routeToUse = id; showingLists = false }
                        } else { Text("Ruta no disponible") }
                        Button("Quitar de la lista", role: .destructive) { toggleRoute(id, listID: list.id) }
                    }
                    Button("Eliminar lista", role: .destructive) {
                        savedLists = savedLists.filter { $0.id != list.id }
                        self.activeListID = nil
                        listName = ""
                    }
                    Button("Volver a Mis listas") { self.activeListID = nil; listName = "" }
                } else {
                    ForEach(savedLists) { list in
                        Button {
                            if let routeID { toggleRoute(routeID, listID: list.id) }
                            else { activeListID = list.id; listName = list.name }
                        } label: {
                            let included = routeID.map { list.routes.contains($0) } ?? false
                            Label(list.name, systemImage: included ? "checkmark.circle.fill" : "list.bullet")
                                .accessibilityValue(included ? "Guardado" : "")
                        }.frame(minHeight: 44)
                    }
                    TextField("Nombre de la lista", text: $listName)
                    Button("Crear lista") {
                        let name = listName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty, !savedLists.contains(where: { normalized($0.name) == normalized(name) }) else { return }
                        savedLists = savedLists + [SavedList(name: name, routes: routeID.map { [$0] } ?? [])]
                        listName = ""
                    }.frame(minHeight: 44)
                }
            }
            .navigationTitle(routeID == nil ? "Mis listas" : "Guardar en listas")
            .toolbar { Button("Listo") { savingToLists = false; showingLists = false } }
        }
    }

    private func toggleRoute(_ routeID: String, listID: UUID) {
        savedLists = savedLists.map { item in
            var list = item
            if list.id == listID {
                if list.routes.contains(routeID) { list.routes.removeAll { $0 == routeID } }
                else { list.routes.append(routeID) }
            }
            return list
        }
    }

    private func informationSheet(_ feature: CatalogFeature) -> some View {
        NavigationStack {
            List {
                Section {
                    Text("Información del catálogo y detalles geométricos.")
                        .font(.footnote).foregroundStyle(.primary)
                }
                ForEach(feature.media ?? [], id: \.self) { media in
                    Section("Fotografía") { CatalogPhoto(id: media) }
                }
                if feature.kind == .route {
                    Section("Servicio") {
                        let fields = feature.information?.fields ?? []
                        ForEach(["fare", "schedule", "frequency"], id: \.self) { category in
                            let title = category == "fare" ? "Tarifa" : category == "schedule" ? "Horario" : "Frecuencia"
                            let values = fields.filter { $0.category == category && !$0.inferred && !$0.value.isEmpty }.map(\.value)
                            Text(title + ": " + (values.isEmpty ? "Desconocido" : values.joined(separator: " · ")))
                                .font(.caption)
                        }
                        Text("Color del vehículo: " + (feature.routeDetails?.vehicleColor ?? "Desconocido"))
                            .font(.caption)
                    }
                }
                if let details = feature.routeDetails {
                    if let code = details.code, !code.isEmpty { Section("Código") { Text(code) } }
                    if let direction = details.direction, !direction.isEmpty { Section("Sentido") { Text(direction) } }
                    if let circular = details.circular { Section("Recorrido") { Text(circular ? "Circular" : "Lineal") } }
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
