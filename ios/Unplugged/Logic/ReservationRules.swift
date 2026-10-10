import Foundation

enum ReservationRules {
    static let arrivalWindow: TimeInterval = 10 * 60
    static let bookingHorizon: TimeInterval = 24 * 60 * 60

    static func validStart(_ start: Date, now: Date) -> Bool {
        let delay = start.timeIntervalSince(now)
        return delay.isFinite && delay >= 0 && delay <= bookingHorizon
    }

    static func deadline(start: Date) -> Date { start.addingTimeInterval(arrivalWindow) }

    static func overlaps(start: Date, end: Date, otherStart: Date, otherEnd: Date) -> Bool {
        start < otherEnd && otherStart < end
    }
}

enum ReservationNotificationPlan {
    enum Kind { case ready, ending, expired }
    struct Item { let id: String; let kind: Kind; let after: TimeInterval }
    static let ids = ["hold-ready", "hold-ending", "hold-expired"]

    static func items(for hold: SpotHold, now: Date, speed: Double) -> [Item] {
        guard hold.releasedAt == nil, hold.until > now, speed.isFinite, speed > 0 else { return [] }
        let dates: [(String, Kind, Date)] = [
            (ids[0], .ready, hold.startedAt),
            (ids[1], .ending, hold.until.addingTimeInterval(-60)),
            (ids[2], .expired, hold.until)
        ]
        return dates.compactMap { id, kind, date in
            guard date > now else { return nil }
            return Item(id: id, kind: kind, after: max(1, date.timeIntervalSince(now) / speed))
        }
    }
}
