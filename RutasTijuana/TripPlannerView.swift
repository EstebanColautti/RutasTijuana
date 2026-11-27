import SwiftUI
import MapKit
import Accessibility
import CoreLocation

/// Parada de subida o bajada: punto pequeño como las paradas de transporte de Apple Maps.
struct TransitStopDot: View {
    let symbol: String
    let fill: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(fill, in: Circle())
            .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

struct TripActionButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppDesign.subtitle)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
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
        let stops: [CatalogFeature] = (0..<3).map { index in
            let latitude = 32.5 + Double(index) * 0.01
            let position = CatalogPosition(longitude: -117, latitude: latitude)
            return CatalogFeature(id: "trip-stop-\(index)", name: "Parada \(index + 1)", groupID: "g", kind: .stop,
                color: "#164B85", verified: false, geometry: .point(position))
        }
        let routes: [CatalogFeature] = (0..<2).map { index in
            let next = index + 1
            let start = CatalogPosition(longitude: -117, latitude: 32.5 + Double(index) * 0.01)
            let end = CatalogPosition(longitude: -117, latitude: 32.5 + Double(next) * 0.01)
            return CatalogFeature(id: "trip-route-\(index)", name: "Recorrido \(next)", groupID: "g", kind: .route,
                color: "#164B85", verified: false, geometry: .line([start, end]),
                itinerary: .init(stopIDs: ["trip-stop-\(index)", "trip-stop-\(next)"],
                                 circular: false, direction: "Sentido de ejemplo", updatedAt: "2026-11-07"))
        }
        return .init(schemaVersion: 1, version: "trip-example", publishable: true, licenseStatus: "published",
                     groups: [.init(id: "g", name: "Ejemplo")], features: stops + routes)
    }
}
#endif

struct TripPlannerView: View {
    @AppStorage("recent-planned-routes") private var recentPlannedData = Data()

    let catalog: RouteCatalog
    let integratedHome: Bool
    @Environment(\.homeTripActive) private var homeTripActive
    @State private var useCurrentOrigin = true
    @State private var centeredOnLocation = false
    private enum HomePanelHeight: Int {
        case collapsed, regular, expanded

        var accessibilityValue: String {
            switch self {
            case .collapsed: "Reducido"
            case .regular: "Medio"
            case .expanded: "Expandido"
            }
        }

        func moved(up: Bool) -> Self {
            Self(rawValue: rawValue + (up ? 1 : -1)) ?? self
        }
    }

    @State private var homePanelHeight: HomePanelHeight = .regular
    @State private var homePanelDrag: CGFloat = 0
    @State private var homeFeature: MapFeature?
    @State private var lastFeatureTap = Date.distantPast
    @State private var homeMapTap: Task<Void, Never>?
    @State private var placeLookup: Task<Void, Never>?
    @State private var geocoder = CLGeocoder()
    @State private var homeStagesExpanded = false
    @State private var alternative: PlannedTrip?
    @State private var recommended: PlannedTrip?
    @State private var showingAlternative = false
    @State private var alternativeTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openAppDestination) private var openAppDestination
    @Environment(\.activeAppDestination) private var activeAppDestination
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var searchExpanded = false
    @State private var searchMessage = ""
    @State private var searchingPlaces = false
    @State private var placeSearchFailed = false
    @State private var searchDelay: Task<Void, Never>?
    @AppStorage("journey-recent") private var recentData = Data()
    @State private var selectingOrigin = true
    @State private var places: [MKMapItem] = []
    @State private var message = ""
    @State private var transferCache = TripTransferCache()
    @State private var planner: TripPlanner?
    @State private var plannedVersion: String?
    @State private var trip: PlannedTrip?
    @State private var selectedLegIndex: Int?
    @State private var working = false
    @State private var paused = false
    @State private var canRetry = false
    @State private var task: Task<Void, Never>?
    @State private var search: MKLocalSearch?
    @State private var searchGeneration = UUID()
    @State private var travelling = false
    @FocusState private var searchFocused: Bool
    @AccessibilityFocusState private var resultFocused: Bool
    @State private var selectingOnMap = false
    @State private var mapPoint: GeoPoint?
    @State private var selectorCamera: MapCameraPosition = .region(AppDesign.city)
    @State private var camera: MapCameraPosition = .region(AppDesign.city)
    @State private var requiredRouteID: String?
    @State private var canSearchAll = false

    init(catalog: RouteCatalog, requiredRouteID: String? = nil, integratedHome: Bool = false) {
        self.integratedHome = integratedHome
        _selectingOrigin = State(initialValue: !integratedHome)
        _requiredRouteID = State(initialValue: requiredRouteID)
        self.catalog = catalog
        #if DEBUG
        if integratedHome, ProcessInfo.processInfo.arguments.contains("--capture-walking-stage") {
            _origin = State(initialValue: GeoPoint(latitude: 32.5149, longitude: -117.0382))
            _destination = State(initialValue: GeoPoint(latitude: 32.5158, longitude: -117.0362))
            _originName = State(initialValue: "Hipódromo")
            _destinationName = State(initialValue: "Avenida Hipódromo")
            _useCurrentOrigin = State(initialValue: false)
        } else if ProcessInfo.processInfo.arguments.contains("--capture-catalog"),
           let line = catalog.features.first(where: { $0.kind == .route && !$0.geometry.lines.isEmpty })?.geometry.lines.first,
           line.count >= 2 {
            _origin = State(initialValue: line[Int((Double(line.count - 1) * 0.2).rounded())].point)
            _destination = State(initialValue: line[Int((Double(line.count - 1) * 0.6).rounded())].point)
            _originName = State(initialValue: "Punto de origen")
            _destinationName = State(initialValue: "Punto de destino")
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
        if integratedHome { homeMap }
        else { consultation }
    }

    private var homeMotion: Animation? {
        reduceMotion ? nil : AppDesign.navigationMotion
    }

    private var homeTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .offset(y: 8))
    }

    private var homeMap: some View {
        GeometryReader { geometry in
            let regularHeight = geometry.size.height * 0.54
            let panelHeight = travelling || trip != nil || textSize.isAccessibilitySize
                ? regularHeight
                : min(regularHeight, destination == nil ? 96 : working || !message.isEmpty ? 250 : 210)
            let canExpand = travelling || destination != nil
            let tallHeight = canExpand ? max(panelHeight, min(geometry.size.height * 0.80, geometry.size.height - 110)) : panelHeight
            let height = switch homePanelHeight {
            case .collapsed: CGFloat(44)
            case .regular: panelHeight
            case .expanded: tallHeight
            }
            let visibleHeight = min(tallHeight, max(44, height - homePanelDrag))
            VStack(spacing: 0) {
                Text("Rutas Tijuana")
                    .font(AppDesign.type(17, relativeTo: .headline, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.bottom, 10)
                    .background { AppDesign.header.ignoresSafeArea(edges: .top) }
                    .accessibilityIdentifier("home-title")

                ZStack(alignment: .bottom) {
                MapReader { proxy in
                    Map(position: $camera, selection: $homeFeature) {
                        UserAnnotation()
                        mapContents
                    }
                    .mapStyle(.standard(elevation: .flat))
                    .safeAreaPadding(.top, travelling ? 0 : 64)
                    .safeAreaPadding(.bottom, visibleHeight + geometry.safeAreaInsets.bottom)
                    .accessibilityLabel("Mapa de Tijuana")
                    .onTapGesture { position in
                        guard !travelling, let coordinate = proxy.convert(position, from: .local) else { return }
                        homeMapTap?.cancel()
                        homeMapTap = Task {
                            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                            guard homeFeature == nil, Date().timeIntervalSince(lastFeatureTap) > 0.35 else { return }
                            markHomeCoordinate(coordinate)
                        }
                    }
                    .onChange(of: homeFeature) { _, feature in
                        guard !travelling, let feature else { return }
                        homeMapTap?.cancel()
                        lastFeatureTap = Date()
                        homeFeature = nil
                        markHomeCoordinate(feature.coordinate, label: feature.title)
                    }
                    .overlay(alignment: .top) {
                        if !travelling { homeSearch.padding(14).transition(homeTransition) }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if let point = location.point {
                            Button {
                                centerHome(on: point)
                            } label: {
                                Image(systemName: "location.fill")
                                    .frame(width: 44, height: 44)
                                    .appGlass(in: Circle(), interactive: true)
                            }
                            .accessibilityLabel("Centrar en mi ubicación")
                            .padding(12)
                            .padding(.bottom, visibleHeight + geometry.safeAreaInsets.bottom)
                            .transition(reduceMotion ? .identity : .opacity)
                        }
                    }
                    .animation(homeMotion, value: location.point != nil)
                }
                .ignoresSafeArea(.container, edges: .bottom)
                VStack(spacing: 0) {
                    Button {
                        resizeHomePanel(up: homePanelHeight == .collapsed, canExpand: canExpand)
                    } label: {
                        Capsule().fill(.secondary.opacity(0.55))
                            .frame(width: 34, height: 5)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(homePanelHeight == .collapsed ? "Ampliar panel" : "Reducir panel")
                    .accessibilityIdentifier("home-panel-handle")
                    .accessibilityValue(homePanelHeight.accessibilityValue)
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: resizeHomePanel(up: true, canExpand: canExpand)
                        case .decrement: resizeHomePanel(up: false, canExpand: canExpand)
                        @unknown default: break
                        }
                    }
                    .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { homePanelDrag = $0.translation.height }
                        .onEnded { value in
                            if abs(value.translation.height) > 24 {
                                resizeHomePanel(up: value.translation.height < 0, canExpand: canExpand)
                            } else if abs(value.translation.height) < 8 {
                                resizeHomePanel(up: homePanelHeight == .collapsed, canExpand: canExpand)
                            } else {
                                withAnimation(reduceMotion ? nil : AppDesign.navigationMotion) { homePanelDrag = 0 }
                            }
                        })
                    if travelling, let trip {
                        TripTravelView(trip: trip, destinationName: destinationName, onReplan: { point in
                            travelling = false
                            useCurrentOrigin = false
                            origin = point
                            originName = "Tu ubicación"
                            invalidate()
                            calculate()
                        }, inlineFinish: {
                            travelling = false
                            invalidate()
                            destination = nil
                            destinationName = ""
                            homePanelHeight = .regular
                        }, onStageChange: { index in
                            homeTripActive?.wrappedValue = trip.legs.indices.contains(index)
                            if trip.legs.indices.contains(index) {
                                selectedLegIndex = index
                                showLeg(trip.legs[index])
                            }
                        })
                        .transition(homeTransition)
                    } else {
                        ScrollView {
                            homeDetails.frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.bottom, 6)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .transition(homeTransition)
                    }
                }
                .frame(height: visibleHeight, alignment: .top)
                .clipped()
                .contentShape(Rectangle())
                .background { AppDesign.glassPanel().ignoresSafeArea(.container, edges: .bottom) }
                }
            }
            .animation(homeMotion, value: travelling)
            .animation(homeMotion, value: destination != nil)
            .animation(homeMotion, value: trip != nil)
            .animation(homeMotion, value: working)
        }
        .tint(AppDesign.primary)
        .onAppear {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--ui-testing"), !arguments.contains("--test-current-location") { return }
            #endif
            location.request(continuously: true)
            if !useCurrentOrigin && origin != nil && destination != nil && trip == nil { calculate() }
        }
        .onChange(of: travelling) { _, active in homeTripActive?.wrappedValue = active }
        .onChange(of: catalog.version, initial: true) { _, _ in
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--capture-catalog"), origin == nil, destination == nil,
               let line = catalog.features.first(where: { $0.kind == .route })?.geometry.lines.first, line.count > 2 {
                useCurrentOrigin = false
                origin = line[Int(Double(line.count - 1) * 0.2)].point
                destination = line[Int(Double(line.count - 1) * 0.6)].point
                originName = "Punto de origen"
                destinationName = "Punto de destino"
            }
            if ProcessInfo.processInfo.arguments.contains("--capture-catalog") { resolveCaptureNames() }
            #endif
            if origin != nil && destination != nil && trip == nil && !working { calculate() }
        }
        .onChange(of: location.point) { _, point in
            guard let point else {
                if useCurrentOrigin && !travelling { invalidate(); origin = nil; originName = "" }
                return
            }
            if !centeredOnLocation {
                centeredOnLocation = true
                if !camera.positionedByUser && destination == nil { centerHome(on: point) }
            }
            if useCurrentOrigin, origin == nil {
                origin = point
                originName = "Mi ubicación"
                if destination != nil { calculate() }
            }
        }
        .onDisappear {
            location.cancel()
            homeMapTap?.cancel()
            cancelPlaceLookup()
            searchDelay?.cancel()
            search?.cancel()
            if !travelling { invalidate() }
        }
    }

    private func resizeHomePanel(up: Bool, canExpand: Bool) {
        withAnimation(reduceMotion ? nil : AppDesign.navigationMotion) {
            let next = homePanelHeight.moved(up: up)
            homePanelHeight = next == .expanded && !canExpand ? .regular : next
            homePanelDrag = 0
        }
    }

    private var homeSearch: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").accessibilityHidden(true)
                let placeholder = selectingOrigin ? "Buscar origen" : "Buscar destino"
                TextField(placeholder, text: $query, prompt: Text(placeholder).foregroundStyle(AppDesign.secondaryInk))
                    .frame(minHeight: 44)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { findPlaces() }
                    .accessibilityIdentifier("trip-place-search")
                if searchExpanded {
                    Button("Cerrar", systemImage: "xmark") {
                        searchFocused = false
                        searchExpanded = false
                        selectingOrigin = false
                        query = ""
                    }
                    .buttonStyle(AppIconButtonStyle())
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
            .onTapGesture { searchFocused = true }
            if searchExpanded && (!places.isEmpty || !searchMessage.isEmpty || searchingPlaces) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if searchingPlaces { AppLoadingView(title: "Buscando lugares…", symbol: "magnifyingglass", compact: true) }
                        if !searchMessage.isEmpty { Text(searchMessage).font(AppDesign.note) }
                        ForEach(Array(places.prefix(8).enumerated()), id: \.offset) { row in
                            let item = row.element
                            Button {
                                let point = item.placemark.coordinate
                                chooseHomePoint(.init(latitude: point.latitude, longitude: point.longitude),
                                                name: item.name ?? "Punto en el mapa")
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "Lugar").font(AppDesign.subtitle)
                                    if let address = item.placemark.title, address != item.name {
                                        Text(address).font(AppDesign.note)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("trip-place-\(row.offset)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.bottom, 10)
                }
                .frame(height: min(210, CGFloat(max(1, places.count)) * 56))
                .transition(homeTransition)
            }
        }
        .foregroundStyle(.primary)
        .appSearchSurface()
        .animation(homeMotion, value: searchExpanded)
        .animation(homeMotion, value: places.count)
        .animation(homeMotion, value: searchingPlaces)
        .onChange(of: searchFocused) { _, focused in if focused { searchExpanded = true } }
        .onChange(of: query) { _, value in
            searchDelay?.cancel()
            search?.cancel()
            searchGeneration = UUID()
            places = []
            searchMessage = ""
            searchingPlaces = false
            guard searchExpanded, value.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return }
            searchDelay = Task {
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                if searchExpanded { findPlaces(dismissKeyboard: false) }
            }
        }
    }

    private var homeDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let destination {
                AppPanelHeading(title: "Tu trayecto") {
                    Button("Quitar destino", systemImage: "xmark") {
                        invalidate()
                        cancelPlaceLookup()
                        homeFeature = nil
                        self.destination = nil
                        destinationName = ""
                        homePanelHeight = .regular
                        selectingOrigin = false
                        query = ""
                        searchFocused = false
                        searchExpanded = false
                        homeStagesExpanded = false
                    }
                    .buttonStyle(AppIconButtonStyle())
                }
                VStack(spacing: 0) {
                    Button {
                        selectingOrigin = true
                        searchExpanded = true
                        query = ""
                        searchFocused = true
                    } label: {
                        endpointRow(originName.isEmpty ? "Elegir origen" : originName,
                                    caption: "Origen", symbol: "location.fill", editable: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(originName.isEmpty ? "Elegir origen" : "Cambiar origen: " + originName)
                    Divider().padding(.leading, 52)
                    endpointRow(destinationName, caption: "Destino", symbol: "mappin", editable: false)
                        .accessibilityIdentifier("home-destination")
                }
                .padding(.horizontal, 10)
                .appCard()

                if !useCurrentOrigin, let current = location.point, current != destination {
                    Button("Usar mi ubicación") {
                        useCurrentOrigin = true
                        cancelPlaceLookup()
                        invalidate()
                        origin = current
                        originName = "Mi ubicación"
                        calculate()
                    }.frame(minHeight: 44)
                }
                if working {
                    AppLoadingView(title: "Calculando itinerario…")
                        .transition(homeTransition)
                }
                if !message.isEmpty {
                    Text(message).accessibilityIdentifier("trip-status")
                    if canRetry { Button("Volver a calcular", action: calculate).frame(minHeight: 44) }
                }
                if let trip {
                    homeItineraryCard(trip)
                        .transition(homeTransition)
                    if let recommended, let alternative {
                        Picker("Itinerario", selection: Binding(
                            get: { showingAlternative },
                            set: { showingAlternative = $0; chooseItinerary($0 ? alternative : recommended) }
                        )) {
                            Text("Recomendada").tag(false)
                            Text("Alternativa").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .transition(homeTransition)
                    }
                    DisclosureGroup("Ver etapas", isExpanded: $homeStagesExpanded) {
                        ForEach(Array(trip.legs.enumerated()), id: \.offset) { row in
                            tripLegCard(row.element, index: row.offset, total: trip.legs.count)
                        }
                    }
                    .font(AppDesign.subtitle)
                    .padding(.vertical, 6)
                    .animation(homeMotion, value: homeStagesExpanded)
                }
            } else {
                Text("Elige un destino en el mapa o búscalo arriba.")
                    .font(AppDesign.explanation)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func endpointRow(_ title: String, caption: String, symbol: String, editable: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppDesign.primary)
                .frame(width: 32, height: 32)
                .background(AppDesign.selectionFill, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(caption).font(AppDesign.note).foregroundStyle(AppDesign.secondaryInk)
                Text(title).font(AppDesign.subtitle)
                    .foregroundStyle(editable && originName.isEmpty ? AppDesign.primary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if editable { Image(systemName: "pencil").foregroundStyle(AppDesign.secondaryInk).accessibilityHidden(true) }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func homeItineraryCard(_ trip: PlannedTrip) -> some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(estimatedDuration(trip).map { WalkingFormat.duration($0, arrived: false) } ?? "Itinerario")
                    .font(AppDesign.title)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("trip-result")
                if let service = primaryService { Text(service.name).font(AppDesign.note) }
                Text(trip.summary)
                    .font(AppDesign.note)
                    .foregroundStyle(AppDesign.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                searchFocused = false
                alternativeTask?.cancel()
                selectedLegIndex = nil
                travelling = true
            } label: {
                Text("Iniciar viaje")
            }
            .buttonStyle(AppActionStyle())
            .accessibilityIdentifier("trip-begin")
        }
        .padding(12)
        .appCard()
        .animation(homeMotion, value: estimatedDuration(trip))
    }

    private func cancelPlaceLookup() {
        placeLookup?.cancel()
        geocoder.cancelGeocode()
    }

    private func markHomeCoordinate(_ coordinate: CLLocationCoordinate2D, label: String? = nil) {
        let pickingOrigin = selectingOrigin
        let point = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let knownName = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        chooseHomePoint(point, name: knownName.flatMap { $0.isEmpty ? nil : $0 } ?? "Buscando dirección…")
        guard knownName == nil || knownName == "" else { return }
        placeLookup = Task {
            let place = try? await geocoder.reverseGeocodeLocation(
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            ).first
            guard !Task.isCancelled else { return }
            let street = [place?.thoroughfare, place?.subThoroughfare].compactMap { $0 }.joined(separator: " ")
            let name = street.isEmpty ? (place?.subLocality ?? place?.locality ?? "Ubicación sin dirección") : street
            if pickingOrigin, origin == point { originName = name }
            if !pickingOrigin, destination == point { destinationName = name }
        }
    }

    #if DEBUG
    /// Las capturas parten de puntos del catálogo; muestra la dirección real en lugar del rótulo provisional.
    private func resolveCaptureNames() {
        guard let origin, let destination,
              originName == "Punto de origen" || destinationName == "Punto de destino" else { return }
        Task {
            let lookup = CLGeocoder()
            for (point, isOrigin) in [(origin, true), (destination, false)] {
                guard let place = try? await lookup.reverseGeocodeLocation(
                    CLLocation(latitude: point.latitude, longitude: point.longitude)
                ).first else { continue }
                let street = [place.thoroughfare, place.subThoroughfare].compactMap { $0 }.joined(separator: " ")
                guard let name = street.isEmpty ? (place.subLocality ?? place.locality) : street else { continue }
                if isOrigin, self.origin == point, originName == "Punto de origen" { originName = name }
                if !isOrigin, self.destination == point, destinationName == "Punto de destino" { destinationName = name }
            }
        }
    }
    #endif

    private func centerHome(on point: GeoPoint) {
        withAnimation(homeMotion) {
            camera = .region(.init(center: .init(latitude: point.latitude, longitude: point.longitude),
                                   span: .init(latitudeDelta: 0.025, longitudeDelta: 0.031)))
        }
    }

    private func chooseHomePoint(_ point: GeoPoint, name: String) {
        let pickingOrigin = selectingOrigin
        cancelPlaceLookup()
        invalidate()
        homeStagesExpanded = false
        search?.cancel()
        searchGeneration = UUID()
        searchFocused = false
        searchExpanded = false
        selectingOrigin = false
        query = ""
        places = []
        if pickingOrigin {
            useCurrentOrigin = false
            origin = point
            originName = name
        } else {
            destination = point
            destinationName = name
            if useCurrentOrigin {
                origin = location.point
                originName = origin == nil ? "" : "Mi ubicación"
            }
        }
        homePanelHeight = .regular
        centerHome(on: point)
        if origin != nil && destination != nil { calculate() }
    }

    private func chooseItinerary(_ itinerary: PlannedTrip) {
        guard let origin, let destination else { return }
        trip = itinerary
        selectedLegIndex = nil
        showTrip(itinerary, origin: origin, destination: destination)
    }

    private var consultation: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                tripMap(height: geometry.size.height)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("--trip-fixture") {
                            Text("Datos de evaluación").font(AppDesign.note)
                        }
                        #endif
                        if trip == nil {
                        AppPanelHeading(title: selectingOrigin ? "¿Desde dónde sales?" : "¿A dónde vas?",
                                        back: { if selectingOrigin { dismiss() } else { selectingOrigin = true } },
                                        centered: false) {
                            EmptyView()
                        }
                        if selectingOrigin, !originName.isEmpty {
                            Text(originName).font(AppDesign.note)
                        }
                        Button {
                            searchExpanded = true
                        } label: {
                            Text(selectingOrigin ? "Buscar origen…" : "Buscar destino…")
                                .font(AppDesign.note)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 14)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .background {
                                    Capsule().fill(Color(uiColor: .tertiarySystemFill)).padding(.vertical, 2)
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .accessibilityIdentifier("trip-search-toggle")
                        .disabled(working)
                        if !selectingOrigin {
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    selectingOrigin = true
                                } label: {
                                    HStack {
                                        Text(originName.isEmpty ? "Cambiar origen" : originName)
                                        Spacer()
                                        Image(systemName: "pencil")
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 44)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14).strokeBorder(.secondary.opacity(0.35))
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Cambiar origen")
                                .accessibilityValue(originName)
                                .disabled(working)
                                if !destinationName.isEmpty { Label(destinationName, systemImage: "mappin.circle") }
                            }
                            .font(AppDesign.note)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                        }
                        if selectingOrigin {
                            let actions = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 14))
                            actions {
                                selectionMap
                                    .buttonStyle(AppActionStyle(fill: AppDesign.header, verticalInset: 0))
                                TripActionButton("Usar ubicación") {
                                    invalidate()
                                    requestingOriginLocation = true
                                    location.request()
                                }
                                .accessibilityLabel("Usar mi ubicación")
                                .buttonStyle(AppActionStyle(verticalInset: 0))
                                .disabled(location.isRequesting || working)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            selectionMap
                                .buttonStyle(AppActionStyle(fill: AppDesign.dock))
                        }
                        stopSuggestions
                        if let error = location.message { Text(error) }
                        if !message.isEmpty { Text(message).accessibilityIdentifier("trip-status") }
                        }
                        if let trip { tripResult(trip) }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                }
                .id("\(trip != nil)-\(selectingOrigin)")
                .transition(reduceMotion ? .identity : .opacity)
                .scrollDismissesKeyboard(.interactively)
                .clipped()
                .accessibilityIdentifier("trip-panel")
                .background { AppDesign.panelSurface() }
                .padding(.top, -AppDesign.panelOverlap)
                if (selectingOrigin ? origin != nil : destination != nil) || working || trip != nil {
                    VStack(spacing: 8) { primaryAction }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .systemBackground))
                        .layoutPriority(1)
                }
            }
            .animation(reduceMotion ? nil : AppDesign.navigationMotion, value: selectingOrigin)
            .animation(reduceMotion ? nil : AppDesign.navigationMotion, value: trip != nil)
        }
        .tint(colorScheme == .dark ? Color(red: 0.65, green: 0.81, blue: 1) : AppDesign.primary)
        .preferredColorScheme(testColorScheme)
        .navigationTitle(trip != nil ? "Tu trayecto" : selectingOrigin ? "Desde dónde sales" : "A dónde vas")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(AppDesign.header, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .principal) { AppBrandTitle() } }
        .tint(.white)

        .sheet(isPresented: $selectingOnMap) { mapSelection.presentationDragIndicator(.visible) }
        .sheet(isPresented: $searchExpanded, onDismiss: {
            searchDelay?.cancel()
            search?.cancel()
            searchGeneration = UUID()
            searchingPlaces = false
            placeSearchFailed = false
            places = []
            query = ""
            searchFocused = false
            searchMessage = ""
        }) {
            searchSheet
                .presentationDetents([.fraction(0.83), .large])
                .presentationCornerRadius(AppDesign.panelRadius)
                .presentationDragIndicator(.visible)
        }
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
            searchExpanded = false
            message = ""
        }
        .onDisappear {
            searchDelay?.cancel()
            searchGeneration = UUID()
            task?.cancel()
            let cancelledPlanner = planner
            Task { await cancelledPlanner?.cancel() }
            search?.cancel()
            location.cancel()
        }
    }

    private func tripResult(_ trip: PlannedTrip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if integratedHome {
                Text("Tu trayecto").font(AppDesign.subtitle).accessibilityAddTraits(.isHeader)
            } else {
                AppPanelHeading(title: "Tu trayecto", back: { invalidate() }) {
                    Button("Cambiar origen o destino", systemImage: "pencil") { invalidate() }
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("Cambiar origen o destino")
                }
            }
            if let error = location.message { Text(error) }
            if !message.isEmpty { Text(message).accessibilityIdentifier("trip-status") }
            let layout = textSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            layout {
                if let duration = estimatedDuration(trip) {
                    Text(WalkingFormat.duration(duration, arrived: false)).font(AppDesign.title)
                        .accessibilityLabel("Duración estimada: " + WalkingFormat.duration(duration, arrived: false))
                }
                Text(primaryService?.name ?? "Ruta recomendada")
                    .font(AppDesign.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($resultFocused)
                    .accessibilityIdentifier("trip-result")
                    .onAppear { resultFocused = true }
            }
            if let direction = primaryService?.direction, !direction.isEmpty {
                Text(direction).font(AppDesign.subtitle)
            }
            let stops = trip.legs.reduce(0) { count, leg in
                guard case let .ride(_, stops) = leg else { return count }
                return count + stops.filter { !$0.suggested }.count
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Información del recorrido").font(AppDesign.subtitle).accessibilityAddTraits(.isHeader)
                if !integratedHome {
                    Label(originName.isEmpty ? "Origen" : "Origen: \(originName)", systemImage: "location.circle")
                }
                if stops > 0 {
                    Label(stops == 1 ? "1 parada" : "\(stops) paradas", systemImage: "bus")
                }
                if !integratedHome {
                    Label(destinationName.isEmpty ? "Destino" : "Destino: \(destinationName)", systemImage: "mappin.circle")
                }
            }
            .font(AppDesign.body)
            .fixedSize(horizontal: false, vertical: true)
            Label("\(trip.transfers) \(trip.transfers == 1 ? "transbordo" : "transbordos") · \(WalkingFormat.distance(trip.walkingMeters)) a pie",
                  systemImage: "figure.walk")
                .font(AppDesign.type(14, relativeTo: .subheadline, weight: .semibold))
                .foregroundStyle(AppDesign.header)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AppDesign.selectionFill, in: RoundedRectangle(cornerRadius: 12))
            if trip.exceedsPreferences {
                AppNotice(text: "Este viaje requiere ampliar la caminata o los transbordos preferidos.", tone: .caution)
            }
            ForEach(Array(trip.legs.enumerated()), id: \.offset) { row in
                tripLegCard(row.element, index: row.offset, total: trip.legs.count)
            }
            Text("El seguimiento utiliza tu ubicación durante el viaje. Los avisos de bajada son opcionales.")
                .font(AppDesign.note)
            Button("Nueva consulta") { resetConsultation() }
                .frame(minHeight: 44)
        }
    }

    private func tripLegCard(_ leg: TripLeg, index: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paso \(index + 1) de \(total)").font(AppDesign.note).foregroundStyle(AppDesign.secondaryInk)
            legSummary(leg)
            if selectedLegIndex == index {
                Label("Etapa seleccionada", systemImage: "checkmark.circle.fill").font(AppDesign.note)
            }
            Button {
                selectedLegIndex = index
                showLeg(leg)
            } label: {
                Text("Mostrar etapa en el mapa")
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(colorScheme == .dark ? Color(red: 0.65, green: 0.81, blue: 1) : AppDesign.primary)
            .accessibilityValue(selectedLegIndex == index ? "Seleccionada" : "")
            .accessibilityIdentifier("trip-show-leg-\(index)")
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(selectedLegIndex == index ? Color.blue.opacity(0.12) : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func tripMap(height: CGFloat) -> some View {
        let fraction: CGFloat
        if textSize.isAccessibilitySize { fraction = 0.26 }
        else if trip != nil { fraction = height < 560 ? 0.38 : 0.43 }
        else if selectingOrigin && origin == nil { fraction = height < 560 ? 0.59 : 0.69 }
        else if !selectingOrigin && destination == nil && height >= 560 { fraction = 0.62 }
        else { fraction = height < 560 ? 0.38 : 0.53 }
        return Map(position: $camera) { mapContents }
            .mapStyle(.standard(elevation: .flat))
            .frame(height: height * fraction + AppDesign.panelOverlap)
            .accessibilityLabel("Mapa de origen, destino e itinerario")
            .accessibilityHint("Las etapas del viaje también están disponibles en la lista.")
            .overlay(alignment: .bottomTrailing) {
                if let trip, let origin, let destination {
                    Button {
                        selectedLegIndex = nil
                        showTrip(trip, origin: origin, destination: destination)
                    } label: {
                        Label("Mostrar viaje completo", systemImage: "arrow.up.left.and.arrow.down.right")
                            .labelStyle(.iconOnly).frame(width: 44, height: 44)
                            .appGlass(in: Circle(), interactive: true)
                    }
                    .accessibilityLabel("Mostrar viaje completo")
                    .accessibilityIdentifier("trip-show-all")
                    .padding(10)
                }
            }
    }

    @ViewBuilder private var primaryAction: some View {
        if trip != nil {
            let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                if !textSize.isAccessibilitySize {
                    Button { invalidate() } label: {
                        Text("Cancelar").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(AppActionStyle(fill: AppDesign.danger))
                }
                Button { travelling = true } label: {
                    Text("Continuar")
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                .tint(AppDesign.primary)
                .accessibilityIdentifier("trip-begin")
                .disabled(working)
                .buttonStyle(AppActionStyle())
            }
        } else if selectingOrigin {
            Button { selectingOrigin = false } label: {
                Text("Continuar").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityIdentifier("trip-continue")
            .disabled(origin == nil || working)
            .buttonStyle(AppActionStyle())
        } else if working {
            HStack {
                ProgressView("Calculando itinerario")
                Spacer()
                TripActionButton("Cancelar") { invalidate() }.frame(minHeight: 44)
            }
        } else {
            Button(action: calculate) {
                Text(paused ? "Continuar búsqueda" : canRetry ? "Reintentar" : "Ver trayecto")
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityIdentifier("trip-calculate")
            .disabled(origin == nil || destination == nil)
            .buttonStyle(AppActionStyle())
            if canSearchAll {
                Button("Buscar en todas las rutas") {
                    requiredRouteID = nil
                    canSearchAll = false
                    planner = nil
                    calculate()
                }
                .frame(minHeight: 44)
            }
        }
    }

    private var testColorScheme: ColorScheme? {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--trip-dark") ? .dark : nil
        #else
        return nil
        #endif
    }

    private func estimatedDuration(_ trip: PlannedTrip) -> TimeInterval? {
        var seconds: TimeInterval = 0
        for leg in trip.legs {
            switch leg {
            case .walk(_, _, let route):
                seconds += route.duration
            case .ride(let service, let stops):
                guard let section = service.section(through: stops), section.count > 1 else { return nil }
                seconds += RouteMeasure(section).length / TripCost.ridingSpeed
            }
        }
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    private var primaryService: TripService? {
        guard let trip else { return nil }
        for leg in trip.legs {
            if case .ride(let service, _) = leg { return service }
        }
        return nil
    }

    @MapContentBuilder private var mapContents: some MapContent {

        if let origin, !integratedHome || !useCurrentOrigin || travelling {
            Marker("Origen", systemImage: "a.circle.fill", coordinate: .init(latitude: origin.latitude, longitude: origin.longitude))
                .tint(.blue)
        }
        if let destination, integratedHome || !selectingOrigin || trip != nil {
            Marker("Destino", systemImage: "b.circle.fill", coordinate: .init(latitude: destination.latitude, longitude: destination.longitude))
                .tint(colorScheme == .dark ? .indigo : .black)
        }
        if let trip {
            if let leg = trip.legs.first(where: {
                if case .ride = $0 { return true }
                return false
            }), case let .ride(service, stops) = leg,
               let path = service.section(through: stops), !path.isEmpty {
                let middle = path[path.count / 2]
                Annotation("Recorrido", coordinate: .init(latitude: middle.latitude, longitude: middle.longitude), anchor: .bottom) {
                    MapRouteBadge(title: estimatedDuration(trip).map { WalkingFormat.duration($0, arrived: false) } ?? "Recorrido",
                                  detail: nil)
                }
                .annotationTitles(.hidden)
            }
            ForEach(Array(trip.legs.enumerated()), id: \.offset) { row in
                switch row.element {
                case .walk(_, _, let route):
                    MapPolyline(coordinates: route.points.map { .init(latitude: $0.latitude, longitude: $0.longitude) })
                        .stroke(.white.opacity(selectedLegIndex == nil || selectedLegIndex == row.offset ? 1 : 0.4), style: StrokeStyle(lineWidth: selectedLegIndex == row.offset ? 10 : 7, dash: [6, 4]))
                    MapPolyline(coordinates: route.points.map { .init(latitude: $0.latitude, longitude: $0.longitude) })
                        .stroke(.blue.opacity(selectedLegIndex == nil || selectedLegIndex == row.offset ? 1 : 0.4), style: StrokeStyle(lineWidth: selectedLegIndex == row.offset ? 7 : 4, dash: [6, 4]))
                case .ride(let service, let stops):
                    if let path = service.section(through: stops) {
                        MapPolyline(coordinates: path.map { .init(latitude: $0.latitude, longitude: $0.longitude) })
                            .stroke(.white.opacity(selectedLegIndex == nil || selectedLegIndex == row.offset ? 1 : 0.4), style: StrokeStyle(lineWidth: selectedLegIndex == row.offset ? 11 : 9, lineCap: .round, lineJoin: .round))
                        MapPolyline(coordinates: path.map { .init(latitude: $0.latitude, longitude: $0.longitude) })
                            .stroke(AppDesign.routeInk.opacity(selectedLegIndex == nil || selectedLegIndex == row.offset ? 1 : 0.4), style: StrokeStyle(lineWidth: selectedLegIndex == row.offset ? 8 : 6, lineCap: .round, lineJoin: .round))
                    } else {
                        ForEach(Array(service.geometry.enumerated()), id: \.offset) { part in
                            MapPolyline(coordinates: part.element.map { .init(latitude: $0.latitude, longitude: $0.longitude) })
                                .stroke(.gray, lineWidth: 3)
                        }
                    }
                    if let stop = stops.first, origin.map({ stop.point.distance(to: $0) > 60 }) ?? true {
                        Annotation(stop.suggested ? "Subida" : "Sube en " + stop.name,
                                   coordinate: .init(latitude: stop.point.latitude, longitude: stop.point.longitude)) {
                            TransitStopDot(symbol: "bus.fill", fill: AppDesign.primary)
                        }
                        .annotationTitles(.hidden)
                    }
                    if let stop = stops.last, destination.map({ stop.point.distance(to: $0) > 60 }) ?? true {
                        Annotation(stop.suggested ? "Bajada" : "Baja en " + stop.name,
                                   coordinate: .init(latitude: stop.point.latitude, longitude: stop.point.longitude)) {
                            TransitStopDot(symbol: "arrow.down", fill: AppDesign.routeInk)
                        }
                        .annotationTitles(.hidden)
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
                .font(AppDesign.note)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } else if (selectingOrigin ? originReference : destinationReference) == nil {
            Text("Elige un punto en el mapa o busca un lugar para ver paradas cercanas.")
                .font(AppDesign.note)
        } else if nearbyStops.isEmpty {
            Text("No hay paradas cercanas a este punto. Puedes elegir otro lugar.")
                .font(AppDesign.note)
        } else {
            Text("Paradas cercanas").font(AppDesign.title).accessibilityAddTraits(.isHeader)
            if selectingOrigin && originReferenceUsesLocation {
                Text("Al elegir una parada, el viaje comenzará desde ella; no se incluye la caminata desde tu ubicación.").font(AppDesign.note)
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
                            Text("A \(WalkingFormat.distance(item.distance)) en línea recta").font(AppDesign.note)
                        }
                        Spacer(minLength: 0)
                        if isSelected(item.feature) {
                            Image(systemName: "checkmark").accessibilityHidden(true)
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
        TripActionButton(selectingOrigin ? "Usar mapa" : "Elegir destino en el mapa") {
            requestingOriginLocation = false
            location.cancel()
            mapPoint = selectingOrigin ? origin : destination
            selectorCamera = mapPoint.map {
                .region(MKCoordinateRegion(center: .init(latitude: $0.latitude, longitude: $0.longitude),
                                           span: .init(latitudeDelta: 0.008, longitudeDelta: 0.010)))
            } ?? camera
            selectingOnMap = true
        }
        .accessibilityLabel(selectingOrigin ? "Elegir origen en el mapa" : "Elegir destino en el mapa")
        .disabled(working)
    }

    private var searchSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                AppPanelHeading(title: selectingOrigin ? "Buscar origen" : "Buscar destino", backLabel: "Cerrar",
                                back: {
                                    searchFocused = false
                                    searchExpanded = false
                                }) { EmptyView() }
                HStack {
                    TextField(selectingOrigin ? "Buscar origen" : "Buscar destino", text: $query)
                        .focused($searchFocused)
                        .accessibilityIdentifier("trip-place-search")
                        .appField(focused: searchFocused, invalid: placeSearchFailed)
                        .submitLabel(.search).onSubmit { findPlaces() }
                    if !query.isEmpty {
                        Button { query = ""; searchFocused = true } label: {
                            Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                        }.accessibilityLabel("Borrar búsqueda")
                    }
                    Button("Buscar") { findPlaces() }
                        .buttonStyle(AppActionStyle())
                        .controlSize(.large)
                        .frame(minHeight: 44)
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && recentStops.isEmpty {
                    Text("Busca una parada o un lugar.").font(AppDesign.note)
                } else if query.trimmingCharacters(in: .whitespacesAndNewlines).count == 1 {
                    Text("Escribe al menos dos caracteres.").font(AppDesign.note)
                }
                if searchingPlaces { ProgressView("Buscando lugares…") }
                if !searchMessage.isEmpty { Text(searchMessage).accessibilityIdentifier("trip-search-status") }
                if placeSearchFailed {
                    Button("Reintentar búsqueda") { findPlaces() }.frame(minHeight: 44)
                }
                List {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !recentStops.isEmpty {
                        Section("Consultas recientes") {
                            ForEach(recentStops) { feature in
                                Button(feature.name) { selectRecentStop(feature) }
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                        }
                    }
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
                        searchExpanded = false
                        camera = .automatic
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.element.name ?? "Lugar").font(AppDesign.subtitle)
                                if let address = row.element.placemark.title, address != row.element.name {
                                    Text(address).font(AppDesign.note)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            AppGlyph(icon: .navigation)
                        }
                        .foregroundStyle(.primary)
                        .padding(10)
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 24))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24)
                                .strokeBorder(.secondary.opacity(0.45))
                                .allowsHitTesting(false)
                        }
                        .contentShape(Rectangle())
                    }
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("trip-place-\(row.offset)")
                    }
                }
                .listStyle(.plain)
            }
            .padding(16)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(.blue)
        .onChange(of: query) { _, text in
            searchDelay?.cancel()
            search?.cancel()
            searchGeneration = UUID()
            searchingPlaces = false
            placeSearchFailed = false
            places = []
            searchMessage = ""
            guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return }
            searchDelay = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: 400_000_000) } catch { return }
                guard !Task.isCancelled, searchExpanded else { return }
                findPlaces(dismissKeyboard: false)
            }
        }
        .onChange(of: searchMessage) { _, text in
            if !text.isEmpty { AccessibilityNotification.Announcement(text).post() }
        }
    }

    private var recentStops: [CatalogFeature] {
        let entries = (try? JSONDecoder().decode([RecentJourney].self, from: recentData)) ?? []
        let ids = entries.map { selectingOrigin ? $0.originID : $0.destinationID }
        var seen = Set<String>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return catalog.features.first { feature in
                guard feature.id == id, feature.kind == .stop, case .point = feature.geometry else { return false }
                return true
            }
        }.prefix(5).map { $0 }
    }

    private func selectRecentStop(_ feature: CatalogFeature) {
        guard case .point(let coordinate) = feature.geometry else { return }
        requestingOriginLocation = false
        location.cancel()
        invalidate()
        if selectingOrigin {
            origin = coordinate.point; originName = feature.name
            originReference = coordinate.point; originReferenceUsesLocation = false
        } else {
            destination = coordinate.point; destinationName = feature.name
            destinationReference = coordinate.point
        }
        searchExpanded = false
        camera = .automatic
    }

    private var mapSelection: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $selectorCamera) {
                    mapContents
                    if let mapPoint {
                        Marker("Punto seleccionado", coordinate: .init(latitude: mapPoint.latitude, longitude: mapPoint.longitude))
                    }
                }
                .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                    guard let coordinate = proxy.convert(tap.location, from: .local) else { return }
                    mapPoint = .init(latitude: coordinate.latitude, longitude: coordinate.longitude)
                })
            }
            .navigationTitle(selectingOrigin ? "Elegir origen" : "Elegir destino")

            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { AppBrandTitle() } }
            .toolbarBackground(AppDesign.header, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: -AppDesign.panelOverlap) {
                VStack(spacing: 8) {
                    TripActionButton("Seleccionar") {
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
                    }
                    .buttonStyle(AppActionStyle())
                    .disabled(mapPoint == nil)
                    .padding(.bottom, -2)

                    VStack(spacing: 4) {
                        Text(selectingOrigin ? "Selecciona el origen" : "Selecciona el destino")
                            .font(AppDesign.subtitle)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 54)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityAddTraits(.isHeader)
                            .overlay(alignment: .leading) {
                                Button {
                                    selectingOnMap = false
                                } label: {
                                    Image(systemName: "arrow.left")
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Cancelar")
                                .padding(.leading, 8)
                            }
                        if let openAppDestination {
                            AppDock(selection: activeAppDestination) { destination in
                                selectingOnMap = false
                                openAppDestination(destination)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.vertical, 6)
                    .background {
                        AppDesign.panelSurface().ignoresSafeArea(edges: .bottom)
                    }
                }
            }
        }
        .tint(.blue)
    }

    @ViewBuilder private func legSummary(_ leg: TripLeg) -> some View {
        switch leg {
        case .walk(_, _, let route):
            Label("Camina \(WalkingFormat.distance(route.length)) · \(WalkingFormat.duration(route.duration, arrived: false))", systemImage: "figure.walk")
        case .ride(let service, let stops):
            VStack(alignment: .leading, spacing: 12) {
                Label(service.name, systemImage: "bus").font(AppDesign.title)
                Text(service.direction ?? "Sentido del recorrido").font(AppDesign.body)
                let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                layout {
                    boardingPoint(
                        stops.first?.suggested == true ? "Punto de subida sugerido" : "Sube en \(stops.first?.name ?? "")",
                        symbol: "arrow.up.circle.fill", color: .blue
                    )
                    boardingPoint(
                        stops.last?.suggested == true ? "Punto de bajada sugerido" : "Baja en \(stops.last?.name ?? "")",
                        symbol: "arrow.down.circle.fill", color: .orange
                    )
                }
                if stops.contains(where: \.suggested) {
                    Text("Confirma con el conductor dónde puedes subir y bajar.").font(AppDesign.note)
                }
                DisclosureGroup("Información del recorrido") {
                    let feature = catalog.features.first { $0.id == (service.catalogRouteID ?? service.id) }
                    let schedules = feature?.publishedValues(for: "schedule") ?? []
                    let fares = feature?.publishedValues(for: "fare") ?? []
                    VStack(alignment: .leading, spacing: 6) {
                        Text(schedules.isEmpty ? "Horario no disponible" : "Horario: " + schedules.joined(separator: "; "))
                        Text(fares.isEmpty ? "Tarifa no disponible" : "Tarifa: " + fares.joined(separator: "; "))
                        if service.section(through: stops) == nil {
                            Text("El seguimiento de esta etapa usa confirmación manual.")
                        }
                    }.font(AppDesign.note)
                }
            }
        }
    }

    private func boardingPoint(_ title: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color).accessibilityHidden(true)
            Text(title).fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func invalidate() {
        task?.cancel()
        alternativeTask?.cancel()
        recommended = nil
        alternative = nil
        showingAlternative = false
        let cancelledPlanner = planner
        Task { await cancelledPlanner?.cancel() }
        planner = nil
        plannedVersion = nil
        trip = nil
        selectedLegIndex = nil
        paused = false
        canRetry = false
        canSearchAll = false
        working = false
        message = ""
    }

    private func resetConsultation() {
        invalidate()
        location.cancel()
        requestingOriginLocation = false
        origin = nil; destination = nil
        originName = ""; destinationName = ""
        homePanelHeight = .regular
        originReference = nil; destinationReference = nil
        originReferenceUsesLocation = false
        selectingOrigin = !integratedHome
        if integratedHome {
            useCurrentOrigin = true
            location.request(continuously: true)
        }
        camera = .region(AppDesign.city)
    }

    private func findPlaces(dismissKeyboard: Bool = true) {
        searchDelay?.cancel()
        search?.cancel()
        search = nil
        searchingPlaces = false
        let token = UUID()
        searchGeneration = token
        let request = MKLocalSearch.Request()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { places = []; searchMessage = "Escribe el nombre de un lugar."; return }
        places = []
        searchMessage = ""
        placeSearchFailed = false
        if dismissKeyboard { searchFocused = false }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--trip-fixture") {
            places = catalog.features.compactMap { feature in
                guard feature.kind == .stop, feature.name.localizedStandardContains(text),
                      case .point(let coordinate) = feature.geometry else { return nil }
                let item = MKMapItem(placemark: .init(coordinate: .init(latitude: coordinate.latitude, longitude: coordinate.longitude)))
                item.name = feature.name
                return item
            }
            searchMessage = places.isEmpty ? "No se encontraron lugares." : ""
            return
        }
        #endif
        request.naturalLanguageQuery = text
        request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 32.53, longitude: -117),
                                            span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3))
        let operation = MKLocalSearch(request: request)
        search = operation
        searchingPlaces = true
        operation.start { response, error in
            guard searchGeneration == token else { return }
            searchingPlaces = false
            search = nil
            placeSearchFailed = error != nil
            places = response?.mapItems ?? []
            searchMessage = error == nil ? (places.isEmpty ? "No se encontraron lugares." : "") : "No se pudo buscar. Intenta de nuevo."
        }
    }

    private func showTrip(_ trip: PlannedTrip, origin: GeoPoint, destination: GeoPoint) {
        var points = [origin, destination]
        for leg in trip.legs {
            switch leg {
            case .walk(_, _, let route):
                points.append(contentsOf: route.points)
            case .ride(let service, let stops):
                points.append(contentsOf: service.section(through: stops) ?? service.geometry.flatMap { $0 })
                points.append(contentsOf: stops.map(\.point))
            }
        }
        showPoints(points)
    }

    private func showLeg(_ leg: TripLeg) {
        switch leg {
        case .walk(_, _, let route): showPoints(route.points)
        case .ride(let service, let stops):
            showPoints((service.section(through: stops) ?? service.geometry.flatMap { $0 }) + stops.map(\.point))
        }
    }

    private func showPoints(_ points: [GeoPoint]) {
        if let position = AppDesign.routeCamera(points, padding: integratedHome ? 1.8 : 1.3) {
            withAnimation(integratedHome ? homeMotion : nil) { camera = position }
        }
    }

    private func calculate() {
        guard !working else { return }
        guard !integratedHome || catalog.readyForDistribution else {
            message = "El catálogo aún no está disponible."
            return
        }
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
                planner = TripPlanner(network: .init(catalog: catalog), provider: AppleTripWalkingProvider(), preferences: .init(requiredRouteID: requiredRouteID), transferCache: transferCache)
            }
            #else
            planner = TripPlanner(network: .init(catalog: catalog), provider: AppleTripWalkingProvider(), preferences: .init(requiredRouteID: requiredRouteID), transferCache: transferCache)
            #endif
            plannedVersion = catalog.version
        }
        guard let activePlanner = planner else { return }
        working = true
        canRetry = false
        message = ""
        task = Task {
            do {
                try Task.checkCancellation()
                let result = try await activePlanner.searchContinuously(from: origin, to: destination)
                guard !Task.isCancelled else { return }
                switch result {
                case .found(let result):
                    trip = result
                    if let recent = result.legs.compactMap({ leg -> String? in
                        guard case .ride(let service, _) = leg else { return nil }
                        return service.catalogRouteID ?? service.id
                    }).first {
                        let previous = (try? JSONDecoder().decode([String].self, from: recentPlannedData)) ?? []
                        recentPlannedData = (try? JSONEncoder().encode(Array(([recent] + previous.filter { $0 != recent }).prefix(12)))) ?? recentPlannedData
                    }
                    paused = false
                    showTrip(result, origin: origin, destination: destination)
                    if integratedHome { findAlternative(to: result, origin: origin, destination: destination) }
                case .paused: paused = true; message = "La búsqueda necesita continuar."
                case .unavailable:
                    trip = nil
                    paused = false
                    canSearchAll = requiredRouteID != nil
                    message = canSearchAll ? "No se encontró un viaje que use esta ruta." : "No se encontró una conexión con los recorridos disponibles."
                }
            } catch TripPlanningError.tryAgainLater {
                guard !Task.isCancelled else { return }
                canRetry = true
                message = "No se pudo completar el cálculo en este momento."
            } catch {
                guard !Task.isCancelled else { return }
                canRetry = true
                message = "No se pudo calcular el viaje. Comprueba la conexión y vuelve a intentar."
            }
            working = false
        }
    }
    private func findAlternative(to result: PlannedTrip, origin: GeoPoint, destination: GeoPoint) {
        let routeIDs = Set(result.legs.compactMap { leg -> String? in
            guard case .ride(let service, _) = leg else { return nil }
            return service.catalogRouteID ?? service.id
        })
        guard !routeIDs.isEmpty else { return }
        recommended = result
        alternativeTask?.cancel()
        alternativeTask = Task {
            let network = TripNetwork(catalog: catalog)
            let services = network.services.filter { !routeIDs.contains($0.catalogRouteID ?? $0.id) }
            let options = TripPlanner(network: .init(version: network.version, services: services),
                                      provider: AppleTripWalkingProvider(), transferCache: transferCache)
            if case .found(let candidate)? = try? await options.searchContinuously(
                from: origin, to: destination, timeout: .seconds(35)
            ), !Task.isCancelled, candidate.legs.contains(where: { if case .ride = $0 { return true }; return false }) {
                alternative = candidate
            }
        }
    }

}
