import SwiftUI
import MapKit

struct WalkingNavigationView: View {
    @StateObject private var model: WalkingNavigationCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition = .automatic
    @State private var follow = true
    @State private var showingSteps = false
    @State private var confirmEnd = false
    init(destination: WalkingDestination) {
        _model = StateObject(wrappedValue: WalkingNavigationCoordinator(destination: destination))
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Map(position: $camera) {
                    if let route = model.route {
                        MapPolyline(coordinates: route.points.map(\.walkingCoordinate)).stroke(.blue, lineWidth: 6)
                    }
                    Annotation(model.destination.name, coordinate: model.destination.point.walkingCoordinate) {
                        Image(systemName: "bus.fill").padding(10).background(.blue, in: Circle()).foregroundStyle(.white)
                    }
                    if let fix = model.fix {
                        Annotation("Tu ubicación", coordinate: fix.point.walkingCoordinate) {
                            Circle().fill(.blue).frame(width: 18, height: 18).overlay(Circle().stroke(.white, lineWidth: 3))
                        }
                    }
                }
                .onChange(of: camera.positionedByUser) { _, value in if value { follow = false } }
                .onChange(of: model.fix?.timestamp) { _, _ in recenter() }
                .overlay(alignment: .bottomTrailing) {
                    Button("Recentrar", systemImage: "location.fill") { follow = true; recenter() }
                        .padding().background(.regularMaterial, in: Capsule()).padding()
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.destination.name).font(.headline)
                    if model.phase == .navigating {
                        Text(model.instruction).font(.title2.bold()).accessibilityIdentifier("walking-instruction")
                        Text("En \(Int(model.progress.stepRemaining)) m")
                        if model.progress.stepRemaining <= WalkingPolicy.maneuverDistance { Text("Próxima indicación").font(.caption) }
                    }
                    if model.route != nil {
                        Text("\(Int(model.progress.remaining)) m · \(max(1, Int(ceil(model.secondsRemaining / 60)))) min aprox.")
                        Button("Ver pasos") { showingSteps = true }
                    }
                    if !model.message.isEmpty { Text(model.message).font(.subheadline).accessibilityIdentifier("walking-status") }
                    if model.phase == .preview { Button("Iniciar guía") { model.start() }.buttonStyle(.borderedProminent) }
                    if model.phase == .paused { Button("Reanudar") { model.resume() } }
                    if model.phase == .arrived || model.phase == .ended {
                        Button("Volver al viaje") { dismiss() }
                    } else {
                        Button("Reintentar") { model.retry() }
                        Button("Abrir en Apple Maps") { openMaps() }.font(.footnote)
                    }
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Ir a la parada").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Finalizar") { confirmEnd = true } } }
            .confirmationDialog("¿Finalizar la guía?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("Finalizar", role: .destructive) { model.finish(); dismiss() }
            }
            .sheet(isPresented: $showingSteps) {
                NavigationStack {
                    List(Array((model.route?.steps ?? []).enumerated()), id: \.offset) { _, step in Text(step.instruction) }
                        .navigationTitle("Indicaciones")
                        .toolbar { Button("Cerrar") { showingSteps = false } }
                }
            }
        }
        .interactiveDismissDisabled()
        .task { model.prepare() }
        .onDisappear { model.finish() }
    }
    private func recenter() {
        guard follow, let fix = model.fix else { return }
        let heading = fix.speed >= 0.7 && fix.course >= 0 ? fix.course : 0
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
