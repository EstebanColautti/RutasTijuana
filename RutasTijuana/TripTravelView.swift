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
    private let locations = AppleNavigationLocationProvider()
    private let activity = NavigationActivityController()
    private var timer: Task<Void, Never>?
    private var path: [GeoPoint] = []
    private var traveled = 0.0
    private var previous: WalkingFix?
    private var nearSince: Date?
    private var nearCount = 0
    private var alerted = false
    private var started = Date()
    private var movement = Date()
    private var movementPoint: GeoPoint?
    private let session = UUID().uuidString
    private var active = true

    init(trip: PlannedTrip) {
        self.trip = trip
        locations.transportMode()
        locations.onFix = { [weak self] fix in self?.receive(fix) }
        locations.onDenied = { [weak self] in
            self?.pause("La ubicación está desactivada. Puedes confirmar la bajada manualmente.")
        }
        locations.onError = { [weak self] _ in self?.message = "No se pudo actualizar tu ubicación." }
    }
    var leg: TripLeg? { trip.legs.indices.contains(index) ? trip.legs[index] : nil }
    var finished: Bool { index >= trip.legs.count }

    func advance() {
        stopTracking()
        index += 1
        message = ""
        remaining = nil
        paused = false
        alerted = false
        nearCount = 0
        nearSince = nil
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
            traveled = 0
        }
        let scenario = JourneyScenario(schemaVersion: 1, name: service.name, coverageRadius: 1000,
            stops: service.stops, places: [], circular: service.circular, routeGeometry: service.geometry)
        path = scenario.mappedSection(for: stops) ?? []
        guard path.count > 1 else {
            message = "Confirma tu bajada en la parada indicada. No hay un trazado continuo para seguir este tramo."
            return
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
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
        }
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
        guard active, aboard, !paused, fix.isReliable(at: Date()),
              case .ride(_, let stops)? = leg, let stop = stops.last else { return }
        if let previous {
            let interval = fix.timestamp.timeIntervalSince(previous.timestamp)
            guard interval > 0, fix.point.distance(to: previous.point) <= interval * 55 + fix.accuracy + previous.accuracy else { return }
        }
        let advance = previous.map { max(100, fix.timestamp.timeIntervalSince($0.timestamp) * 55 + fix.accuracy) } ?? 500
        let scale = cos(fix.point.latitude * .pi / 180)
        var cumulative = 0.0
        var nearest = Double.infinity
        var chosen: (distance: Double, along: Double)?
        for (a, b) in zip(path, path.dropFirst()) {
            let x = (b.longitude - a.longitude) * scale * 111195
            let y = (b.latitude - a.latitude) * 111195
            let px = (fix.point.longitude - a.longitude) * scale * 111195
            let py = (fix.point.latitude - a.latitude) * 111195
            let squared = x*x + y*y
            let t = squared > 0 ? min(1, max(0, (px*x + py*y) / squared)) : 0
            let length = a.distance(to: b)
            let distance = hypot(px - t*x, py - t*y)
            let along = cumulative + t*length
            nearest = min(nearest, distance)
            if along >= traveled - 30 && along <= traveled + advance && distance < (chosen?.distance ?? .infinity) {
                chosen = (distance, along)
            }
            cumulative += length
        }
        previous = fix
        point = fix.point
        if movementPoint == nil || movementPoint!.distance(to: fix.point) >= max(10, fix.accuracy) {
            movementPoint = fix.point
            movement = Date()
        }
        guard nearest <= max(60, fix.accuracy * 2), let chosen,
              chosen.distance <= max(60, nearest + 10) else {
            message = "Tu ubicación no coincide con el recorrido. Revisa la parada de bajada."
            return
        }
        traveled = max(traveled, chosen.along)
        remaining = max(0, cumulative - traveled)
        message = "Baja en " + stop.name
        if (remaining ?? .infinity) <= 350 {
            nearCount += 1
            if nearSince == nil { nearSince = fix.timestamp }
            if nearCount >= 3, fix.timestamp.timeIntervalSince(nearSince!) >= 5, !alerted {
                alerted = true
                let content = UNMutableNotificationContent()
                content.title = "Se acerca tu parada"
                content.body = "Prepárate para bajar. Abre la app para ver el viaje."
                content.sound = .default
                UNUserNotificationCenter.current().add(.init(identifier: session + "-\(index)", content: content, trigger: nil)) { _ in }
            }
        } else { nearSince = nil; nearCount = 0 }
        if traveled >= cumulative - 40 && fix.point.distance(to: stop.point) > 150 {
            message = "Parece que pasaste tu parada. Confirma dónde bajaste para volver a planear."
        }
        activity.update(destination: stop.name, instruction: message, meters: Int(remaining ?? 0),
                        status: "En transporte", locationCurrent: true)
    }
}

struct TripTravelView: View {
    @StateObject private var model: TripTravelController
    @Environment(\.dismiss) private var dismiss
    @State private var walking: WalkingDestination?
    init(trip: PlannedTrip) { _model = StateObject(wrappedValue: TripTravelController(trip: trip)) }

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
                            Label("Camina al siguiente punto", systemImage: "figure.walk").font(.title2)
                            Text(WalkingFormat.distance(route.length))
                            Map {
                                MapPolyline(coordinates: route.points.map { .init(latitude: $0.latitude, longitude: $0.longitude) }).stroke(.blue, lineWidth: 5)
                            }.frame(height: 220)
                            Button("Iniciar caminata") {
                                walking = .init(id: "leg-\(model.index)", name: "Siguiente punto del viaje", point: target)
                            }.buttonStyle(.borderedProminent)
                            Button("Ya llegué") { model.advance() }
                        case .ride(let service, let stops):
                            Label(service.name, systemImage: "bus").font(.title2)
                            Text(service.direction ?? "Sigue el sentido indicado en el recorrido")
                            Text("Sube en \(stops.first?.name ?? "")")
                            Text("Baja en \(stops.last?.name ?? "")")
                            if let meters = model.remaining { Text("Faltan \(WalkingFormat.distance(meters)) para la bajada") }
                            if model.aboard {
                                if model.paused { Button("Continuar seguimiento") { model.resume() } }
                                Button("Ya bajé") { model.advance() }.buttonStyle(.borderedProminent)
                            } else {
                                Button("Ya subí") { model.board() }.buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    if !model.message.isEmpty { Text(model.message) }
                }.padding()
            }
            .navigationTitle("Tu viaje")
            .toolbar { Button("Finalizar") { model.finish(); dismiss() } }
            .fullScreenCover(item: $walking) { destination in
                WalkingNavigationView(destination: destination, onArrival: {
                    walking = nil
                    model.advance()
                })
            }
        }
        .interactiveDismissDisabled()
    }
}
