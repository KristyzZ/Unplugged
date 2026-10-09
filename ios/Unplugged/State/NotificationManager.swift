import Foundation
import UserNotifications

/// Local notifications for charging events. In the foreground the app shows its
/// own banner, so system notifications only go to Notification Center there.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    static let chargeDoneId = "charge-done"
    static let graceOverId = "grace-over"
    /// Charging notifications carry an "I moved my car" button.
    static let moveCategory = "charging.move"
    static let movedAction = "moved"
    static let holdReadyId = "hold-ready"
    static let holdEndingId = "hold-ending"
    /// Held-spot notifications carry a "Release spot" button.
    static let holdCategory = "queue.hold"
    static let releaseAction = "release"

    private let center = UNUserNotificationCenter.current()
    /// The notification center talks to a system service and some calls wait
    /// for its reply. Keep them off the main thread so a slow or restarting
    /// service can never freeze the UI (it did at launch in the simulator).
    /// Serial, so a cancel always runs before the schedule that follows it.
    private let queue = DispatchQueue(label: "unplugged.notifications", qos: .utility)

    func setUp() {
        center.delegate = self
        registerCategories()
        queue.async { [center] in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    /// Call again after the language changes so the button title follows it.
    func registerCategories() {
        // No `.foreground` option: the press is handled in the background,
        // the Lock Screen activity updates, and the phone stays locked.
        let moved = UNNotificationAction(identifier: Self.movedAction, title: tr("I moved my car"), options: [])
        let category = UNNotificationCategory(identifier: Self.moveCategory, actions: [moved], intentIdentifiers: [])
        let release = UNNotificationAction(identifier: Self.releaseAction, title: tr("Release spot"), options: [.destructive])
        let hold = UNNotificationCategory(identifier: Self.holdCategory, actions: [release], intentIdentifiers: [])
        queue.async { [center] in center.setNotificationCategories([category, hold]) }
    }

    func schedule(id: String, title: String, body: String, after seconds: TimeInterval, category: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category { content.categoryIdentifier = category }
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action: ChargingAction? = switch response.actionIdentifier {
        case Self.movedAction: .moved
        case Self.releaseAction: .releaseHold
        default: nil
        }
        guard let action else {
            completionHandler()
            return
        }
        Task { @MainActor in
            ChargingActionInbox.deliver(action)
            completionHandler()
        }
    }
}
