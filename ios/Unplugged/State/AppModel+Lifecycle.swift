import Foundation
#if os(iOS)
import UIKit
#endif

#if os(iOS)
/// Background time asked for while a session runs with the app closed.
@MainActor private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

extension AppModel {
    // MARK: Lock Screen buttons

    /// Buttons on the Lock Screen / Dynamic Island run in this process.
    func listenForLockScreenActions() {
        ChargingActionInbox.handler = { [weak self] action in self?.handle(action) }
        takePendingAction()
    }

    /// An action pressed on the Live Activity while the app wasn't running.
    func takePendingAction() {
        if let action = ChargingActionInbox.take() { handle(action) }
    }

    func handle(_ action: ChargingAction) {
        switch action {
        case .moved: leaveSpot()
        case .stop: stopCharging()
        case .releaseHold: releaseHold()
        }
    }

    // MARK: App in the background

    /// Live Activities can't change by themselves at an exact time, so when the
    /// app is sent away mid-session it asks for the usual ~30 s of background
    /// time. A phase change inside that window (charging done, free time over)
    /// still updates the Lock Screen right on time.
    func enteredBackground() {
        guard hasActiveSession, backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "charging-session") { [weak self] in
            self?.endBackgroundTime()
        }
        checkBackgroundTime()
    }

    func becameActive() {
        endBackgroundTime()
        takePendingAction()
        checkQueueAndHolds()
        refreshStations()
        // Back while the car is due to move: show the session first.
        if let s = session, s.endedAt == nil, s.doneAt != nil {
            tab = .charging
        }
    }

    func endBackgroundTime() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// Gives the background time back as soon as nothing will happen within it.
    func checkBackgroundTime() {
        guard backgroundTask != .invalid else { return }
        guard let s = session, s.endedAt == nil else { return endBackgroundTime() }
        let done = s.doneAt ?? s.scheduledDoneAt
        let graceEnd = done.addingTimeInterval(Double(s.graceMinutes) * 60)
        let next = [done, graceEnd].map(realDate).filter { $0 > Date() }.min()
        let remaining = UIApplication.shared.backgroundTimeRemaining
        if next == nil || next!.timeIntervalSinceNow > remaining - 2 {
            endBackgroundTime()
        }
    }
}
#else
// Non-iOS builds (the macOS persistence check harness) have no app lifecycle.
extension AppModel {
    func checkBackgroundTime() {}
}
#endif
