import ActivityKit
import Foundation

/// Mirrors the charging session onto the Lock Screen and Dynamic Island.
/// Countdowns run on wall-clock dates, so they keep ticking with the app
/// closed; phase changes are pushed whenever the app is running.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var lastState: ChargingActivityAttributes.ContentState?
    /// Activities we've asked to end. Ending is asynchronous, so they can still
    /// report `.active` for a moment and must not be picked up again.
    private var ending: Set<String> = []

    private func current(for session: ChargingSession) -> Activity<ChargingActivityAttributes>? {
        for activity in Activity<ChargingActivityAttributes>.activities
        where activity.activityState == .active && !ending.contains(activity.id) {
            // Compare loosely: dates may lose precision on the way through the system.
            if abs(activity.attributes.sessionStart.timeIntervalSince(session.startedAt)) < 1 { return activity }
            // Left over from an earlier session.
            end(activity)
        }
        return nil
    }

    func sync(session: ChargingSession?, enabled: Bool, simNow: Date, speed: Double, lang: Lang) {
        guard enabled, let s = session else {
            endAll()
            return
        }
        let state = makeState(s, simNow: simNow, speed: speed)

        if let activity = current(for: s) {
            guard state != lastState else { return }
            lastState = state
            let content = ActivityContent(state: state, staleDate: state.staleDate)
            Task {
                if state.phase != .ended {
                    await activity.update(content)
                }
            }
            if state.phase == .ended {
                // Leave the receipt up for a while, then clear it.
                ending.insert(activity.id)
                Task { await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(15 * 60))) }
            }
        } else if state.phase != .ended, ActivityAuthorizationInfo().areActivitiesEnabled {
            let attributes = ChargingActivityAttributes(
                sessionStart: s.startedAt,
                stationName: s.stationName,
                connectorLabel: s.connectorLabel,
                lang: lang.rawValue
            )
            do {
                _ = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: state.staleDate),
                    pushType: nil
                )
                lastState = state
            } catch {
                // Live Activities turned off or unavailable — the app works without them.
            }
        }
    }

    /// Clears everything at once, including a receipt left up after the session.
    func endAll() {
        lastState = nil
        for activity in Activity<ChargingActivityAttributes>.activities {
            end(activity)
        }
    }

    private func end(_ activity: Activity<ChargingActivityAttributes>) {
        ending.insert(activity.id)
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
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

        func cents(_ v: Double) -> Double { (v * 100).rounded() / 100 }
        // Stopped early: the bar and labels end where charging did.
        let target = s.doneAt != nil ? snap.soc.rounded() : s.targetSoc
        let total: Double
        let points: Int
        switch phase {
        case .ended:
            total = snap.chargingCost + snap.idleFee
            points = s.pointsEarned ?? 0
        case .charging:
            total = s.plannedCost
            points = PointsReason.movedFast.points
        case .grace, .idle:
            total = snap.chargingCost
            points = PointsReason.movedFast.points
        }

        return .init(
            phase: phase,
            soc: snap.soc.rounded(),
            startSoc: s.startSoc.rounded(),
            targetSoc: target,
            chargeStart: chargeStart.roundedToSecond,
            chargeEnd: chargeEnd.roundedToSecond,
            graceEnd: graceEnd.roundedToSecond,
            powerKw: s.averageKw.rounded(),
            energyCostEur: cents(snap.chargingCost),
            totalEur: cents(total),
            idleRateEurPerMin: s.appliedFeePolicy.currentRate(minutes: snap.idleMinutes),
            idleFeeEur: cents(snap.idleFee),
            points: points,
            handedOver: s.handedOver
        )
    }
}

private extension Date {
    /// Avoids pushing an "update" that differs only by milliseconds.
    var roundedToSecond: Date { Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate.rounded()) }
}
