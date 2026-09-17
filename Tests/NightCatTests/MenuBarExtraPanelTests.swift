import AppKit
import XCTest

/// The dismissal path matches two private AppKit/SwiftUI window classes by name.
/// These tests pin the names down so a rename shows up here rather than as a
/// popover that silently stops closing.
@MainActor
final class MenuBarExtraPanelTests: XCTestCase {

    func testRecognisesTheSwiftUIPopoverWindow() {
        XCTAssertTrue(MenuBarExtraPanel.isPanelWindow(className: "SwiftUI.MenuBarExtraWindow"))
        XCTAssertFalse(MenuBarExtraPanel.isPanelWindow(className: "NSWindow"))
        XCTAssertFalse(MenuBarExtraPanel.isPanelWindow(className: "NSStatusBarWindow"))
    }

    func testRecognisesTheStatusBarWindow() {
        XCTAssertTrue(MenuBarExtraPanel.isStatusBarWindow(className: "NSStatusBarWindow"))
        XCTAssertFalse(MenuBarExtraPanel.isStatusBarWindow(className: "NSWindow"))
        XCTAssertFalse(MenuBarExtraPanel.isStatusBarWindow(className: "SwiftUI.MenuBarExtraWindow"))
    }

    // MARK: Which window gets closed

    // These test the selection rather than the closing. An earlier version stood
    // up a real `NSWindow` and asserted it was still visible afterwards, which
    // failed on a headless CI runner for reasons that had nothing to do with the
    // behaviour: `orderFront(nil)` can't show a window with no window server.
    // Replacing the visibility check with a close-recording `NSWindow` subclass
    // was worse — swallowing `close()` breaks AppKit's release-on-close
    // lifecycle and crashes XCTest's memory checker. The thing actually worth
    // pinning down is that only the panel is ever picked, and that needs no
    // windows at all.

    func testPicksThePanelWindowToClose() {
        let windows = ["NSWindow", "NSStatusBarWindow", "SwiftUI.MenuBarExtraWindow", "NSWindow"]
        XCTAssertEqual(MenuBarExtraPanel.panelWindowIndex(classNames: windows), 2)
    }

    /// The point of the old "harmless" test, without the windows: ordinary app
    /// windows are never candidates for closing.
    func testPicksNothingWhenNoPanelIsPresent() {
        XCTAssertNil(MenuBarExtraPanel.panelWindowIndex(
            classNames: ["NSWindow", "NSStatusBarWindow", "NSToolbarWindow", "_NSFullScreenWindow"]
        ))
        XCTAssertNil(MenuBarExtraPanel.panelWindowIndex(classNames: []))
    }

    func testPicksTheFirstPanelWhenSeveralMatch() {
        let windows = ["NSWindow", "SwiftUI.MenuBarExtraWindow", "SwiftUI.MenuBarExtraWindow"]
        XCTAssertEqual(MenuBarExtraPanel.panelWindowIndex(classNames: windows), 1)
    }

    /// One status bar window per screen when "Displays have Separate Spaces" is
    /// on, so the walk has to consider all of them and no one else.
    func testFindsEveryStatusBarWindowAndNothingElse() {
        let windows = ["NSWindow", "NSStatusBarWindow", "SwiftUI.MenuBarExtraWindow", "NSStatusBarWindow"]
        XCTAssertEqual(MenuBarExtraPanel.statusBarWindowIndices(classNames: windows), [1, 3])
        XCTAssertEqual(MenuBarExtraPanel.statusBarWindowIndices(classNames: ["NSWindow"]), [])
    }

    /// The no-match path must fall through quietly rather than trap — the same
    /// path the app takes if these private classes are ever renamed.
    func testDismissWithNoWindowsIsHarmless() {
        MenuBarExtraPanel.dismiss(windows: [])
    }
}
