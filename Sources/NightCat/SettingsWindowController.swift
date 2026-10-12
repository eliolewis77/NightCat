import AppKit
import SwiftUI

/// Hosts the Settings window in a standalone AppKit window.
///
/// NightCat is an `LSUIElement` menu-bar app with no Dock presence, so SwiftUI's
/// `Settings` scene doesn't reliably surface: `SettingsLink` (macOS 14+) never
/// activates an accessory app, and the `showSettingsWindow:` selector isn't a
/// dependable way to present the scene. A plain `NSWindow` gives precise control
/// over showing, focusing, and closing — the same reasoning as
/// `OnboardingController`.
///
/// The content arrives as a view factory rather than a concrete view, so this
/// file depends only on AppKit/SwiftUI and can be compiled into the unit-test
/// bundle (which can't link the app target).
@MainActor
final class SettingsWindowController {
    private let title: String
    private let contentSize: CGSize
    private let frameAutosaveName: String
    private let makeContent: () -> AnyView

    private(set) var window: NSWindow?
    /// Whether `show` switched the app to `.regular` for this window (see
    /// there), so closing it goes back to `.accessory`. Never set in a host
    /// that is already regular — the unit-test runner — which keeps the tests
    /// policy-free.
    private var promotedToRegular = false
    private var closeObserver: NSObjectProtocol?

    init(title: String = "NightCat Settings",
         contentSize: CGSize,
         frameAutosaveName: String = "NightCatSettingsWindow",
         makeContent: @escaping () -> AnyView) {
        self.title = title
        self.contentSize = contentSize
        self.frameAutosaveName = frameAutosaveName
        self.makeContent = makeContent
    }

    /// Show the window, building it on first use and reusing it afterwards so we
    /// never stack duplicates.
    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: makeContent())
            let win = NSWindow(contentViewController: hosting)
            win.title = title
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.isReleasedWhenClosed = false
            // Follow the user to whichever Space they're on; without this the
            // window can re-open on the Space it was last shown and read as
            // "Settings did nothing".
            win.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            // An accessory app deactivates constantly; don't vanish with it.
            win.hidesOnDeactivate = false
            // The hosting controller's fitting size isn't resolved before the
            // window is displayed, so state the size rather than inherit it.
            win.setContentSize(contentSize)
            // Center on creation, then let the autosave name remember wherever
            // the user drags it. Setting the name last means a saved frame wins.
            win.center()
            win.setFrameAutosaveName(frameAutosaveName)
            // Without this, AppKit's initial key-view walk lands on a control —
            // observed: the schedule's time picker, its hour segment selected
            // and the Form auto-scrolled down to reveal it. Pointing the walk
            // at the hosting view means no control owns focus until clicked.
            win.initialFirstResponder = win.contentView
            window = win
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: win, queue: .main
            ) { [weak self] _ in
                self?.releaseActivationPromotion()
            }
        }

        // An accessory app cannot reliably win key any other way on modern
        // macOS: cooperative `activate()` declines requests that don't ride a
        // user event on the app itself, and by the time the settings button
        // runs, the menu-bar panel is about to hand activation to whatever
        // app had it before. Momentarily becoming a regular app makes the
        // request land — the standard menu-bar-app pattern for surfacing one
        // real window. The Dock icon and Cmd+Tab entry exist for exactly as
        // long as the window is up, and `releaseActivationPromotion` takes
        // them back on close.
        if NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
            promotedToRegular = true
        }

        // The window is reused across close/open: a control that held the
        // field editor when the user last closed it (e.g. mid-edit on a time
        // picker) would resurface with its segment still selected. Every open
        // starts from a clean slate.
        window?.makeFirstResponder(nil)

        window?.makeKeyAndOrderFront(nil)
        // SwiftUI's Form assigns initial focus to a control of its own
        // choosing once the window keys — observed: the schedule's time
        // picker, hour segment selected, the form auto-scrolled to reveal it.
        // The hosting view is the neutral first responder: no control owns
        // focus until the user clicks one.
        window?.makeFirstResponder(window?.contentView)

        if #available(macOS 14.0, *) {
            NSApplication.shared.activate()
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        // The policy change registers with the window server across a
        // runloop tick; re-asserting once it has keeps first-open focus from
        // falling into that gap.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.isVisible else { return }
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(window.contentView)
            if #available(macOS 14.0, *) {
                NSApplication.shared.activate()
            } else {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }

    func close() {
        window?.close()
    }

    deinit {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
    }

    /// Undo `show`'s policy promotion when the window goes away — a menu-bar
    /// app that stayed regular would keep a Dock icon and a Cmd+Tab entry
    /// for nothing.
    private func releaseActivationPromotion() {
        guard promotedToRegular else { return }
        promotedToRegular = false
        NSApp.setActivationPolicy(.accessory)
    }
}
