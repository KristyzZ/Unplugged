import Foundation
import UserNotifications

/// Local notifications for charging events. In the foreground the app shows its
/// own banner, so system notifications only go to Notification Center there.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    static let chargeDoneId = "charge-done"
    static let graceOverId = "grace-over"

    private let center = UNUserNotificationCenter.current()

    func setUp() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func schedule(id: String, title: String, body: String, after seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func cancel(_ ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.list, .sound])
    }
}
