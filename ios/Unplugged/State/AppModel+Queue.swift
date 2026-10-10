import Foundation

struct QueueEntry: Codable, Equatable {
    let stationId: String
    let joinedAt: Date
    /// Your place in line; 1 = next.
    var position: Int
    /// Simulated-clock time the next car is expected to leave. Optional so
    /// older saved queues still decode.
    var nextEventAt: Date? = nil
}

extension AppModel {
    /// A spot held for you right now.
    var myHold: SpotHold? { holds.first { $0.forMe } }

    /// Marks the held chargers as reserved on the current station list. Applied last, so a hold is
    /// never hidden by the "just released" overlay of the session that handed the spot over.
    func applyHolds() {
        for hold in holds {
            guard let si = stations.firstIndex(where: { $0.id == hold.stationId }),
                  let ci = stations[si].connectors.firstIndex(where: { $0.id == hold.connectorId }) else { continue }
            stations[si].connectors[ci].status = .reserved
            stations[si].connectors[ci].idleMinutes = nil
            stations[si].connectors[ci].etaMinutes = nil
        }
    }

    func openStation(_ id: String) {
        tab = .explore
        openStationId = id
    }

    // MARK: Queue

    func joinQueue(_ station: Station) {
        let hour = Calendar.current.component(.hour, from: .now)
        // Busier station, more people ahead (1–3). The first car is due when the
        // soonest charging session there is expected to end.
        let position = 1 + min(2, Int(station.demandLevel(hour: hour) * 3))
        let soonest = Double(station.connectors.compactMap(\.etaMinutes).min() ?? 8)
        queue = QueueEntry(
            stationId: station.id, joinedAt: .now, position: position,
            nextEventAt: simNow().addingTimeInterval(min(15, max(3, soonest)) * 60)
        )
        save()
        rescheduleQueueNotifications()
        showBanner(tr("You joined the queue"), tr("\(station.name): we'll hold the next free spot for you."))
    }

    func leaveQueue() {
        queue = nil
        save()
        rescheduleQueueNotifications()
    }

    // MARK: Held spots

    /// Give up the spot held for you; it goes to the next driver.
    func releaseHold() {
        guard myHold != nil else { return }
        holds.removeAll { $0.forMe }
        refreshStations()
        save()
        rescheduleQueueNotifications()
        showBanner(tr("Spot released"), tr("It goes to the next driver in line."))
    }

    /// The car left: if someone is waiting here, keep this charger for them.
    func handOverSpot(_ s: ChargingSession, at now: Date) -> Bool {
        guard let station = stations.first(where: { $0.id == s.stationId }) else { return false }
        guard someoneWaitingAt(station) else { return false }
        let connector = station.connectors.first { $0.id == s.connectorId } ?? station.connectors[0]
        holds.removeAll { $0.id == "\(station.id)|\(connector.id)" }
        holds.append(SpotHold(
            stationId: station.id, stationName: station.name, connectorId: connector.id,
            connectorLabel: "\(connector.type.label) · \(Int(connector.powerKw)) kW",
            startedAt: now, until: now.addingTimeInterval(SpotHold.minutes * 60), forMe: false
        ))
        refreshStations()
        return true
    }

    /// Moves the queue along and lets holds run out. Runs with the session loop.
    func checkQueueAndHolds() {
        let now = simNow()

        let expired = holds.filter { $0.until <= now }
        if !expired.isEmpty {
            holds.removeAll { $0.until <= now }
            refreshStations()
            save()
            if expired.contains(where: \.forMe) {
                rescheduleQueueNotifications()
                showBanner(tr("Your held spot was passed on"), tr("The \(Int(SpotHold.minutes)) minutes ran out, so it went to the next driver."))
            }
        }

        guard var q = queue, myHold == nil, let next = q.nextEventAt, now >= next else { return }
        guard let station = stations.first(where: { $0.id == q.stationId }) else {
            queue = nil
            return
        }
        if q.position > 1 {
            // A car left, but someone ahead of you gets that spot.
            q.position -= 1
            q.nextEventAt = next.addingTimeInterval(Double(3 + 2 * q.position) * 60)
            queue = q
            save()
            rescheduleQueueNotifications()
            showBanner(tr("You moved up"), q.position == 1 ? tr("You're next at \(station.name).") : tr("\(q.position) in line at \(station.name)."))
            return
        }

        // Your turn: the charger that just freed up is held for you.
        let vehicle = self.vehicle
        let usable = station.connectors.filter { Charging.isCompatible(vehicle, $0) && $0.status != .offline }
        let connector = usable.first { [.charging, .idle, .blocked].contains($0.status) } ?? usable.first ?? station.connectors[0]
        holds.removeAll { $0.connectorId == connector.id }
        holds.append(SpotHold(
            stationId: station.id, stationName: station.name, connectorId: connector.id,
            connectorLabel: "\(connector.type.label) · \(Int(connector.powerKw)) kW",
            startedAt: next, until: next.addingTimeInterval(SpotHold.minutes * 60), forMe: true
        ))
        queue = nil
        refreshStations()
        save()
        rescheduleQueueNotifications()
        showBanner(tr("A spot is held for you"), tr("\(station.name): it's yours for \(Int(SpotHold.minutes)) min."))
    }

    /// "Spot held for you" when your turn comes, and a reminder a minute
    /// before a held spot is passed on. Both work with the app closed.
    func rescheduleQueueNotifications() {
        let n = NotificationManager.shared
        n.cancel([NotificationManager.holdReadyId, NotificationManager.holdEndingId])
        let now = simNow()
        if let q = queue, q.position == 1, let next = q.nextEventAt, next > now,
           let station = stations.first(where: { $0.id == q.stationId }) {
            n.schedule(
                id: NotificationManager.holdReadyId,
                title: tr("A spot is held for you"),
                body: tr("\(station.name): it's yours for \(Int(SpotHold.minutes)) min."),
                after: next.timeIntervalSince(now) / speed,
                category: NotificationManager.holdCategory
            )
        }
        if let hold = myHold, hold.until.timeIntervalSince(now) > 90 {
            n.schedule(
                id: NotificationManager.holdEndingId,
                title: tr("1 min left on your spot"),
                body: tr("\(hold.stationName): start charging or it goes to the next driver."),
                after: (hold.until.timeIntervalSince(now) - 60) / speed,
                category: NotificationManager.holdCategory
            )
        }
    }

    // MARK: Queue persistence

    private struct QueueState: Codable {
        var queue: QueueEntry?
        // Added later; optional so older saves still decode.
        var holds: [SpotHold]?
    }

    func saveQueue(to snapshot: inout PersistenceSnapshot) throws {
        try snapshot.set(QueueState(queue: queue, holds: holds), for: "queue")
    }

    func loadQueue(from snapshot: PersistenceSnapshot) {
        guard let state: QueueState = snapshot.value(for: "queue") else { return }
        queue = state.queue
        holds = state.holds ?? []
    }
}
