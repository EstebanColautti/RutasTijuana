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
    @State private var tabResets: [AppDestination: Int] = [:]
    @State private var tripActive = false
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
                .id("routes-\(tabResets[.routes, default: 0])")
                .tag(AppDestination.routes)

                home
                    .toolbar(.hidden, for: .tabBar)
                    .id("home-\(tabResets[.home, default: 0])")
                    .tag(AppDestination.home)

                NavigationStack { CatalogView(favoritesOnly: true) }
                    .toolbar(.hidden, for: .tabBar)
                    .id("favorites-\(tabResets[.favorites, default: 0])")
                    .tag(AppDestination.favorites)
            }
            .padding(.bottom, dockHeight)

            AppDock(selection: selected, confirmsSelection: selected == .home && tripActive,
                    confirmsReselectionOnly: true, onSelect: select)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { dockHeight = $0 }
        }
        .environment(\.homeTripActive, $tripActive)
        .environment(\.activeAppDestination, selected)
        .environment(\.openAppDestination, select)
        .tint(AppDesign.primary)
    }

    @ViewBuilder private var home: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--legacy-consultation-test") {
            ContentView()
        } else { integratedPlanner }
        #else
        integratedPlanner
        #endif
    }

    private var integratedPlanner: some View {
        TripPlannerView(
            catalog: repository.catalog ?? RouteCatalog(schemaVersion: 1, version: "", publishable: false,
                                                        licenseStatus: "", groups: [], features: []),
            integratedHome: true
        )
    }

    private func select(_ destination: AppDestination) {
        if selected == destination {
            if destination == .home { tripActive = false }
            tabResets[destination, default: 0] += 1
        }
        selected = destination
    }
}
