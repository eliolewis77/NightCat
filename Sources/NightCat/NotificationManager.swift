import AppKit
import Foundation
import UserNotifications

/// UNUserNotificationCenter delegate: shows the banner even when the app is
/// frontmost (menu-bar agent: the "app" is never really looked at, so
/// foreground silence would hide everything forever).
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// Posts system notifications for keep-awake lifecycle events (safety pause,
/// external-clear restore, timer expiry). These must reach the user even when
/// the panel is closed — the UU远程 incident showed panel-only notices go
/// unseen. Authorization is requested once per launch; a denial simply leaves
/// the events panel-only.
enum AppNotifier {
    /// Attach the presentation options. Call once at startup.
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
        Task { _ = await postDelivered(body) }
    }

    /// Posts and reports whether the system accepted the banner — `add` fails
    /// when authorization is pending or denied, in which case nothing will
    /// ever show. Callers that spend a scarce quota on a notification (a
    /// throttle window) must mark it only on `true`.
    static func postDelivered(_ body: String) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = "NightCat"
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }
}
