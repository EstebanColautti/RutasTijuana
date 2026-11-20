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
    @State private var dockHeight: CGFloat = 66
    @ObservedObject private var repository = CatalogRepository.shared

    var body: some View {
        ZStack(alignment: .bottom) {
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
            .safeAreaPadding(.bottom, selected == .map ? 0 : dockHeight)

            AppDock(selection: selected) { selected = $0 }
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { dockHeight = $0 }
        }
        .environment(\.activeAppDestination, selected)
        .environment(\.openAppDestination) { selected = $0 }
        .tint(AppDesign.primary)
    }

    private var mapHome: some View {
        ZStack(alignment: .bottom) {
            Map(initialPosition: .region(AppDesign.city))
                .mapStyle(.standard(elevation: .flat))
                .ignoresSafeArea(.container, edges: .bottom)
                .accessibilityLabel("Mapa de Tijuana")
            VStack(spacing: 8) {
                Text("¿A dónde quieres ir hoy?")
                    .font(AppDesign.subtitle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let catalog = repository.catalog, catalog.readyForDistribution {
                    NavigationLink {
                        TripPlannerView(catalog: catalog).safeAreaPadding(.bottom, dockHeight)
                    } label: {
                        Text("Empezar viaje").padding(.horizontal, 14)
                    }
                    .accessibilityIdentifier("map-start")
                    .buttonStyle(AppActionStyle())
                } else {
                    NavigationLink {
                        CatalogView().safeAreaPadding(.bottom, dockHeight)
                    } label: {
                        Text("Consultar recorridos").padding(.horizontal, 14)
                    }
                    .buttonStyle(AppActionStyle())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 20)
            .foregroundStyle(.primary)
            .background {
                RoundedRectangle(cornerRadius: 58)
                    .fill(Color(uiColor: .systemBackground))
                    .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, dockHeight + 12)
        }
        .navigationTitle("Rutas Tijuana")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { AppBrandTitle() }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink { CatalogView(favoritesOnly: true).safeAreaPadding(.bottom, dockHeight) } label: {
                    AppFavoriteIcon().frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityLabel("Favoritos")
            }
        }
        .toolbarBackground(AppDesign.header, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
