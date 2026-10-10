import Foundation

struct QueueEntry: Codable, Equatable {
    let stationId: String
    let joinedAt: Date
    /// Local demo queue position. Legacy saves may contain drivers ahead.
    var position: Int
    /// An estimate/poll time, never proof that an occupied bay is available.
    var nextEventAt: Date? = nil
}

extension AppModel {
    var myReservation: SpotHold? {
        holds.first { $0.forMe && $0.releasedAt == nil && $0.until > simNow() }
    }
    var myHold: SpotHold? { myReservation.flatMap { $0.isActive(at: simNow()) ? $0 : nil } }

    func applyHolds(at suppliedNow: Date? = nil) {
        let now = suppliedNow ?? simNow()
        // Released demo bays remain free for five simulated minutes. An active
        // reservation wins over that overlay, and charging wins over both.
        let ordered = holds.filter { $0.releasedAt != nil } + holds.filter { $0.releasedAt == nil }
        for hold in ordered {
            let released = hold.releasedAt.map { now >= $0 && now.timeIntervalSince($0) < 300 } ?? false
            guard released || hold.isActive(at: now),
                  !(hasActiveSession && session?.stationId == hold.stationId && session?.connectorId == hold.connectorId),
                  let si = stations.firstIndex(where: { $0.id == hold.stationId }), stations[si].capabilities.simulated,
                  let ci = stations[si].connectors.firstIndex(where: { $0.id == hold.connectorId }) else { continue }
            stations[si].connectors[ci].status = released ? .available : .reserved
            stations[si].connectors[ci].idleMinutes = nil
            stations[si].connectors[ci].etaMinutes = nil
            stations[si].connectors[ci].provenance = .demo(at: .now, source: tr("Demo reservation"))
        }
    }

    func openStation(_ id: String) { tab = .explore; openStationId = id }

    @discardableResult
    func reserveConnector(at station: Station, connector: Connector, startsAt suppliedStart: Date? = nil, now suppliedNow: Date? = nil) -> Bool {
        let now = suppliedNow ?? simNow()
        expireReservations(at: now)
        let startsAt = suppliedStart ?? now
        guard let latest = stations.first(where: { $0.id == station.id }),
              latest.capabilities.simulated, latest.capabilities.supportsSessionControl,
              let current = latest.connectors.first(where: { $0.id == connector.id }),
              Charging.isCompatible(vehicle, current), current.isConfirmedAvailable() else { return false }
        guard !hasActiveSession, queue == nil,
              !holds.contains(where: { $0.forMe && $0.releasedAt == nil && $0.until > now }),
              station.capabilities.simulated, station.capabilities.supportsSessionControl,
              station.connectors.contains(where: { $0.id == connector.id }),
              Charging.isCompatible(vehicle, connector), connector.isConfirmedAvailable(),
              ReservationRules.validStart(startsAt, now: now),
              !holds.contains(where: {
                  $0.releasedAt == nil && $0.stationId == station.id && $0.connectorId == connector.id
                  && ReservationRules.overlaps(start: startsAt, end: ReservationRules.deadline(start: startsAt),
                                               otherStart: $0.startedAt, otherEnd: $0.until)
              }) else { return false }
        var hold = SpotHold(stationId: station.id, stationName: station.name, connectorId: connector.id,
                            connectorLabel: "\(connector.type.label) · \(Int(connector.powerKw)) kW",
                            startedAt: startsAt, until: ReservationRules.deadline(start: startsAt), forMe: true)
        hold.bookedAt = now
        hold.readyAnnounced = startsAt <= now
        holds.removeAll { $0.id == hold.id && $0.releasedAt != nil }
        holds.append(hold)
        applyHolds(at: now)
        save()
        rescheduleQueueNotifications()
        showBanner(tr("Demo reservation saved"), tr("Begin charging within 10 min of the reserved start, or the spot is released."))
        return true
    }

    @discardableResult
    func joinQueue(_ station: Station, now suppliedNow: Date? = nil) -> Bool {
        let now = suppliedNow ?? simNow()
        expireReservations(at: now)
        guard !hasActiveSession, myReservation == nil,
              station.capabilities.simulated, station.capabilities.supportsSessionControl,
              station.connectors.contains(where: { Charging.isCompatible(vehicle, $0) && ![.offline, .unknown].contains($0.effectiveStatus()) }) else { return false }
        if let queue { return queue.stationId == station.id } // Re-taps preserve position/time.
        queue = QueueEntry(stationId: station.id, joinedAt: now, position: 1, nextEventAt: now)
        checkQueueAndHolds(at: now)
        save()
        rescheduleQueueNotifications()
        if queue != nil {
            showBanner(tr("You joined the queue"), tr("Demo queue: a compatible free connector will be held for 10 min when it is your turn."))
        }
        return true
    }

    func leaveQueue() { queue = nil; save(); rescheduleQueueNotifications() }

    /// Cancel an upcoming reservation or release an active hold.
    func releaseHold() {
        guard let hold = myReservation else { return }
        let now = simNow()
        if hold.startedAt > now {
            holds.removeAll { $0.id == hold.id && $0.forMe }
        } else if let i = holds.firstIndex(where: { $0.id == hold.id && $0.forMe && $0.releasedAt == nil }) {
            holds[i].releasedAt = now
        }
        applyHolds(at: now)
        checkQueueAndHolds(at: now)
        save()
        rescheduleQueueNotifications()
        showBanner(tr("Reservation cancelled"), tr("The spot is available to the next driver when free."))
    }

    func handOverSpot(_ s: ChargingSession, at now: Date) -> Bool {
        guard let station = stations.first(where: { $0.id == s.stationId }),
              let connector = station.connectors.first(where: { $0.id == s.connectorId }),
              queue?.stationId == station.id || someoneWaitingAt(station) else { return false }
        if var q = queue, q.stationId == station.id {
            let forMe = q.position <= 1
            var hold = SpotHold(stationId: station.id, stationName: station.name, connectorId: connector.id,
                                connectorLabel: "\(connector.type.label) · \(Int(connector.powerKw)) kW",
                                startedAt: now, until: ReservationRules.deadline(start: now), forMe: forMe)
            hold.readyAnnounced = true
            holds.removeAll { $0.id == hold.id && $0.releasedAt != nil }
            holds.append(hold)
            if forMe { queue = nil }
            else { q.position -= 1; q.nextEventAt = now.addingTimeInterval(20); queue = q }
            // The release caller saves hold, session settlement and rewards together.
            return true
        }
        guard !holds.contains(where: { $0.stationId == station.id && $0.connectorId == connector.id && $0.releasedAt == nil && $0.until > now }) else { return true }
        holds.removeAll { $0.id == "\(station.id)|\(connector.id)" && $0.releasedAt != nil }
        holds.append(SpotHold(stationId: station.id, stationName: station.name, connectorId: connector.id,
                              connectorLabel: "\(connector.type.label) · \(Int(connector.powerKw)) kW",
                              startedAt: now, until: ReservationRules.deadline(start: now), forMe: false))
        applyHolds(at: now)
        return true
    }

    func expireReservations(at now: Date) {
        var changed = false
        var expiredMine = false
        for i in holds.indices where holds[i].releasedAt == nil && holds[i].until <= now {
            expiredMine = expiredMine || holds[i].forMe
            holds[i].releasedAt = holds[i].until // Never restart a deadline after relaunch.
            changed = true
        }
        let oldCount = holds.count
        holds.removeAll { $0.releasedAt.map { now.timeIntervalSince($0) >= 300 } ?? false }
        if changed || holds.count != oldCount { applyHolds(at: now); save(); rescheduleQueueNotifications() }
        if expiredMine {
            showBanner(tr("Reservation expired"), tr("Charging did not start before the deadline. The spot was released."))
        }
    }

    func checkQueueAndHolds(at suppliedNow: Date? = nil) {
        let now = suppliedNow ?? simNow()
        expireReservations(at: now)
        var announced = false
        for i in holds.indices where holds[i].forMe && holds[i].isActive(at: now) && holds[i].readyAnnounced != true {
            holds[i].readyAnnounced = true
            announced = true
            showBanner(tr("Your reservation has started"), tr("Begin charging within 10 min of the reserved start, or the spot is released."))
        }
        applyHolds(at: now)
        if announced { save(); rescheduleQueueNotifications() }
        guard !hasActiveSession, myReservation == nil, var q = queue, (q.nextEventAt ?? now) <= now else { return }
        guard let station = stations.first(where: { $0.id == q.stationId }), station.capabilities.simulated,
              station.capabilities.supportsSessionControl else { leaveQueue(); return }
        // An ETA never converts a charging/idle/blocked/unknown connector into a free bay.
        guard let connector = station.connectors.first(where: { c in
            Charging.isCompatible(vehicle, c) && c.isConfirmedAvailable()
                && !holds.contains { $0.releasedAt == nil && $0.stationId == station.id && $0.connectorId == c.id && $0.until > now }
        }) else {
            q.nextEventAt = now.addingTimeInterval(20)
            queue = q
            save()
            return
        }
        let forMe = q.position <= 1
        var hold = SpotHold(stationId: station.id, stationName: station.name, connectorId: connector.id,
                            connectorLabel: "\(connector.type.label) · \(Int(connector.powerKw)) kW",
                            startedAt: now, until: ReservationRules.deadline(start: now), forMe: forMe)
        hold.readyAnnounced = true
        holds.removeAll { $0.id == hold.id && $0.releasedAt != nil }
        holds.append(hold)
        if forMe {
            queue = nil
            showBanner(tr("A spot is held for you"), tr("\(station.name): it's yours for \(Int(SpotHold.minutes)) min."))
        } else {
            q.position -= 1
            q.nextEventAt = now.addingTimeInterval(20)
            queue = q
        }
        applyHolds(at: now)
        save()
        rescheduleQueueNotifications()
    }

    func rescheduleQueueNotifications() {
        let n = NotificationManager.shared
        n.cancel(ReservationNotificationPlan.ids)
        guard let hold = myReservation else { return }
        for item in ReservationNotificationPlan.items(for: hold, now: simNow(), speed: speed) {
            let title: String
            let body: String
            switch item.kind {
            case .ready:
                title = tr("Your reservation has started")
                body = tr("Begin charging within 10 min of the reserved start, or the spot is released.")
            case .ending:
                title = tr("1 min left on your spot")
                body = tr("\(hold.stationName): start charging or it goes to the next driver.")
            case .expired:
                title = tr("Reservation expired")
                body = tr("Charging did not start before the deadline. The spot was released.")
            }
            n.schedule(id: item.id, title: title, body: body, after: item.after, category: NotificationManager.holdCategory)
        }
    }

    private struct QueueState: Codable { var queue: QueueEntry?; var holds: [SpotHold]? }
    func saveQueue(to snapshot: inout PersistenceSnapshot) throws {
        try snapshot.set(QueueState(queue: queue, holds: holds), for: "queue")
    }
    func loadQueue(from snapshot: PersistenceSnapshot) {
        guard let state: QueueState = snapshot.value(for: "queue") else { return }
        queue = state.queue
        holds = (state.holds ?? []).map { old in
            var hold = old
            hold.until = min(hold.until, ReservationRules.deadline(start: hold.startedAt))
            return hold
        }
    }
}
