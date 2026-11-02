import SwiftUI
import MapKit

struct WalkingNavigationView: View {
    @StateObject private var model: WalkingNavigationCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition = .automatic
    @State private var lastHeading = 0.0
    @State private var follow = true
    @StateObject private var connectivity = ConnectivityMonitor()
    @State private var showingSteps = false
    @State private var confirmEnd = false
    init(destination: WalkingDestination) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--walking-fixture") {
            _model = StateObject(wrappedValue: WalkingNavigationCoordinator(destination: destination, provider: FixtureWalkingRouteProvider(), locations: FixtureNavigationLocationProvider(destination: destination)))
        } else {
            _model = StateObject(wrappedValue: WalkingNavigationCoordinator(destination: destination))
        }
        #else
        _model = StateObject(wrappedValue: WalkingNavigationCoordinator(destination: destination))
        #endif
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
            VStack(spacing: 0) {
                Map(position: $camera) {
                    if let route = model.route {
                        MapPolyline(coordinates: route.points.map(\.walkingCoordinate)).stroke(.blue, lineWidth: 6)
                    }
                    Annotation(model.destination.name, coordinate: model.destination.point.walkingCoordinate) {
                        Image(systemName: "bus.fill").padding(10).background(.blue, in: Circle()).foregroundStyle(.white)
                    }
                    if let fix = model.fix {
                        if model.isLocationCurrent {
                            MapCircle(center: fix.point.walkingCoordinate, radius: max(5, fix.accuracy))
                                .foregroundStyle(.blue.opacity(0.15))
                        }
                        Annotation("Tu ubicación", coordinate: fix.point.walkingCoordinate) {
                            Circle().fill(model.isLocationCurrent ? .blue : .gray).frame(width: 18, height: 18)
                                .overlay(Circle().stroke(.white, lineWidth: 3))
                                .accessibilityLabel(model.isLocationCurrent ? "Ubicación actual" : "Última ubicación · Sin actualizar")
                        }
                    }
                }
                .onChange(of: camera.positionedByUser) { _, value in if value { follow = false } }
                .onChange(of: model.fix?.timestamp) { _, _ in recenter() }
                .onChange(of: model.phase) { _, phase in
                    if phase == .preview { follow = false; camera = .automatic }
                    if phase == .navigating { follow = true; recenter() }
                }
                .overlay(alignment: .bottomTrailing) {
                    Button("Recentrar", systemImage: "location.fill") { follow = true; recenter() }
                        .frame(minHeight: 44).padding(.horizontal).background(.regularMaterial, in: Capsule()).padding()
                }
                ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.destination.name).font(.headline)
                    if model.phase == .navigating {
                        Text(model.instruction).font(.title2.bold()).accessibilityIdentifier("walking-instruction")
                        Text("En \(WalkingFormat.distance(model.progress.stepRemaining))")
                        if model.progress.stepRemaining <= WalkingPolicy.maneuverDistance { Text("Próxima indicación").font(.caption) }
                    }
                    if model.route != nil {
                        Text("\(WalkingFormat.distance(model.progress.remaining)) · \(WalkingFormat.duration(model.secondsRemaining, arrived: model.phase == .arrived))")
                        Button("Ver pasos") { showingSteps = true }
                    }
                    if !model.message.isEmpty { Text(model.message).font(.subheadline).accessibilityIdentifier("walking-status") }
                    if model.phase == .preview { Button("Iniciar guía") { model.start() }.buttonStyle(.borderedProminent).disabled(model.status.waitingToStart || model.status.calculating) }
                    if model.phase == .paused { Button("Reanudar") { model.resume() } }
                    if model.phase == .arrived || model.phase == .ended {
                        Button("Volver al viaje") { dismiss() }
                    } else {
                        if model.offersRetry {
                            Button("Reintentar") { model.retry() }.buttonStyle(.borderedProminent)
                                .disabled(!model.retryAvailable || !model.status.connected)
                            if !model.retryAvailable { Text("Espera un momento antes de reintentar.").font(.caption) }
                        }
                        Button("Abrir en Apple Maps") { openMaps() }.font(.footnote)
                    }
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: min(360, geometry.size.height * 0.5))
                .dynamicTypeSize(...DynamicTypeSize.accessibility5)
            }
            }
            .navigationTitle("Ir a la parada").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Finalizar") { confirmEnd = true } } }
            .confirmationDialog("¿Finalizar la guía?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("Finalizar", role: .destructive) { model.finish(); dismiss() }
            }
            .sheet(isPresented: $showingSteps) {
                NavigationStack {
                    List(Array((model.route?.steps ?? []).enumerated()), id: \.offset) { index, step in
                        Label {
                            VStack(alignment: .leading) {
                                Text(step.instruction)
                                if model.phase == .navigating {
                                    Text(index < model.progress.stepIndex ? "Completado" : index == model.progress.stepIndex ? "Paso actual" : "Siguiente")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: index < model.progress.stepIndex ? "checkmark.circle" : index == model.progress.stepIndex ? "location.circle.fill" : "circle")
                        }.fontWeight(index == model.progress.stepIndex ? .semibold : .regular)
                    }
                        .navigationTitle("Indicaciones")
                        .toolbar { Button("Cerrar") { showingSteps = false } }
                }
            }
        }
        .interactiveDismissDisabled()
        .task { model.connectivityChanged(connectivity.isConnected); model.prepare() }
        .onChange(of: connectivity.isConnected) { _, value in model.connectivityChanged(value) }
        .onDisappear { model.finish() }
    }
    private func recenter() {
        guard follow, let fix = model.fix else { return }
        if fix.speed >= 0.7 && fix.course >= 0 { lastHeading = fix.course }
        let heading = lastHeading
        camera = .camera(MapCamera(centerCoordinate: fix.point.walkingCoordinate, distance: 500, heading: heading, pitch: 0))
    }
    private func openMaps() {
        model.finish()
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: model.destination.point.walkingCoordinate))
        destination.name = model.destination.name
        destination.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
        dismiss()
    }
}
