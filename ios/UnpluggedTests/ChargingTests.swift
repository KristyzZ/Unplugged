import XCTest
@testable import Unplugged

final class ChargingTests: XCTestCase {
    // MARK: Taper curve

    func testTaperIsFullPowerBelowHalf() {
        XCTAssertEqual(Charging.taper(0), 1)
        XCTAssertEqual(Charging.taper(49.9), 1)
        XCTAssertEqual(Charging.taper(50), 1)
    }

    func testTaperKnownPoints() {
        XCTAssertEqual(Charging.taper(65), 0.775, accuracy: 1e-9)
        XCTAssertEqual(Charging.taper(80), 0.55, accuracy: 1e-9)
        XCTAssertEqual(Charging.taper(100), 0.15, accuracy: 1e-9)
    }

    func testTaperNeverIncreases() {
        var previous = 1.0
        for soc in stride(from: 0.0, through: 100, by: 1) {
            let value = Charging.taper(soc)
            XCTAssertLessThanOrEqual(value, previous + 1e-12, "taper rose at \(soc) %")
            XCTAssertGreaterThan(value, 0)
            previous = value
        }
    }

    // MARK: Compatibility

    func testCompatibilityFollowsTheVehiclesConnectors() {
        let car = Fixtures.vehicle(connectors: [.ccs2, .type2])
        XCTAssertTrue(Charging.isCompatible(car, Fixtures.connector(.ccs2)))
        XCTAssertTrue(Charging.isCompatible(car, Fixtures.connector(.type2, kw: 22)))
        XCTAssertFalse(Charging.isCompatible(car, Fixtures.connector(.chademo, kw: 50)))
    }

    func testChademoCarDoesNotAcceptCcs() {
        let leaf = Fixtures.vehicle(maxDc: 50, maxAc: 6.6, connectors: [.chademo, .type2])
        XCTAssertTrue(Charging.isCompatible(leaf, Fixtures.connector(.chademo, kw: 50)))
        XCTAssertFalse(Charging.isCompatible(leaf, Fixtures.connector(.ccs2, kw: 150)))
    }

    // MARK: Power limits

    func testCarLimitsDcPower() {
        let car = Fixtures.vehicle(maxDc: 135)
        XCTAssertEqual(Charging.effectivePeakKw(car, Fixtures.connector(.ccs2, kw: 350)), 135)
        XCTAssertEqual(Charging.effectivePeakKw(car, Fixtures.connector(.ccs2, kw: 50)), 50)
    }

    func testCarLimitsAcPower() {
        let car = Fixtures.vehicle(maxAc: 11)
        XCTAssertEqual(Charging.effectivePeakKw(car, Fixtures.connector(.type2, kw: 22)), 11)
        XCTAssertEqual(Charging.effectivePeakKw(car, Fixtures.connector(.type2, kw: 7.4)), 7.4)
    }

    // MARK: Charge time and energy

    func testNothingToChargeWhenTargetIsNotAboveStart() {
        let car = Fixtures.vehicle()
        let result = Charging.chargeTime(car, Fixtures.connector(), from: 80, to: 80)
        XCTAssertEqual(result.minutes, 0)
        XCTAssertEqual(result.kwh, 0)
        XCTAssertEqual(Charging.chargeTime(car, Fixtures.connector(), from: 90, to: 20).minutes, 0)
    }

    func testAcChargingIsFlat() {
        // 60 kWh battery, 11 kW AC: 60 % = 36 kWh / 11 kW = 196.4 min; energy includes ~8 % losses.
        let result = Charging.chargeTime(Fixtures.vehicle(), Fixtures.connector(.type2, kw: 22), from: 20, to: 80)
        XCTAssertEqual(result.minutes, 196)
        XCTAssertEqual(result.kwh, 39.1, accuracy: 1e-9)
    }

    func testDcBelowTheTaperRunsAtPeakPower() {
        // 40 % of 60 kWh = 24 kWh at 150 kW = 9.6 min.
        let result = Charging.chargeTime(Fixtures.vehicle(), Fixtures.connector(.ccs2, kw: 150), from: 10, to: 50)
        XCTAssertEqual(result.minutes, 10)
        XCTAssertEqual(result.kwh, 26.1, accuracy: 1e-9)
    }

    func testTopOfTheBatteryChargesSlowerThanTheMiddle() {
        let car = Fixtures.vehicle()
        let dc = Fixtures.connector(.ccs2, kw: 150)
        let middle = Charging.chargeTime(car, dc, from: 10, to: 30).minutes
        let top = Charging.chargeTime(car, dc, from: 80, to: 100).minutes
        XCTAssertGreaterThan(top, middle * 2, "20 points near full should take far longer than in the middle")
    }

    func testConnectorPowerAboveTheCarsLimitChangesNothing() {
        let car = Fixtures.vehicle(maxDc: 100)
        let at150 = Charging.chargeTime(car, Fixtures.connector(.ccs2, kw: 150), from: 10, to: 80)
        let at350 = Charging.chargeTime(car, Fixtures.connector(.ccs2, kw: 350), from: 10, to: 80)
        XCTAssertEqual(at150.minutes, at350.minutes)
        XCTAssertEqual(at150.kwh, at350.kwh)
    }

    func testFasterConnectorChargesFasterUntilTheCarsLimit() {
        let car = Fixtures.vehicle(maxDc: 250)
        let slow = Charging.chargeTime(car, Fixtures.connector(.ccs2, kw: 50), from: 10, to: 80).minutes
        let fast = Charging.chargeTime(car, Fixtures.connector(.ccs2, kw: 150), from: 10, to: 80).minutes
        XCTAssertLessThan(fast, slow)
    }

    func testEnergyScalesWithTheAmountCharged() {
        let car = Fixtures.vehicle()
        let dc = Fixtures.connector()
        let small = Charging.chargeTime(car, dc, from: 20, to: 40).kwh
        let large = Charging.chargeTime(car, dc, from: 20, to: 60).kwh
        XCTAssertEqual(large, small * 2, accuracy: 0.2)
    }

    // MARK: Range

    func testRangeFollowsBatteryAndConsumption() {
        let car = Fixtures.vehicle(battery: 60, consumption: 15)
        XCTAssertEqual(car.rangeKm(soc: 100), 400, accuracy: 1e-9)
        XCTAssertEqual(car.rangeKm(soc: 50), 200, accuracy: 1e-9)
        XCTAssertEqual(car.rangeKm(soc: 0), 0)
    }
}
