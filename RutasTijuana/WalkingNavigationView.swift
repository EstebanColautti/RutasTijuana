import SwiftUI
import MapKit

struct WalkingNavigationView: View {
    private let onArrival: (() -> Void)?
    @StateObject private var model: WalkingNavigationCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openAppDestination) private var openAppDestination
    @Environment(\.activeAppDestination) private var activeAppDestination
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
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    VStack(spacing: -MapPanelEdge.deep.depth) {
                        Map(position: $camera) {
                            if let route = model.route {
                                MapPolyline(coordinates: route.points.map(\.walkingCoordinate)).stroke(.white, style: AppDesign.routeOutline)
                                MapPolyline(coordinates: route.points.map(\.walkingCoordinate)).stroke(AppDesign.routeInk, style: AppDesign.routeStroke)
                                if !route.points.isEmpty {
                                    Annotation("Duración y distancia", coordinate: route.points[route.points.count / 2].walkingCoordinate, anchor: .bottom) {
                                        MapRouteBadge(title: WalkingFormat.duration(model.secondsRemaining, arrived: model.phase == .arrived),
                                                      detail: WalkingFormat.distance(model.progress.remaining))
                                    }
                                }
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
                        .mapStyle(.standard(elevation: .flat))
                        .accessibilityLabel("Mapa de la guía a pie")
                        .overlay {
                            if showingSteps {
                                Color.black.opacity(0.16).allowsHitTesting(false).accessibilityHidden(true)
                            }
                        }
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
                            if phase == .preview {
                                follow = false
                                camera = AppDesign.routeCamera(model.route?.points ?? [], minimumSpan: 0.0012) ?? .automatic
                            }
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
                        .frame(height: mapHeight(in: geometry.size))
                        ScrollView {
                            if showingSteps {
                                VStack(spacing: 0) {
                                    AppPanelHeading(title: "Indicaciones", backLabel: "Cerrar",
                                                    backIdentifier: "walking-close-steps",
                                                    back: { showingSteps = false }) { EmptyView() }
                                    .padding(.horizontal, 12)
                                    walkingSteps
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 8) {
                                        Button {
                                            confirmEnd = true
                                        } label: {
                                            Image(systemName: "arrow.left")
                                                .frame(width: 44, height: 44)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Finalizar")
                                        .accessibilityIdentifier("walking-finish")
                                        Text(model.destination.title)
                                            .font(AppDesign.subtitle)
                                            .accessibilityAddTraits(.isHeader)
                                    }
                                    if model.phase == .navigating {
                                        Text(model.instruction).font(AppDesign.type(17, relativeTo: .title2, weight: .semibold)).accessibilityIdentifier("walking-instruction")
                                        Text("En \(WalkingFormat.distance(model.progress.stepRemaining))")
                                        if model.progress.stepRemaining <= WalkingPolicy.maneuverDistance { Text("Próxima indicación").font(AppDesign.note) }
                                    }
                                    Text(model.destination.name)
                                        .font(model.phase == .navigating ? AppDesign.subtitle : AppDesign.title)
                                        .accessibilityAddTraits(model.phase == .navigating ? [] : .isHeader)
                                    if model.route != nil {
                                        let layout = textSize.isAccessibilitySize
                                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                            : AnyLayout(HStackLayout(spacing: 16))
                                        layout {
                                            Label(WalkingFormat.duration(model.secondsRemaining, arrived: model.phase == .arrived), systemImage: "clock")
                                            Label(WalkingFormat.distance(model.phase == .arrived ? 0 : model.progress.remaining), systemImage: "figure.walk")
                                                .frame(maxWidth: .infinity, alignment: textSize.isAccessibilitySize ? .leading : .trailing)
                                        }
                                        .font(AppDesign.subtitle)
                                        if !model.status.offersStart(phase: model.phase) && model.phase != .navigating {
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
                        .padding(.top, 12)
                        .id(showingSteps)
                        .frame(maxHeight: .infinity)
                        .clipped()
                        .background { AppDesign.panelSurface(.deep) }
                    }
                }
                VStack(spacing: 4) {
                    if !showingSteps && model.status.offersStart(phase: model.phase) {
                        let actions = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 10))
                        actions {
                            Button { showingSteps = true } label: {
                                Text("Ver pasos")
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(AppActionStyle(fill: Color(uiColor: .systemGray4), ink: .primary))
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
                    } else if !showingSteps && model.phase == .navigating && model.route != nil {
                        Button("Ver pasos") { showingSteps = true }
                            .buttonStyle(AppActionStyle(fill: Color(uiColor: .systemGray4), ink: .primary))
                            .padding(.vertical, 6)
                    }
                    if openAppDestination != nil {
                        AppDock(selection: activeAppDestination) { destination in
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
            .modifier(AppFavoritesToolbar(confirmBeforeOpening: model.phase == .navigating))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { AppBrandTitle() } }
            .toolbarBackground(AppDesign.header, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .confirmationDialog("¿Finalizar la guía?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("Terminar guía", role: .destructive) { model.finish(); dismiss() }
            }

        }
        .preferredColorScheme(testColorScheme)
        .interactiveDismissDisabled()
        .task { model.connectivityChanged(connectivity.isConnected); model.prepare() }
        .onChange(of: connectivity.isConnected) { _, value in model.connectivityChanged(value) }
        .onDisappear { model.finish() }
    }

    private func mapHeight(in size: CGSize) -> CGFloat {
        let compact = size.width < 390
        let fraction: CGFloat
        if textSize.isAccessibilitySize { fraction = 0.26 }
        else if showingSteps { fraction = compact ? 0.57 : 0.61 }
        else if model.phase == .preview { fraction = compact ? 0.57 : 0.72 }
        else { fraction = compact ? 0.52 : 0.63 }
        return size.height * fraction + MapPanelEdge.deep.depth
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
                    if completed {
                        Image(systemName: "checkmark.circle").accessibilityHidden(true)
                    } else {
                        AppGlyph(icon: isCurrent ? .turn : .chevron)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        if model.phase == .navigating {
                            Text(completed ? "Completado" : isCurrent ? "Paso actual" : "Siguiente")
                                .font(AppDesign.subtitle)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(step.instruction)
                            .font(AppDesign.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fontWeight(isCurrent ? .semibold : .regular)
                .padding(12)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
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
