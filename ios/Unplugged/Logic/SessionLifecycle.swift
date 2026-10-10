import Foundation

/// Stable event contract for later queue and analytics consumers. `at` is simulated
/// session time; `recordedAt` is wall-clock observation time, never operator telemetry.
struct SessionEvent: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case started, completed, released }
    let sessionId: String
    let stationId: String
    let connectorId: String?
    let kind: Kind
    let at: Date
    let recordedAt: Date
    let points: Int
    var id: String { "\(sessionId):\(kind.rawValue)" }
}

/// Pure notification timing, shared by scheduling and boundary tests.
enum SessionNotificationPlan {
    enum Kind: String { case completed, warning, idleStarted }
    struct Item: Equatable {
        let id: String
        let kind: Kind
        let after: TimeInterval
    }

    static func ids(for session: ChargingSession) -> [String] {
        [Kind.completed, .warning, .idleStarted].map { "session:\(session.id):\($0.rawValue)" }
    }

    static func items(for s: ChargingSession, now: Date, speed: Double) -> [Item] {
        guard s.endedAt == nil else { return [] }
        let done = s.doneAt ?? s.scheduledDoneAt
        let graceEnd = done.addingTimeInterval(Double(s.graceMinutes) * 60)
        let warning = graceEnd.addingTimeInterval(-min(120, Double(s.graceMinutes) * 60))
        let dates: [(Kind, Date)] = (s.doneAt == nil ? [(.completed, done)] : [])
            + [(.warning, warning), (.idleStarted, graceEnd)]
        return dates.compactMap { kind, date in
            guard date > now else { return nil }
            return Item(id: "session:\(s.id):\(kind.rawValue)", kind: kind,
                        after: date.timeIntervalSince(now) / max(1, speed))
        }
    }
}
