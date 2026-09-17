import SwiftUI

/// Bridge between AppKit's terminate sequence and the SwiftUI-owned
/// `AppState`. The adaptor's lifecycle isn't ordered against `@StateObject`,
/// so `AppState` registers itself here on init instead.
@MainActor
enum ExitRestoreBridge {
    static weak var appState: AppState?
}

@main
struct NightCatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(state)
        } label: {
            // Panel-mockup §1: tier color + optional countdown + lock badge.
            // `mode` (the live tier), not `controlMode`: the bar shows what
            // the Mac is actually doing, and in auto mode that can differ
            // from the armed intent the picker displays.
            MenubarIndicator(mode: state.mode,
                             autoOffRemaining: state.autoOffRemaining,
                             isModeLocked: state.isModeLocked)
        }
        .menuBarExtraStyle(.window)
        // No `Settings` scene: it doesn't reliably surface in an LSUIElement app
        // (issue #22). `AppState.showSettings()` presents it via AppKit instead.
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// A normal quit restores the pre-takeover baseline (SPEC §9) before the
    /// process goes away. Crashes never reach this — the helper's watchdog
    /// handles those.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        ExitRestoreBridge.appState?.restoreOnExit() ?? .terminateNow
    }
}
