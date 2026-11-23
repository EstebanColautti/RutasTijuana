import SwiftUI
import MapKit
import UniformTypeIdentifiers
import Accessibility

struct CatalogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.insideFavorites) private var insideFavorites
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @FocusState private var routeSearchFocused: Bool
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var showingRouteSearch = false
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
    @State private var routeSummaryHeight: CGFloat?
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
    @State private var camera: MapCameraPosition = .region(AppDesign.city)

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
                let fields = [feature.name, feature.routeDetails?.code ?? "",
                              feature.routeDetails?.direction ?? "", groupName(feature.groupID), zone(feature)]
                return term.isEmpty || (fields + zones(feature)).contains { normalized($0).contains(term) }
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
        if let selection { return [selection] }
        if !routesTab && filter == .routes && reference == nil { return [] }
        return matches
    }

    var body: some View {
        VStack(spacing: 0) {
            if let catalog {
                if !catalog.readyForDistribution {
                    Label("Catálogo local", systemImage: "info.circle")
                        .font(AppDesign.note).padding(10).frame(maxWidth: .infinity)
                        .background(.orange.opacity(0.1))
                }
                if favoritesOnly {
                    favoritesContent(catalog)
                } else if routesTab {
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
                            routeSelection(selection, catalog: catalog)
                            .transition(reduceMotion ? .identity : .opacity)
                        }
                    }
                    .animation(reduceMotion ? nil : AppDesign.navigationMotion, value: selectedID)
                } else {
                    map.frame(height: textSize.isAccessibilitySize ? 154 : 232)
                        .contentShape(Rectangle())
                        .clipped()
                    VStack(spacing: 0) {
                        AppPanelHeading(title: filter == .stops ? "Paradas" : "Recorridos",
                                        back: { dismiss() }, sideWidth: 88) {
                            HStack(spacing: 0) {
                                Button { showingServices = true } label: {
                                    Image(systemName: "info.circle")
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("Servicios")
                                Button(action: refreshCatalog) {
                                    Image(systemName: "arrow.clockwise")
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("Actualizar ahora")
                                .disabled(repository.isUpdating)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        filters
                        catalogPanelList
                    }
                    .background { AppDesign.panelSurface() }
                    .padding(.top, -AppDesign.panelOverlap)
                    .zIndex(1)
                }
            } else {
                ContentUnavailableView {
                    Label("Recorridos", systemImage: "map")
                } description: {
                    Text("Descarga el catálogo para consultar sus recorridos y referencias.")
                } actions: {
                    Button("Descargar catálogo") { Task { await repository.update(force: true) } }.buttonStyle(AppActionStyle()).disabled(repository.isUpdating)
                }
            }
            if loading || repository.isUpdating { ProgressView("Actualizando catálogo…").padding() }
            if !favoriteNotice.isEmpty {
                Text(favoriteNotice).font(AppDesign.note).padding(10)
                    .accessibilityIdentifier("favorite-notice")
                    .task(id: favoriteNotice) {
                        do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
                        favoriteNotice = ""
                    }
            }
            if let message = repository.message { Text(message).font(AppDesign.note).foregroundStyle(.primary).padding(10) }
        }
        .tint(colorScheme == .dark ? Color(red: 0.65, green: 0.81, blue: 1) : AppDesign.primary)
        .sheet(isPresented: $showingRouteSearch) {
            routeSearchSheet
                .presentationDetents([.fraction(0.83), .large])
                .presentationCornerRadius(AppDesign.panelRadius)
                .presentationDragIndicator(.hidden)
        }
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
        .navigationBarBackButtonHidden(catalog != nil && !routesTab)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(AppDesign.header, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .principal) { AppBrandTitle() } }
        .tint(.white)
        .modifier(AppFavoritesToolbar(enabled: !favoritesOnly))
        .environment(\.insideFavorites, insideFavorites || favoritesOnly)
        .preferredColorScheme(catalogTestColorScheme)
        .toolbar {
            if !favoritesOnly {
                if routesTab || catalog == nil {
                    ToolbarItem {
                        Button("Servicios", systemImage: "info.circle") { showingServices = true }
                    }
                    ToolbarItem {
                        Button("Actualizar ahora", systemImage: "arrow.clockwise", action: refreshCatalog)
                            .disabled(repository.isUpdating)
                    }
                    #if DEBUG
                    ToolbarItem { Button("Abrir catálogo", systemImage: "folder") { importing = true }.disabled(loading) }
                    #endif
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { searchFocused = false }
                    .foregroundStyle(colorScheme == .dark ? Color(red: 0.65, green: 0.81, blue: 1) : AppDesign.primary)
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
        .onChange(of: groupID) { _, _ in
            selectedID = nil
            camera = !routesTab && filter == .routes && reference == nil ? .region(AppDesign.city) : .automatic
        }
        .onChange(of: filter) { _, next in
            selectedID = nil
            reference = nil
            camera = !routesTab && next == .routes ? .region(AppDesign.city) : .automatic
        }
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
        .modifier(AppFavoritesToolbar(darkHeader: false))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { showingServices = false } } }
    }

    private func refreshCatalog() {
        privateCatalog = nil
        Task { await repository.update(force: true) }
    }

    private var catalogPanelList: some View {
        ScrollViewReader { scroll in
            List {
                if let selection {
                    detail(selection)
                        .buttonStyle(.borderless)
                        .listRowInsets(EdgeInsets(top: 5, leading: 24, bottom: 5, trailing: 24))
                        .listRowSeparator(.hidden)
                        .id(selection.id)
                }
                ForEach(matches.filter { $0.id != selectedID }) { feature in
                    row(feature)
                        .listRowInsets(EdgeInsets(top: 5, leading: 24, bottom: 5, trailing: 24))
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .overlay { if matches.isEmpty { emptySearch } }
            .onChange(of: selectedID) { _, id in
                if let id { scroll.scrollTo(id, anchor: .top) }
            }
        }
    }

    private var featureList: some View {
            List {
                if grouped {
                    let sections = Dictionary(grouping: matches, by: zone)
                    ForEach(sections.keys.sorted {
                        if $0 == "Otras rutas" { return false }
                        if $1 == "Otras rutas" { return true }
                        return $0.localizedStandardCompare($1) == .orderedAscending
                    }, id: \.self) { name in
                        Section(name) { ForEach(sections[name] ?? []) { row($0) } }
                    }
                } else {
                    ForEach(matches) { feature in
                        row(feature)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if matches.isEmpty { emptySearch }
            }
    }

    private func favoritesContent(_ catalog: RouteCatalog) -> some View {
        VStack(spacing: 0) {
            AppPanelHeading(title: "Favoritos", back: { dismiss() }) { EmptyView() }
                .padding(.horizontal, 14)
            Divider().padding(.horizontal, 18)
            Group {
            if let selection {
                ScrollView {
                    VStack(spacing: 0) {
                        map.frame(height: 220)
                        detail(selection)
                    }
                }
            } else if matches.isEmpty {
                VStack(spacing: 10) {
                    AppFavoriteIcon(scale: textSize.isAccessibilitySize ? 2.6 : 5.2)
                    Text("No hay rutas guardadas.")
                        .font(AppDesign.body)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    NavigationLink("Explorar recorridos") { CatalogView(routesTab: true) }
                        .frame(minHeight: 44)
                        .font(AppDesign.note)
                        .foregroundStyle(.primary)
                }
                .padding(24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(matches) { feature in
                            let layout = textSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                                : AnyLayout(HStackLayout(spacing: 8))
                            layout {
                                row(feature)
                                if catalog.readyForDistribution {
                                    NavigationLink {
                                        TripPlannerView(catalog: catalog, requiredRouteID: feature.id)
                                    } label: {
                                        Text("Iniciar ruta")
                                            .font(AppDesign.type(14, relativeTo: .subheadline, weight: .semibold))
                                            .multilineTextAlignment(.center)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }.buttonStyle(AppActionStyle())
                                }
                            }
                            .padding(10)
                            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 24))
                            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Color.secondary.opacity(0.42)).allowsHitTesting(false) }
                        }
                    }.padding(16)
                }
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(uiColor: .systemBackground))
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
                if favoritesOnly {
                    AppFavoriteIcon()
                } else {
                    if feature.kind == .route {
                        AppGlyph(icon: .turn).foregroundStyle(routeColor(feature))
                    } else {
                        AppGlyph(icon: feature.kind == .stop ? .vehicle : .pin)
                            .foregroundStyle(color(feature.color))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(feature.name).fontWeight(.medium)
                    Text(routesTab ? zone(feature) : groupName(feature.groupID)).font(AppDesign.note).foregroundStyle(.primary)
                    if (routesTab || favoritesOnly), let direction = feature.routeDetails?.direction, direction != feature.name {
                        Text(direction).font(AppDesign.note).foregroundStyle(.secondary)
                    }
                    if let reference, let distance = feature.distance(to: reference) {
                        Text(distanceCaption(feature, meters: distance))
                            .font(AppDesign.note).foregroundStyle(.primary)
                    }
                }
                Spacer(minLength: 0)
                if !favoritesOnly && feature.kind == .route && FavoriteRoutes.decode(favoriteData).contains(feature.id) {
                    AppFavoriteIcon(filled: true)
                }
                if selectedID == feature.id { Image(systemName: "checkmark") }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(selectedID == feature.id ? (colorScheme == .dark ? AppDesign.accent.opacity(0.22) : AppDesign.selectionFill) : Color(uiColor: .systemBackground))
            }
            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Color.secondary.opacity(favoritesOnly ? 0 : 0.42)).allowsHitTesting(false) }
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityValue([
            selectedID == feature.id ? "Seleccionado" : nil,
            feature.kind == .route && FavoriteRoutes.decode(favoriteData).contains(feature.id) ? "Favorito" : nil
        ].compactMap { $0 }.joined(separator: ", "))
        .accessibilityIdentifier("catalog-\(feature.id)")
    }

    private var routeSearchSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                AppPanelHeading(title: "Buscar recorridos", backLabel: "Cerrar", back: {
                    routeSearchFocused = false
                    showingRouteSearch = false
                }) { EmptyView() }
                HStack(spacing: 10) {
                    TextField("Buscar recorridos", text: $query)
                        .focused($routeSearchFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { routeSearchFocused = false }
                        .accessibilityIdentifier("route-search-field")
                        .appField(focused: routeSearchFocused)
                    Button("Buscar") { routeSearchFocused = false }
                        .buttonStyle(AppActionStyle())
                        .controlSize(.large)
                        .frame(minHeight: 44)
                }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if matches.isEmpty { emptySearch }
                        ForEach(matches) { feature in
                            Button {
                                routeSearchFocused = false
                                selectedID = feature.id
                                fit(feature)
                                showingRouteSearch = false
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(feature.name).font(AppDesign.subtitle)
                                        let subtitle = feature.routeDetails?.direction ?? groupName(feature.groupID)
                                        if !subtitle.isEmpty, subtitle != feature.name {
                                            Text(subtitle).font(AppDesign.note)
                                        }
                                    }
                                    .fixedSize(horizontal: false, vertical: true)
                                } icon: {
                                    AppGlyph(icon: feature.kind == .route ? .navigation : .pin)
                                }
                                .multilineTextAlignment(.leading)
                                .padding(10)
                                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 24))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 24)
                                        .strokeBorder(Color.secondary.opacity(0.42))
                                        .allowsHitTesting(false)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("route-search-result-\(feature.id)")
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(16)
            .toolbar(.hidden, for: .navigationBar)
            .tint(AppDesign.primary)
        }
    }

    private var filters: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Buscar nombre, grupo o información").font(AppDesign.subtitle)
                let layout = textSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 10))
                layout {
                    TextField("Buscar nombre, grupo o información", text: $query, prompt: Text("Buscar…"))
                        .focused($searchFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { searchFocused = false }
                        .accessibilityLabel("Buscar nombre, grupo o información")
                        .accessibilityIdentifier("catalog-search")
                        .appField(focused: searchFocused)
                    Button("Buscar") {
                        searchFocused = false
                        showingRouteSearch = true
                    }
                    .buttonStyle(AppActionStyle())
                    .accessibilityIdentifier("catalog-open-search")
                }
            }
            HStack {
                Text("Filtros").font(AppDesign.subtitle)
                    .accessibilityHidden(true)
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
                Text("Resultados: \(matches.count)").font(AppDesign.note).foregroundStyle(.primary)
                Spacer()
                if reference != nil {
                    Button("Quitar cercanía") { reference = nil; selectedID = nil; camera = .automatic }
                        .font(AppDesign.note)
                }
            }
        }.padding(12)
    }

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera) {
                ForEach(mapFeatures) { feature in
                    let lines = feature.kind == .route ? feature.geometry.routeDisplayLines : feature.geometry.lines
                    ForEach(Array(lines.enumerated()), id: \.offset) { part in
                        MapPolyline(coordinates: part.element.map(\.coordinate))
                            .stroke(.white, lineWidth: selectedID == feature.id ? 11 : 7)
                        MapPolyline(coordinates: part.element.map(\.coordinate))
                            .stroke(.black, style: StrokeStyle(lineWidth: selectedID == feature.id ? 9 : 5, lineCap: .round, lineJoin: .round))
                        MapPolyline(coordinates: part.element.map(\.coordinate))
                            .stroke(feature.kind == .route ? routeColor(feature) : color(feature.color),
                                    style: StrokeStyle(lineWidth: selectedID == feature.id ? 6 : 3, lineCap: .round, lineJoin: .round))
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
                guard !routesTab, filter.supportsProximity, let point = proxy.convert(position, from: .local) else { return }
                selectedID = nil
                reference = GeoPoint(latitude: point.latitude, longitude: point.longitude)
            }
            .overlay(alignment: .topLeading) {
                if !routesTab {
                    Text(filter.supportsProximity ? "Toca el mapa para consultar a 1 km" : filter.title)
                        .font(AppDesign.note).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(10).allowsHitTesting(false)
                }
            }
        }
    }

    private func routeSelection(_ feature: CatalogFeature, catalog: RouteCatalog) -> some View {
        let hasTrace = !feature.geometry.routeDisplayLines.isEmpty
        return GeometryReader { geometry in
            VStack(spacing: -AppDesign.panelOverlap) {
                map
                    .frame(maxHeight: .infinity)
                    .clipShape(Rectangle())
                    .overlay(alignment: .topTrailing) {
                        if feature.kind != .route || hasTrace {
                            Button {
                                fit(feature)
                            } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 44, height: 44)
                                    .background(Color(uiColor: .systemBackground), in: Circle())
                                    .shadow(color: .black.opacity(0.16), radius: 3, y: 2)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppDesign.primary)
                            .accessibilityLabel("Volver a encuadrar")
                            .padding(12)
                        }
                    }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 4) {
                        if textSize.isAccessibilitySize {
                            Spacer(minLength: 0)
                        } else {
                            routeTitle(feature)
                        }
                        selectionActions(feature)
                            .foregroundStyle(routeActionInk)
                    }
                    ScrollView {
                        routeSummary(feature, hasTrace: hasTrace)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                                routeSummaryHeight = height
                            }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: min(routeSummaryHeight ?? 160, geometry.size.height * 0.45))

                    if feature.kind == .route && hasTrace && catalog.readyForDistribution {
                        NavigationLink {
                            TripPlannerView(catalog: catalog, requiredRouteID: feature.id)
                        } label: {
                            Text("Usar esta ruta").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AppActionStyle())
                    } else if feature.kind == .stop, case .point(let point) = feature.geometry {
                        Button {
                            walkingDestination = WalkingDestination(id: feature.id, name: feature.name, point: point.point)
                        } label: {
                            Text("Ir a la parada").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AppActionStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { AppDesign.panelSurface() }
                .zIndex(1)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var routeActionInk: Color {
        colorScheme == .dark ? Color(red: 0.65, green: 0.81, blue: 1) : AppDesign.primary
    }

    private func routeTitle(_ feature: CatalogFeature) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if feature.kind == .route {
                AppGlyph(icon: .turn, size: 20)
                    .foregroundStyle(routeActionInk)
                    .frame(width: 30, height: 30)
                    .background(colorScheme == .dark ? AppDesign.accent.opacity(0.22) : AppDesign.selectionFill,
                                in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
            }
            Text(feature.name).font(AppDesign.title)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func routeSummary(_ feature: CatalogFeature, hasTrace: Bool) -> some View {
        let fields = CatalogPublic.information(feature.information, description: false)?.fields ?? []
        return VStack(alignment: .leading, spacing: 6) {
            if textSize.isAccessibilitySize { routeTitle(feature) }
            if feature.kind == .route {
                Text("Zona: " + zone(feature)).font(AppDesign.note)
                if !hasTrace {
                    Text("Trazado no disponible").font(AppDesign.note)
                }
                if let direction = feature.routeDetails?.direction, !direction.isEmpty, direction != feature.name {
                    Text("Sentido: " + direction).font(AppDesign.note)
                }
                ForEach(["fare", "schedule"], id: \.self) { category in
                    if let field = fields.first(where: { $0.category == category && !$0.value.isEmpty }) {
                        let title = category == "fare" ? "Tarifa" : "Horario"
                        Text(field.value.localizedCaseInsensitiveContains(title + ":") ? field.value : title + ": " + field.value)
                            .font(AppDesign.note)
                    }
                }
            }
            if feature.kind == .route || feature.information != nil || feature.routeDetails != nil || !(feature.media ?? []).isEmpty {
                Button("Ver información", systemImage: "info.circle") { showingInformation = true }
                    .font(AppDesign.subtitle)
                    .foregroundStyle(routeActionInk)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("catalog-information")
            }
        }
        .foregroundStyle(.primary)
        .tint(colorScheme == .dark ? Color(red: 0.65, green: 0.81, blue: 1) : AppDesign.primary)
    }

    private func selectionActions(_ feature: CatalogFeature) -> some View {
        HStack(spacing: 0) {
            if feature.kind == .route && privateCatalog == nil {
                let saved = FavoriteRoutes.decode(favoriteData).contains(feature.id)
                Button {
                    favoriteData = FavoriteRoutes.toggle(feature.id, in: favoriteData)
                    favoriteNotice = saved ? "Quitado de favoritos" : "Guardado en favoritos"
                    AccessibilityNotification.Announcement(favoriteNotice).post()
                } label: {
                    AppFavoriteIcon(filled: saved)
                        .contentTransition(reduceMotion ? .identity : .opacity)
                        .animation(reduceMotion ? nil : AppDesign.selectionMotion, value: saved)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(saved ? "Quitar de favoritos" : "Guardar en favoritos")
                .accessibilityIdentifier("favorite-toggle")
            }
            if feature.kind == .route {
                let saved = savedLists.contains { $0.routes.contains(feature.id) }
                Button("Guardar en listas", systemImage: saved ? "bookmark.fill" : "bookmark") {
                    listName = ""
                    savingToLists = true
                }
                .labelStyle(.iconOnly)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .animation(reduceMotion ? nil : AppDesign.selectionMotion, value: saved)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityValue(saved ? "Guardado en listas" : "Sin guardar")
            }
            Button("Cerrar", systemImage: "xmark") { selectedID = nil }
                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func detail(_ feature: CatalogFeature) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(feature.name).font(AppDesign.title)
                Spacer()
                selectionActions(feature)
            }
            Text(feature.kind == .route ? "Recorrido" : feature.kind == .stop ? "Parada" : "Área de referencia")
                .font(AppDesign.note).foregroundStyle(.primary)
            if !routesTab, let direction = feature.routeDetails?.direction, !direction.isEmpty, direction != feature.name {
                Text(direction).font(AppDesign.body)
            }
            if feature.kind == .stop, case .point(let point) = feature.geometry {
                Button("Ir a la parada") { walkingDestination = WalkingDestination(id: feature.id, name: feature.name, point: GeoPoint(latitude: point.latitude, longitude: point.longitude)) }
            }
            if feature.kind == .route {
                if !feature.geometry.routeDisplayLines.isEmpty, let catalog, catalog.readyForDistribution,
                   let scenario = catalog.journeyScenario(for: feature) {
                    Button("Planear este recorrido") {
                        plannedRoute = PlannedRoute(id: feature.id, scenario: scenario)
                    }.frame(minHeight: 44)
                }
                Text("Distancia al trazado en línea recta.")
                    .font(AppDesign.note).foregroundStyle(.primary)
            }
            if feature.kind == .route || feature.information != nil || feature.routeDetails != nil || !(feature.media ?? []).isEmpty {
                Button("Ver información disponible") { showingInformation = true }
                    .accessibilityIdentifier("catalog-information")
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if favoritesOnly {
                Color(uiColor: .secondarySystemBackground)
            } else {
                RoundedRectangle(cornerRadius: 24)
                    .fill(colorScheme == .dark ? AppDesign.accent.opacity(0.22) : AppDesign.selectionFill)
            }
        }
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
            .modifier(AppFavoritesToolbar(darkHeader: false))
            .toolbar { Button("Listo") { savingToLists = false; showingLists = false } }
        }
        .tint(colorScheme == .dark ? Color(red: 0.65, green: 0.81, blue: 1) : AppDesign.primary)
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
        let information = CatalogPublic.information(feature.information, description: true)
        let serviceCategories = [("fare", "Tarifa"), ("schedule", "Horario"), ("frequency", "Frecuencia")]
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(feature.name)
                        .font(AppDesign.type(17, relativeTo: .title2, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    if let description = information?.description, !description.isEmpty {
                        Text(description).textSelection(.enabled)
                    }
                    ForEach(feature.media ?? [], id: \.self) { media in
                        CatalogPhoto(id: media)
                    }
                    if feature.kind == .route {
                        ForEach(serviceCategories, id: \.0) { category, title in
                            let values = (information?.fields ?? []).filter { $0.category == category }.map(\.value)
                            Text(title + ": " + (values.isEmpty ? "Desconocido" : values.joined(separator: " · ")))
                        }
                        Text("Color del vehículo: " + (feature.routeDetails?.vehicleColor ?? "Desconocido"))
                    }
                    if let details = feature.routeDetails {
                        if let code = details.code, !code.isEmpty { Text("Código: " + code) }
                        if let direction = details.direction, !direction.isEmpty { Text("Sentido: " + direction) }
                        if let circular = details.circular { Text(circular ? "Recorrido circular" : "Recorrido lineal") }
                    }
                    if let information {
                        let fields = information.fields.filter { field in
                            feature.kind != .route || !serviceCategories.contains { $0.0 == field.category }
                        }
                        ForEach(Array(fields.enumerated()), id: \.offset) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.element.label).font(AppDesign.title)
                                Text(item.element.value).textSelection(.enabled)
                            }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle("Información")
            .modifier(AppFavoritesToolbar(darkHeader: false))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { showingInformation = false }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("catalog-information-close")
                }
            }
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
        let positions = feature.kind == .route ? feature.geometry.routeDisplayLines.flatMap { $0 } : feature.geometry.positions
        if let position = AppDesign.routeCamera(positions.map(\.point), minimumSpan: 0.004) {
            camera = position
        } else if feature.kind == .route {
            camera = .region(AppDesign.city)
        }
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
