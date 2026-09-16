import SwiftUI

@main
struct LidlessApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(state)
        } label: {
            Image(state.isActive ? "MenubarLaptopActive" : "MenubarLaptop")
        }
        .menuBarExtraStyle(.window)
        // No `Settings` scene: it doesn't reliably surface in an LSUIElement app
        // (issue #22). `AppState.showSettings()` presents it via AppKit instead.
    }
}
