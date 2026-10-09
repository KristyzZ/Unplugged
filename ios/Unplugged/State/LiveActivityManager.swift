import ActivityKit
import Foundation

/// Mirrors the charging session onto the Lock Screen and Dynamic Island.
/// Countdowns run on wall-clock dates, so they keep ticking with the app
/// closed; phase changes are pushed whenever the app is running.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var lastState: ChargingActivityAttributes.ContentState?

    private var current: Activity<ChargingActivityAttributes>? {
        Activity<ChargingActivityAttributes>.activities.first { $0.activityState == .active }
    }

    func sync(session: ChargingSession?, enabled: Bool, simNow: Date, speed: Double, lang: Lang) {
        guard enabled, let s = session else {
            endAll()
            return
        }
        let state = makeState(s, simNow: simNow, speed: speed)

        if let activity = current {
            guard state != lastState else { return }
            lastState = state
            let content = ActivityContent(state: state, staleDate: nil)
            Task {
                if state.phase == .ended {
                    // Leave the "finished" card up briefly, then clear it.
                    await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(5 * 60)))
                } else {
                    await activity.update(content)
                }
            }
        } else if state.phase != .ended, ActivityAuthorizationInfo().areActivitiesEnabled {
            let attributes = ChargingActivityAttributes(
                stationName: s.stationName,
                connectorLabel: s.connectorLabel,
                lang: lang.rawValue
            )
            do {
                _ = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
                lastState = state
            } catch {
                // Live Activities turned off or unavailable — the app works without them.
            }
        }
    }

    func endAll() {
        lastState = nil
        for activity in Activity<ChargingActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func makeState(_ s: ChargingSession, simNow: Date, speed: Double) -> ChargingActivityAttributes.ContentState {
        let snap = SessionSnapshot(s, now: simNow)
        let now = Date()
        // Convert a simulated-clock date into the wall-clock date it will happen.
        func real(_ d: Date) -> Date { now.addingTimeInterval(d.timeIntervalSince(simNow) / max(speed, 1)) }

        let doneSim = s.doneAt ?? s.scheduledDoneAt
        let chargeStart = real(s.startedAt)
        let chargeEnd = max(real(doneSim), chargeStart.addingTimeInterval(1))
        let graceEnd = max(real(doneSim.addingTimeInterval(Double(s.graceMinutes) * 60)), chargeEnd.addingTimeInterval(1))

        let phase: ChargingActivityAttributes.ContentState.Phase
        switch snap.phase {
        case .charging: phase = .charging
        case .grace: phase = .grace
        case .idle: phase = .idle
        case .ended: phase = .ended
        }

        return .init(
            phase: phase,
            soc: snap.soc.rounded(),
            targetSoc: s.targetSoc,
            chargeStart: chargeStart.roundedToSecond,
            chargeEnd: chargeEnd.roundedToSecond,
            graceEnd: graceEnd.roundedToSecond,
            energyCostEur: (snap.energyCost * 100).rounded() / 100,
            idleRateEurPerMin: IdleFee.currentRate(minutes: snap.idleMinutes)
        )
    }
}

private extension Date {
    /// Avoids pushing an "update" that differs only by milliseconds.
    var roundedToSecond: Date { Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate.rounded()) }
}
