import Foundation
import Sparkle

/// Thin wrapper over Sparkle's standard updater so Settings can offer
/// 「检查更新」. An LSUIElement menu-bar app has no "App ▸ Check for Updates"
/// menu item, so an explicit button in the Settings window is the only entry
/// point. The updater itself reads `SUFeedURL` / `SUPublicEDKey` from
/// Info.plist; until those placeholders are filled in, checks fail quietly —
/// see the one-time setup at the top of `scripts/release.sh`.
@MainActor
final class UpdaterManager: ObservableObject {
    static let shared = UpdaterManager()

    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
