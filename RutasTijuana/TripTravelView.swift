import SwiftUI
import MapKit
import UserNotifications
import Combine
import Accessibility

@MainActor final class TripTravelController: ObservableObject {
    let trip: PlannedTrip
    @Published private(set) var index = 0
    @Published private(set) var aboard = false
    @Published private(set) var message = ""
    @Published private(set) var remaining: Double?
    @Published private(set) var paused = false
    @Published private(set) var point: GeoPoint?
    @Published private(set) var locationCurrent = false
    @Published private(set) var missedStop = false
    private var locations: any NavigationLocationProvider
    private let fixture: Bool
    private let activity = NavigationActivityController()
    private var timer: Task<Void, Never>?
    private var path: [GeoPoint] = []
    private var engine: TransitProgressEngine?
    private var previous: WalkingFix?
    private var started = Date()
    private var movement = Date()
    private var movementPoint: GeoPoint?
    private let session = UUID().uuidString
    private var active = true
    private var requestedNotifications = false

    init(trip: PlannedTrip) {
        self.trip = trip
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        fixture = arguments.contains("--capture-catalog")
        if fixture {
            locations = FixtureNavigationLocationProvider(destination: .init(id: "fixture", name: "Parada de ejemplo",
                point: .init(latitude: 32.51, longitude: -117)))
        } else {
            let native = AppleNavigationLocationProvider()
            native.transportMode()
            locations = native
        }
        #else
        fixture = false
        let native = AppleNavigationLocationProvider()
        native.transportMode()
        locations = native
        #endif
        connectLocations()
    }

    private func connectLocations() {
        locations.onFix = { [weak self] fix in self?.receive(fix) }
        locations.onDenied = { [weak self] in
            self?.pause("La ubicación está desactivada. Puedes confirmar la bajada manualmente.")
        }
        locations.onError = { [weak self] _ in self?.message = "No se pudo actualizar tu ubicación." }
    }
    var leg: TripLeg? { trip.legs.indices.contains(index) ? trip.legs[index] : nil }
    var finished: Bool { index >= trip.legs.count }
    var ridePath: [GeoPoint] { path }
    var locationIsCurrent: Bool { locationCurrent && previous?.isReliable(at: Date()) == true }

    func previousLeg(from expected: Int) {
        guard active, expected == index, index > 0 else { return }
        stopTracking()
        index -= 1
        engine = nil
        remaining = nil
        paused = false
        missedStop = false
        message = ""
    }

    func advance(from expected: Int) {
        guard active, expected == index, index < trip.legs.count else { return }
        stopTracking()
        index += 1
        message = ""
        remaining = nil
        paused = false
        engine = nil
        missedStop = false
    }
    func board(from expected: Int) {
        guard active, expected == index, (!aboard || paused), case .ride(let service, let stops)? = leg else { return }
        let resuming = aboard
        aboard = true
        paused = false
        started = Date()
        movement = Date()
        if !resuming {
            previous = nil
            engine = nil
        }
        path = service.section(through: stops) ?? []
        guard path.count > 1 else {
            message = "Confirma tu bajada en la parada indicada. No hay un trazado continuo para seguir este tramo."
            return
        }
        if engine == nil, let destination = stops.last?.point {
            engine = TransitProgressEngine(path: path, destination: destination)
        }
        #if DEBUG
        if fixture, let boarding = stops.first?.point {
            locations.stop()
            locations = FixtureNavigationLocationProvider(destination: .init(id: "ride", name: "Parada de ejemplo",
                point: .init(latitude: boarding.latitude + 0.001, longitude: boarding.longitude)))
            connectLocations()
        }
        #endif
        locations.start()
        locations.enableBackground()
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                if Date().timeIntervalSince(started) >= 7200 || Date().timeIntervalSince(movement) >= 900 {
                    pause("Seguimiento pausado. Confirma que quieres continuar.")
                    return
                }
                if previous.map({ !$0.isReliable(at: Date()) }) ?? true {
                    locationCurrent = false
                    message = "Ubicación sin actualizar. Puedes confirmar tu bajada manualmente."
                    if case .ride(_, let stops)? = leg, let stop = stops.last {
                        activity.update(destination: stop.name, instruction: message, meters: Int(remaining ?? 0),
                                        status: "Sin ubicación actual", locationCurrent: false)
                    }
                }
            }
        }
        if !fixture && !requestedNotifications {
            requestedNotifications = true
            Task { [weak self] in
                guard let self, active else { return }
                let center = UNUserNotificationCenter.current()
                let settings = await center.notificationSettings()
                guard active else { return }
                if settings.authorizationStatus == .notDetermined {
                    _ = try? await center.requestAuthorization(options: [.alert, .sound])
                }
            }
        }
    }
    func resume() {
        guard aboard && paused else { return }
        board(from: index)
    }
    func finish() {
        active = false
        stopTracking()
        let identifiers = trip.legs.indices.map { session + "-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }
    private func pause(_ text: String) {
        locations.stop()
        timer?.cancel()
        timer = nil
        activity.end(message: "Viaje pausado")
        paused = true
        locationCurrent = false
        message = text
    }
    private func stopTracking() {
        locations.stop()
        timer?.cancel()
        timer = nil
        aboard = false
        locationCurrent = false
        let identifier = session + "-\(index)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        activity.end(message: "Etapa finalizada")
    }
    private func receive(_ fix: WalkingFix) {
        guard active, aboard, !paused,
              case .ride(_, let stops)? = leg, let stop = stops.last else { return }
        guard Date().timeIntervalSince(started) < 7200, Date().timeIntervalSince(movement) < 900 else {
            pause("Seguimiento pausado. Confirma que quieres continuar.")
            return
        }
        guard let progress = engine?.update(fix, now: Date()) else {
            locationCurrent = false
            message = "Ubicación sin actualizar. Puedes confirmar tu bajada manualmente."
            activity.update(destination: stop.name, instruction: message, meters: Int(remaining ?? 0),
                            status: "Ubicación imprecisa", locationCurrent: false)
            return
        }
        previous = fix
        point = fix.point
        locationCurrent = true
        if movementPoint == nil || movementPoint!.distance(to: fix.point) >= max(10, fix.accuracy) {
            movementPoint = fix.point
            movement = Date()
        }
        remaining = progress.remaining
        missedStop = progress.passedStop
        defer {
            activity.update(destination: stop.name, instruction: message, meters: Int(progress.remaining),
                            status: progress.offRoute ? "Revisa el recorrido" : "En transporte", locationCurrent: true)
        }
        if progress.passedStop {
            message = stop.suggested ? "Parece que pasaste el punto de bajada sugerido. Puedes volver a planear desde tu ubicación." : "Parece que pasaste tu parada. Puedes volver a planear desde tu ubicación."
            return
        }
        guard !progress.offRoute else {
            message = stop.suggested ? "Tu ubicación no coincide con el recorrido. Revisa el punto de bajada sugerido." : "Tu ubicación no coincide con el recorrido. Revisa la parada de bajada."
            return
        }
        message = stop.suggested
            ? (progress.remaining <= 350 ? "Se acerca el punto de bajada sugerido. Confirma con el conductor." : "Continúa hasta el punto de bajada sugerido.")
            : (progress.remaining <= 350 ? "Se acerca tu parada. Baja en " : "Baja en ") + stop.name
        if progress.notifyAlighting {
            let content = UNMutableNotificationContent()
            content.title = stop.suggested ? "Se acerca tu bajada" : "Se acerca tu parada"
            content.body = "Prepárate para bajar. Abre la app para ver el viaje."
            content.sound = .default
            UNUserNotificationCenter.current().add(.init(identifier: session + "-\(index)", content: content, trigger: nil)) { _ in }
        }
    }
}

struct TripTravelView: View {
    private let onReplan: ((GeoPoint) -> Void)?
    private let destinationName: String
    private let inlineFinish: () -> Void
    private let onStageChange: ((Int) -> Void)?
    @StateObject private var model: TripTravelController
    @Environment(\.homeTripActive) private var homeTripActive
    @State private var confirmFinish = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stopNames: [String: String] = [:]
    @AccessibilityFocusState private var stageFocused: Bool
    init(trip: PlannedTrip, destinationName: String = "Destino", onReplan: ((GeoPoint) -> Void)? = nil,
         inlineFinish: @escaping () -> Void, onStageChange: ((Int) -> Void)? = nil) {
        self.inlineFinish = inlineFinish
        self.onStageChange = onStageChange
        self.onReplan = onReplan
        self.destinationName = destinationName
        _model = StateObject(wrappedValue: TripTravelController(trip: trip))
    }

    private var currentStatus: String {
        if model.finished { return "Viaje finalizado" }
        switch model.leg {
        case .walk: return "Caminata"
        case .ride: return model.paused ? "Seguimiento pausado" : (model.aboard ? "En transporte" : "Esperando para subir")
        case nil: return "Trayecto en curso"
        }
    }

    // MARK: Presentación por etapas

    /// «Sube en Parada X» o, si la parada es sugerida, «Sube cerca de Calle Y».
    private func stopPhrase(_ verb: String, _ stop: TransitStop?) -> String {
        guard let stop else { return verb + " en la parada" }
        if !stop.suggested { return verb + " en " + stop.name }
        return stopNames[stop.id].map { verb + " cerca de " + $0 } ?? verb + " en la parada sugerida"
    }

    private func resolveStopNames() async {
        guard case .ride(_, let stops)? = model.leg else { return }
        for stop in [stops.first, stops.last].compactMap({ $0 }) where stop.suggested && stopNames[stop.id] == nil {
            let place = try? await CLGeocoder().reverseGeocodeLocation(
                CLLocation(latitude: stop.point.latitude, longitude: stop.point.longitude)).first
            if let street = place?.thoroughfare ?? place?.subLocality { stopNames[stop.id] = street }
        }
    }

    /// Tira de etapas: lila las hechas, el color de su tipo la actual y gris las pendientes.
    private var stageStrip: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.trip.legs.enumerated()), id: \.offset) { item in
                let done = model.finished || item.offset < model.index
                let current = !model.finished && item.offset == model.index
                Capsule()
                    .fill(done ? AppDesign.accent : current ? (item.element.isWalk ? AppNoticeTone.caution.accent : AppDesign.primary)
                                                         : Color(uiColor: .tertiarySystemFill))
                    .frame(height: 5)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : AppDesign.navigationMotion, value: model.index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progreso por etapas del viaje")
        .accessibilityValue(model.finished ? "Completado" : "Etapa \(model.index + 1) de \(model.trip.legs.count)")
        .accessibilityIdentifier("trip-stage-strip")
    }

    private var header: some View {
        HStack(spacing: 12) {
            stageStrip
            Button("Finalizar viaje", systemImage: "xmark") { confirmFinish = true }
                .buttonStyle(AppIconButtonStyle())
                .foregroundStyle(AppDesign.secondaryInk)
                .accessibilityIdentifier("trip-finish")
                .confirmationDialog("¿Finalizar el viaje?", isPresented: $confirmFinish, titleVisibility: .visible) {
                    Button("Finalizar", role: .destructive) { closeTrip() }
                    Button("Cancelar", role: .cancel) {}
                }
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(AppDesign.title).contentTransition(.numericText())
            Text(label).font(AppDesign.note).foregroundStyle(AppDesign.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }

    private func hero(_ title: String, _ subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AppDesign.type(21, relativeTo: .title2, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            if let subtitle { Text(subtitle).font(AppDesign.explanation).foregroundStyle(AppDesign.secondaryInk) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityFocused($stageFocused)
    }

    private var nextLegIsRide: Bool {
        model.trip.legs.indices.contains(model.index + 1) && !model.trip.legs[model.index + 1].isWalk
    }

    @ViewBuilder private func stageContent(_ leg: TripLeg) -> some View {
        switch leg {
        case .walk(_, _, let route):
            let steps = route.steps.map { WalkingFormat.spanish($0.instruction) }
            stageBadge(symbol: "figure.walk", fill: AppNoticeTone.caution.accent, ink: AppDesign.header)
            hero(steps.first ?? (nextLegIsRide ? "Camina a la parada" : "Camina a tu destino"),
                 nextLegIsRide ? "Hacia la parada donde subes" : "Hacia " + destinationName)
            HStack(spacing: 24) {
                metric(WalkingFormat.distance(route.length), "a pie")
                metric(WalkingFormat.minutes(route.duration), nextLegIsRide ? "a la parada" : "al destino")
            }
            if steps.count > 1 {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.dropFirst().enumerated()), id: \.offset) { step in
                        if step.offset > 0 { Divider().padding(.leading, 40) }
                        Label {
                            Text(step.element).font(AppDesign.body).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: WalkingFormat.turnSymbol(step.element))
                                .foregroundStyle(AppDesign.primary).frame(width: 24)
                        }
                        .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard()
            }
        case .ride(let service, let stops):
            stageBadge(symbol: "bus.fill", fill: AppDesign.primary, ink: .white)
            if model.aboard {
                hero(stopPhrase("Baja", stops.last), service.name)
                HStack(spacing: 24) {
                    if let meters = model.remaining ?? leg.distance { metric(WalkingFormat.distance(meters), "para bajar") }
                    if let meters = model.remaining ?? leg.distance { metric(WalkingFormat.minutes(meters / TripCost.ridingSpeed), "aprox.") }
                }
            } else {
                hero(stopPhrase("Sube", stops.first), service.name)
                HStack(spacing: 24) {
                    if let seconds = leg.duration { metric(WalkingFormat.minutes(seconds), "en transporte") }
                    if let meters = leg.distance { metric(WalkingFormat.distance(meters), "de recorrido") }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Label(stops.first?.suggested == true ? "Punto de subida sugerido" : "Sube en \(stops.first?.name ?? "")", systemImage: "bus.fill")
                    .font(model.aboard ? AppDesign.body : AppDesign.title)
                    .foregroundStyle(model.aboard ? AppDesign.secondaryInk : .primary)
                Label(stops.last?.suggested == true ? "Punto de bajada sugerido" : "Baja en \(stops.last?.name ?? "")", systemImage: "mappin.circle.fill")
                    .font(model.aboard ? AppDesign.title : AppDesign.body)
                    .foregroundStyle(model.aboard ? .primary : AppDesign.secondaryInk)
                if let direction = service.direction, !WalkingFormat.sameText(direction, service.name) {
                    Label(direction, systemImage: "arrow.triangle.turn.up.right.diamond")
                        .font(AppDesign.body).foregroundStyle(AppDesign.secondaryInk)
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .appCard()
            .animation(reduceMotion ? nil : AppDesign.selectionMotion, value: model.aboard)
            if stops.contains(where: \.suggested) {
                Text("Confirma con el conductor dónde subir y bajar.").font(AppDesign.note).foregroundStyle(AppDesign.secondaryInk)
            }
        }
    }

    @AppStorage("favorite-routes") private var favoriteData = Data()

    private var finishedContent: some View {
        let rides = model.trip.legs.compactMap { leg -> TripService? in
            if case .ride(let service, _) = leg { return service } else { return nil }
        }
        let walked = model.trip.legs.filter(\.isWalk).compactMap(\.distance).reduce(0, +)
        let route = rides.first?.catalogRouteID
        let saved = route.map { FavoriteRoutes.decode(favoriteData).contains($0) } ?? true
        return VStack(alignment: .leading, spacing: 12) {
            Label("Llegaste al destino", systemImage: "checkmark.circle.fill")
                .font(AppDesign.type(21, relativeTo: .title2, weight: .semibold))
                .foregroundStyle(AppDesign.primary)
                .accessibilityAddTraits(.isHeader).accessibilityFocused($stageFocused)
            Text(destinationName).font(AppDesign.explanation).foregroundStyle(AppDesign.secondaryInk)
            HStack(spacing: 24) {
                if let seconds = model.trip.duration { metric(WalkingFormat.minutes(seconds), "de viaje") }
                if walked >= 1 { metric(WalkingFormat.distance(walked), "a pie") }
            }
            if !rides.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(rides.enumerated()), id: \.offset) { ride in
                        Label(ride.element.name, systemImage: "bus.fill").font(AppDesign.body)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .appCard()
            }
            if let route, !saved {
                Button("Guardar ruta en favoritos", systemImage: "star") {
                    favoriteData = FavoriteRoutes.toggle(route, in: favoriteData)
                }
                .font(AppDesign.subtitle)
                .frame(minHeight: 44)
                .accessibilityIdentifier("trip-save-favorite")
            }
        }
    }

    @ViewBuilder private func stageAction(stage: Int) -> some View {
        Group {
            if model.finished {
                TripActionButton("Terminar", fullWidth: true) { closeTrip() }
                    .accessibilityIdentifier("trip-close")
            } else if let leg = model.leg {
                switch leg {
                case .walk:
                    TripActionButton(nextLegIsRide ? "Ya llegué a la parada" : "Ya llegué", fullWidth: true) { model.advance(from: stage) }
                        .accessibilityIdentifier("trip-walk-arrived")
                case .ride:
                    if model.aboard && model.paused {
                        TripActionButton("Continuar seguimiento", fullWidth: true) { model.resume() }
                    } else if model.aboard {
                        TripActionButton("Ya bajé", fullWidth: true) { model.advance(from: stage) }
                            .accessibilityIdentifier("trip-alight")
                    } else {
                        TripActionButton("Ya subí", fullWidth: true) { model.board(from: stage) }
                            .accessibilityIdentifier("trip-board")
                    }
                }
            }
        }
        .buttonStyle(AppActionStyle())
        .frame(maxWidth: .infinity)
    }

    private func closeTrip() {
        model.finish()
        inlineFinish()
    }

    private func stageBadge(symbol: String, fill: Color, ink: Color) -> some View {
        Label(currentStatus, systemImage: symbol)
            .font(AppDesign.subtitle)
            .foregroundStyle(ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(fill, in: Capsule())
            .contentTransition(reduceMotion ? .identity : .opacity)
    }

    /// Avisos que requieren atención; el avance normal ya lo cuentan el título y las métricas.
    private var attentionMessage: String? {
        guard !model.message.isEmpty else { return nil }
        if model.paused || model.missedStop || model.message.hasPrefix("Se acerca") || model.message.hasPrefix("No ")
            || model.message.contains("ubicación") || model.message.hasPrefix("Confirma") { return model.message }
        return nil
    }

    private func travelPanel(stage: Int) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if model.finished {
                        finishedContent
                    } else if let leg = model.leg {
                        stageContent(leg)
                    }
                    if let attention = attentionMessage {
                        AppNotice(text: attention, tone: .caution).accessibilityIdentifier("trip-travel-status")
                    }
                    if model.missedStop, model.point != nil, let onReplan {
                        TripActionButton("Recalcular desde aquí") {
                            guard model.missedStop, model.locationIsCurrent, let point = model.point else { return }
                            model.finish()
                            onReplan(point)
                        }.frame(minHeight: 44).disabled(!model.locationIsCurrent)
                    }
                    if !model.finished, model.index > 0 {
                        Button("Volver a la etapa anterior", systemImage: "arrow.uturn.backward") { model.previousLeg(from: stage) }
                            .font(AppDesign.subtitle).foregroundStyle(AppDesign.secondaryInk)
                            .frame(minHeight: 44)
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(model.index)
            .transition(reduceMotion ? .identity : .opacity)
            .clipped()
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 18)
                }
            }
            stageAction(stage: stage)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .task(id: model.index) { await resolveStopNames() }
    }

    var body: some View {
        let stage = model.index
        return travelPanel(stage: stage)
            .animation(reduceMotion ? nil : AppDesign.navigationMotion, value: model.index)
            .animation(reduceMotion ? nil : AppDesign.selectionMotion, value: currentStatus)
            .onChange(of: model.index, initial: true) { _, index in onStageChange?(index) }
            .onDisappear {
                if homeTripActive?.wrappedValue != true { model.finish() }
            }
        .tint(colorScheme == .dark ? Color(red: 0.65, green: 0.81, blue: 1) : AppDesign.primary)
        .onChange(of: model.message) { _, text in
            if !text.isEmpty { AccessibilityNotification.Announcement(text).post() }
        }
        .onChange(of: model.index) { _, _ in stageFocused = true }
        .interactiveDismissDisabled()
    }
}
