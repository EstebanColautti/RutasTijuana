import CoreText
import SwiftUI

enum AppDesign {
    static let navigationMotion = Animation.easeInOut(duration: 0.20)
    static let selectionMotion = Animation.easeOut(duration: 0.16)
    static let header = Color(red: 23 / 255, green: 25 / 255, blue: 30 / 255)
    static let primary = Color(red: 0, green: 80 / 255, blue: 208 / 255)
    static let accent = Color(red: 184 / 255, green: 170 / 255, blue: 1)
    static let dock = Color(red: 38 / 255, green: 38 / 255, blue: 38 / 255)
    static let danger = Color(red: 215 / 255, green: 0, blue: 21 / 255)

    private static let interName: String? = {
        guard let url = Bundle.main.url(forResource: "Inter", withExtension: "ttf", subdirectory: "Typography")
                ?? Bundle.main.url(forResource: "Inter", withExtension: "ttf"),
              let provider = CGDataProvider(url: url as CFURL),
              let font = CGFont(provider),
              let name = font.postScriptName else { return nil }
        CTFontManagerRegisterGraphicsFont(font, nil)
        return name as String
    }()

    static func type(_ size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        if let interName { return .custom(interName, size: size, relativeTo: style).weight(weight) }
        return .system(style, design: .default).weight(weight)
    }
}

enum AppDestination: String, CaseIterable {
    case routes = "Rutas"
    case home = "Inicio"
    case map = "Mapa"

    var icon: String {
        switch self {
        case .routes: return "map"
        case .home: return "house"
        case .map: return "mappin"
        }
    }
}

struct AppDock: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var selection: AppDestination?
    var onSelect: (AppDestination) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppDestination.allCases, id: \.self) { destination in
                Button {
                    onSelect(destination)
                } label: {
                    Image(systemName: destination.icon)
                        .font(.title3)
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
