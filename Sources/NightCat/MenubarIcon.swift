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

    /// Countdown text: only when a timer is actually running. No placeholder
    /// for indefinite holds — the tier name already says what's happening.
    static func countdownText(autoOffRemaining: String) -> String? {
        autoOffRemaining.isEmpty ? nil : autoOffRemaining
    }
}

/// The cat-head mark (echoes the app icon): a round head with two triangular
/// ears, filled in the tier color — silhouette reads better than stroke at
/// status-item size.
struct CatShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Design space: 20×18. Head circle + two ear triangles as one Path.
        let unit = min(rect.width / 20, rect.height / 18)
        let w = 20 * unit, h = 18 * unit
        let ox = rect.midX - w / 2, oy = rect.midY - h / 2
        var p = Path()
        let headR = 6.5 * unit
        let headC = CGPoint(x: ox + 10 * unit, y: oy + 11 * unit)
        p.addEllipse(in: CGRect(x: headC.x - headR, y: headC.y - headR,
                                width: headR * 2, height: headR * 2))
        // Left ear, then right ear.
        p.move(to: CGPoint(x: ox + 4.4 * unit, y: oy + 8 * unit))
        p.addLine(to: CGPoint(x: ox + 3.6 * unit, y: oy + 0.6 * unit))
        p.addLine(to: CGPoint(x: ox + 9.2 * unit, y: oy + 5.6 * unit))
        p.closeSubpath()
        p.move(to: CGPoint(x: ox + 15.6 * unit, y: oy + 8 * unit))
        p.addLine(to: CGPoint(x: ox + 16.4 * unit, y: oy + 0.6 * unit))
        p.addLine(to: CGPoint(x: ox + 10.8 * unit, y: oy + 5.6 * unit))
        p.closeSubpath()
        return p
    }
}

/// A closed padlock pinned to the cat's forehead when the mode is locked
/// (panel-mockup §1 ⑤⑦). White, no backing — reads as cut out of the
/// silhouette.
private struct LockBadge: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 6, weight: .semibold))
            .foregroundColor(.white)
    }
}

/// The menu-bar mark: the tier-colored cat, plus a lock badge pinned to the
/// icon's bottom-right corner when the mode is locked. Countdown text lives
/// in the panel's status row, not the menu bar.
///
/// Rasterized via `ImageRenderer` before reaching `MenuBarExtra`'s label:
/// a `MenuBarExtra` label reliably renders `Image`/`Text`, but composite
/// Shape-based views can come out empty on the status item (seen on macOS 26).
/// Rendering to `NSImage` on every body evaluation keeps it working and stays
/// cheap — the label only re-renders when the tier/timer/lock actually change.
struct MenubarIndicator: View {
    let mode: KeepAwakeMode
    let autoOffRemaining: String
    let isModeLocked: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var tierColor: Color {
        MenubarStyle.tierColor(mode, colorScheme: colorScheme)
    }

    var body: some View {
        Image(nsImage: renderedImage)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
    }

    private var renderedImage: NSImage {
        let renderer = ImageRenderer(content: cluster)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage ?? NSImage()
    }

    private var cluster: some View {
        CatShape()
            .fill(tierColor)
            .frame(width: 22, height: 20)
            .overlay {
                if isModeLocked {
                    LockBadge()
                        .offset(y: 2)
                }
            }
            .padding(.vertical, 1)
            .fixedSize()
    }

    private var accessibilitySummary: String {
        var parts = ["NightCat", mode.displayName]
        if isModeLocked { parts.append(NSLocalizedString("已锁定", comment: "a11y; locked")) }
        return parts.joined(separator: "，")
    }
}
