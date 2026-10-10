import XCTest
@testable import Unplugged

/// Route used throughout: Vilnius -> Klaipeda (about 337 road km). A 60 kWh car at 15 kWh/100 km
/// uses 0.25 % per km, so the whole trip needs ~84 % of the battery.
final class TripPlannerTests: XCTestCase {
    private let from = Fixtures.vilnius
    private let to = Fixtures.klaipeda
    private var routeKm: Double { Geo.roadKm(from, to) }

    private func input(
        vehicle: Vehicle = Fixtures.vehicle(),
        startSoc: Double,
        stations: [Station],
        reserve: Double = 10
    ) -> TripInput {
        TripInput(vehicle: vehicle, startSoc: startSoc, origin: from, destination: to,
                  stations: stations, departure: Fixtures.t0, reserveSoc: reserve)
    }

    // MARK: Feasibility without stops

    func testFullBatteryReachesTheDestinationWithoutStopping() {
        let plan = TripPlanner.plan(input(startSoc: 100, stations: []))
        XCTAssertTrue(plan.feasible)
        XCTAssertTrue(plan.stops.isEmpty)
        XCTAssertEqual(plan.arriveSoc, Int((100 - routeKm * 0.25).rounded()))
        XCTAssertGreaterThanOrEqual(plan.arriveSoc, 10)
        XCTAssertEqual(plan.totalKm, Int(routeKm.rounded()))
        XCTAssertEqual(plan.costEur, 0)
    }

    func testTooLittleBatteryAndNoStationsIsInfeasibleWithAnExplanation() {
        let plan = TripPlanner.plan(input(startSoc: 50, stations: []))
        XCTAssertFalse(plan.feasible)
        XCTAssertTrue(plan.stops.isEmpty)
        XCTAssertNotNil(plan.message)
    }

    // MARK: Stops

    func testAddsChargingStopsWhenTheBatteryIsNotEnough() {
        let stations = Fixtures.corridor(from: from, to: to, count: 5)
        let plan = TripPlanner.plan(input(startSoc: 50, stations: stations))
        XCTAssertTrue(plan.feasible, plan.message ?? "")
        XCTAssertFalse(plan.stops.isEmpty)
        XCTAssertLessThanOrEqual(plan.stops.count, TripPlanner.maxStops)
    }

    func testEveryStopAndTheArrivalRespectTheReserve() {
        let stations = Fixtures.corridor(from: from, to: to, count: 8)
        for reserve in [10.0, 20.0, 30.0] {
            let plan = TripPlanner.plan(input(startSoc: 70, stations: stations, reserve: reserve))
            guard plan.feasible else { continue }
            XCTAssertGreaterThanOrEqual(Double(plan.arriveSoc), reserve - 0.5, "arrival below reserve \(reserve)")
            for stop in plan.stops {
                XCTAssertGreaterThanOrEqual(Double(stop.arriveSoc), reserve - 0.5, "stop \(stop.station.id) below reserve \(reserve)")
            }
        }
    }

    func testAHigherReserveForcesAStopThatALowerReserveDoesNot() {
        // Arriving with ~16 % is fine for a 10 % reserve but not for a 25 % reserve.
        let stations = Fixtures.corridor(from: from, to: to, count: 6)
        let relaxed = TripPlanner.plan(input(startSoc: 100, stations: stations, reserve: 10))
        let strict = TripPlanner.plan(input(startSoc: 100, stations: stations, reserve: 25))
        XCTAssertTrue(relaxed.feasible)
        XCTAssertTrue(relaxed.stops.isEmpty)
        XCTAssertTrue(strict.feasible, strict.message ?? "")
        XCTAssertFalse(strict.stops.isEmpty)
    }

    func testStopsAreConsistentWithTheirOwnNumbers() {
        let stations = Fixtures.corridor(from: from, to: to, count: 6)
        let plan = TripPlanner.plan(input(startSoc: 40, stations: stations))
        XCTAssertTrue(plan.feasible, plan.message ?? "")
        XCTAssertEqual(plan.chargeMinutes, plan.stops.reduce(0) { $0 + $1.chargeMinutes })
        for stop in plan.stops {
            XCTAssertGreaterThan(stop.departSoc, stop.arriveSoc)
            XCTAssertLessThanOrEqual(stop.departSoc, 100)
            XCTAssertEqual(stop.costEur, (stop.energyKwh * stop.station.pricePerKwh * 100).rounded() / 100, accuracy: 0.011)
        }
        XCTAssertEqual(plan.costEur, plan.stops.reduce(0) { $0 + $1.costEur }, accuracy: 0.011)
    }

    func testTravelTimeAddsUpFromTheDepartureTime() {
        let stations = Fixtures.corridor(from: from, to: to, count: 6)
        let plan = TripPlanner.plan(input(startSoc: 40, stations: stations))
        XCTAssertTrue(plan.feasible)
        let elapsed = plan.arriveAt.timeIntervalSince(Fixtures.t0) / 60
        // Drive minutes and charge minutes are each rounded, so allow a minute per leg.
        XCTAssertEqual(elapsed, Double(plan.driveMinutes + plan.chargeMinutes), accuracy: Double(plan.stops.count + 2))
    }

    // MARK: Which stations may be used

    func testOfflineConnectorsAreNeverUsed() {
        let offline = Fixtures.corridor(from: from, to: to, count: 6, connectors: [Fixtures.connector(status: .offline)])
        let plan = TripPlanner.plan(input(startSoc: 50, stations: offline))
        XCTAssertFalse(plan.feasible)
        XCTAssertTrue(plan.stops.isEmpty)
    }

    func testIncompatibleConnectorsAreNeverUsed() {
        let leaf = Fixtures.vehicle(battery: 40, maxDc: 50, maxAc: 6.6, connectors: [.chademo, .type2])
        let ccsOnly = Fixtures.corridor(from: from, to: to, count: 6, connectors: [Fixtures.connector(.ccs2)])
        let plan = TripPlanner.plan(input(vehicle: leaf, startSoc: 60, stations: ccsOnly))
        XCTAssertFalse(plan.feasible)
        XCTAssertTrue(plan.stops.isEmpty)
    }

    func testStationsFarFromTheRouteAreIgnored() {
        let detour = LatLng(lat: from.lat + 2, lng: from.lng) // ~220 km off the line
        let plan = TripPlanner.plan(input(startSoc: 50, stations: [Fixtures.station("far", at: detour)]))
        XCTAssertFalse(plan.feasible)
        XCTAssertTrue(plan.stops.isEmpty)
    }

    func testCompatibleStationIsPreferredOverAnIncompatibleOneAtTheSameSpot() {
        let spot = Fixtures.point(0.4, from: from, to: to)
        let bad = Fixtures.station("bad", at: spot, connectors: [Fixtures.connector(.chademo, kw: 50)])
        let good = Fixtures.station("good", at: spot, connectors: [Fixtures.connector(.ccs2, kw: 150)])
        let plan = TripPlanner.plan(input(startSoc: 50, stations: [bad, good]))
        XCTAssertTrue(plan.feasible, plan.message ?? "")
        XCTAssertTrue(plan.stops.allSatisfy { $0.station.id == "good" })
    }

    // MARK: Limits

    func testPlansNeedingMoreThanTheMaximumStopsAreRejected() {
        // 12 kWh at 24 kWh/100 km is 2 % per km: ~45 km per full charge, so ~8 stops are needed.
        let tiny = Fixtures.vehicle(battery: 12, consumption: 24, maxDc: 100)
        let stations = Fixtures.corridor(from: from, to: to, count: 30)
        let plan = TripPlanner.plan(input(vehicle: tiny, startSoc: 100, stations: stations))
        XCTAssertFalse(plan.feasible)
        XCTAssertLessThanOrEqual(plan.stops.count, TripPlanner.maxStops)
        XCTAssertNotNil(plan.message)
    }

    // MARK: Determinism

    func testSameInputGivesTheSamePlan() {
        let stations = Fixtures.corridor(from: from, to: to, count: 6)
        let a = TripPlanner.plan(input(startSoc: 40, stations: stations))
        let b = TripPlanner.plan(input(startSoc: 40, stations: stations))
        XCTAssertEqual(a.stops.map(\.station.id), b.stops.map(\.station.id))
        XCTAssertEqual(a.arriveSoc, b.arriveSoc)
        XCTAssertEqual(a.costEur, b.costEur)
        XCTAssertEqual(a.arriveAt, b.arriveAt)
    }
}
