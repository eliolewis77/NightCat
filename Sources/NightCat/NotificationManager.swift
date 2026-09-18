import AppKit
import Foundation
import UserNotifications

/// Posts system notifications for keep-awake lifecycle events (safety pause,
/// external-clear restore, timer expiry). These must reach the user even when
/// the panel is closed — the UU远程 incident showed panel-only notices go
/// unseen. Authorization is requested once per launch; a denial simply leaves
/// the events panel-only.
/// Routes notification taps. The purchase nudge opens the Gumroad page.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if response.notification.request.content.categoryIdentifier == "PURCHASE" {
            NSWorkspace.shared.open(LicenseManager.purchaseURL)
        }
    }

    // Show the banner even when the app is frontmost (menu-bar agent: the
    // "app" is never really looked at, so foreground silence would hide
    // everything forever).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

enum AppNotifier {
    /// Attach the tap router and banner options. Call once at startup.
    static func install() {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }

    static func requestAuthorizationIfNeeded() {
        Task { @MainActor in
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        }
    }

    /// Fire-and-forget. Duplicates are acceptable (each event carries its own
    /// identity), and every current caller fires at most once per incident.
    static func post(_ body: String) {
        let content = UNMutableNotificationContent()
        content.title = "NightCat"
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
