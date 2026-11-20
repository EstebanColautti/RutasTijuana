import SwiftUI
import MapKit

@main
struct RutasTijuanaApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @ViewBuilder private var root: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--trip-fixture") {
            NavigationStack { TripPlannerView(catalog: .tripSample) }
        } else { MainTabs() }
        #else
        MainTabs()
        #endif
    }
    var body: some Scene {
        WindowGroup {
            root
                .font(AppDesign.body)
                .task { await NavigationActivityController.clearPreviousSession(); await CatalogRepository.shared.open() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await CatalogRepository.shared.update(force: false) } }
                }
        }
    }
}

private struct MainTabs: View {
    @State private var selected: AppDestination = .home
    @ObservedObject private var repository = CatalogRepository.shared

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selected) {
                NavigationStack {
                    CatalogView(routesTab: true)
                        .toolbarBackground(AppDesign.header, for: .navigationBar)
                        .toolbarBackground(.visible, for: .navigationBar)
                        .toolbarColorScheme(.dark, for: .navigationBar)
                }
                .toolbar(.hidden, for: .tabBar)
                .tag(AppDestination.routes)

                ContentView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(AppDestination.home)

                NavigationStack {
                    mapHome
                }
                .toolbar(.hidden, for: .tabBar)
                .tag(AppDestination.map)
            }
            AppDock(selection: selected) { selected = $0 }
                .layoutPriority(1)
        }
        .environment(\.activeAppDestination, selected)
        .environment(\.openAppDestination) { selected = $0 }
        .tint(AppDesign.primary)
    }

    private var mapHome: some View {
        ZStack(alignment: .bottom) {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 32.531, longitude: -117.012),
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )))
            .accessibilityLabel("Mapa de Tijuana")
            VStack(spacing: 12) {
                Text("¿A dónde quieres ir hoy?")
                    .font(AppDesign.type(17, relativeTo: .title3, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                if let catalog = repository.catalog, catalog.readyForDistribution {
                    NavigationLink { TripPlannerView(catalog: catalog) } label: {
                        Text("Empezar viaje").frame(minWidth: 160, minHeight: 44)
                    }
                    .accessibilityIdentifier("map-start")
                    .buttonStyle(AppActionStyle())
                } else {
                    NavigationLink { CatalogView() } label: {
                        Text("Consultar recorridos").frame(minWidth: 160, minHeight: 44)
                    }
                    .buttonStyle(AppActionStyle())
                }
            }
            .padding(16)
            .foregroundStyle(.primary)
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(uiColor: .systemBackground))
                    .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .navigationTitle("Rutas Tijuana")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppDesign.header, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
