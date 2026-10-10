import SwiftUI

/// Hover highlight for `.plain` buttons: a low-contrast fill that fades in
/// under the pointer and out when it leaves. Native controls light up as the
/// pointer crosses them; `.buttonStyle(.plain)` strips that away, so the
/// panel's text-like controls (footer buttons, timer chips, the IP row) sit
/// silent under the pointer. This puts the feedback back.
///
/// `Color.primary` at low opacity keeps the fill neutral in both appearances,
/// matching the chips' own selection treatment. `isEnabled: false` freezes it
/// off, for controls whose `.disabled` state the hover gesture can't see.
struct HoverHighlight<S: Shape>: ViewModifier {
    @State private var hovering = false

    let shape: S
    var fillOpacity: Double = 0.08
    var isEnabled = true

    func body(content: Content) -> some View {
        content
            .background(
                shape.fill(Color.primary.opacity(hovering && isEnabled ? fillOpacity : 0))
            )
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverHighlight<S: Shape>(in shape: S,
                                  opacity: Double = 0.08,
                                  isEnabled: Bool = true) -> some View {
        modifier(HoverHighlight(shape: shape, fillOpacity: opacity, isEnabled: isEnabled))
    }
}
