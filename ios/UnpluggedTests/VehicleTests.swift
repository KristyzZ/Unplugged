import XCTest
@testable import Unplugged

final class VehicleTests: XCTestCase {
    // MARK: Bundled catalog (Open EV Data)

    func testCatalogLoadsEveryModel() {
        XCTAssertGreaterThan(VehicleCatalog.all.count, 500)
        XCTAssertEqual(Set(VehicleCatalog.all.map(\.id)).count, VehicleCatalog.all.count, "ids must be unique")
    }

    func testEarlierBuiltInIdsStillResolve() {
        // Saved state from before the catalog used short ids like "ioniq5".
        let car = VehicleCatalog.vehicle("ioniq5")
        XCTAssertEqual(car.brand, "Hyundai")
        XCTAssertTrue(car.name.contains("IONIQ 5"))
    }

    func testUnknownIdFallsBackToTheDefaultCar() {
        XCTAssertEqual(VehicleCatalog.vehicle("no-such-car").id, VehicleCatalog.vehicle(VehicleCatalog.defaultId).id)
    }

    func testEveryModelIsUsable() {
        for car in VehicleCatalog.all {
            XCTAssertGreaterThan(car.batteryKwh, 0, car.id)
            XCTAssertGreaterThan(car.consumptionKwhPer100, 0, car.id)
            XCTAssertFalse(car.connectors.isEmpty, car.id)
        }
    }

    func testSearchMatchesEveryWord() {
        let results = VehicleCatalog.search("tesla model 3")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.brand == "Tesla" })
        XCTAssertTrue(results.contains { $0.model.hasPrefix("Model 3") })
    }

    // MARK: Charging curve

    func testCurveIsInterpolatedBetweenPoints() {
        let car = Fixtures.vehicle(curve: [[0, 100], [50, 200], [100, 20]])
        XCTAssertEqual(car.dcPower(atSoc: 25), 150, accuracy: 1e-9)
        XCTAssertEqual(car.dcPower(atSoc: 50), 200, accuracy: 1e-9)
        XCTAssertEqual(car.dcPower(atSoc: 75), 110, accuracy: 1e-9)
    }

    func testWithoutACurveTheTypicalTaperApplies() {
        let car = Fixtures.vehicle(maxDc: 150)
        XCTAssertEqual(car.dcPower(atSoc: 30), 150, accuracy: 1e-9)
        XCTAssertEqual(car.dcPower(atSoc: 80), 150 * Charging.taper(80), accuracy: 1e-9)
    }

    func testChargeTimeFollowsTheCarsCurve() {
        // Flat 60 kW curve on a 60 kWh battery: 10 → 60 % is 30 kWh = 30 min.
        let car = Fixtures.vehicle(maxDc: 60, curve: [[0, 60], [100, 60]])
        let result = Charging.chargeTime(car, Fixtures.connector(.ccs2, kw: 150), from: 10, to: 60)
        XCTAssertEqual(result.minutes, 30)
    }

    func testChargerPowerStillCapsTheCurve() {
        let car = Fixtures.vehicle(maxDc: 200, curve: [[0, 200], [100, 200]])
        let slow = Charging.chargeTime(car, Fixtures.connector(.ccs2, kw: 50), from: 10, to: 60)
        // 30 kWh at 50 kW = 36 min.
        XCTAssertEqual(slow.minutes, 36)
    }
}
