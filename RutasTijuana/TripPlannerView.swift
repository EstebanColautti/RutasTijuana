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

/// Ícono de etapa: naranja para caminar y azul de marca para el transporte, como las cápsulas del trayecto.
struct TripLegIcon: View {
    let leg: TripLeg
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: leg.isWalk ? "figure.walk" : "bus.fill")
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(leg.isWalk ? AppDesign.header : .white)
            .frame(width: size, height: size)
            .background(leg.isWalk ? AppNoticeTone.caution.accent : AppDesign.primary, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Tira del itinerario: 🚶 4 min › 🚌 R1 › 🚶 2 min.
struct TripLegChips: View {
    let legs: [TripLeg]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row
            ScrollView(.horizontal, showsIndicators: false) { row }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(legs.map { leg -> String in
            switch leg {
            case .walk(_, _, let route): return "Caminar " + WalkingFormat.minutes(route.duration)
            case .ride(let service, _): return "Transporte " + service.name
            }
        }.joined(separator: ", "))
    }

    private var row: some View {
        HStack(spacing: 6) {
            ForEach(Array(legs.enumerated()), id: \.offset) { item in
                if item.offset > 0 {
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(AppDesign.secondaryInk)
                }
                chip(item.element)
            }
        }
    }

    private func chip(_ leg: TripLeg) -> some View {
        let walking = leg.isWalk
        let text: String = switch leg {
        case .walk(_, _, let route): WalkingFormat.minutes(route.duration)
        case .ride(let service, _): service.shortName
        }
        return Label(text, systemImage: walking ? "figure.walk" : "bus.fill")
            .font(AppDesign.subtitle)
            .lineLimit(1)
            .foregroundStyle(walking ? AppDesign.header : .white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(walking ? AppNoticeTone.caution.accent : AppDesign.primary, in: Capsule())
    }
}

struct TripActionButton: View {
    let title: String
    let fullWidth: Bool
    let action: () -> Void

    init(_ title: String, fullWidth: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.fullWidth = fullWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppDesign.subtitle)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 44, maxWidth: fullWidth ? .infinity : nil, minHeight: 44)
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

struct TripPlannerView: View {

    let catalog: RouteCatalog
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
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var location = LocationService()
    @State private var origin: GeoPoint?
    @State private var destination: GeoPoint?
    @State private var originName = ""
    @State private var destinationName = ""
    @State private var query = ""
    @State private var searchExpanded = false
    @State private var searchMessage = ""
    @State private var searchingPlaces = false
    @State private var placeSearchFailed = false
    @State private var searchDelay: Task<Void, Never>?
    @State private var selectingOrigin = false
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
    @State private var camera: MapCameraPosition = .region(AppDesign.city)
    @State private var requiredRouteID: String?
    @State private var canSearchAll = false

    init(catalog: RouteCatalog) {
        self.catalog = catalog
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--capture-walking-stage") {
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
        }
        #endif
    }

    var body: some View {
        homeMap
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
                        VStack(spacing: 0) {
                            ScrollView {
                                homeDetails.frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16).padding(.bottom, 6)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                            // Como en el trayecto, la acción principal queda fija y siempre visible sobre el dock.
                            if trip != nil {
                                startTripButton
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .transition(homeTransition)
                            }
                        }
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
            if arguments.contains("--ui-testing") { return }
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Etapas").font(AppDesign.subtitle).foregroundStyle(AppDesign.secondaryInk)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(Array(trip.legs.enumerated()), id: \.offset) { row in
                            tripLegCard(row.element, index: row.offset, total: trip.legs.count)
                        }
                    }
                    .padding(.top, 4)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(trip.duration.map { WalkingFormat.minutes($0) } ?? "Itinerario")
                    .font(AppDesign.type(24, relativeTo: .title, weight: .semibold))
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("trip-result")
                if let seconds = trip.duration {
                    Text("Llegada " + WalkingFormat.arrival(after: seconds))
                        .font(AppDesign.explanation).foregroundStyle(AppDesign.secondaryInk)
                }
            }
            TripLegChips(legs: trip.legs)
            Text(trip.summary).font(AppDesign.note).foregroundStyle(AppDesign.secondaryInk)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
        .animation(homeMotion, value: trip.duration)
    }

    private var startTripButton: some View {
        TripActionButton("Iniciar viaje", fullWidth: true) {
            searchFocused = false
            alternativeTask?.cancel()
            selectedLegIndex = nil
            travelling = true
        }
        .buttonStyle(AppActionStyle())
        .accessibilityIdentifier("trip-begin")
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

    private func tripLegCard(_ leg: TripLeg, index: Int, total: Int) -> some View {
        Button {
            selectedLegIndex = selectedLegIndex == index ? nil : index
            if selectedLegIndex != nil { showLeg(leg) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                TripLegIcon(leg: leg)
                VStack(alignment: .leading, spacing: 2) {
                    switch leg {
                    case .walk(_, _, let route):
                        Text("Camina \(WalkingFormat.distance(route.length))").font(AppDesign.subtitle)
                        Text(index == total - 1 ? "Hasta tu destino" : "Hasta la parada").font(AppDesign.note).foregroundStyle(AppDesign.secondaryInk)
                    case .ride(let service, let stops):
                        Text(service.name).font(AppDesign.subtitle).fixedSize(horizontal: false, vertical: true)
                        Text(stops.first?.suggested == true ? "Subida y bajada sugeridas" : "\(stops.first?.name ?? "") → \(stops.last?.name ?? "")")
                            .font(AppDesign.note).foregroundStyle(AppDesign.secondaryInk)
                    }
                }
                Spacer(minLength: 0)
                if let seconds = leg.duration {
                    Text(WalkingFormat.minutes(seconds)).font(AppDesign.subtitle).foregroundStyle(AppDesign.secondaryInk)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard(selected: selectedLegIndex == index)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(AppPressStyle())
        .accessibilityHint("Muestra la etapa en el mapa")
        .accessibilityAddTraits(selectedLegIndex == index ? .isSelected : [])
        .accessibilityIdentifier("trip-show-leg-\(index)")
    }

    private func estimatedDuration(_ trip: PlannedTrip) -> TimeInterval? { trip.duration }

    @MapContentBuilder private var mapContents: some MapContent {

        if let origin, !useCurrentOrigin || travelling {
            Marker("Origen", systemImage: "a.circle.fill", coordinate: .init(latitude: origin.latitude, longitude: origin.longitude))
                .tint(.blue)
        }
        if let destination {
            Marker("Destino", systemImage: "b.circle.fill", coordinate: .init(latitude: destination.latitude, longitude: destination.longitude))
                .tint(colorScheme == .dark ? .indigo : .black)
        }
        if let trip {
            // Durante el viaje el tiempo ya está en el panel; el rótulo taparía paradas.
            if !travelling, let leg = trip.legs.first(where: {
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
        if let position = AppDesign.routeCamera(points, padding: 1.8) {
            withAnimation(homeMotion) { camera = position }
        }
    }

    private func calculate() {
        guard !working else { return }
        guard catalog.readyForDistribution else {
            message = "El catálogo aún no está disponible."
            return
        }
        guard let origin, let destination, origin != destination else {
            message = "Elige un destino distinto del origen."
            return
        }
        if planner == nil || (!paused && plannedVersion != catalog.version) {
            if plannedVersion != catalog.version { trip = nil }
            planner = TripPlanner(network: .init(catalog: catalog), provider: AppleTripWalkingProvider(), preferences: .init(requiredRouteID: requiredRouteID), transferCache: transferCache)
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
                    paused = false
                    showTrip(result, origin: origin, destination: destination)
                    findAlternative(to: result, origin: origin, destination: destination)
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
