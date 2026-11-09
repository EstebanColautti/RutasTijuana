import SwiftUI

@main
struct RutasTijuanaApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @ViewBuilder private var root: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--trip-fixture") {
            NavigationStack { TripPlannerView(catalog: .tripSample) }
        } else { ContentView() }
        #else
        ContentView()
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
