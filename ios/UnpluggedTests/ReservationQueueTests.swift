import XCTest
@testable import Unplugged

final class ReservationQueueTests: XCTestCase {
    @MainActor private func withModel(_ action: (AppModel, Station, Connector) throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let keys = ["unplugged.state.v1", "unplugged.state.v2", "unplugged.lang"]
        let previous = keys.map { defaults.object(forKey: $0) }
        keys.forEach { defaults.removeObject(forKey: $0) }
        let model = AppModel(runLoops: false)
        model.lockScreenEnabled = false
        model.realAnchor = .now
        model.simAnchor = Fixtures.t0
        defer {
            model.resetDemo()
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        var station = model.stations.first { $0.id == "akropolis" }!
        station.connectors = [Fixtures.connector(id: "reserved-port", dataClass: .demo)]
        station.connectors[0].provenance = .demo(at: .now)
        model.stations = [station]
        try action(model, station, station.connectors[0])
    }

    func testArrivalWindowIsExactlyTenMinutesFromScheduledStart() {
        let start = Fixtures.at(minutes: 30)
        let hold = SpotHold(stationId: "s", stationName: "S", connectorId: "c", connectorLabel: "CCS2",
                            startedAt: start, until: ReservationRules.deadline(start: start), forMe: true)
        XCTAssertFalse(hold.isActive(at: start.addingTimeInterval(-0.001)))
        XCTAssertTrue(hold.isActive(at: start))
        XCTAssertTrue(hold.isActive(at: start.addingTimeInterval(599.999)))
        XCTAssertFalse(hold.isActive(at: start.addingTimeInterval(600)))
        XCTAssertEqual(hold.duration, 600)
    }

    func testPastAndOutOfHorizonStartsAreRejected() {
        XCTAssertFalse(ReservationRules.validStart(Fixtures.t0.addingTimeInterval(-1), now: Fixtures.t0))
        XCTAssertTrue(ReservationRules.validStart(Fixtures.t0, now: Fixtures.t0))
        XCTAssertTrue(ReservationRules.validStart(Fixtures.t0.addingTimeInterval(86400), now: Fixtures.t0))
        XCTAssertFalse(ReservationRules.validStart(Fixtures.t0.addingTimeInterval(86401), now: Fixtures.t0))
    }

    @MainActor func testScheduledReservationActivatesAndExpiresWithoutExtendingItsDeadline() throws {
        try withModel { model, station, connector in
            let start = Fixtures.at(minutes: 30)
            XCTAssertTrue(model.reserveConnector(at: station, connector: connector, startsAt: start, now: Fixtures.t0))
            XCTAssertEqual(model.stations[0].connectors[0].status, .available)
            XCTAssertNil(model.myHold)
            model.checkQueueAndHolds(at: start)
            XCTAssertEqual(model.stations[0].connectors[0].status, .reserved)
            XCTAssertEqual(model.holds.first?.until, Fixtures.at(minutes: 40))
            model.checkQueueAndHolds(at: Fixtures.at(minutes: 40))
            XCTAssertNotNil(model.holds.first?.releasedAt)
            XCTAssertEqual(model.stations[0].connectors[0].status, .available)
            let bannerCount = model.banners.count
            model.checkQueueAndHolds(at: Fixtures.at(minutes: 40))
            XCTAssertEqual(model.banners.count, bannerCount)
            model.load()
            XCTAssertEqual(model.holds.first?.until, Fixtures.at(minutes: 40))
            XCTAssertNotNil(model.holds.first?.releasedAt)
        }
    }

    @MainActor func testCanStartBeforeExpiryAndConsumedReservationDoesNotExpireCharging() throws {
        try withModel { model, station, connector in
            XCTAssertTrue(model.reserveConnector(at: station, connector: connector, now: Fixtures.t0))
            let held = model.stations[0].connectors[0]
            model.startCharging(at: station, connector: held, targetSoc: 80, now: Fixtures.at(minutes: 9))
            XCTAssertNotNil(model.session)
            XCTAssertTrue(model.holds.filter(\.forMe).isEmpty)
            model.checkQueueAndHolds(at: Fixtures.at(minutes: 10))
            XCTAssertEqual(model.stations[0].connectors[0].status, .charging)
            XCTAssertTrue(model.hasActiveSession)
        }
    }

    @MainActor func testEarlyAndExactDeadlineStartsCannotUseReservationPrivilege() throws {
        try withModel { model, station, connector in
            let start = Fixtures.at(minutes: 30)
            XCTAssertTrue(model.reserveConnector(at: station, connector: connector, startsAt: start, now: Fixtures.t0))
            model.startCharging(at: station, connector: connector, targetSoc: 80, now: Fixtures.at(minutes: 29))
            XCTAssertNil(model.session)
            model.checkQueueAndHolds(at: start)
            let held = model.stations[0].connectors[0]
            model.startCharging(at: station, connector: held, targetSoc: 80, now: Fixtures.at(minutes: 40))
            XCTAssertNil(model.session)
        }
    }

    @MainActor func testStaleAvailableSnapshotCannotStealAnotherDriversReservation() {
        withModel { model, station, connector in
            model.holds = [SpotHold(stationId: station.id, stationName: station.name, connectorId: connector.id,
                connectorLabel: "CCS2", startedAt: Fixtures.t0, until: Fixtures.at(minutes: 10), forMe: false)]
            model.startCharging(at: station, connector: connector, targetSoc: 80, now: Fixtures.at(minutes: 1))
            XCTAssertNil(model.session)
        }
    }

    @MainActor func testDuplicateReservationAndQueueAreRejectedWhileBookingExists() {
        withModel { model, station, connector in
            XCTAssertTrue(model.reserveConnector(at: station, connector: connector, now: Fixtures.t0))
            XCTAssertFalse(model.reserveConnector(at: station, connector: connector, now: Fixtures.t0))
            XCTAssertFalse(model.joinQueue(station, now: Fixtures.t0))
            XCTAssertEqual(model.holds.count, 1)
        }
    }

    @MainActor func testQueueNeverAssignsOccupiedConnectorsAndRetapsKeepPosition() {
        withModel { model, input, _ in
            var station = input
            station.connectors[0].status = .charging
            model.stations = [station]
            XCTAssertTrue(model.joinQueue(station, now: Fixtures.t0))
            let queued = model.queue
            XCTAssertTrue(model.joinQueue(station, now: Fixtures.at(minutes: 1)))
            XCTAssertEqual(model.queue, queued)
            model.checkQueueAndHolds(at: Fixtures.at(minutes: 2))
            XCTAssertTrue(model.holds.isEmpty)
            XCTAssertNotNil(model.queue)
            model.stations[0].connectors[0].status = .available
            model.checkQueueAndHolds(at: Fixtures.at(minutes: 3))
            XCTAssertNil(model.queue)
            XCTAssertEqual(model.holds.first?.until, Fixtures.at(minutes: 13))
            XCTAssertEqual(model.holds.first?.forMe, true)
        }
    }

    @MainActor func testExpiryPassesReleasedPortToNextQueuedDriver() {
        withModel { model, station, connector in
            model.holds = [SpotHold(stationId: station.id, stationName: station.name, connectorId: connector.id,
                connectorLabel: "CCS2", startedAt: Fixtures.t0, until: Fixtures.at(minutes: 10), forMe: false)]
            model.applyHolds(at: Fixtures.t0)
            XCTAssertTrue(model.joinQueue(model.stations[0], now: Fixtures.t0))
            model.checkQueueAndHolds(at: Fixtures.at(minutes: 10))
            XCTAssertNil(model.queue)
            XCTAssertEqual(model.holds.first?.forMe, true)
            XCTAssertEqual(model.holds.first?.until, Fixtures.at(minutes: 20))
            XCTAssertEqual(model.stations[0].connectors[0].status, .reserved)
        }
    }

    @MainActor func testCancellationReleasesActiveHoldAndRemovesFutureBooking() {
        withModel { model, station, connector in
            XCTAssertTrue(model.reserveConnector(at: station, connector: connector, now: Fixtures.t0))
            model.releaseHold()
            XCTAssertNil(model.myReservation)
            XCTAssertEqual(model.stations[0].connectors[0].status, .available)
            XCTAssertTrue(model.reserveConnector(at: station, connector: connector, startsAt: Fixtures.at(minutes: 30), now: Fixtures.t0))
            model.releaseHold()
            XCTAssertNil(model.myReservation)
            XCTAssertTrue(model.holds.isEmpty)
        }
    }

    @MainActor func testInvalidConnectorAndDiscoveryStationCannotBeBookedOrQueued() {
        withModel { model, input, connector in
            var station = input
            station.capabilities = .discoveryOnly
            XCTAssertFalse(model.reserveConnector(at: station, connector: connector, now: Fixtures.t0))
            XCTAssertFalse(model.joinQueue(station, now: Fixtures.t0))
            station = input
            station.connectors[0].status = .offline
            XCTAssertFalse(model.reserveConnector(at: station, connector: station.connectors[0], now: Fixtures.t0))
            XCTAssertFalse(model.joinQueue(station, now: Fixtures.t0))
        }
    }

    @MainActor func testOldAvailableSnapshotCannotReserveAnOccupiedConnector() {
        withModel { model, station, connector in
            model.stations[0].connectors[0].status = .charging
            XCTAssertFalse(model.reserveConnector(at: station, connector: connector, now: Fixtures.t0))
            XCTAssertTrue(model.holds.isEmpty)
        }
    }

    @MainActor func testRelaunchKeepsBookingTimeAndResetClearsIt() {
        withModel { model, station, connector in
            let start = Fixtures.at(minutes: 30)
            XCTAssertTrue(model.reserveConnector(at: station, connector: connector, startsAt: start, now: Fixtures.t0))
            model.load()
            XCTAssertEqual(model.myReservation?.startedAt, start)
            XCTAssertEqual(model.myReservation?.until, Fixtures.at(minutes: 40))
            model.resetDemo()
            model.load()
            XCTAssertNil(model.myReservation)
            XCTAssertNil(model.queue)
        }
    }

    func testLegacyHoldDecodesWithoutNewMetadataAndKeepsShorterWindow() throws {
        let hold = SpotHold(stationId: "s", stationName: "S", connectorId: "c", connectorLabel: "CCS2",
                            startedAt: Fixtures.t0, until: Fixtures.at(minutes: 5), forMe: true)
        let decoded = try JSONDecoder().decode(SpotHold.self, from: JSONEncoder().encode(hold))
        XCTAssertEqual(decoded.duration, 300)
        XCTAssertNil(decoded.bookedAt)
        XCTAssertNil(decoded.releasedAt)
    }

    func testNotificationBoundariesAndAcceleratedClock() {
        let start = Fixtures.at(minutes: 5)
        let hold = SpotHold(stationId: "s", stationName: "S", connectorId: "c", connectorLabel: "CCS2",
                            startedAt: start, until: Fixtures.at(minutes: 15), forMe: true)
        let plans = ReservationNotificationPlan.items(for: hold, now: Fixtures.t0, speed: 10)
        XCTAssertEqual(plans.map(\.after), [30, 84, 90])
        XCTAssertEqual(ReservationNotificationPlan.items(for: hold, now: Fixtures.at(minutes: 14), speed: 1).map(\.after), [60])
        XCTAssertTrue(ReservationNotificationPlan.items(for: hold, now: Fixtures.at(minutes: 15), speed: 1).isEmpty)
    }
}
