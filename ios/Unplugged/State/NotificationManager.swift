import Foundation
import UserNotifications

/// Local notifications for charging events. In the foreground the app shows its
/// own banner, so system notifications only go to Notification Center there.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    static let chargeDoneId = "charge-done"
    static let graceOverId = "grace-over"

    private let center = UNUserNotificationCenter.current()
    /// The notification center talks to a system service and some calls wait
    /// for its reply. Keep them off the main thread so a slow or restarting
    /// service can never freeze the UI (it did at launch in the simulator).
    /// Serial, so a cancel always runs before the schedule that follows it.
    private let queue = DispatchQueue(label: "unplugged.notifications", qos: .utility)

    func setUp() {
        center.delegate = self
        queue.async { [center] in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    func schedule(id: String, title: String, body: String, after seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        queue.async { [center] in center.add(request) }
    }

    func cancel(_ ids: [String]) {
        queue.async { [center] in center.removePendingNotificationRequests(withIdentifiers: ids) }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.list, .sound])
    }
}
