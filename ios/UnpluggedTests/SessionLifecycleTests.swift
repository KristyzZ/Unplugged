import XCTest
@testable import Unplugged

final class SessionLifecycleTests: XCTestCase {
    @MainActor
    private func withModel(_ action: (AppModel, Station, Connector) throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let keys = ["unplugged.state.v1", "unplugged.state.v2", "unplugged.lang"]
        let previous = keys.map { defaults.object(forKey: $0) }
        keys.forEach { defaults.removeObject(forKey: $0) }
        let model = AppModel(runLoops: false)
        model.lockScreenEnabled = false
        model.someoneWaitingAt = { _ in false }   // hand-over is covered by HandOverTests
        defer {
            model.resetDemo()
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        var station = model.stations.first { $0.id == "akropolis" }!
        station.connectors[0].status = .available
        station.connectors[0].provenance = .demo(at: .now)
        try action(model, station, station.connectors[0])
    }

    @MainActor
    func testStartCompletionReleaseAndRefreshOverlay() throws {
        try withModel { model, station, connector in
            model.startCharging(at: station, connector: connector, targetSoc: 80)
            let s = try XCTUnwrap(model.session)
            XCTAssertEqual(s.connectorId, connector.id)
            XCTAssertNotNil(s.sessionId)
            @MainActor func status() -> ConnectorStatus? {
                model.stations.first { $0.id == station.id }?.connectors.first { $0.id == connector.id }?.status
            }
            XCTAssertEqual(status(), .charging)
            model.refreshStations()
            XCTAssertEqual(status(), .charging)
            model.setLang(.lt)
            XCTAssertEqual(status(), .charging)
            model.checkSession(at: s.scheduledDoneAt)
            XCTAssertEqual(status(), .idle)
            model.refreshStations()
            XCTAssertEqual(status(), .idle)
            model.leaveSpot(at: s.scheduledDoneAt.addingTimeInterval(60))
            XCTAssertEqual(status(), .available)
            model.finishSession()
            model.refreshStations()
            XCTAssertEqual(status(), .available)
            XCTAssertEqual(model.sessionEvents.map(\.kind), [.started, .completed, .released])
            XCTAssertEqual(Set(model.sessionEvents.map(\.id)).count, 3)
        }
    }

    @MainActor
    func testSecondStartCannotReplaceActiveSession() throws {
        try withModel { model, station, connector in
            model.startCharging(at: station, connector: connector, targetSoc: 80)
            let original = try XCTUnwrap(model.session)
            model.startCharging(at: station, connector: connector, targetSoc: 90)
            XCTAssertEqual(model.session, original)
            XCTAssertEqual(model.sessionEvents.count, 1)
            model.finishSession()
            XCTAssertEqual(model.session, original)
        }
    }

    @MainActor
    func testReleaseAndRewardAreOnceOnlyAcrossReloadAndRepeatedDismissal() throws {
        try withModel { model, station, connector in
            let points = model.points
            model.startCharging(at: station, connector: connector, targetSoc: 80)
            let s = try XCTUnwrap(model.session)
            model.checkSession(at: s.scheduledDoneAt)
            model.leaveSpot(at: s.scheduledDoneAt.addingTimeInterval(60))
            model.leaveSpot(at: s.scheduledDoneAt.addingTimeInterval(61))
            XCTAssertEqual(model.points, points + 30)
            model.load()
            model.leaveSpot(at: s.scheduledDoneAt.addingTimeInterval(62))
            XCTAssertEqual(model.points, points + 30)
            XCTAssertEqual(model.sessionEvents.filter { $0.kind == .released }.count, 1)
            model.finishSession()
            model.finishSession()
            XCTAssertEqual(model.sessionHistory.filter { $0.id == s.id }.count, 1)
        }
    }

    @MainActor
    func testWarningsPersistAndInAppFeedbackDoesNotDependOnNotificationPermission() throws {
        try withModel { model, station, connector in
            model.startCharging(at: station, connector: connector, targetSoc: 80)
            let s = try XCTUnwrap(model.session)
            model.banners.removeAll()
            model.checkSession(at: s.scheduledDoneAt)
            XCTAssertEqual(model.banners.count, 1)
            let end = s.scheduledDoneAt.addingTimeInterval(Double(s.graceMinutes) * 60)
            model.checkSession(at: end.addingTimeInterval(-120))
            XCTAssertEqual(model.banners.count, 2)
            model.load()
            model.checkSession(at: end.addingTimeInterval(-119))
            XCTAssertEqual(model.banners.count, 2)
            model.checkSession(at: end)
            XCTAssertEqual(model.banners.count, 3)
            model.load()
            model.checkSession(at: end.addingTimeInterval(1))
            XCTAssertEqual(model.banners.count, 3)
            XCTAssertTrue(model.session?.idleAnnounced == true)
        }
    }

    @MainActor
    func testEarlyStopKeepsConnectorOccupiedUntilRelease() throws {
        try withModel { model, station, connector in
            model.startCharging(at: station, connector: connector, targetSoc: 80)
            let s = try XCTUnwrap(model.session)
            let stop = s.startedAt.addingTimeInterval(60)
            model.stopCharging(at: stop)
            model.stopCharging(at: stop.addingTimeInterval(1))
            XCTAssertEqual(model.session?.doneAt, stop)
            XCTAssertEqual(model.sessionEvents.filter { $0.kind == .completed }.count, 1)
            model.refreshStations()
            let c = model.stations.first { $0.id == station.id }!.connectors.first { $0.id == connector.id }!
            XCTAssertEqual(c.status, .idle)
            model.leaveSpot(at: stop.addingTimeInterval(60))
            XCTAssertEqual(model.session?.pointsEarned, 30)
        }
    }

    @MainActor
    func testResetClearsSessionEventsAndScheduledNotifications() throws {
        try withModel { model, station, connector in
            model.startCharging(at: station, connector: connector, targetSoc: 80)
            XCTAssertEqual(model.scheduledSessionNotificationIds.count, 3)
            model.resetDemo()
            XCTAssertNil(model.session)
            XCTAssertTrue(model.sessionEvents.isEmpty)
            XCTAssertTrue(model.scheduledSessionNotificationIds.isEmpty)
            XCTAssertEqual(model.points, 120)
        }
    }

    func testNotificationsScaleWithSimulatedClockAndCancelAfterRelease() {
        let s = Fixtures.session()
        let real = SessionNotificationPlan.items(for: s, now: Fixtures.t0, speed: 1)
        let fast = SessionNotificationPlan.items(for: s, now: Fixtures.t0, speed: 60)
        XCTAssertEqual(real.map(\.kind), [.completed, .warning, .idleStarted])
        XCTAssertEqual(real.map(\.after), [1800, 2280, 2400])
        XCTAssertEqual(fast.map(\.after), [30, 38, 40])
        XCTAssertEqual(real.map(\.id), fast.map(\.id))
        var ended = s
        ended.endedAt = Fixtures.at(minutes: 45)
        XCTAssertTrue(SessionNotificationPlan.items(for: ended, now: Fixtures.t0, speed: 1).isEmpty)
    }

    func testEarlyStopReschedulesWarningAndIdleFromActualCompletion() {
        var s = Fixtures.session()
        s.doneAt = Fixtures.at(minutes: 10)
        let plan = SessionNotificationPlan.items(for: s, now: Fixtures.at(minutes: 10), speed: 1)
        XCTAssertEqual(plan.map(\.kind), [.warning, .idleStarted])
        XCTAssertEqual(plan.map(\.after), [480, 600])
    }

    func testFeePolicyIsFrozenAndSurvivesSerialization() throws {
        let policy = IdleFee.Policy(tiers: [.init(fromMin: 0, eurPerMin: 1)], capEur: 3)
        var s = ChargingSession(stationId: "s", stationName: "S", connectorLabel: "CCS2", startedAt: Fixtures.t0,
                                startSoc: 20, targetSoc: 80, minutesToTarget: 30, graceMinutes: 10,
                                pricePerKwh: 0.5, batteryKwh: 60, connectorId: "c", feePolicy: policy)
        s.doneAt = s.scheduledDoneAt
        let restored = try JSONDecoder().decode(ChargingSession.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(restored.id, s.id)
        XCTAssertEqual(restored.appliedFeePolicy, policy)
        let snap = SessionSnapshot(restored, now: Fixtures.at(minutes: 45))
        XCTAssertEqual(snap.idleFee, 3)
        XCTAssertEqual(snap.idleRate, 1)
        XCTAssertEqual(IdleFee.fee(minutes: 5), 0.5)
    }

    func testLegacySessionsGetStableFallbackIdentityWithoutInventingConnector() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Fixtures.session())) as! [String: Any]
        for key in ["sessionId", "connectorId", "feePolicy", "completionAnnounced", "graceWarningAnnounced", "idleAnnounced"] {
            json.removeValue(forKey: key)
        }
        let data = try JSONSerialization.data(withJSONObject: json)
        let first = try JSONDecoder().decode(ChargingSession.self, from: data)
        let second = try JSONDecoder().decode(ChargingSession.self, from: data)
        XCTAssertEqual(first.id, second.id)
        XCTAssertNil(first.connectorId)
        XCTAssertEqual(first.appliedFeePolicy, .standard)
    }
}
