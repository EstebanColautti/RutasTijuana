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
        fixture = ProcessInfo.processInfo.arguments.contains("--trip-fixture")
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
            message = "Parece que pasaste tu parada. Puedes volver a planear desde tu ubicación."
            return
        }
        guard !progress.offRoute else {
            message = "Tu ubicación no coincide con el recorrido. Revisa la parada de bajada."
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
    @StateObject private var model: TripTravelController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var walking: WalkingDestination?
    @AccessibilityFocusState private var stageFocused: Bool
    init(trip: PlannedTrip, destinationName: String = "Destino", onReplan: ((GeoPoint) -> Void)? = nil) {
        self.onReplan = onReplan
        self.destinationName = destinationName
        _model = StateObject(wrappedValue: TripTravelController(trip: trip))
    }

    private var walkingRoute: WalkingRoute? {
        if case .walk(_, _, let route)? = model.leg { return route }
        return nil
    }

    private var walkingTarget: String {
        let next = model.index + 1
        if model.trip.legs.indices.contains(next), case .ride(_, let stops) = model.trip.legs[next] {
            return stops.first?.name ?? "Parada de subida"
        }
        return destinationName
    }

    var body: some View {
        let stage = model.index
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--trip-fixture") {
                        Text("Datos de evaluación").font(.footnote)
                    }
                    #endif
                    if model.finished {
                        Label("Llegaste al destino", systemImage: "checkmark.circle")
                            .accessibilityAddTraits(.isHeader).accessibilityFocused($stageFocused)
                            .onAppear { stageFocused = true }
                        TripActionButton("Terminar") { model.finish(); dismiss() }
                    } else if let leg = model.leg {
                        switch leg {
                        case .walk(_, let target, let route):
                            Label("Camina hasta " + walkingTarget, systemImage: "figure.walk").font(.title2)
                                .accessibilityAddTraits(.isHeader).accessibilityFocused($stageFocused)
                                .onAppear { stageFocused = true }
                            Text(WalkingFormat.distance(route.length))
                            Map(interactionModes: []) {
                                MapPolyline(coordinates: route.points.map { .init(latitude: $0.latitude, longitude: $0.longitude) }).stroke(.blue, lineWidth: 5)
                            }.frame(height: 220)
                            TripActionButton("Iniciar caminata") {
                                walking = .init(id: "leg-\(model.index)", name: walkingTarget, point: target)
                            }.buttonStyle(.borderedProminent).tint(Color(red: 0.02, green: 0.29, blue: 0.57)).accessibilityIdentifier("trip-walk")
                            TripActionButton("Ya llegué") { model.advance(from: stage) }.accessibilityIdentifier("trip-walk-arrived").frame(minHeight: 44)
                        case .ride(let service, let stops):
                            Label(service.name, systemImage: "bus").font(.title2)
                                .accessibilityAddTraits(.isHeader).accessibilityFocused($stageFocused)
                                .onAppear { stageFocused = true }
                            Text(service.direction ?? "Sigue el sentido indicado en el recorrido")
                            Text("Sube en \(stops.first?.name ?? "")")
                            Text("Baja en \(stops.last?.name ?? "")")
                            if model.ridePath.count > 1 {
                                Map(interactionModes: []) {
                                    MapPolyline(coordinates: model.ridePath.map { .init(latitude: $0.latitude, longitude: $0.longitude) })
                                        .stroke(.indigo, lineWidth: 5)
                                    if let point = model.point {
                                        Marker(model.locationIsCurrent ? "Tu ubicación" : "Última ubicación",
                                               coordinate: .init(latitude: point.latitude, longitude: point.longitude))
                                            .tint(model.locationIsCurrent ? .blue : .gray)
                                    }
                                }.frame(height: 220)
                                .accessibilityLabel("Recorrido hasta la parada de bajada")
                            }
                            if let meters = model.remaining { Text("Faltan \(WalkingFormat.distance(meters)) para la bajada") }
                            if model.aboard {
                                if model.paused { TripActionButton("Continuar seguimiento") { model.resume() } }
                                TripActionButton("Ya bajé") { model.advance(from: stage) }.accessibilityIdentifier("trip-alight").buttonStyle(.borderedProminent).tint(Color(red: 0.02, green: 0.29, blue: 0.57))
                            } else {
                                TripActionButton("Ya subí") { model.board(from: stage) }.accessibilityIdentifier("trip-board").buttonStyle(.borderedProminent).tint(Color(red: 0.02, green: 0.29, blue: 0.57))
                            }
                        }
                    }
                    if !model.finished, model.index > 0 {
                        TripActionButton("Volver a la etapa anterior") { model.previousLeg(from: stage) }.frame(minHeight: 44)
                    }
                    if !model.message.isEmpty { Text(model.message).accessibilityIdentifier("trip-travel-status") }
                    if model.missedStop, model.point != nil, let onReplan {
                        TripActionButton("Recalcular desde aquí") {
                            guard model.missedStop, model.locationIsCurrent, let point = model.point else { return }
                            model.finish()
                            onReplan(point)
                            dismiss()
                        }.frame(minHeight: 44).disabled(!model.locationIsCurrent)
                    }
                }.padding()
            }
            .id(model.index)
            .navigationTitle("Tu viaje")
            .toolbar { TripActionButton("Finalizar") { model.finish(); dismiss() }.accessibilityIdentifier("trip-finish") }
            .fullScreenCover(item: $walking) { destination in
                WalkingNavigationView(destination: destination, preparedRoute: walkingRoute, onArrival: {
                    walking = nil
                    model.advance(from: stage)
                })
            }
        }
        .tint(colorScheme == .dark ? Color(red: 0.65, green: 0.81, blue: 1) : Color(red: 0.02, green: 0.29, blue: 0.57))
        .onChange(of: model.message) { _, text in
            if !text.isEmpty { AccessibilityNotification.Announcement(text).post() }
        }
        .onChange(of: model.index) { _, _ in stageFocused = true }
        .interactiveDismissDisabled()
    }
}
