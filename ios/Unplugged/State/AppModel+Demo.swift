import Foundation

extension AppModel {
    func resetDemo() {
        vehicleId = "ioniq5"
        soc = 34
        points = 120
        lifetimePoints = 240
        history = AppModel.demoHistory
        session = nil
        sessionEvents = []
        banners.removeAll()
        tileHiddenFor = nil
        moment = nil
        queue = nil
        holds = []
        hostListings = []
        HostPhotoStore.deleteAll()
        refreshStations()
        reports = AppModel.demoReports
        sessionHistory = AppModel.demoSessionHistory
        defaultPaymentId = "visa"
        activePlanIds = ["ignitis"]
        realAnchor = Date()
        simAnchor = Date()
        speed = 1
        refreshStations()
        rescheduleNotifications()
        save()
    }

    // MARK: Fake reservations (Demo screen)

    /// Free connectors for your car that can be reserved in the app, nearest first.
    private func demoReservableConnectors(at now: Date) -> [(Station, Connector)] {
        let vehicle = self.vehicle
        return stations
            .filter { $0.capabilities.simulated && $0.capabilities.supportsSessionControl }
            .sorted { Geo.haversineKm(origin, $0.latLng) < Geo.haversineKm(origin, $1.latLng) }
            .compactMap { s in
                s.connectors.first { c in
                    Charging.isCompatible(vehicle, c) && c.isConfirmedAvailable()
                        && !holds.contains { $0.releasedAt == nil && $0.stationId == s.id && $0.connectorId == c.id && $0.until > now }
                }.map { (s, $0) }
            }
    }

    /// Books the nearest reservable connector for you, starting in `minutes` on the demo clock.
    /// Goes through the normal booking rules, so it fails while you charge, queue or already hold a spot.
    @discardableResult
    func fakeReservation(startingIn minutes: Double) -> Bool {
        let now = simNow()
        expireReservations(at: now)
        guard let (station, connector) = demoReservableConnectors(at: now).first else { return false }
        return reserveConnector(at: station, connector: connector,
                                startsAt: now.addingTimeInterval(minutes * 60), now: now)
    }

    /// Another (invented) driver reserves the nearest free connector right now,
    /// so it shows as reserved on the map for the 10-minute arrival window.
    @discardableResult
    func fakeOthersReservation() -> Bool {
        let now = simNow()
        expireReservations(at: now)
        guard let (station, connector) = demoReservableConnectors(at: now).first else { return false }
        var hold = SpotHold(stationId: station.id, stationName: station.name, connectorId: connector.id,
                            connectorLabel: "\(connector.type.label) · \(Int(connector.powerKw)) kW",
                            startedAt: now, until: ReservationRules.deadline(start: now), forMe: false)
        hold.bookedAt = now
        holds.removeAll { $0.id == hold.id && $0.releasedAt != nil }
        holds.append(hold)
        applyHolds(at: now)
        save()
        showBanner(tr("Another driver reserved a spot"), tr("\(station.name) is reserved for the next \(Int(SpotHold.minutes)) min."))
        return true
    }

    /// Active reservations by other drivers, soonest to expire first.
    var othersReservations: [SpotHold] {
        let now = simNow()
        return holds.filter { !$0.forMe && $0.releasedAt == nil && $0.until > now }.sorted { $0.until < $1.until }
    }

    // MARK: Demo seed data

    static let demoHistory: [PointsEntry] = [
        PointsEntry(reason: .movedFast, points: 30, at: Date().addingTimeInterval(-2 * 86_400)),
        PointsEntry(reason: .offPeak, points: 10, at: Date().addingTimeInterval(-2 * 86_400)),
    ]

    static let demoSessionHistory: [ChargingSession] = {
        let now = Date()
        func entry(_ id: String, _ name: String, _ connector: String, daysAgo: Double, charge: Double,
                   idle: Double, grace: Int, price: Double, from: Double, to: Double, kwh: Double, points: Int) -> ChargingSession {
            let start = now.addingTimeInterval(-daysAgo * 86_400)
            let done = start.addingTimeInterval(charge * 60)
            return ChargingSession(
                stationId: id, stationName: name, connectorLabel: connector, startedAt: start,
                startSoc: from, targetSoc: to, minutesToTarget: charge, graceMinutes: grace,
                pricePerKwh: price, batteryKwh: kwh,
                doneAt: done, endedAt: done.addingTimeInterval((Double(grace) + idle) * 60),
                idleFeeEur: IdleFee.fee(minutes: idle), pointsEarned: points
            )
        }
        return [
            entry("akropolis", "Akropolis", "CCS2 · 150 kW", daysAgo: 2, charge: 32, idle: 0, grace: 10, price: 0.59, from: 22, to: 80, kwh: 77, points: 30),
            entry("ozas", "Ozas", "CCS2 · 120 kW", daysAgo: 6, charge: 41, idle: 12, grace: 8, price: 0.55, from: 18, to: 85, kwh: 77, points: 0),
        ]
    }()

    static let demoReports: [AbuseReport] = [
        AbuseReport(
            id: "r-demo", stationId: "europa", plate: "KLM 482",
            description: "A petrol car has been parked in the charging spot since morning.",
            hasPhoto: true, telemetryMatches: false, confirmations: 1,
            createdAt: Date().addingTimeInterval(-3600), byMe: false
        ),
        AbuseReport(
            id: "r-demo-2", stationId: "europa", plate: "",
            description: "The first connector won't start a session.",
            hasPhoto: false, telemetryMatches: false, confirmations: 2,
            createdAt: Date().addingTimeInterval(-7200), byMe: false,
            kind: .chargerProblem
        ),
    ]
}
