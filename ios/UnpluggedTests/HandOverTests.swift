import XCTest
@testable import Unplugged

/// When a driver leaves a station where someone is waiting, the charger is held for the next driver
/// (shown as reserved), and an on-time driver earns a bonus. "Someone waiting" is injected so these
/// tests do not depend on the hour they run.
final class HandOverTests: XCTestCase {
    @MainActor
    private func withModel(someoneWaiting: Bool, _ action: (AppModel, Station, Connector) throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let keys = ["unplugged.state.v1", "unplugged.state.v2", "unplugged.lang"]
        let previous = keys.map { defaults.object(forKey: $0) }
        keys.forEach { defaults.removeObject(forKey: $0) }
        let model = AppModel(runLoops: false, stationSource: .demo)
        model.lockScreenEnabled = false
        model.someoneWaitingAt = { _ in someoneWaiting }
        defer {
            model.resetDemo()
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        var station = model.stations.first { $0.id == "akropolis" }!
        station.connectors[0].status = .available
        station.connectors[0].provenance = .demo(at: .now)
        try action(model, station, station.connectors[0])
    }

    @MainActor
    private func status(_ model: AppModel, _ station: Station, _ connector: Connector) -> ConnectorStatus? {
        model.stations.first { $0.id == station.id }?.connectors.first { $0.id == connector.id }?.status
    }

    @MainActor
    func testNobodyWaitingFreesTheSpotWithNoBonus() throws {
        try withModel(someoneWaiting: false) { model, station, connector in
            model.startCharging(at: station, connector: connector, targetSoc: 80)
            let s = try XCTUnwrap(model.session)
            model.checkSession(at: s.scheduledDoneAt)
            model.leaveSpot(at: s.scheduledDoneAt.addingTimeInterval(60))
            XCTAssertTrue(model.holds.isEmpty)
            XCTAssertEqual(status(model, station, connector), .available)
            XCTAssertEqual(model.session?.handedOver, false)
            XCTAssertEqual(model.session?.pointsEarned, PointsReason.movedFast.points)
        }
    }

    @MainActor
    func testSomeoneWaitingHoldsTheChargerAndPaysTheBonusToAnOnTimeDriver() throws {
        try withModel(someoneWaiting: true) { model, station, connector in
            model.startCharging(at: station, connector: connector, targetSoc: 80)
            let s = try XCTUnwrap(model.session)
            model.checkSession(at: s.scheduledDoneAt)
            model.leaveSpot(at: s.scheduledDoneAt.addingTimeInterval(60))
            let hold = try XCTUnwrap(model.holds.first)
            XCTAssertEqual(model.holds.count, 1)
            XCTAssertFalse(hold.forMe)
            XCTAssertEqual(hold.connectorId, connector.id)
            XCTAssertEqual(status(model, station, connector), .reserved, "the hold wins over the 'just released' overlay")
            XCTAssertEqual(model.session?.handedOver, true)
            XCTAssertEqual(model.session?.pointsEarned, PointsReason.movedFast.points + PointsReason.handedOver.points)
            XCTAssertTrue(model.history.contains { $0.reason == .handedOver })
        }
    }

    @MainActor
    func testAnOverstayStillHandsTheSpotOnButEarnsNothing() throws {
        try withModel(someoneWaiting: true) { model, station, connector in
            model.startCharging(at: station, connector: connector, targetSoc: 80)
            let s = try XCTUnwrap(model.session)
            model.checkSession(at: s.scheduledDoneAt)
            model.leaveSpot(at: s.scheduledDoneAt.addingTimeInterval(Double(s.graceMinutes + 5) * 60))
            XCTAssertEqual(model.holds.count, 1)
            XCTAssertEqual(model.session?.handedOver, true)
            XCTAssertEqual(model.session?.pointsEarned, 0)
            XCTAssertFalse(model.history.contains { $0.reason == .handedOver })
        }
    }

    @MainActor
    func testTheSpotHeldForMeCanBeStartedEvenThoughItIsReservedForEveryoneElse() throws {
        try withModel(someoneWaiting: false) { model, station, connector in
            let now = model.simNow()
            model.holds = [SpotHold(stationId: station.id, stationName: station.name, connectorId: connector.id,
                                    connectorLabel: "CCS2", startedAt: now,
                                    until: now.addingTimeInterval(SpotHold.minutes * 60), forMe: true)]
            model.refreshStations()
            XCTAssertEqual(status(model, station, connector), .reserved)
            let held = try XCTUnwrap(model.stations.first { $0.id == station.id }?.connectors.first { $0.id == connector.id })
            model.startCharging(at: station, connector: held, targetSoc: 80)
            XCTAssertNotNil(model.session, "starting at the spot held for you must work")
            XCTAssertTrue(model.holds.filter(\.forMe).isEmpty, "starting uses up the hold")
            XCTAssertEqual(status(model, station, connector), .charging)
        }
    }

    @MainActor
    func testSomeoneElsesHoldCannotBeStarted() throws {
        try withModel(someoneWaiting: false) { model, station, connector in
            let now = model.simNow()
            model.holds = [SpotHold(stationId: station.id, stationName: station.name, connectorId: connector.id,
                                    connectorLabel: "CCS2", startedAt: now,
                                    until: now.addingTimeInterval(SpotHold.minutes * 60), forMe: false)]
            model.refreshStations()
            let held = try XCTUnwrap(model.stations.first { $0.id == station.id }?.connectors.first { $0.id == connector.id })
            model.startCharging(at: station, connector: held, targetSoc: 80)
            XCTAssertNil(model.session)
        }
    }
}
