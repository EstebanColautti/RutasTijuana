import CoreText
import SwiftUI

enum AppDesign {
    static let navigationMotion = Animation.easeInOut(duration: 0.20)
    static let selectionMotion = Animation.easeOut(duration: 0.16)
    static let header = Color(red: 23 / 255, green: 25 / 255, blue: 30 / 255)
    static let primary = Color(red: 0, green: 80 / 255, blue: 208 / 255)
    static let accent = Color(red: 184 / 255, green: 170 / 255, blue: 1)
    static let dock = Color(red: 38 / 255, green: 38 / 255, blue: 38 / 255)
    static let routeInk = Color(red: 0.25, green: 0.16, blue: 0.80)
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
                path.move(to: CGPoint(x: 2, y: 4))
                path.addLines([CGPoint(x: 8, y: 2), CGPoint(x: 16, y: 5), CGPoint(x: 22, y: 3),
                               CGPoint(x: 22, y: 20), CGPoint(x: 16, y: 22), CGPoint(x: 8, y: 19),
                               CGPoint(x: 2, y: 21)])
                path.closeSubpath()
                path.move(to: CGPoint(x: 8, y: 2))
                path.addLine(to: CGPoint(x: 8, y: 19))
                path.move(to: CGPoint(x: 16, y: 5))
                path.addLine(to: CGPoint(x: 16, y: 22))
            case .home:
                path.addLines([CGPoint(x: 2, y: 11), CGPoint(x: 12, y: 2), CGPoint(x: 22, y: 11)])
                path.move(to: CGPoint(x: 5, y: 9))
                path.addLines([CGPoint(x: 5, y: 22), CGPoint(x: 10, y: 22), CGPoint(x: 10, y: 15),
                               CGPoint(x: 14, y: 15), CGPoint(x: 14, y: 22), CGPoint(x: 19, y: 22),
                               CGPoint(x: 19, y: 9)])
            case .map:
                path.move(to: CGPoint(x: 12, y: 22))
                path.addQuadCurve(to: CGPoint(x: 4, y: 10), control: CGPoint(x: 4, y: 15))
                path.addQuadCurve(to: CGPoint(x: 12, y: 2), control: CGPoint(x: 4, y: 2))
                path.addQuadCurve(to: CGPoint(x: 20, y: 10), control: CGPoint(x: 20, y: 2))
                path.addQuadCurve(to: CGPoint(x: 12, y: 22), control: CGPoint(x: 20, y: 15))
                path.closeSubpath()
                path.addEllipse(in: CGRect(x: 10, y: 7, width: 4, height: 4))
            }
        }
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
    }
}

struct AppDock: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var iconSize = 19.0
    var selection: AppDestination?
    var onSelect: (AppDestination) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppDestination.allCases, id: \.self) { destination in
                Button {
                    onSelect(destination)
                } label: {
                    VStack(spacing: 2) {
                        DockIcon(destination: destination)
                            .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .frame(width: iconSize, height: iconSize)
                            .accessibilityHidden(true)
                        Text(destination.rawValue)
                            .font(.caption2.weight(.medium))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                        .frame(maxWidth: .infinity, minHeight: 44)
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
        .foregroundStyle(.white)
        .padding(4)
        .appGlass(in: Capsule(), dark: true)
        .padding(.horizontal, 28)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("app-dock")
    }
}

private struct AppDestinationAction: EnvironmentKey {
    static let defaultValue: ((AppDestination) -> Void)? = nil
}

extension EnvironmentValues {
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
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppDesign.subtitle)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(isEnabled ? Color.white : Color.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 44)
            .background {
                Capsule().fill(isEnabled ? fill : Color(white: 0.88))
            }
            .overlay {
                if configuration.isPressed && isEnabled {
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
