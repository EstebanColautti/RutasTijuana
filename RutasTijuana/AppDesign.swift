import CoreText
import MapKit
import UIKit
import SwiftUI

enum AppDesign {
    static let panelRadius: CGFloat = 36
    /// Liquid Glass existe desde iOS 26; antes se usan materiales y colores sólidos.
    static var hasLiquidGlass: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }
    static let panelOverlap: CGFloat = 32
    static let dockSelection = Color(white: 81 / 255)
    static let city = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 32.5304, longitude: -117.0250),
        span: MKCoordinateSpan(latitudeDelta: 0.032, longitudeDelta: 0.037)
    )
    static let selectionFill = Color(red: 228 / 255, green: 223 / 255, blue: 1)

    static func panelSurface(_ edge: MapPanelEdge = .shallow) -> some View {
        MapPanelShape(edge: edge)
            .fill(Color(uiColor: .systemBackground))
            .shadow(color: .black.opacity(0.16), radius: 7, x: 0, y: -2)
    }

    /// Panel flotante sobre el mapa, en vidrio como la hoja de Apple Maps.
    static func glassPanel(_ edge: MapPanelEdge = .shallow) -> some View {
        Color.clear
            .appGlass(in: MapPanelShape(edge: edge), glassTint: Color(uiColor: .systemBackground).opacity(0.88))
            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: -2)
    }

    static func raisedAction(_ shape: Capsule, fill: Color, raised: Bool) -> some View {
        shape.fill(fill)
            .shadow(color: .black.opacity(raised ? 0.24 : 0), radius: 3, x: 0, y: 3)
    }

    static func routeCamera(_ points: [GeoPoint], padding: Double = 1.3, minimumSpan: Double = 0.0025) -> MapCameraPosition? {
        let valid = points.filter { (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) }
        guard let minLat = valid.map(\.latitude).min(), let maxLat = valid.map(\.latitude).max(),
              let minLon = valid.map(\.longitude).min(), let maxLon = valid.map(\.longitude).max() else { return nil }
        return .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(minimumSpan, (maxLat - minLat) * padding),
                                   longitudeDelta: max(minimumSpan, (maxLon - minLon) * padding))
        ))
    }

    static let navigationMotion = Animation.easeInOut(duration: 0.20)
    static let selectionMotion = Animation.easeOut(duration: 0.16)
    static let header = Color(red: 23 / 255, green: 25 / 255, blue: 30 / 255)
    static let primary = Color(red: 0, green: 80 / 255, blue: 208 / 255)
    static let accent = Color(red: 184 / 255, green: 170 / 255, blue: 1)
    static let dock = Color(red: 38 / 255, green: 38 / 255, blue: 38 / 255)
    static let routeInk = Color(red: 43 / 255, green: 24 / 255, blue: 202 / 255)
    static let routeOutline = StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
    static let routeStroke = StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
    static let fieldError = Color(red: 197 / 255, green: 26 / 255, blue: 26 / 255)
    static let focus = Color(red: 5 / 255, green: 149 / 255, blue: 240 / 255)
    static let danger = Color(red: 215 / 255, green: 0, blue: 21 / 255)
    /// Texto secundario con contraste suficiente sobre blanco, tarjetas y vidrio (WCAG AA).
    static let secondaryInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.74, alpha: 1) : UIColor(white: 0.36, alpha: 1)
    })

    static var title: Font { type(17, relativeTo: .headline, weight: .semibold) }
    static var subtitle: Font { type(14, relativeTo: .subheadline, weight: .semibold) }
    static var body: Font { type(14, relativeTo: .body, weight: .light) }
    static var note: Font { type(12, relativeTo: .footnote, weight: .lightItalic) }
    /// Texto explicativo de estados vacíos e indicaciones: peso regular para leerse sobre vidrio.
    static var explanation: Font { type(15, relativeTo: .subheadline, weight: .regular) }

    enum Face: String, CaseIterable {
        case light = "Light"
        case regular = "Regular"
        case medium = "Medium"
        case semibold = "SemiBold"
        case lightItalic = "LightItalic"

        var systemWeight: Font.Weight {
            switch self {
            case .light, .lightItalic: return .light
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            }
        }
    }

    private static let interNames: [Face: String] = {
        var names: [Face: String] = [:]
        for face in Face.allCases {
            let resource = "Inter-" + face.rawValue
            guard let url = Bundle.main.url(forResource: resource, withExtension: "ttf", subdirectory: "Typography")
                    ?? Bundle.main.url(forResource: resource, withExtension: "ttf"),
                  let provider = CGDataProvider(url: url as CFURL),
                  let font = CGFont(provider),
                  let name = font.postScriptName else { continue }
            CTFontManagerRegisterGraphicsFont(font, nil)
            names[face] = name as String
        }
        return names
    }()

    static func type(_ size: CGFloat, relativeTo style: Font.TextStyle, weight: Face = .regular) -> Font {
        if let name = interNames[weight] {
            return .custom(name, size: size, relativeTo: style)
        }
        let fallback = Font.system(style, design: .default).weight(weight.systemWeight)
        return weight == .lightItalic ? fallback.italic() : fallback
    }
}

enum MapPanelEdge: Equatable {
    case shallow, deep

    var depth: CGFloat { self == .deep ? 42 : 16 }
    var width: CGFloat { self == .deep ? 68 : 52 }
}

private struct MapPanelShape: Shape {
    let edge: MapPanelEdge

    func path(in rect: CGRect) -> Path {
        let width = min(rect.width / 2, edge.width)
        let depth = min(rect.height, edge.depth)
        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + depth))
            path.addQuadCurve(to: CGPoint(x: rect.minX + width, y: rect.minY),
                              control: CGPoint(x: rect.minX + 5, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - width, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + depth),
                              control: CGPoint(x: rect.maxX - 5, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

struct AppBrandTitle: View {
    var body: some View {
        Text("Rutas Tijuana")
            .font(AppDesign.title)
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

extension ToolbarContent {
    @ToolbarContentBuilder
    func appHeaderControl() -> some ToolbarContent {
        #if compiler(>=6.4)
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

struct AppPanelHeading<Trailing: View>: View {
    let title: String
    var backLabel: String = "Regresar"
    var backIdentifier: String?
    var back: (() -> Void)?
    var centered = true
    var sideWidth: CGFloat = 48
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        Text(title)
            .font(AppDesign.type(21, relativeTo: .title2, weight: .semibold).bold())
            .multilineTextAlignment(centered ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, sideWidth)
            .padding(.trailing, centered ? sideWidth : 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: centered ? .center : .leading)
            .contentTransition(.opacity)
            .accessibilityAddTraits(.isHeader)
            .overlay(alignment: .leading) {
                if let back {
                    Button(action: back) {
                        Image(systemName: "arrow.left")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(backLabel)
                    .accessibilityIdentifier(backIdentifier ?? backLabel)
                }
            }
            .overlay(alignment: .trailing, content: trailing)
            .foregroundStyle(.primary)
    }
}

/// Cuenta los toques sobre la pestaña ya activa; las pantallas vuelven a su raíz al cambiar.
private struct TabResetKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var tabReset: Int {
        get { self[TabResetKey.self] }
        set { self[TabResetKey.self] = newValue }
    }
}

private struct HomeTripActiveKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}

extension EnvironmentValues {
    var homeTripActive: Binding<Bool>? {
        get { self[HomeTripActiveKey.self] }
        set { self[HomeTripActiveKey.self] = newValue }
    }
}

struct MapRouteBadge: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(AppDesign.subtitle)
            if let detail { Text(detail).font(AppDesign.note) }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .appGlass(in: Capsule(), tint: AppDesign.primary, glassTint: Color(red: 0, green: 52 / 255, blue: 150 / 255))
        .background(AppDesign.primary, in: Capsule())
        .shadow(color: .black.opacity(0.22), radius: 4, x: 0, y: 2)
        .accessibilityElement(children: .combine)
    }
}

enum AppDestination: String, CaseIterable {
    case routes = "Rutas"
    case home = "Inicio"
    case favorites = "Favoritos"

    var icon: AppIcon {
        switch self {
        case .routes: return .compass
        case .home: return .home
        case .favorites: return .star
        }
    }

}

enum AppIcon: String {
    case compass = "app-compass"
    case pin = "app-pin"
    case home = "app-home"
    case chevron = "app-chevron"
    case turn = "app-turn"
    case navigation = "app-navigation"
    case star = "app-star"
    case vehicle = "app-vehicle"
}

struct AppGlyph: View {
    let icon: AppIcon
    var size: CGFloat = 20

    var body: some View {
        Image(icon.rawValue)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct AppFavoriteIcon: View {
    var filled = false
    var scale: CGFloat = 1
    @ScaledMetric(relativeTo: .body) private var size = 19.0

    var body: some View {
        Group {
            if filled {
                Image(systemName: "star.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(AppDesign.accent)
                    .frame(width: size * scale, height: size * scale)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                AppGlyph(icon: .star, size: size * scale)
            }
        }
        .accessibilityHidden(true)
    }
}

struct AppDock: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .body) private var iconSize = 23.0
    var selection: AppDestination?
    var confirmsSelection = false
    var confirmsReselectionOnly = false
    var onSelect: (AppDestination) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppDestination.allCases, id: \.self) { destination in
                destinationButton(destination)
            }
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .padding(3)
        .appGlass(in: Capsule(), dark: true)
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .padding(.horizontal, textSize.isAccessibilitySize ? 10 : 32)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("app-dock")
    }

    @State private var confirmationDestination: AppDestination?
    @Namespace private var selectionSpace

    private func destinationButton(_ destination: AppDestination) -> some View {
        Button {
            if confirmsSelection && (!confirmsReselectionOnly || selection == destination) {
                confirmationDestination = destination
            }
            else { onSelect(destination) }
        } label: {
            VStack(spacing: 2) {
                if !textSize.isAccessibilitySize {
                    AppGlyph(icon: destination.icon, size: iconSize)
                        .foregroundStyle(selection == destination ? AppDesign.accent : .white)
                }
                DockCaption(title: destination.rawValue,
                            color: selection == destination ? UIColor(AppDesign.accent) : .white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(destination.rawValue)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 48)
            .background {
                if selection == destination {
                    Capsule().fill(AppDesign.dockSelection)
                        .overlay { Capsule().strokeBorder(.white.opacity(0.17), lineWidth: 1) }
                        .matchedGeometryEffect(id: "dock-selection", in: selectionSpace)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Capsule())
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: selection)
        }
        .buttonStyle(AppPressStyle())
        .accessibilityLabel(destination.rawValue)
        .accessibilityIdentifier("dock-" + destination.rawValue)
        .accessibilityAddTraits(selection == destination ? .isSelected : [])
        .confirmationDialog("¿Finalizar el trayecto?", isPresented: Binding(
            get: { confirmationDestination == destination },
            set: { if !$0 && confirmationDestination == destination { confirmationDestination = nil } }
        ), titleVisibility: .visible) {
            Button("Finalizar trayecto", role: .destructive) { onSelect(destination) }
            Button("Cancelar", role: .cancel) {}
        }
    }
}

private struct DockCaption: UIViewRepresentable {
    let title: String
    var color: UIColor = .white

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.isAccessibilityElement = false
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.text = title
        label.textColor = color
        label.font = UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: label.traitCollection)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        uiView.sizeThatFits(CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width,
                                  height: .greatestFiniteMagnitude))
    }
}

private struct AppDestinationAction: EnvironmentKey {
    static let defaultValue: ((AppDestination) -> Void)? = nil
}

private struct ActiveAppDestination: EnvironmentKey {
    static let defaultValue: AppDestination? = nil
}

extension EnvironmentValues {
    var activeAppDestination: AppDestination? {
        get { self[ActiveAppDestination.self] }
        set { self[ActiveAppDestination.self] = newValue }
    }

    var openAppDestination: ((AppDestination) -> Void)? {
        get { self[AppDestinationAction.self] }
        set { self[AppDestinationAction.self] = newValue }
    }
}

extension View {
    /// `tint` colorea el vidrio y su respaldo opaco; `glassTint` solo matiza el vidrio de iOS 26.
    func appGlass<S: Shape>(in shape: S, dark: Bool = false, interactive: Bool = false,
                            tint: Color? = nil, glassTint: Color? = nil) -> some View {
        modifier(AppGlassSurface(shape: shape, dark: dark, interactive: interactive, tint: tint, glassTint: glassTint))
    }
}

/// Agrupa superficies de vidrio cercanas para que se combinen y transformen juntas (iOS 26).
struct AppGlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

private struct AppGlassSurface<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let shape: S
    let dark: Bool
    let interactive: Bool
    var tint: Color?
    var glassTint: Color?

    private var solid: Color { tint ?? (dark ? AppDesign.dock : Color(uiColor: .systemBackground)) }

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(solid, in: shape)
        } else {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.tint(glassTint ?? tint ?? (dark ? AppDesign.dock : Color(uiColor: .systemBackground).opacity(0.55)))
                    .interactive(interactive), in: shape)
            } else {
                fallback(content)
            }
            #else
            fallback(content)
            #endif
        }
    }

    @ViewBuilder private func fallback(_ content: Content) -> some View {
        if let tint {
            content.background(tint, in: shape)
        } else if dark {
            content.background(AppDesign.dock, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

enum AppNoticeTone {
    case information, caution, success

    var accent: Color {
        switch self {
        case .information: return Color(red: 83 / 255, green: 162 / 255, blue: 183 / 255)
        case .caution: return Color(red: 244 / 255, green: 162 / 255, blue: 62 / 255)
        case .success: return Color(red: 0.10, green: 0.62, blue: 0.33)
        }
    }
}

struct AppNotice: View {
    let text: String
    let tone: AppNoticeTone

    var body: some View {
        Text(text)
            .font(AppDesign.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(tone.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(tone.accent, lineWidth: 1) }
    }
}

/// Espera común de la app: icono en círculo lila con pulso y una barra que avanza.
/// `compact` la reduce a una fila para espacios pequeños, como los resultados de búsqueda.
struct AppLoadingView: View {
    let title: String
    var symbol = "bus.fill"
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweeping = false

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 10) {
                    badge(size: 28)
                    Text(title).font(AppDesign.subtitle).foregroundStyle(AppDesign.secondaryInk)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
            } else {
                VStack(spacing: 12) {
                    badge(size: 48)
                    Text(title).font(AppDesign.subtitle).multilineTextAlignment(.center)
                    track.frame(width: 120)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .appCard()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.updatesFrequently)
        .onAppear { sweeping = true }
    }

    private func badge(size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(AppDesign.primary)
            .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            .frame(width: size, height: size)
            .background(AppDesign.selectionFill, in: Circle())
    }

    private var track: some View {
        Capsule().fill(Color(uiColor: .tertiarySystemFill))
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule().fill(AppDesign.accent)
                        .frame(width: geometry.size.width * 0.38)
                        .offset(x: reduceMotion ? geometry.size.width * 0.31 : (sweeping ? geometry.size.width * 0.62 : 0))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: sweeping)
                }
            }
            .clipShape(Capsule())
    }
}

/// Botón de icono con área táctil mínima de 44 pt dentro del propio botón.
struct AppIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Respuesta táctil discreta y común para controles sin relleno propio.
struct AppPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct AppActionStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var fill = AppDesign.primary
    var ink = Color.white
    var verticalInset: CGFloat = 8

    /// El vidrio aclara su tinte; se tiñe con un tono más profundo para que el resultado
    /// se vea como el color de marca y el texto blanco conserve el contraste AA.
    private var glassFill: Color {
        if fill == AppDesign.primary { return Color(red: 0, green: 52 / 255, blue: 150 / 255) }
        if fill == AppDesign.danger { return Color(red: 170 / 255, green: 0, blue: 16 / 255) }
        return fill
    }

    private var pressedFill: Color {
        if fill == AppDesign.primary { return Color(red: 0, green: 56 / 255, blue: 145 / 255) }
        if fill == AppDesign.danger { return Color(red: 233 / 255, green: 77 / 255, blue: 49 / 255) }
        return fill
    }
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        surface(configuration.label
            .font(AppDesign.subtitle)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(isEnabled && !(configuration.isPressed && fill == AppDesign.danger) ? ink : Color.black)
            .padding(.horizontal, 16)
            .padding(.vertical, verticalInset)
            .frame(minWidth: 44, minHeight: 44), pressed: configuration.isPressed)
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }

    /// Botón principal: vidrio teñido con el color de la acción (equivalente a `.glassProminent`).
    @ViewBuilder private func surface(_ label: some View, pressed: Bool) -> some View {
        if isEnabled {
            // El color va sobre el vidrio y bajo el texto: el brillo del vidrio no reduce el contraste.
            label
                .background(pressed ? pressedFill : fill, in: Capsule())
                .appGlass(in: Capsule(), interactive: true, tint: pressed ? pressedFill : fill,
                          glassTint: pressed ? pressedFill : glassFill)
                .shadow(color: fill.opacity(pressed || !AppDesign.hasLiquidGlass ? 0 : 0.28), radius: 6, y: 3)
        } else {
            label.background(Color(white: 0.88), in: Capsule())
        }
    }
}

extension View {
    /// Tarjeta común de la app: la misma superficie que el itinerario de Inicio.
    func appCard(selected: Bool = false, radius: CGFloat = 18) -> some View {
        background(selected ? AppDesign.selectionFill : Color(uiColor: .secondarySystemBackground),
                   in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Superficie flotante de búsqueda, compartida por Inicio y Rutas.
    func appSearchSurface() -> some View {
        self
            .appGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    func appField(focused: Bool, invalid: Bool = false) -> some View {
        self
            .font(AppDesign.body)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(invalid ? AppDesign.fieldError : focused ? AppDesign.focus : Color.secondary.opacity(0.38),
                                  lineWidth: invalid || focused ? 2 : 1)
                    .allowsHitTesting(false)
            }
    }
}
