import Foundation

extension AppModel {
    var hasActiveSession: Bool { session != nil && session?.endedAt == nil }

    func checkSession() {
        guard var s = session, s.endedAt == nil else { return }
        let now = simNow()
        if s.doneAt == nil && now >= s.scheduledDoneAt {
            s.doneAt = s.scheduledDoneAt
            session = s
            save()
            syncLiveActivity()
            showBanner(tr("Charging complete"), tr("You have \(s.graceMinutes) min to move your car. After that an idle fee applies."))
        }
        if let done = s.doneAt, graceAnnouncedFor != done, now >= done.addingTimeInterval(Double(s.graceMinutes) * 60) {
            graceAnnouncedFor = done
            syncLiveActivity()
            showBanner(tr("Idle fee has started"), tr("The longer you stay, the higher the rate."))
        }
    }

    // MARK: Charging

    func startCharging(at station: Station, connector: Connector, targetSoc: Double) {
        let estimate = Charging.chargeTime(vehicle, connector, from: soc, to: targetSoc)
        let hour = Calendar.current.component(.hour, from: .now)
        session = ChargingSession(
            stationId: station.id,
            stationName: station.name,
            connectorLabel: "\(connector.type.rawValue) · \(Int(connector.powerKw)) kW",
            startedAt: simNow(),
            startSoc: soc,
            targetSoc: targetSoc,
            minutesToTarget: Double(max(1, estimate.minutes)),
            graceMinutes: IdleFee.graceMinutes(demand: station.demandLevel(hour: hour)),
            pricePerKwh: station.pricePerKwh,
            batteryKwh: vehicle.batteryKwh
        )
        queue = nil
        graceAnnouncedFor = nil
        tileHiddenFor = nil
        rescheduleNotifications()
        save()
    }

    func stopCharging() {
        guard var s = session, s.doneAt == nil else { return }
        s.doneAt = simNow()
        session = s
        rescheduleNotifications()
        save()
        showBanner(tr("Charging stopped"), tr("You have \(s.graceMinutes) min to move your car."))
    }

    /// The driver has moved the car: settle the idle fee and award points.
    func leaveSpot() {
        guard var s = session, s.endedAt == nil else { return }
        let now = simNow()
        let done = s.doneAt ?? now
        let minutesAfter = now.timeIntervalSince(done) / 60
        let idle = max(0, minutesAfter - Double(s.graceMinutes))
        s.doneAt = done
        s.endedAt = now
        s.idleFeeEur = IdleFee.fee(minutes: idle)
        let reason = Points.forMove(minutesAfterDone: minutesAfter, graceMinutes: s.graceMinutes)
        s.pointsEarned = reason?.points ?? 0
        session = s
        soc = SessionSnapshot(s, now: now).soc.rounded()
        if let reason {
            addPoints(reason, note: s.stationName)
            showBanner(tr("+\(reason.points) pts"), reason.label)
        }
        NotificationManager.shared.cancel([NotificationManager.chargeDoneId, NotificationManager.graceOverId])
        save()
        syncLiveActivity()
    }

    func finishSession() {
        if let s = session, s.endedAt != nil {
            sessionHistory.insert(s, at: 0)
            sessionHistory = Array(sessionHistory.prefix(30))
        }
        session = nil
        tileHiddenFor = nil
        save()
        syncLiveActivity()
    }

    // MARK: Lock Screen and charging tile

    func setLockScreen(_ on: Bool) {
        lockScreenEnabled = on
        save()
        syncLiveActivity()
    }

    func syncLiveActivity() {
        LiveActivityManager.shared.sync(
            session: session,
            enabled: lockScreenEnabled,
            simNow: simNow(),
            speed: speed,
            lang: lang
        )
    }

    /// × on the charging tile. A finished session is closed for good;
    /// otherwise the tile hides until the next phase.
    func hideTile() {
        guard let s = session else { return }
        let phase = SessionSnapshot(s, now: simNow()).phase
        if phase == .ended {
            finishSession()
        } else {
            tileHiddenFor = phase
        }
    }

    // MARK: Notifications

    func rescheduleNotifications() {
        syncLiveActivity()
        let n = NotificationManager.shared
        n.cancel([NotificationManager.chargeDoneId, NotificationManager.graceOverId])
        guard let s = session, s.endedAt == nil else { return }
        let now = simNow()
        let done = s.doneAt ?? s.scheduledDoneAt
        if s.doneAt == nil, done > now {
            n.schedule(
                id: NotificationManager.chargeDoneId,
                title: tr("Charging complete"),
                body: tr("\(s.stationName): you have \(s.graceMinutes) min to move your car."),
                after: done.timeIntervalSince(now) / speed
            )
        }
        let graceEnd = done.addingTimeInterval(Double(s.graceMinutes) * 60)
        if graceEnd > now {
            n.schedule(
                id: NotificationManager.graceOverId,
                title: tr("Idle fee has started"),
                body: tr("Move your car from \(s.stationName) — the rate is increasing."),
                after: graceEnd.timeIntervalSince(now) / speed
            )
        }
    }

    // MARK: Session persistence

    private struct SessionState: Codable {
        var session: ChargingSession?
        var sessionHistory: [ChargingSession]?
        var lockScreen: Bool?
    }

    func saveSession(to snapshot: inout PersistenceSnapshot) throws {
        try snapshot.set(SessionState(session: session, sessionHistory: sessionHistory,
                                      lockScreen: lockScreenEnabled), for: "session")
    }

    func loadSession(from snapshot: PersistenceSnapshot) {
        guard let state: SessionState = snapshot.value(for: "session") else { return }
        session = state.session
        sessionHistory = state.sessionHistory ?? AppModel.demoSessionHistory
        lockScreenEnabled = state.lockScreen ?? true
    }
}
