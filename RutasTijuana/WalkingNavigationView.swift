import SwiftUI
import MapKit

struct WalkingNavigationView: View {
    private let onArrival: (() -> Void)?
    @StateObject private var model: WalkingNavigationCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openAppDestination) private var openAppDestination
    @State private var pendingDestination: AppDestination?
    @State private var confirmingDestination = false
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: MapCameraPosition = .automatic
    @State private var lastHeading = 0.0
    @State private var follow = true
    @StateObject private var connectivity = ConnectivityMonitor()
    @State private var showingSteps = false
    @State private var confirmEnd = false
    init(destination: WalkingDestination, preparedRoute: WalkingRoute? = nil, onArrival: (() -> Void)? = nil) {
        self.onArrival = onArrival
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--walking-live-directions") {
            _model = StateObject(wrappedValue: WalkingNavigationCoordinator(destination: destination, provider: AppleWalkingRouteProvider(), locations: FixtureNavigationLocationProvider(destination: destination)))
        } else if ProcessInfo.processInfo.arguments.contains("--walking-fixture") || ProcessInfo.processInfo.arguments.contains("--trip-fixture") {
            _model = StateObject(wrappedValue: WalkingNavigationCoordinator(destination: destination, provider: FixtureWalkingRouteProvider(), locations: FixtureNavigationLocationProvider(destination: destination), preparedRoute: preparedRoute))
        } else {
            _model = StateObject(wrappedValue: WalkingNavigationCoordinator(destination: destination, preparedRoute: preparedRoute))
        }
        #else
        _model = StateObject(wrappedValue: WalkingNavigationCoordinator(destination: destination, preparedRoute: preparedRoute))
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
                            Image(systemName: model.destination.purpose == .destination ? "flag.fill" : "bus.fill").padding(10).background(.blue, in: Circle()).foregroundStyle(.white)
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
                    #if DEBUG
                    .overlay(alignment: .topLeading) {
                        if ProcessInfo.processInfo.arguments.contains("--walking-live-directions") {
                            Text("Ubicación simulada · Camino calculado por Apple")
                                .font(AppDesign.note).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(8)
                        }
                    }
                    #endif
                    .accessibilityHint("Consulta la indicación actual y la lista de pasos debajo del mapa.")
                    .onChange(of: camera.positionedByUser) { _, value in if value { follow = false } }
                    .onChange(of: model.fix?.timestamp) { _, _ in recenter() }
                    .onChange(of: model.phase) { _, phase in
                        if phase == .preview { follow = false; camera = .automatic }
                        if phase == .navigating { follow = true; recenter() }
                        if phase == .arrived, let onArrival { onArrival(); dismiss() }
                    }
                    .overlay(alignment: .topTrailing) {
                        Button {
                            follow = true
                            recenter(animated: true)
                        } label: {
                            Label("Recentrar", systemImage: "location.fill")
                                .labelStyle(.iconOnly)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .frame(minWidth: 44, minHeight: 44)
                                .appGlass(in: Circle(), interactive: true)
                        }
                        .accessibilityLabel("Recentrar")
                        .padding()
                    }
                    .frame(height: geometry.size.height * (textSize.isAccessibilitySize ? 0.26 : showingSteps ? 0.56 : 0.60))
                    ScrollView {
                        if showingSteps {
                            walkingSteps
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(model.destination.name).font(AppDesign.title)
                                if model.phase == .navigating {
                                    Text(model.instruction).font(AppDesign.type(17, relativeTo: .title2, weight: .semibold)).accessibilityIdentifier("walking-instruction")
                                    Text("En \(WalkingFormat.distance(model.progress.stepRemaining))")
                                    if model.progress.stepRemaining <= WalkingPolicy.maneuverDistance { Text("Próxima indicación").font(AppDesign.note) }
                                }
                                if model.route != nil {
                                    Text("\(WalkingFormat.distance(model.phase == .arrived ? 0 : model.progress.remaining)) · \(WalkingFormat.duration(model.secondsRemaining, arrived: model.phase == .arrived))")
                                    if !model.status.offersStart(phase: model.phase) {
                                        Button("Ver pasos") { showingSteps = true }.frame(minHeight: 44)
                                    }
                                }
                                if !model.message.isEmpty {
                                    AppNotice(text: model.message, tone: noticeTone)
                                        .accessibilityIdentifier("walking-status")
                                }
                                if model.phase == .paused { Button("Reanudar") { model.resume() }.buttonStyle(AppActionStyle()).controlSize(.large) }
                                if model.phase == .arrived || model.phase == .ended {
                                    Button("Volver al viaje") { dismiss() }.buttonStyle(AppActionStyle()).controlSize(.large)
                                } else {
                                    if model.offersRetry {
                                        Button("Reintentar") { model.retry() }.buttonStyle(AppActionStyle()).controlSize(.large)
                                            .disabled(!model.retryAvailable || !model.status.connected)
                                        if !model.retryAvailable { Text("Espera un momento antes de reintentar.").font(AppDesign.note) }
                                    }
                                    Button("Abrir en Apple Maps") { openMaps() }.font(AppDesign.note).frame(minHeight: 44)
                                }
                            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .id(showingSteps)
                    .frame(maxHeight: .infinity)
                    .background(Color(uiColor: .secondarySystemBackground), in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 4) {
                    if !showingSteps && model.status.offersStart(phase: model.phase) {
                        let actions = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 10))
                        actions {
                            Button { showingSteps = true } label: {
                                Text("Ver pasos")
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .tint(.primary)
                            Button { model.start() } label: {
                                Text("Iniciar guía")
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(AppActionStyle())
                            .disabled(model.status.waitingToStart || model.status.calculating)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                    if openAppDestination != nil {
                        AppDock(selection: nil) { destination in
                            pendingDestination = destination
                            confirmingDestination = true
                        }
                    }
                }
                .background(Color(uiColor: .systemBackground))
            }
            .confirmationDialog("¿Salir de la guía?", isPresented: $confirmingDestination, titleVisibility: .visible) {
                Button("Salir", role: .destructive) {
                    guard let pendingDestination else { return }
                    model.finish()
                    dismiss()
                    openAppDestination?(pendingDestination)
                }
                Button("Cancelar", role: .cancel) { pendingDestination = nil }
            }
            .navigationTitle(showingSteps ? "Indicaciones" : model.destination.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppDesign.header, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Button {
                        if showingSteps { showingSteps = false } else { confirmEnd = true }
                    } label: {
                        Text(showingSteps ? "Cerrar" : "Finalizar")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier(showingSteps ? "walking-close-steps" : "walking-finish")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .background(Color(uiColor: .systemBackground))
            }
            .confirmationDialog("¿Finalizar la guía?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("Finalizar", role: .destructive) { model.finish(); dismiss() }
            }

        }
        .preferredColorScheme(testColorScheme)
        .interactiveDismissDisabled()
        .task { model.connectivityChanged(connectivity.isConnected); model.prepare() }
        .onChange(of: connectivity.isConnected) { _, value in model.connectivityChanged(value) }
        .onDisappear { model.finish() }
    }
    private var noticeTone: AppNoticeTone {
        if model.phase == .arrived { return .success }
        if !model.status.connected || model.status.error != nil ||
            model.status.endpointGap > 25 || model.status.location == .imprecise { return .caution }
        return .information
    }

    private var walkingSteps: some View {
        VStack(spacing: 10) {
            ForEach(Array((model.route?.steps ?? []).enumerated()), id: \.offset) { index, step in
                let isCurrent = index == model.progress.stepIndex
                let completed = index < model.progress.stepIndex
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: completed ? "checkmark.circle" : isCurrent ? "location.circle.fill" : "circle")
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(step.instruction)
                            .font(AppDesign.body)
                            .fixedSize(horizontal: false, vertical: true)
                        if model.phase == .navigating {
                            Text(completed ? "Completado" : isCurrent ? "Paso actual" : "Siguiente")
                                .font(AppDesign.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fontWeight(isCurrent ? .semibold : .regular)
                .padding(12)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.secondary.opacity(0.45), lineWidth: isCurrent ? 2 : 1)
                        .allowsHitTesting(false)
                }
            }
        }.padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var testColorScheme: ColorScheme? {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--walking-dark") ? .dark : nil
        #else
        return nil
        #endif
    }
    private func recenter(animated: Bool = false) {
        guard follow, let fix = model.fix else { return }
        if fix.speed >= 0.7 && fix.course >= 0 { lastHeading = fix.course }
        let heading = reduceMotion ? 0 : lastHeading
        let target = MapCameraPosition.camera(MapCamera(centerCoordinate: fix.point.walkingCoordinate, distance: 500, heading: heading, pitch: 0))
        if animated && !reduceMotion {
            withAnimation(.easeInOut(duration: 0.25)) { camera = target }
        } else {
            camera = target
        }
    }
    private func openMaps() {
        model.finish()
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: model.destination.point.walkingCoordinate))
        destination.name = model.destination.name
        destination.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
        dismiss()
    }
}
