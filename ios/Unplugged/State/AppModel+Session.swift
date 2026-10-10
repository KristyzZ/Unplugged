import Foundation

extension AppModel {
    var hasActiveSession: Bool { session != nil && session?.endedAt == nil }

    func checkSession(at suppliedNow: Date? = nil) {
        defer { checkBackgroundTime() }
        guard var s = session, s.endedAt == nil else { return }
        let now = suppliedNow ?? simNow()
        var changed = false
        if s.doneAt == nil && now >= s.scheduledDoneAt {
            s.doneAt = s.scheduledDoneAt
            s.completionAnnounced = true
            recordSessionEvent(s, kind: .completed, at: s.scheduledDoneAt)
            showBanner(tr("Charging complete"), tr("You have \(s.graceMinutes) min to move your car. After that an idle fee applies."))
            moment = .completed(stopped: false)
            changed = true
        }
        if let done = s.doneAt {
            let graceEnd = done.addingTimeInterval(Double(s.graceMinutes) * 60)
            if now >= graceEnd, s.idleAnnounced != true {
                s.idleAnnounced = true
                s.graceWarningAnnounced = true
                showBanner(tr("Idle fee has started"), tr("The longer you stay, the higher the rate."))
                changed = true
            } else if now >= graceEnd.addingTimeInterval(-120), now < graceEnd, s.graceWarningAnnounced != true {
                s.graceWarningAnnounced = true
                showBanner(tr("Grace period ending soon"), tr("Move your car before idle fees start."))
                changed = true
            }
        }
        session = s
        applySessionStatus()
        if changed { save(); rescheduleNotifications() }
    }

    // MARK: Charging

    func startCharging(at station: Station, connector: Connector, targetSoc: Double, now suppliedNow: Date? = nil) {
        let now = suppliedNow ?? simNow()
        expireReservations(at: now)
        // Validate reservation ownership/deadline independently of the caller's
        // connector snapshot, which may still say available after another hold.
        let mine = holds.first { $0.forMe && $0.releasedAt == nil && $0.until > now }
        if let mine, !(mine.stationId == station.id && mine.connectorId == connector.id && mine.isActive(at: now)) {
            showBanner(tr("Reservation not ready"), tr("Wait for its start time, or cancel it before charging elsewhere."))
            return
        }
        guard !holds.contains(where: { !$0.forMe && $0.stationId == station.id && $0.connectorId == connector.id
            && $0.releasedAt == nil && $0.until > now }) else { return }
        // The spot held for you is marked reserved for everyone else, but it is yours to start.
        let heldForMe = mine?.isActive(at: now) == true
        guard !hasActiveSession, targetSoc > soc, targetSoc <= 100,
              station.capabilities.simulated, station.capabilities.supportsSessionControl,
              station.connectors.contains(where: { $0.id == connector.id }),
              Charging.isCompatible(vehicle, connector),
              connector.effectiveStatus() == .available || (heldForMe && connector.effectiveStatus() == .reserved) else { return }
        if session?.endedAt != nil { finishSession() }
        let terms = pricingTerms(at: station, connector: connector)
        let estimate = Charging.chargeTime(vehicle, connector, from: soc, to: targetSoc)
        let hour = Calendar.current.component(.hour, from: .now)
        let s = ChargingSession(
            stationId: station.id, stationName: station.name,
            connectorLabel: "\(connector.type.rawValue) · \(Int(connector.powerKw)) kW",
            startedAt: now, startSoc: soc, targetSoc: targetSoc,
            minutesToTarget: Double(max(1, estimate.minutes)),
            graceMinutes: IdleFee.graceMinutes(demand: station.demandLevel(hour: hour)),
            pricePerKwh: terms.energyEurPerKwh, batteryKwh: vehicle.batteryKwh,
            pricingTerms: terms, connectorId: connector.id, feePolicy: .standard
        )
        session = s
        recordSessionEvent(s, kind: .started, at: s.startedAt)
        // Charging at the spot held for you uses up the hold.
        if heldForMe {
            holds.removeAll { $0.forMe }
        }
        queue = nil
        tileHiddenFor = nil
        moment = .started
        applySessionStatus()
        rescheduleNotifications()
        save()
        tab = .charging
    }

    func stopCharging(at suppliedNow: Date? = nil) {
        guard var s = session, s.doneAt == nil, s.endedAt == nil else { return }
        s.doneAt = min(s.scheduledDoneAt, max(s.startedAt, suppliedNow ?? simNow()))
        s.completionAnnounced = true
        session = s
        recordSessionEvent(s, kind: .completed, at: s.doneAt!)
        applySessionStatus()
        rescheduleNotifications()
        save()
        moment = .completed(stopped: true)
    }

    /// The driver has moved the car: settle the idle fee, award points and,
    /// if someone is waiting, hold the charger for them.
    func leaveSpot(at suppliedNow: Date? = nil) {
        guard var s = session, s.endedAt == nil else { return }
        let now = max(s.startedAt, suppliedNow ?? simNow())
        if s.doneAt == nil {
            s.doneAt = min(now, s.scheduledDoneAt)
            s.completionAnnounced = true
            recordSessionEvent(s, kind: .completed, at: s.doneAt!)
        }
        let minutesAfter = max(0, now.timeIntervalSince(s.doneAt!) / 60)
        s.endedAt = now
        s.idleFeeEur = s.appliedFeePolicy.fee(minutes: max(0, minutesAfter - Double(s.graceMinutes)))
        let reason = Points.forMove(minutesAfterDone: minutesAfter, graceMinutes: s.graceMinutes)
        let handOver = handOverSpot(s, at: now)
        // The handover bonus is for moving on time; an overstay still hands the
        // spot on, but earns nothing.
        let handOverBonus = handOver && reason != nil
        s.handedOver = handOver
        s.pointsEarned = (reason?.points ?? 0) + (handOverBonus ? PointsReason.handedOver.points : 0)
        session = s
        recordSessionEvent(s, kind: .released, at: now, points: s.pointsEarned ?? 0)
        soc = SessionSnapshot(s, now: now).soc.rounded()
        if let reason {
            // Session/release state is already set; addPoints persists it atomically
            // with the balance, so repeated calls and relaunch cannot award twice.
            addPoints(reason, note: s.stationName)
        }
        if handOverBonus {
            addPoints(.handedOver, note: s.stationName)
        }
        applySessionStatus(reservationNow: now)
        rescheduleNotifications()
        // The receipt shows the points, so no banner here.
        moment = .finished
        save()
    }

    func finishSession() {
        guard let s = session, s.endedAt != nil else { return }
        if !sessionHistory.contains(where: { $0.id == s.id }) {
            sessionHistory.insert(s, at: 0)
            sessionHistory = Array(sessionHistory.prefix(30))
        }
        session = nil
        tileHiddenFor = nil
        moment = nil
        rescheduleNotifications()
        save()
    }

    func recordSessionEvent(_ s: ChargingSession, kind: SessionEvent.Kind, at: Date, points: Int = 0) {
        let event = SessionEvent(sessionId: s.id, stationId: s.stationId, connectorId: s.connectorId,
                                 kind: kind, at: at, recordedAt: .now, points: points)
        guard !sessionEvents.contains(where: { $0.id == event.id }) else { return }
        sessionEvents.append(event)
    }

    // MARK: Station overlay

    /// Fresh demo snapshot plus hosted chargers, then the active session / release overlay and finally
    /// the held spots (which win over the overlay).
    func refreshStations(at date: Date = .now) {
        var fresh = stationSource == .demo ? DemoData.stations(at: date, tick: tick) : baseStations
        fresh += hostListings.compactMap { Hosting.station(for: $0) }
        stations = fresh
        applySessionStatus(at: date)
        publishNearby()
    }

    func applySessionStatus(at observedNow: Date = .now, reservationNow: Date? = nil) {
        defer { applyHolds(at: reservationNow) }
        // A released demo bay stays visibly free for five real minutes. Thereafter
        // background simulation may change it. An active session always wins.
        for event in sessionEvents where event.kind == .released && observedNow.timeIntervalSince(event.recordedAt) < 300 {
            overlay(stationId: event.stationId, connectorId: event.connectorId, status: .available,
                    observedNow: observedNow, idleMinutes: nil, etaMinutes: nil)
        }
        guard let s = session, s.endedAt == nil else { return }
        let idle = s.doneAt.map { Int(max(0, simNow().timeIntervalSince($0) / 60)) }
        let eta = s.doneAt == nil ? Int(max(0, ceil(s.scheduledDoneAt.timeIntervalSince(simNow()) / 60))) : nil
        overlay(stationId: s.stationId, connectorId: s.connectorId, status: s.doneAt == nil ? .charging : .idle,
                observedNow: observedNow, idleMinutes: idle, etaMinutes: eta)
    }

    private func overlay(stationId: String, connectorId: String?, status: ConnectorStatus,
                         observedNow: Date, idleMinutes: Int?, etaMinutes: Int?) {
        guard let connectorId, let i = stations.firstIndex(where: { $0.id == stationId }),
              stations[i].capabilities.simulated,
              let j = stations[i].connectors.firstIndex(where: { $0.id == connectorId }) else { return }
        stations[i].connectors[j].status = status
        stations[i].connectors[j].idleMinutes = idleMinutes
        stations[i].connectors[j].etaMinutes = etaMinutes
        stations[i].connectors[j].provenance = .demo(at: observedNow, source: "Demo session")
    }

    func dismissMoment() {
        moment = nil
    }

    // MARK: Lock Screen and charging tile

    func setLockScreen(_ on: Bool) { lockScreenEnabled = on; save(); syncLiveActivity() }

    func syncLiveActivity() {
        LiveActivityManager.shared.sync(session: session, enabled: lockScreenEnabled,
                                        simNow: simNow(), speed: speed, lang: lang)
    }

    func hideTile() {
        guard let s = session else { return }
        if s.endedAt != nil { finishSession() }
        else { tileHiddenFor = SessionSnapshot(s, now: simNow()).phase }
    }

    // MARK: Notifications

    func rescheduleNotifications() {
        syncLiveActivity()
        rescheduleQueueNotifications()
        let n = NotificationManager.shared
        n.cancel([NotificationManager.chargeDoneId, NotificationManager.graceOverId]
                 + scheduledSessionNotificationIds + (session.map { SessionNotificationPlan.ids(for: $0) } ?? []))
        scheduledSessionNotificationIds = []
        guard let s = session else { return }
        let planned = SessionNotificationPlan.items(for: s, now: simNow(), speed: speed)
        scheduledSessionNotificationIds = planned.map(\.id)
        for item in planned {
            let title: String
            let body: String
            switch item.kind {
            case .completed:
                title = tr("Charging complete")
                body = tr("\(s.stationName): you have \(s.graceMinutes) min to move your car.")
            case .warning:
                title = tr("Grace period ending soon")
                body = tr("Move your car before idle fees start.")
            case .idleStarted:
                title = tr("Idle fee has started")
                body = tr("Move your car from \(s.stationName) — the rate is increasing.")
            }
            n.schedule(id: item.id, title: title, body: body, after: item.after, category: NotificationManager.moveCategory)
        }
    }

    private struct SessionState: Codable {
        var session: ChargingSession?
        var sessionHistory: [ChargingSession]?
        var lockScreen: Bool?
        var sessionEvents: [SessionEvent]?
    }

    func saveSession(to snapshot: inout PersistenceSnapshot) throws {
        try snapshot.set(SessionState(session: session, sessionHistory: sessionHistory,
                                      lockScreen: lockScreenEnabled, sessionEvents: sessionEvents), for: "session")
    }

    func loadSession(from snapshot: PersistenceSnapshot) {
        guard let state: SessionState = snapshot.value(for: "session") else { return }
        session = state.session
        sessionHistory = state.sessionHistory ?? AppModel.demoSessionHistory
        lockScreenEnabled = state.lockScreen ?? true
        sessionEvents = state.sessionEvents ?? []
    }
}
