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
                .task { await NavigationActivityController.clearPreviousSession(); await CatalogRepository.shared.open() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await CatalogRepository.shared.update(force: false) } }
                }
        }
    }
}

private struct MainTabs: View {
    private enum Section: Hashable { case stops, home, map }
    @State private var selected: Section = .home
    @ObservedObject private var repository = CatalogRepository.shared

    var body: some View {
        TabView(selection: $selected) {
            NavigationStack {
                CatalogView(initialFilter: .stops)
                    .toolbarBackground(.black, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbarColorScheme(.dark, for: .navigationBar)
            }
            .tabItem { Label("Paradas", systemImage: "octagon") }
            .tag(Section.stops)

            ContentView()
                .tabItem { Label("Inicio", systemImage: "house") }
                .tag(Section.home)

            NavigationStack {
                mapHome
            }
            .tabItem { Label("Mapa", systemImage: "mappin") }
            .tag(Section.map)
        }
        .tint(.primary)
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
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                if let catalog = repository.catalog, catalog.readyForDistribution {
                    NavigationLink { TripPlannerView(catalog: catalog) } label: {
                        Text("Empezar viaje").frame(minWidth: 160, minHeight: 44)
                    }
                    .accessibilityIdentifier("map-start")
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.02, green: 0.29, blue: 0.57))
                } else {
                    NavigationLink { CatalogView() } label: {
                        Text("Consultar recorridos").frame(minWidth: 160, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.02, green: 0.29, blue: 0.57))
                }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding(20)
        }
        .navigationTitle("Rutas Tijuana")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
