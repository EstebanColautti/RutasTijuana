import SwiftUI
import MapKit

private extension GeoPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct ContentView: View {
    private enum Stage { case home, origin, destination, journey }
    private let route = TransitRoute.demonstration
    @State private var stage = Stage.home
    @State private var origin: GeoPoint?
    @State private var destination: GeoPoint?
    @State private var originID: String?
    @State private var destinationID: String?
    @State private var selectedStop: String?
    @State private var invalidDestination = false
    @State private var camera = MapCameraPosition.region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 32.531, longitude: -117.012),
        span: MKCoordinateSpan(latitudeDelta: 0.024, longitudeDelta: 0.024)
    ))
    #if os(iOS)
    @StateObject private var location = LocationService()
    #endif

    private var title: String {
        switch stage {
        case .home: return ""
        case .origin: return "Desde dónde sales"
        case .destination: return "A dónde vas"
        case .journey: return "Tu trayecto"
        }
    }

    private var trip: [TransitStop] {
        guard let originID, let destinationID else { return [] }
        return route.journey(from: originID, to: destinationID) ?? []
    }

    var body: some View {
        NavigationStack {
            Group {
                if stage == .home { welcome }
                else {
                    VStack(spacing: 0) {
                        routeMap.frame(minHeight: 180)
                        panel
                    }
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if stage != .home {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: back) {
                            Label(stage == .destination ? "Cambiar origen" : "Regresar", systemImage: "chevron.left")
                        }
                    }
                }
            }
            .alert("Destino no válido", isPresented: $invalidDestination) {
                Button("Cambiar destino", role: .cancel) {
                    destination = nil
                    destinationID = nil
                    selectedStop = nil
                }
            } message: {
                Text("Elige una parada de bajada distinta de la parada de origen.")
            }
            .onChange(of: selectedStop) { _, id in
                guard stage != .journey,
                      let stop = route.stops.first(where: { $0.id == id }) else { return }
                select(stop.point)
            }
            #if os(iOS)
            .onChange(of: location.point) { _, point in
                if stage == .origin, let point { select(point) }
            }
            #endif
        }
        .frame(minWidth: 320, minHeight: 560)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Image(systemName: "bus.fill")
                .font(.system(size: 44)).foregroundStyle(.blue).padding(20)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
            Text("Rutas Tijuana").font(.largeTitle.bold())
            Text("Consulta cómo llegar de un punto A a un punto B en transporte público.")
                .foregroundStyle(.secondary)
            demoNotice
            Spacer()
            NavigationLink { CatalogView() } label: {
                Label("Explorar recorridos", systemImage: "map").frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.bordered).controlSize(.large)
            .accessibilityIdentifier("Explorar recorridos")
            Text("Puedes elegir tu ubicación manualmente. No se guarda.")
                .font(.footnote).foregroundStyle(.secondary)
            primaryButton("Elegir ubicación inicial") { stage = .origin }
        }
        .padding(24)
    }

    private var routeMap: some View {
        MapReader { proxy in
            Map(position: $camera, selection: $selectedStop) {
                MapPolyline(coordinates: (route.stops + [route.stops[0]]).map { $0.point.coordinate })
                    .stroke(.gray.opacity(0.5), lineWidth: 4)
                if stage == .journey {
                    MapPolyline(coordinates: trip.map { $0.point.coordinate }).stroke(.blue, lineWidth: 7)
                }
                ForEach(route.stops) { stop in
                    Marker(stop.name, systemImage: "bus", coordinate: stop.point.coordinate)
                        .tint(.gray).tag(stop.id)
                }
                if let origin {
                    Annotation("Origen A", coordinate: origin.coordinate) { pin("A", color: .blue) }
                }
                if let destination {
                    Annotation("Destino B", coordinate: destination.coordinate) { pin("B", color: .indigo) }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .onTapGesture { position in
                guard stage != .journey, let point = proxy.convert(position, from: .local) else { return }
                select(GeoPoint(latitude: point.latitude, longitude: point.longitude))
            }
            .overlay(alignment: .topLeading) {
                Text("Recorrido ficticio").font(.caption.weight(.medium)).padding(8)
                    .background(.regularMaterial, in: Capsule()).padding(12).allowsHitTesting(false)
            }
        }
    }

    private var panel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Capsule().fill(.secondary.opacity(0.4))
                    .frame(width: 36, height: 5).frame(maxWidth: .infinity)
                demoNotice
                if stage == .origin { originPanel }
                else if stage == .destination { destinationPanel }
                else { journeyPanel }
            }
            .padding(16)
        }
        .frame(maxHeight: 350).background(.regularMaterial)
    }

    private var originPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(origin == nil ? "Tu ubicación" : "Paradas cercanas").font(.title3.bold())
            Text("Toca el mapa o elige una parada. Las distancias son en línea recta.")
                .font(.subheadline).foregroundStyle(.secondary)
            #if os(iOS)
            Button { location.request() } label: {
                Label(location.isRequesting ? "Obteniendo ubicación…" : "Usar mi ubicación", systemImage: "location")
            }
            .disabled(location.isRequesting)
            if let message = location.message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            #endif
            choices(point: origin, selectedID: originID, isOrigin: true)
            primaryButton("Continuar", disabled: originID == nil) {
                cancelLocation()
                stage = .destination
                selectedStop = nil
            }
        }
    }

    private var destinationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let stop = route.stops.first(where: { $0.id == originID }) {
                Label("Origen: \(stop.name)", systemImage: "a.circle")
            }
            Text("Dónde te bajas").font(.title3.bold())
            Text("Toca el mapa o elige una parada para marcar el destino.")
                .font(.subheadline).foregroundStyle(.secondary)
            choices(point: destination, selectedID: destinationID, isOrigin: false)
            primaryButton("Ver trayecto", disabled: destinationID == nil) {
                if originID == destinationID { invalidDestination = true }
                else {
                    selectedStop = nil
                    stage = .journey
                    camera = .automatic
                }
            }
        }
    }

    private var journeyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(route.name).font(.title3.bold())
            Text("Sentido único · \(max(0, trip.count - 1)) tramos")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Horario y frecuencia: dato no disponible").font(.footnote)
            if let first = trip.first, let last = trip.last {
                journeyRow("Sube en \(first.name)", point: origin, stop: first, symbol: "a.circle.fill")
                journeyRow("Bájate en \(last.name)", point: destination, stop: last, symbol: "b.circle.fill")
            }
            if let stop = route.stops.first(where: { $0.id == selectedStop }) {
                Label(stop.name, systemImage: "bus").font(.subheadline)
            }
            Text("El mapa muestra una simulación. No indica un servicio real ni un camino peatonal.")
                .font(.footnote).foregroundStyle(.secondary)
            primaryButton("Nueva consulta", action: reset)
        }
    }

    @ViewBuilder
    private func choices(point: GeoPoint?, selectedID: String?, isOrigin: Bool) -> some View {
        if let point {
            let nearby = route.nearbyStops(to: point)
            if nearby.isEmpty {
                Text("No hay paradas de demostración a menos de 2 km. Elige un punto cerca del recorrido.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(nearby) { option in
                Button {
                    if isOrigin { originID = option.id } else { destinationID = option.id }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(option.stop.name).fontWeight(.medium)
                            Text(distanceText(option.distance)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedID == option.id { Image(systemName: "checkmark").foregroundStyle(.blue) }
                    }
                    .padding(12).frame(minHeight: 52)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stop-\(option.id)")
                .accessibilityAddTraits(selectedID == option.id ? .isSelected : [])
            }
        } else {
            ForEach(route.stops) { stop in
                Button(stop.name) { select(stop.point) }.frame(minHeight: 44)
                    .accessibilityIdentifier("stop-\(stop.id)")
            }
        }
    }

    private var demoNotice: some View {
        Label("Demostración · Datos ficticios", systemImage: "info.circle")
            .font(.caption).foregroundStyle(.secondary)
    }

    private func primaryButton(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity, minHeight: 32) }
            .buttonStyle(.borderedProminent).controlSize(.large).disabled(disabled)
            .accessibilityIdentifier(title)
    }

    private func pin(_ text: String, color: Color) -> some View {
        Text(text).font(.headline).foregroundStyle(.white).frame(width: 32, height: 32)
            .background(color, in: Circle()).accessibilityLabel(text == "A" ? "Origen" : "Destino")
    }

    private func journeyRow(_ title: String, point: GeoPoint?, stop: TransitStop, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading) {
                Text(title).fontWeight(.medium)
                if let point { Text(distanceText(point.distance(to: stop.point))).font(.caption).foregroundStyle(.secondary) }
            }
        } icon: { Image(systemName: symbol).foregroundStyle(.blue) }
    }

    private func distanceText(_ distance: Double) -> String { "A \(Int(distance.rounded())) m en línea recta" }

    private func select(_ point: GeoPoint) {
        cancelLocation()
        let closest = route.nearbyStops(to: point).first?.id
        if stage == .origin { origin = point; originID = closest }
        else if stage == .destination { destination = point; destinationID = closest }
    }

    private func back() {
        cancelLocation()
        selectedStop = nil
        switch stage {
        case .home: break
        case .origin: stage = .home
        case .destination: stage = .origin
        case .journey: stage = .destination
        }
    }

    private func reset() {
        cancelLocation()
        origin = nil
        destination = nil
        originID = nil
        destinationID = nil
        selectedStop = nil
        stage = .home
        camera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 32.531, longitude: -117.012),
            span: MKCoordinateSpan(latitudeDelta: 0.024, longitudeDelta: 0.024)
        ))
    }

    private func cancelLocation() {
        #if os(iOS)
        location.cancel()
        #endif
    }
}

#Preview {
    ContentView()
}
