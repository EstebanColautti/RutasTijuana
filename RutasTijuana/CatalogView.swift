import SwiftUI
import MapKit
import UniformTypeIdentifiers
import Accessibility

struct CatalogView: View {
    @Environment(\.openAppDestination) private var openAppDestination
    @Environment(\.tabReset) private var tabReset
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
    @State private var routeToUse: String?
    @State private var listPath: [UUID] = []
    @State private var listNaming: ListNaming?
    @State private var listPendingDeletion: UUID?
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
                        if selection == nil {
                            VStack(spacing: 0) {
                                routeFilters
                                featureList
                                    .refreshable { privateCatalog = nil; await repository.update(force: true) }
                            }
                            .transition(reduceMotion ? .identity : .opacity)
                        }
                        if let selection {
                            routeSelection(selection)
                            .transition(reduceMotion ? .identity : .opacity)
                        }
                    }
                    .animation(reduceMotion ? nil : AppDesign.navigationMotion, value: selectedID)
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
            if loading || repository.isUpdating {
                AppLoadingView(title: "Actualizando catálogo…", symbol: "arrow.triangle.2.circlepath", compact: true)
                    .padding(.horizontal, 16)
            }
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
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $savingToLists) {
            if let selection {
                listEditor(routeID: selection.id)
                    .presentationDetents([.medium, .large])
                    .presentationCornerRadius(AppDesign.panelRadius)
                    .presentationDragIndicator(.visible)
            }
        }
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
        }) {
            listEditor(routeID: nil)
                .presentationCornerRadius(AppDesign.panelRadius)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingInformation) {
            if let selection { informationSheet(selection)
                    .tint(.blue)
                    .presentationDetents([.fraction(0.72), .large])
                    .presentationDragIndicator(.visible) }
        }
        .sheet(isPresented: $showingServices) {
            NavigationStack { services }
                .tint(.blue)
                .presentationDetents([.fraction(0.72), .large])
                .presentationDragIndicator(.visible)
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

        .toolbar {
            if !favoritesOnly {
                if catalog == nil {
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
            if ProcessInfo.processInfo.arguments.contains("--catalog-info-sample") { privateCatalog = .informationSample }
            if ProcessInfo.processInfo.arguments.contains("--catalog-services-sample") {
                let sample = RouteCatalog.informationSample
                privateCatalog = RouteCatalog(schemaVersion: sample.schemaVersion, version: sample.version,
                    publishable: true, licenseStatus: "published", groups: sample.groups, features: sample.features,
                    serviceInformation: .init(notices: ["Aviso de ejemplo · Cambio de horario"], contact: nil))
            }
            #endif
        }
        .onChange(of: tabReset) { _, _ in
            withAnimation(reduceMotion ? nil : AppDesign.navigationMotion) {
                searchFocused = false
                query = ""
                groupID = nil
                reference = nil
                selectedID = nil
            }
            for sheet in [$showingLists, $savingToLists, $showingInformation, $showingServices, $showingRouteSearch] { sheet.wrappedValue = false }
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
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { showingServices = false } }
            #if DEBUG
            ToolbarItem(placement: .topBarLeading) {
                Button("Abrir catálogo", systemImage: "folder") { showingServices = false; importing = true }.disabled(loading)
            }
            #endif
        }
    }

    private func refreshCatalog() {
        privateCatalog = nil
        Task { await repository.update(force: true) }
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
                        Section {
                            ForEach(sections[name] ?? []) { feature in
                                row(feature)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                    .listRowSeparator(.hidden)
                            }
                        } header: {
                            Text(name).font(AppDesign.subtitle).foregroundStyle(AppDesign.secondaryInk).textCase(nil)
                        }
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
            .animation(reduceMotion ? nil : AppDesign.navigationMotion, value: grouped)
            .animation(reduceMotion ? nil : AppDesign.navigationMotion, value: matches.count)
            .overlay {
                if matches.isEmpty { emptySearch }
            }
    }

    private func favoritesContent(_ catalog: RouteCatalog) -> some View {
        VStack(spacing: 0) {
            AppPanelHeading(title: "Favoritos") { EmptyView() }
                .padding(.horizontal, 14).padding(.top, 8)
            Group {
            if let selection {
                ScrollView {
                    VStack(spacing: 0) {
                        map.frame(height: 220)
                        detail(selection)
                    }
                }
            } else if matches.isEmpty {
                VStack(spacing: 14) {
                    AppFavoriteIcon(scale: textSize.isAccessibilitySize ? 2.6 : 4)
                        .foregroundStyle(AppDesign.accent)
                        .frame(width: 88, height: 88)
                        .background(AppDesign.selectionFill, in: Circle())
                    Text("No hay rutas guardadas.")
                        .font(AppDesign.subtitle)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("Toca la estrella en la ficha de una ruta para tenerla aquí.")
                        .font(AppDesign.explanation)
                        .foregroundStyle(AppDesign.secondaryInk)
                        .multilineTextAlignment(.center)
                    if let openAppDestination {
                        Button("Explorar rutas") { openAppDestination(.routes) }
                            .buttonStyle(AppActionStyle())
                    } else {
                        NavigationLink("Explorar rutas") { CatalogView(routesTab: true) }
                            .buttonStyle(AppActionStyle())
                    }
                }
                .frame(maxWidth: 300)
                .padding(24)
                .transition(reduceMotion ? .identity : .opacity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(matches) { feature in
                            let layout = textSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                                : AnyLayout(HStackLayout(spacing: 8))
                            layout {
                                row(feature)
                            }
                            .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.97)))
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
                    AppFavoriteIcon(filled: true)
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
                    if !(routesTab && grouped) {
                        Text(routesTab || favoritesOnly ? zone(feature) : groupName(feature.groupID)).font(AppDesign.note).foregroundStyle(AppDesign.secondaryInk)
                    }
                    if (routesTab || favoritesOnly), let direction = feature.routeDetails?.direction, !WalkingFormat.sameText(direction, feature.name) {
                        Text(direction).font(AppDesign.note).foregroundStyle(AppDesign.secondaryInk)
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
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .appCard(selected: selectedID == feature.id)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(AppPressStyle())
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
                                        if !subtitle.isEmpty, !WalkingFormat.sameText(subtitle, feature.name) {
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
                                .appCard()
                            }
                            .buttonStyle(AppPressStyle())
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

    private var routeFilters: some View {
        VStack(spacing: 12) {
            AppPanelHeading(title: "Rutas") { EmptyView() }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppDesign.secondaryInk).accessibilityHidden(true)
                TextField("Buscar ruta o zona", text: $query, prompt: Text("Buscar ruta o zona").foregroundStyle(AppDesign.secondaryInk))
                    .frame(minHeight: 44)
                    .focused($searchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { searchFocused = false }
                    .accessibilityLabel("Buscar nombre, grupo o información")
                    .accessibilityIdentifier("catalog-search")
                if !query.isEmpty {
                    Button("Borrar búsqueda", systemImage: "xmark.circle.fill") { query = "" }
                        .buttonStyle(AppIconButtonStyle()).foregroundStyle(AppDesign.secondaryInk)
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onTapGesture { searchFocused = true }
            .appSearchSurface()
            .animation(reduceMotion ? nil : AppDesign.selectionMotion, value: query.isEmpty)
            HStack(spacing: 8) {
                Picker("Organización", selection: $grouped) {
                    Text("Por zona").tag(true)
                    Text("Todas").tag(false)
                }
                .pickerStyle(.segmented)
                AppGlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                Menu {
                    Picker("Grupo", selection: $groupID) {
                        Text("Todos los grupos").tag(String?.none)
                        ForEach(catalog?.groups ?? []) { group in Text(group.name).tag(Optional(group.id)) }
                    }
                } label: {
                    routeTool(groupID == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel(groupID == nil ? "Filtrar por grupo" : "Filtro de grupo activo")
                Button { listName = ""; showingLists = true } label: { routeTool("bookmark") }
                    .buttonStyle(AppPressStyle())
                    .accessibilityLabel("Mis listas")
                if hasServiceNotices || catalog?.serviceContact != nil {
                    Button { showingServices = true } label: {
                        routeTool("info.circle")
                            .overlay(alignment: .topTrailing) {
                                if hasServiceNotices {
                                    Circle().fill(AppDesign.accent)
                                        .frame(width: 11, height: 11)
                                        .overlay { Circle().strokeBorder(Color(uiColor: .systemBackground), lineWidth: 2) }
                                        .offset(x: -3, y: 3)
                                        .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
                                }
                            }
                    }
                    .buttonStyle(AppPressStyle())
                    .accessibilityLabel("Servicios")
                    .accessibilityValue(hasServiceNotices ? "Hay avisos" : "")
                    .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
                }
                }
                }
            }
            HStack {
                let count = "\(matches.count) \(matches.count == 1 ? "ruta" : "rutas")"
                Text(count)
                    .font(AppDesign.note).foregroundStyle(AppDesign.secondaryInk)
                    .contentTransition(.numericText())
                    .accessibilityLabel(count)
                    .animation(reduceMotion ? nil : AppDesign.selectionMotion, value: matches.count)
                Spacer()
                if reference != nil {
                    Button("Quitar cercanía") { reference = nil; selectedID = nil; camera = .automatic }
                        .font(AppDesign.note)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var hasServiceNotices: Bool {
        !(catalog?.serviceNotices.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []).isEmpty
    }

    private func routeTool(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.body.weight(.medium))
            .foregroundStyle(routeActionInk)
            .frame(width: 44, height: 44)
            .appGlass(in: Circle(), interactive: true)
            .contentShape(Circle())
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
                        .font(AppDesign.note).padding(8).appGlass(in: Capsule())
                        .padding(10).allowsHitTesting(false)
                }
            }
        }
    }

    private func routeSelection(_ feature: CatalogFeature) -> some View {
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
                                    .appGlass(in: Circle(), interactive: true)
                            }
                            .buttonStyle(AppPressStyle())
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

                    if feature.kind == .stop, case .point(let point) = feature.geometry {
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

    private func summaryRow(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(AppDesign.body).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(routeActionInk).frame(width: 24)
        }
    }

    private func routeSummary(_ feature: CatalogFeature, hasTrace: Bool) -> some View {
        let fields = CatalogPublic.information(feature.information, description: false)?.fields ?? []
        return VStack(alignment: .leading, spacing: 6) {
            if textSize.isAccessibilitySize { routeTitle(feature) }
            if feature.kind == .route {
                summaryRow("map", "Zona: " + zone(feature))
                if !hasTrace {
                    summaryRow("exclamationmark.triangle", "Trazado no disponible")
                }
                if let direction = feature.routeDetails?.direction, !direction.isEmpty, !WalkingFormat.sameText(direction, feature.name) {
                    summaryRow("arrow.triangle.turn.up.right.diamond", "Sentido: " + direction)
                }
                ForEach(["fare", "schedule"], id: \.self) { category in
                    if let field = fields.first(where: { $0.category == category && !$0.value.isEmpty }) {
                        let title = category == "fare" ? "Tarifa" : "Horario"
                        summaryRow(category == "fare" ? "dollarsign.circle" : "clock",
                                   field.value.localizedCaseInsensitiveContains(title + ":") ? field.value : title + ": " + field.value)
                    }
                }
            }
            if feature.kind == .route || feature.information != nil || feature.routeDetails != nil || !(feature.media ?? []).isEmpty {
                Button { showingInformation = true } label: {
                    Label("Ver información", systemImage: "info.circle")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                    .font(AppDesign.subtitle)
                    .foregroundStyle(routeActionInk)
                    .buttonStyle(AppPressStyle())
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
                .buttonStyle(AppIconButtonStyle())
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .animation(reduceMotion ? nil : AppDesign.selectionMotion, value: saved)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityValue(saved ? "Guardado en listas" : "Sin guardar")
            }
            Button("Cerrar", systemImage: "xmark") { selectedID = nil }
                .buttonStyle(AppIconButtonStyle())
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

    private enum ListNaming: Equatable {
        case create(routeID: String?)
        case rename(UUID)
    }

    private var trimmedListName: String { listName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func listNameIsValid(for naming: ListNaming?) -> Bool {
        guard !trimmedListName.isEmpty else { return false }
        let renaming: UUID? = if case .rename(let id) = naming { id } else { nil }
        return !savedLists.contains { $0.id != renaming && normalized($0.name) == normalized(trimmedListName) }
    }

    private func commitListName(_ naming: ListNaming) {
        guard listNameIsValid(for: naming) else { return }
        withAnimation(reduceMotion ? nil : AppDesign.navigationMotion) {
            switch naming {
            case .create(let routeID):
                savedLists = savedLists + [SavedList(name: trimmedListName, routes: routeID.map { [$0] } ?? [])]
            case .rename(let id):
                savedLists = savedLists.map { item in
                    var changed = item
                    if changed.id == id { changed.name = trimmedListName }
                    return changed
                }
            }
        }
        listName = ""
        listNaming = nil
    }

    private func routeCount(_ count: Int) -> String { "\(count) \(count == 1 ? "ruta" : "rutas")" }

    private func listIcon(_ symbol: String = "list.bullet") -> some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(AppDesign.primary)
            .frame(width: 40, height: 40)
            .background(AppDesign.selectionFill, in: Circle())
            .accessibilityHidden(true)
    }

    private func listRow(_ list: SavedList, trailing: String, highlighted: Bool = false) -> some View {
        HStack(spacing: 12) {
            listIcon()
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name).font(AppDesign.subtitle).foregroundStyle(.primary)
                Text(routeCount(list.routes.count)).font(AppDesign.note).foregroundStyle(AppDesign.secondaryInk)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            Image(systemName: trailing)
                .font(.title3)
                .foregroundStyle(highlighted ? AppDesign.primary : AppDesign.secondaryInk)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .appCard(selected: highlighted)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func newListButton(_ routeID: String?, prominent: Bool) -> some View {
        Group {
            if prominent {
                Button("Nueva lista", systemImage: "plus") { listName = ""; listNaming = .create(routeID: routeID) }
                    .buttonStyle(AppActionStyle())
            } else {
                Button { listName = ""; listNaming = .create(routeID: routeID) } label: {
                    HStack(spacing: 12) {
                        listIcon("plus")
                        Text("Nueva lista").font(AppDesign.subtitle).foregroundStyle(AppDesign.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(AppDesign.secondaryInk.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(AppPressStyle())
            }
        }
        .accessibilityIdentifier("list-new")
    }

    private func listsEmptyState(_ routeID: String?) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(AppDesign.accent)
                .frame(width: 88, height: 88)
                .background(AppDesign.selectionFill, in: Circle())
                .accessibilityHidden(true)
            Text("Aún no tienes listas").font(AppDesign.subtitle).accessibilityAddTraits(.isHeader)
            Text(routeID == nil ? "Agrupa tus rutas, por ejemplo «Trabajo» o «Escuela»."
                                : "Crea una lista para guardar esta ruta.")
                .font(AppDesign.explanation).foregroundStyle(AppDesign.secondaryInk).multilineTextAlignment(.center)
            newListButton(routeID, prominent: true)
        }
        .frame(maxWidth: 300)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }

    /// Contenido de los diálogos de listas. Lo presenta la pantalla visible (raíz o detalle): desde iOS 18 un
    /// diálogo del contenedor no recibe sus botones mientras hay una pantalla apilada encima.
    private var listDialogContent: ListDialogContent {
        let naming = listNaming ?? .create(routeID: nil)
        return ListDialogContent(
            title: { if case .rename = naming { "Renombrar lista" } else { "Nueva lista" } }(),
            confirm: { if case .rename = naming { "Guardar" } else { "Crear" } }(),
            text: $listName,
            valid: listNameIsValid(for: naming),
            commit: { commitListName(naming) },
            cancel: { listName = "" })
    }

    private var listDeletionContent: ListDeletionContent {
        let name = listPendingDeletion.flatMap { id in savedLists.first { $0.id == id } }?.name ?? ""
        return ListDeletionContent(title: "¿Eliminar «\(name)»?", delete: {
            guard let id = listPendingDeletion else { return }
            withAnimation(reduceMotion ? nil : AppDesign.navigationMotion) { savedLists = savedLists.filter { $0.id != id } }
            listPath.removeAll { $0 == id }
            listPendingDeletion = nil
        })
    }

    private func listEditor(routeID: String?) -> some View {
        NavigationStack(path: $listPath) {
            ScrollView {
                VStack(spacing: 12) {
                    if let routeID, let feature = catalog?.features.first(where: { $0.id == routeID }) {
                        HStack(spacing: 12) {
                            AppGlyph(icon: .turn).foregroundStyle(routeColor(feature))
                                .frame(width: 40, height: 40)
                                .background(Color(uiColor: .systemBackground), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ruta").font(AppDesign.note).foregroundStyle(AppDesign.secondaryInk)
                                Text(feature.name).font(AppDesign.subtitle).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .appCard()
                        .accessibilityElement(children: .combine)
                        if !savedLists.isEmpty {
                            Text("Elige en qué listas guardarla")
                                .font(AppDesign.subtitle).foregroundStyle(AppDesign.secondaryInk)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                        }
                    }
                    if savedLists.isEmpty {
                        listsEmptyState(routeID)
                    } else {
                        ForEach(savedLists) { list in
                            if let routeID {
                                let included = list.routes.contains(routeID)
                                Button { withAnimation(reduceMotion ? nil : AppDesign.selectionMotion) { toggleRoute(routeID, listID: list.id) } } label: {
                                    listRow(list, trailing: included ? "checkmark.circle.fill" : "circle", highlighted: included)
                                }
                                .buttonStyle(AppPressStyle())
                                .sensoryFeedback(.selection, trigger: included)
                                .accessibilityLabel(list.name)
                                .accessibilityValue(included ? "Guardada, " + routeCount(list.routes.count) : "Sin guardar, " + routeCount(list.routes.count))
                                .accessibilityAddTraits(included ? .isSelected : [])
                            } else {
                                NavigationLink(value: list.id) {
                                    listRow(list, trailing: "chevron.right")
                                }
                                .buttonStyle(AppPressStyle())
                                .accessibilityLabel(list.name)
                                .accessibilityValue(routeCount(list.routes.count))
                                .contextMenu {
                                    Button("Renombrar", systemImage: "pencil") { listName = list.name; listNaming = .rename(list.id) }
                                    Button("Eliminar lista", systemImage: "trash", role: .destructive) { listPendingDeletion = list.id }
                                }
                            }
                        }
                        newListButton(routeID, prominent: false)
                    }
                }
                .padding(16)
                .animation(reduceMotion ? nil : AppDesign.navigationMotion, value: savedLists.map(\.id))
            }
            .navigationTitle(routeID == nil ? "Mis listas" : "Guardar en listas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { savingToLists = false; showingLists = false }
                }
            }
            .listDialogs(active: listPath.isEmpty, naming: $listNaming, pendingDeletion: $listPendingDeletion,
                         content: listDialogContent, deletion: listDeletionContent)
            .navigationDestination(for: UUID.self) { id in
                listDetail(id)
                    .listDialogs(active: listPath.last == id, naming: $listNaming, pendingDeletion: $listPendingDeletion,
                                 content: listDialogContent, deletion: listDeletionContent)
            }
        }
        .tint(colorScheme == .dark ? Color(red: 0.65, green: 0.81, blue: 1) : AppDesign.primary)
        .onDisappear { listPath = [] }
    }

    @ViewBuilder private func listDetail(_ id: UUID) -> some View {
        if let list = savedLists.first(where: { $0.id == id }) {
            List {
                if list.routes.isEmpty {
                    VStack(spacing: 12) {
                        listIcon("bookmark")
                        Text("Esta lista está vacía").font(AppDesign.subtitle)
                        Text("Abre una ruta y toca el marcador para guardarla aquí.")
                            .font(AppDesign.explanation).foregroundStyle(AppDesign.secondaryInk).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                ForEach(list.routes, id: \.self) { routeID in
                    let feature = catalog?.features.first { $0.id == routeID }
                    Button {
                        guard feature != nil else { return }
                        routeToUse = routeID
                        showingLists = false
                    } label: {
                        HStack(spacing: 12) {
                            if let feature {
                                AppGlyph(icon: .turn).foregroundStyle(routeColor(feature))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.name).font(AppDesign.subtitle).foregroundStyle(.primary)
                                    Text(zone(feature)).font(AppDesign.note).foregroundStyle(AppDesign.secondaryInk)
                                }
                            } else {
                                Image(systemName: "exclamationmark.triangle").foregroundStyle(AppDesign.secondaryInk)
                                Text("Ruta no disponible").font(AppDesign.subtitle).foregroundStyle(AppDesign.secondaryInk)
                            }
                            Spacer(minLength: 0)
                            if feature != nil {
                                Image(systemName: "chevron.right").foregroundStyle(AppDesign.secondaryInk).accessibilityHidden(true)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        .appCard()
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(AppPressStyle())
                    .accessibilityIdentifier("list-route-" + routeID)
                    .accessibilityHint(feature == nil ? "" : "Abre la ruta")
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions {
                        Button("Quitar", systemImage: "minus.circle", role: .destructive) { toggleRoute(routeID, listID: id) }
                    }
                    .contextMenu {
                        Button("Quitar de la lista", systemImage: "minus.circle", role: .destructive) { toggleRoute(routeID, listID: id) }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .animation(reduceMotion ? nil : AppDesign.navigationMotion, value: list.routes)
            .navigationTitle(list.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Renombrar", systemImage: "pencil") { listName = list.name; listNaming = .rename(id) }
                        Button("Eliminar lista", systemImage: "trash", role: .destructive) { listPendingDeletion = id }
                    } label: {
                        Label("Opciones de la lista", systemImage: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("list-options")
                }
            }
        } else {
            ContentUnavailableView("Lista eliminada", systemImage: "trash")
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

struct ListDialogContent {
    let title: String
    let confirm: String
    let text: Binding<String>
    let valid: Bool
    let commit: () -> Void
    let cancel: () -> Void
}

struct ListDeletionContent {
    let title: String
    let delete: () -> Void
}

private extension View {
    /// Diálogos de crear, renombrar y eliminar listas, presentados solo por la pantalla visible.
    func listDialogs<Naming: Equatable>(active: Bool, naming: Binding<Naming?>, pendingDeletion: Binding<UUID?>,
                                        content: ListDialogContent, deletion: ListDeletionContent) -> some View {
        self
            .alert(content.title, isPresented: Binding(get: { active && naming.wrappedValue != nil },
                                                       set: { if !$0 { naming.wrappedValue = nil } })) {
                TextField("Nombre de la lista", text: content.text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.sentences)
                Button("Cancelar", role: .cancel) { content.cancel() }
                // El campo puede entregar el texto después de la acción: se confirma en el siguiente ciclo.
                Button(content.confirm) { Task { @MainActor in await Task.yield(); content.commit() } }
                    .disabled(!content.valid)
            } message: {
                Text("Por ejemplo «Trabajo» o «Escuela».")
            }
            .confirmationDialog(deletion.title, isPresented: Binding(get: { active && pendingDeletion.wrappedValue != nil },
                                                                     set: { if !$0 { pendingDeletion.wrappedValue = nil } }),
                                titleVisibility: .visible) {
                Button("Eliminar lista", role: .destructive) { deletion.delete() }
                Button("Cancelar", role: .cancel) { pendingDeletion.wrappedValue = nil }
            } message: {
                Text("Las rutas siguen disponibles en Rutas.")
            }
    }
}
