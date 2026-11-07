import SwiftUI
import MapKit
import UserNotifications
import Combine

@MainActor final class TripTravelController: ObservableObject {
    let trip: PlannedTrip
    @Published private(set) var index = 0
    @Published private(set) var aboard = false
    @Published private(set) var message = ""
    @Published private(set) var remaining: Double?
    @Published private(set) var paused = false
    @Published private(set) var point: GeoPoint?
    @Published private(set) var missedStop = false
    private let locations: any NavigationLocationProvider
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
        locations.onFix = { [weak self] fix in self?.receive(fix) }
        locations.onDenied = { [weak self] in
            self?.pause("La ubicación está desactivada. Puedes confirmar la bajada manualmente.")
        }
        locations.onError = { [weak self] _ in self?.message = "No se pudo actualizar tu ubicación." }
    }
    var leg: TripLeg? { trip.legs.indices.contains(index) ? trip.legs[index] : nil }
    var finished: Bool { index >= trip.legs.count }
    var ridePath: [GeoPoint] { path }

    func previousLeg() {
        guard index > 0 else { return }
        stopTracking()
        index -= 1
        engine = nil
        remaining = nil
        paused = false
        missedStop = false
        message = ""
    }

    func advance() {
        stopTracking()
        index += 1
        message = ""
        remaining = nil
        paused = false
        engine = nil
        missedStop = false
    }
    func board() {
        guard active, case .ride(let service, let stops)? = leg else { return }
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
                    message = "Ubicación sin actualizar. Puedes confirmar tu bajada manualmente."
                }
            }
        }
        if !fixture { Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
        } }
    }
    func resume() { board() }
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
        message = text
    }
    private func stopTracking() {
        locations.stop()
        timer?.cancel()
        timer = nil
        aboard = false
        activity.end(message: "Etapa finalizada")
    }
    private func receive(_ fix: WalkingFix) {
        guard active, aboard, !paused,
              case .ride(_, let stops)? = leg, let stop = stops.last else { return }
        guard let progress = engine?.update(fix, now: Date()) else {
            message = "Ubicación sin actualizar. Puedes confirmar tu bajada manualmente."
            return
        }
        previous = fix
        point = fix.point
        if movementPoint == nil || movementPoint!.distance(to: fix.point) >= max(10, fix.accuracy) {
            movementPoint = fix.point
            movement = Date()
        }
        remaining = progress.remaining
        if progress.passedStop {
            missedStop = true
            message = "Parece que pasaste tu parada. Puedes volver a planear desde tu ubicación."
            return
        }
        guard !progress.offRoute else {
            message = "Tu ubicación no coincide con el recorrido. Revisa la parada de bajada."
            return
        }
        message = (progress.remaining <= 350 ? "Se acerca tu parada. Baja en " : "Baja en ") + stop.name
        if progress.notifyAlighting {
                let content = UNMutableNotificationContent()
                content.title = "Se acerca tu parada"
                content.body = "Prepárate para bajar. Abre la app para ver el viaje."
                content.sound = .default
                UNUserNotificationCenter.current().add(.init(identifier: session + "-\(index)", content: content, trigger: nil)) { _ in }
        }
        activity.update(destination: stop.name, instruction: message, meters: Int(remaining ?? 0),
                        status: "En transporte", locationCurrent: true)
    }
}

struct TripTravelView: View {
    private let onReplan: ((GeoPoint) -> Void)?
    private let destinationName: String
    @StateObject private var model: TripTravelController
    @Environment(\.dismiss) private var dismiss
    @State private var walking: WalkingDestination?
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.finished {
                        Label("Llegaste al destino", systemImage: "checkmark.circle")
                        Button("Terminar") { model.finish(); dismiss() }
                    } else if let leg = model.leg {
                        switch leg {
                        case .walk(_, let target, let route):
                            Label("Camina hasta " + walkingTarget, systemImage: "figure.walk").font(.title2)
                            Text(WalkingFormat.distance(route.length))
                            Map {
                                MapPolyline(coordinates: route.points.map { .init(latitude: $0.latitude, longitude: $0.longitude) }).stroke(.blue, lineWidth: 5)
                            }.frame(height: 220)
                            Button("Iniciar caminata") {
                                walking = .init(id: "leg-\(model.index)", name: walkingTarget, point: target)
                            }.buttonStyle(.borderedProminent).accessibilityIdentifier("trip-walk")
                            Button("Ya llegué") { model.advance() }.accessibilityIdentifier("trip-walk-arrived").frame(minHeight: 44)
                        case .ride(let service, let stops):
                            Label(service.name, systemImage: "bus").font(.title2)
                            Text(service.direction ?? "Sigue el sentido indicado en el recorrido")
                            Text("Sube en \(stops.first?.name ?? "")")
                            Text("Baja en \(stops.last?.name ?? "")")
                            if model.ridePath.count > 1 {
                                Map {
                                    MapPolyline(coordinates: model.ridePath.map { .init(latitude: $0.latitude, longitude: $0.longitude) })
                                        .stroke(.indigo, lineWidth: 5)
                                    if let point = model.point {
                                        Marker("Tu ubicación", coordinate: .init(latitude: point.latitude, longitude: point.longitude))
                                    }
                                }.frame(height: 220)
                                .accessibilityLabel("Recorrido hasta la parada de bajada")
                            }
                            if let meters = model.remaining { Text("Faltan \(WalkingFormat.distance(meters)) para la bajada") }
                            if model.aboard {
                                if model.paused { Button("Continuar seguimiento") { model.resume() } }
                                Button("Ya bajé") { model.advance() }.accessibilityIdentifier("trip-alight").buttonStyle(.borderedProminent)
                            } else {
                                Button("Ya subí") { model.board() }.accessibilityIdentifier("trip-board").buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    if !model.finished, model.index > 0 {
                        Button("Volver a la etapa anterior") { model.previousLeg() }.frame(minHeight: 44)
                    }
                    if !model.message.isEmpty { Text(model.message) }
                    if model.missedStop, let point = model.point, let onReplan {
                        Button("Recalcular desde aquí") {
                            model.finish()
                            onReplan(point)
                            dismiss()
                        }.frame(minHeight: 44)
                    }
                }.padding()
            }
            .navigationTitle("Tu viaje")
            .toolbar { Button("Finalizar") { model.finish(); dismiss() } }
            .fullScreenCover(item: $walking) { destination in
                WalkingNavigationView(destination: destination, preparedRoute: walkingRoute, onArrival: {
                    walking = nil
                    model.advance()
                })
            }
        }
        .interactiveDismissDisabled()
    }
}
