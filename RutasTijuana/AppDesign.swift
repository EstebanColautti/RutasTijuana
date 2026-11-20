import CoreText
import MapKit
import UIKit
import SwiftUI

enum AppDesign {
    static let panelRadius: CGFloat = 36
    static let panelOverlap: CGFloat = 24
    static let selectionFill = Color(red: 228 / 255, green: 223 / 255, blue: 1)

    static var panelSurface: some View {
        UnevenRoundedRectangle(topLeadingRadius: panelRadius, topTrailingRadius: panelRadius)
            .fill(Color(uiColor: .systemBackground))
            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: -2)
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

    static var title: Font { type(17, relativeTo: .headline, weight: .semibold) }
    static var subtitle: Font { type(14, relativeTo: .subheadline, weight: .semibold) }
    static var body: Font { type(14, relativeTo: .body, weight: .light) }
    static var note: Font { type(12, relativeTo: .footnote, weight: .lightItalic) }

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

enum AppDestination: String, CaseIterable {
    case routes = "Rutas"
    case home = "Inicio"
    case map = "Mapa"

}

private struct DockIcon: Shape {
    let destination: AppDestination

    func path(in rect: CGRect) -> Path {
        let path = Path { path in
            switch destination {
            case .routes:
                path.addEllipse(in: CGRect(x: 1.75, y: 1.75, width: 20.5, height: 20.5))
                path.addLines([CGPoint(x: 16.5, y: 7.5), CGPoint(x: 14.2, y: 14.2),
                               CGPoint(x: 7.5, y: 16.5), CGPoint(x: 9.8, y: 9.8)])
                path.closeSubpath()
            case .home:
                path.addLines([CGPoint(x: 2.25, y: 10), CGPoint(x: 12, y: 2),
                               CGPoint(x: 21.75, y: 10), CGPoint(x: 21.75, y: 20)])
                path.addQuadCurve(to: CGPoint(x: 19.75, y: 22), control: CGPoint(x: 21.75, y: 22))
                path.addLine(to: CGPoint(x: 4.25, y: 22))
                path.addQuadCurve(to: CGPoint(x: 2.25, y: 20), control: CGPoint(x: 2.25, y: 22))
                path.closeSubpath()
                path.addLines([CGPoint(x: 8.75, y: 22), CGPoint(x: 8.75, y: 12),
                               CGPoint(x: 15.25, y: 12), CGPoint(x: 15.25, y: 22)])
            case .map:
                path.move(to: CGPoint(x: 12, y: 22))
                path.addCurve(to: CGPoint(x: 3, y: 10.5), control1: CGPoint(x: 9.3, y: 20.1),
                              control2: CGPoint(x: 3, y: 15.4))
                path.addCurve(to: CGPoint(x: 12, y: 1.75), control1: CGPoint(x: 3, y: 5.7),
                              control2: CGPoint(x: 7, y: 1.75))
                path.addCurve(to: CGPoint(x: 21, y: 10.5), control1: CGPoint(x: 17, y: 1.75),
                              control2: CGPoint(x: 21, y: 5.7))
                path.addCurve(to: CGPoint(x: 12, y: 22), control1: CGPoint(x: 21, y: 15.4),
                              control2: CGPoint(x: 14.7, y: 20.1))
                path.closeSubpath()
                path.addEllipse(in: CGRect(x: 9, y: 7.25, width: 6, height: 6))
            }
        }
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
    }
}

struct AppFavoriteIcon: View {
    var filled = false
    var scale: CGFloat = 1
    @ScaledMetric(relativeTo: .body) private var size = 19.0

    var body: some View {
        let star = Path { path in
            path.addLines([
                CGPoint(x: 12, y: 1), CGPoint(x: 15.1, y: 8.1), CGPoint(x: 23, y: 9),
                CGPoint(x: 17.2, y: 14.2), CGPoint(x: 18.7, y: 22), CGPoint(x: 12, y: 18.1),
                CGPoint(x: 5.3, y: 22), CGPoint(x: 6.8, y: 14.2), CGPoint(x: 1, y: 9),
                CGPoint(x: 8.9, y: 8.1)
            ])
            path.closeSubpath()
        }.applying(CGAffineTransform(scaleX: size * scale / 24, y: size * scale / 24))

        Group {
            if filled {
                star.fill(.foreground)
            } else {
                star.stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size * scale, height: size * scale)
        .accessibilityHidden(true)
    }
}

struct AppDock: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .body) private var iconSize = 19.0
    var selection: AppDestination?
    var onSelect: (AppDestination) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppDestination.allCases, id: \.self) { destination in
                destinationButton(destination)
            }
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .padding(4)
        .appGlass(in: Capsule(), dark: true)
        .padding(.horizontal, textSize.isAccessibilitySize ? 10 : 28)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("app-dock")
    }

    private func destinationButton(_ destination: AppDestination) -> some View {
        Button {
            onSelect(destination)
        } label: {
            VStack(spacing: 2) {
                if !textSize.isAccessibilitySize {
                    DockIcon(destination: destination)
                        .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .frame(width: iconSize, height: iconSize)
                }
                DockCaption(title: destination.rawValue)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(destination.rawValue)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
            .background(selection == destination ? Color.white.opacity(0.18) : .clear, in: Capsule())
            .contentShape(Capsule())
            .animation(reduceMotion ? nil : AppDesign.selectionMotion, value: selection)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(destination.rawValue)
        .accessibilityIdentifier("dock-" + destination.rawValue)
        .accessibilityAddTraits(selection == destination ? .isSelected : [])
    }
}

private struct DockCaption: UIViewRepresentable {
    let title: String

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
    func appGlass<S: Shape>(in shape: S, dark: Bool = false, interactive: Bool = false) -> some View {
        modifier(AppGlassSurface(shape: shape, dark: dark, interactive: interactive))
    }
}

private struct AppGlassSurface<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let shape: S
    let dark: Bool
    let interactive: Bool

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(dark ? AppDesign.dock : Color(uiColor: .systemBackground), in: shape)
        } else {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.tint(dark ? AppDesign.dock.opacity(0.85) : nil)
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
        if dark {
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

struct AppActionStyle: ButtonStyle {
    var fill = AppDesign.primary
    var ink = Color.white

    private var pressedFill: Color {
        if fill == AppDesign.primary { return Color(red: 0, green: 56 / 255, blue: 145 / 255) }
        if fill == AppDesign.danger { return Color(red: 233 / 255, green: 77 / 255, blue: 49 / 255) }
        return fill
    }
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppDesign.subtitle)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(isEnabled && !(configuration.isPressed && fill == AppDesign.danger) ? ink : Color.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 44)
            .background {
                AppDesign.raisedAction(Capsule(), fill: isEnabled ? (configuration.isPressed ? pressedFill : fill) : Color(white: 0.88),
                                       raised: isEnabled && !configuration.isPressed)
            }
            .overlay {
                if configuration.isPressed && isEnabled && fill == pressedFill {
                    Capsule().fill(.black.opacity(0.16)).allowsHitTesting(false)
                }
            }
            .contentShape(Capsule())
    }
}

extension View {
    func appField(focused: Bool, invalid: Bool = false) -> some View {
        self
            .font(AppDesign.body)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(invalid ? AppDesign.fieldError : focused ? AppDesign.focus : Color.secondary,
                                  lineWidth: invalid || focused ? 2 : 1)
                    .allowsHitTesting(false)
            }
    }
}
