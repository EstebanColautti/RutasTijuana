import SwiftUI
import MapKit

struct WalkingNavigationView: View {
    @StateObject private var model: WalkingNavigationCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .accessibilityLabel("Mapa de la guía a pie")
                    .accessibilityHint("Consulta la indicación actual y la lista de pasos debajo del mapa.")
                    .onChange(of: camera.positionedByUser) { _, value in if value { follow = false } }
                    .onChange(of: model.fix?.timestamp) { _, _ in recenter() }
                    .onChange(of: model.phase) { _, phase in
                        if phase == .preview { follow = false; camera = .automatic }
                        if phase == .navigating { follow = true; recenter() }
                    }
                    .overlay(alignment: .topTrailing) {
                        Button {
                            follow = true
                            recenter()
                        } label: {
                            Label("Recentrar", systemImage: "location.fill")
                                .labelStyle(.iconOnly)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(.regularMaterial, in: Circle())
                        }
                        .accessibilityLabel("Recentrar")
                        .padding()
                    }
                    .frame(height: geometry.size.height * (textSize.isAccessibilitySize ? 0.26 : 0.5))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(model.destination.name).font(.headline)
                            if model.phase == .navigating {
                                Text(model.instruction).font(.title2.bold()).accessibilityIdentifier("walking-instruction")
                                Text("En \(WalkingFormat.distance(model.progress.stepRemaining))")
                                if model.progress.stepRemaining <= WalkingPolicy.maneuverDistance { Text("Próxima indicación").font(.caption) }
                            }
                            if model.route != nil {
                                Text("\(WalkingFormat.distance(model.phase == .arrived ? 0 : model.progress.remaining)) · \(WalkingFormat.duration(model.secondsRemaining, arrived: model.phase == .arrived))")
                                Button("Ver pasos") { showingSteps = true }.frame(minHeight: 44)
                            }
                            if !model.message.isEmpty { Text(model.message).font(.subheadline).accessibilityIdentifier("walking-status") }
                            if model.status.offersStart(phase: model.phase) { Button("Iniciar guía") { model.start() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.status.waitingToStart || model.status.calculating) }
                            if model.phase == .paused { Button("Reanudar") { model.resume() }.buttonStyle(.borderedProminent).controlSize(.large) }
                            if model.phase == .arrived || model.phase == .ended {
                                Button("Volver al viaje") { dismiss() }.buttonStyle(.borderedProminent).controlSize(.large)
                            } else {
                                if model.offersRetry {
                                    Button("Reintentar") { model.retry() }.buttonStyle(.borderedProminent).controlSize(.large)
                                        .disabled(!model.retryAvailable || !model.status.connected)
                                    if !model.retryAvailable { Text("Espera un momento antes de reintentar.").font(.caption) }
                                }
                                Button("Abrir en Apple Maps") { openMaps() }.font(.footnote).frame(minHeight: 44)
                            }
                        }.padding().frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .navigationTitle("Ir a la parada").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { confirmEnd = true } label: {
                        Text("Finalizar")
                            .foregroundStyle(colorScheme == .dark ? .white : .primary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
            .confirmationDialog("¿Finalizar la guía?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("Finalizar", role: .destructive) { model.finish(); dismiss() }
            }
            .sheet(isPresented: $showingSteps) {
                NavigationStack {
                    List(Array((model.route?.steps ?? []).enumerated()), id: \.offset) { index, step in
                        Label {
                            VStack(alignment: .leading) {
                                Text(step.instruction).fixedSize(horizontal: false, vertical: true)
                                if model.phase == .navigating {
                                    Text(index < model.progress.stepIndex ? "Completado" : index == model.progress.stepIndex ? "Paso actual" : "Siguiente")
                                        .font(.caption).foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.vertical, 4)
                                }
                            }
                        } icon: {
                            Image(systemName: index < model.progress.stepIndex ? "checkmark.circle" : index == model.progress.stepIndex ? "location.circle.fill" : "circle")
                        }
                        .padding(.vertical, 8)
                        .fontWeight(index == model.progress.stepIndex ? .semibold : .regular)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(step.instruction)
                        .accessibilityValue(model.phase == .navigating
                            ? (index < model.progress.stepIndex ? "Completado" : index == model.progress.stepIndex ? "Paso actual" : "Siguiente")
                            : "")
                    }
                        .navigationTitle("Indicaciones")
                        .toolbar { Button("Cerrar") { showingSteps = false } }
                }
            }
        }
        .preferredColorScheme(testColorScheme)
        .interactiveDismissDisabled()
        .task { model.connectivityChanged(connectivity.isConnected); model.prepare() }
        .onChange(of: connectivity.isConnected) { _, value in model.connectivityChanged(value) }
        .onDisappear { model.finish() }
    }
    private var testColorScheme: ColorScheme? {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--walking-dark") ? .dark : nil
        #else
        return nil
        #endif
    }
    private func recenter() {
        guard follow, let fix = model.fix else { return }
        if fix.speed >= 0.7 && fix.course >= 0 { lastHeading = fix.course }
        let heading = reduceMotion ? 0 : lastHeading
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
