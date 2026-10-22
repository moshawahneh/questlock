import ManagedSettings
import UserNotifications

/// iOS calls this extension when the user taps a button on the shield.
/// It can't open the main app itself, so "Check in" posts a notification that opens QuestLock when tapped.
final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(Self.respond(to: action))
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(Self.respond(to: action))
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(Self.respond(to: action))
    }

    private static func respond(to action: ShieldAction) -> ShieldActionResponse {
        if action == .primaryButtonPressed {
            postCheckInNotification()
            SharedStore.log("Shield: Check in tapped, notification sent")
        }
        // Close the blocked app; the user continues from the notification.
        return .close
    }

    private static func postCheckInNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Tap to check in"
        content.body = "Today's quest: \(SharedStore.todayTarget). Post your photo to unlock your apps."
        content.sound = .default
        // A fixed identifier replaces any earlier unread reminder instead of stacking them.
        let request = UNNotificationRequest(identifier: "check-in", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
