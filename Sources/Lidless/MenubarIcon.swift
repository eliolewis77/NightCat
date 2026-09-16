import SwiftUI

/// Menu-bar indicator per panel-mockup §1: a laptop outline whose color
/// encodes the tier, an optional countdown text to its right, and an optional
/// lock badge pinned to the icon's bottom-right corner.
///
/// Drawn in code rather than image assets: the four tier colors are the
/// signal, and a shape can be tinted per-mode (and per color scheme) without
/// shipping one bitmap per combination.
enum MenubarStyle {
    /// Tier colors (panel-mockup §1). The off-gray is the one value that
    /// fails contrast on a light menu bar, so it (alone) has a light variant;
    /// blue/teal/orange carry enough saturation to read on both.
    static func tierColor(_ mode: KeepAwakeMode, colorScheme: ColorScheme) -> Color {
        switch mode {
        case .off:
            return colorScheme == .dark
                ? Color(red: 0.706, green: 0.698, blue: 0.663)   // #B4B2A9
                : Color(red: 0.435, green: 0.427, blue: 0.388)   // #6F6D63
        case .screen:      return Color(red: 0.522, green: 0.718, blue: 0.922)   // #85B7EB
        case .preventIdle: return Color(red: 0.365, green: 0.796, blue: 0.647)   // #5DCAA5
        case .lidClosed:   return Color(red: 0.937, green: 0.624, blue: 0.153)   // #EF9F27
        }
    }

    /// Countdown rules (panel-mockup §1 table): shown only when a timer runs,
    /// except the lid tier where it's forced — that tier most needs to be
    /// seen — and reads 持续 when no timer is set.
    static func countdownText(mode: KeepAwakeMode, autoOffRemaining: String) -> String? {
        if !autoOffRemaining.isEmpty { return autoOffRemaining }
        return mode == .lidClosed ? "持续" : nil
    }
}

/// The laptop mark from the mockup's SVG (viewBox 22×15): a rounded screen
/// rect over a trapezoid base — the "lid" shape the whole app is named around.
struct LaptopShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Design space: 22×15. Scaled to fit `rect`, preserving aspect.
        let unit = min(rect.width / 22, rect.height / 15)
        let w = 22 * unit, h = 15 * unit
        let ox = rect.midX - w / 2, oy = rect.midY - h / 2
        var p = Path()
        p.addRoundedRect(
            in: CGRect(x: ox + 4 * unit, y: oy + 1.8 * unit,
                       width: 14 * unit, height: 9 * unit),
            cornerSize: CGSize(width: 1.8 * unit, height: 1.8 * unit)
        )
        p.move(to: CGPoint(x: ox + 1.6 * unit, y: oy + 13.2 * unit))
        p.addLine(to: CGPoint(x: ox + 20.4 * unit, y: oy + 13.2 * unit))
        p.addLine(to: CGPoint(x: ox + 18.8 * unit, y: oy + 10.8 * unit))
        p.addLine(to: CGPoint(x: ox + 3.2 * unit, y: oy + 10.8 * unit))
        p.closeSubpath()
        return p
    }
}

/// A closed padlock in the tier's own color on a bar-tinted backing circle,
/// pinned bottom-right of the icon (panel-mockup §1 ⑤⑦).
private struct LockBadge: View {
    let color: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 7.5, weight: .semibold))
            .foregroundColor(color)
            .padding(1.5)
            .background(
                Circle().fill(colorScheme == .dark
                    ? Color.black.opacity(0.55)
                    : Color.white.opacity(0.7))
            )
    }
}

/// The whole menu-bar cluster: icon (+ lock badge) + optional countdown text.
struct MenubarIndicator: View {
    let mode: KeepAwakeMode
    let autoOffRemaining: String
    let isModeLocked: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var tierColor: Color {
        MenubarStyle.tierColor(mode, colorScheme: colorScheme)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            LaptopShape()
                .stroke(tierColor, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(width: 21, height: 14.5)
                .overlay(alignment: .bottomTrailing) {
                    if isModeLocked {
                        LockBadge(color: tierColor)
                            .offset(x: 6.5, y: 4)
                    }
                }

            if let text = MenubarStyle.countdownText(mode: mode,
                                                     autoOffRemaining: autoOffRemaining) {
                Text(text)
                    .font(.system(size: 11.5, weight: .regular).monospacedDigit())
                    .foregroundStyle(.primary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = ["NightCat", mode.displayName]
        if !autoOffRemaining.isEmpty { parts.append("剩余 \(autoOffRemaining)") }
        else if mode == .lidClosed { parts.append("持续") }
        if isModeLocked { parts.append("已锁定") }
        return parts.joined(separator: "，")
    }
}
