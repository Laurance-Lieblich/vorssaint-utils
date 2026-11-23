// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Shared look & feel: brand colors, card styling and the brand mark.
enum Theme {
    /// Near-black background behind the brand mark. Neutral greys into black, no
    /// colour cast, with just a hint of depth so the badge does not read as flat.
    static let spaceGradient = LinearGradient(
        colors: [Color(white: 0.10),
                 Color(white: 0.04),
                 Color.black],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Custom (Laurance): Apple's own adaptive system colors in both appearances,
/// as Control Center and System Settings use, instead of hand-darkened tints
/// in light mode.
enum PanelMetricColor {
    static func green(for scheme: ColorScheme) -> Color { Color(nsColor: .systemGreen) }
    static func cyan(for scheme: ColorScheme) -> Color { Color(nsColor: .systemCyan) }
    static func mint(for scheme: ColorScheme) -> Color { Color(nsColor: .systemMint) }
    static func yellow(for scheme: ColorScheme) -> Color { Color(nsColor: .systemYellow) }
    static func red(for scheme: ColorScheme) -> Color { Color(nsColor: .systemRed) }
    static func orange(for scheme: ColorScheme) -> Color { Color(nsColor: .systemOrange) }
    static func pink(for scheme: ColorScheme) -> Color { Color(nsColor: .systemPink) }
}

/// Custom (Laurance): one set of corner radii for the whole panel, rounder and
/// closer to macOS 26 Control Center modules. Change these to restyle everything.
enum PanelRadius {
    /// Section cards.
    static let card: CGFloat = 16
    /// Buttons, tabs, list rows, inputs.
    static let control: CGFloat = 10
    /// Small chips, badges and icon wells.
    static let small: CGFloat = 8
}

/// Custom (Laurance): the shared motion curve. Quick and springy like the
/// system's own controls, never floaty.
enum PanelMotion {
    static let snappy = Animation.snappy(duration: 0.24, extraBounce: 0.02)
    /// The tab highlight sliding between panel sections: quick, no overshoot.
    static let tab = Animation.snappy(duration: 0.14, extraBounce: 0)
}

/// Custom (Laurance): Apple-style press feedback for every panel button: a
/// slight shrink and dim while pressed, springing back on release. Hovering
/// leaves text untouched (no brightening or weight change); hover feedback
/// comes only from background fills such as `.panelHover()`.
struct PanelPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(PanelMotion.snappy, value: configuration.isPressed)
    }
}

/// Custom (Laurance): a soft fill that fades in under the pointer, like
/// toolbar and Control Center buttons.
private struct PanelHoverModifier: ViewModifier {
    var cornerRadius: CGFloat
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? (colorScheme == .light ? 0.06 : 0.09) : 0))
            )
            .onHover { inside in
                withAnimation(.easeOut(duration: 0.12)) { hovering = inside }
            }
    }
}

/// Custom (Laurance): content that fades in quickly when it first appears.
/// Used when switching panel tabs, so the new section is never seen for the
/// split second before the panel has resized to fit it.
private struct PanelFadeInModifier: ViewModifier {
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .onAppear {
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.14)) { visible = true }
                }
            }
    }
}

/// Custom (Laurance): a Settings page settling into place: a quick fade with
/// a few points of upward drift, like System Settings switching panes.
private struct SettingsPageEntranceModifier: ViewModifier {
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 3)
            .onAppear {
                // Half the previous 0.2 s, matching the panel's faster opening.
                withAnimation(.easeOut(duration: 0.1)) { shown = true }
            }
    }
}

extension View {
    func panelFadeIn() -> some View {
        modifier(PanelFadeInModifier())
    }

    func settingsPageEntrance() -> some View {
        modifier(SettingsPageEntranceModifier())
    }

    func panelHover(cornerRadius: CGFloat = PanelRadius.control) -> some View {
        modifier(PanelHoverModifier(cornerRadius: cornerRadius))
    }
}

private struct NotchPresentationKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var notchPresentation: Bool {
        get { self[NotchPresentationKey.self] }
        set { self[NotchPresentationKey.self] = newValue }
    }
}

enum PanelSurface {
    /// Whether the menu popover hosts the panel across its whole balloon, so the
    /// panel's own surface can reach the arrow (#1030). Only macOS 26 lays the
    /// content out that way. On macOS 15, `hasFullSizeContent` publishes the
    /// full-size safe area but leaves the view at its content size in the frame's
    /// lower-left corner: the popover grows by that safe area, the panel sits off
    /// center, and a band of system material shows along the top and right edges.
    static var popoverHostsFullSizeContent: Bool {
        // Custom (Laurance): the full-size layout showed the same off-center
        // panel described above on Laurance's macOS 26 Mac too (panel pushed to
        // the lower left, a grey band along the top and right). Use the inset
        // layout everywhere: the panel sits centered on the popover's own
        // native material, which is also the most Apple-like look.
        return false
    }

    static func baseFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.68) : Color.black.opacity(0.42)
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        // Custom (Laurance): a touch more body, like Control Center modules.
        scheme == .light ? Color.white.opacity(0.55) : Color.white.opacity(0.08)
    }

    static func controlFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.055) : Color.white.opacity(0.085)
    }

    /// Raised contrast is asked for by someone who cannot see a hairline at a
    /// tenth of an opacity, so the outlines that separate one card from the
    /// next are the ones that answer. A panel is rebuilt every time it opens,
    /// which is when a change to this setting shows.
    static func border(for scheme: ColorScheme) -> Color {
        let raised = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        // Custom (Laurance): softer hairlines; Apple's modules barely outline.
        return scheme == .light
            ? Color.black.opacity(raised ? 0.24 : 0.06)
            : Color.white.opacity(raised ? 0.28 : 0.08)
    }

    /// A control that sits ON a glass surface rather than in it: the system's
    /// own round toggles read as physical because they are lighter than what
    /// is behind them and carry their own shadow.
    static func raisedFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.88) : Color.white.opacity(0.14)
    }

    static func raisedBorder(for scheme: ColorScheme) -> Color {
        let raised = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        return scheme == .light
            ? Color.black.opacity(raised ? 0.22 : 0.07)
            : Color.white.opacity(raised ? 0.32 : 0.16)
    }

    static func raisedShadow(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.14) : Color.black.opacity(0.38)
    }

    /// The lit edge of a glass surface: bright where the light comes from,
    /// gone by the bottom. Without it a translucent panel reads as paper.
    static func rimHighlight(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(colors: [Color.white.opacity(scheme == .light ? 0.95 : 0.30),
                                Color.white.opacity(scheme == .light ? 0.12 : 0.04)],
                       startPoint: .top,
                       endPoint: .bottom)
    }
}

/// Custom (Laurance): panel section headers in Apple's current style:
/// sentence case, semibold, no letter-spaced capitals.
func panelSectionTitle(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(Color.primary.opacity(0.85))
}

func sectionTitle(_ text: String) -> some View {
    Text(text.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .kerning(0.5)
        .foregroundStyle(.secondary)
}

extension View {
    /// The rounded card background used by every panel section. A card
    /// holding a list of rows is not padded: each row brings its own insets,
    /// so hover highlights and separators can reach the card's edges.
    func panelCard(interactive: Bool = true, padded: Bool = true) -> some View {
        modifier(PanelCardModifier(interactive: interactive, padded: padded))
    }

    /// A restrained glass base where the popover hosts full-size content.
    /// Inset content uses the popover's native material; see PanelGlassSurface.
    func panelGlassSurface() -> some View {
        background(PanelGlassSurface())
    }
}

private struct PanelCardModifier: ViewModifier {
    var interactive: Bool
    var padded = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.notchPresentation) private var notchPresentation

    func body(content: Content) -> some View {
        if notchPresentation {
            content.padding(padded ? 12 : 0).modifier(NotchControlSurface(cornerRadius: 18, interactive: interactive))
        } else {
        content
            .padding(padded ? 10 : 0)
            .background(
                RoundedRectangle(cornerRadius: PanelRadius.card, style: .continuous)
                    .fill(PanelSurface.cardFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PanelRadius.card, style: .continuous)
                    .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.5)
            )
        }
    }
}

private struct PanelGlassSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.notchPresentation) private var notchPresentation
    @Environment(\.notchGlassSurface) private var notchGlassSurface
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(DefaultsKey.liquidGlassEnabled) private var liquidGlassEnabled = false

    var body: some View {
        // AppKit hands the hosted panel a safe area for the popover's border and
        // arrow, so a surface that stopped at the panel would leave the tip in the
        // plain system material. The panel content keeps that inset and never sits
        // under the arrow; only this background bleeds into it. The popover clips
        // it to its own balloon, so the surface is a plain rectangle: rounding would
        // expose the system material at the corners, while stroking would duplicate
        // the outline AppKit already draws. Before macOS 26, inset content uses
        // the native popover material alone: a separate rounded card cannot
        // follow the balloon's corners and leaves a second outline (#2225).
        if notchPresentation {
            Rectangle().fill(notchGlassSurface ? Color.clear : .black)
        } else if PanelSurface.popoverHostsFullSizeContent {
            surface.ignoresSafeArea()
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var surface: some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *), liquidGlassEnabled, !reduceTransparency {
            Rectangle()
                .fill(Color.clear)
                .glassEffect(.regular, in: Rectangle())
                .overlay(
                    Rectangle()
                        .fill(PanelSurface.baseFill(for: colorScheme).opacity(colorScheme == .light ? 0.35 : 0.45))
                )
        } else {
            standardSurface
        }
#else
        standardSurface
#endif
    }

    @ViewBuilder
    private var standardSurface: some View {
        Rectangle()
            .fill(.regularMaterial)
            .overlay(Rectangle().fill(PanelSurface.baseFill(for: colorScheme)))
    }
}

func appDelegate() -> AppDelegate? {
    NSApp.delegate as? AppDelegate
}

/// The official mark (Resources/Brand/logo.png, trimmed at build time),
/// tintable for light or dark surfaces.
struct BrandMark: View {
    var width: CGFloat
    var tint: Color = .white

    private static let mark: NSImage? = {
        guard let url = Bundle.main.url(forResource: "BrandMark", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        if let mark = Self.mark {
            Image(nsImage: mark)
                .renderingMode(.template)
                .interpolation(.high)
                .antialiased(true)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(tint)
                .frame(width: width)
        } else {
            Image(systemName: "circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(tint)
                .frame(width: width * 0.5)
        }
    }
}

struct DiscordMark: View {
    var width: CGFloat

    private static let mark: NSImage? = {
        guard let url = Bundle.main.url(forResource: "discord-symbol",
                                        withExtension: "svg",
                                        subdirectory: "Images") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        if let mark = Self.mark {
            Image(nsImage: mark)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: width)
        }
    }
}

/// Squircle badge with the mark on the space gradient — the app's face in the
/// About tab and onboarding.
struct BrandBadge: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(Theme.spaceGradient)
            BrandMark(width: size * 0.8)
        }
        .frame(width: size, height: size)
    }
}
