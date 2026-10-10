import XCTest
@testable import Unplugged

/// Station page helpers: charge level reached for a chosen time, and the header subtitle.
final class StationPageTests: XCTestCase {
    private let car = Fixtures.vehicle()

    func testTargetSocGrowsWithTimeAndStopsAtFull() {
        let c = Fixtures.connector(status: .available)
        let short = Charging.targetSoc(car, c, from: 30, minutes: 10)
        let long = Charging.targetSoc(car, c, from: 30, minutes: 60)
        XCTAssertGreaterThan(short, 30)
        XCTAssertGreaterThanOrEqual(long, short)
        XCTAssertEqual(Charging.targetSoc(car, c, from: 30, minutes: 100_000), 100)
        XCTAssertEqual(Charging.targetSoc(car, c, from: 30, minutes: 0), 30)
    }

    func testTargetSocMatchesChargeTime() {
        let c = Fixtures.connector(status: .available)
        let target = Charging.targetSoc(car, c, from: 20, minutes: 25)
        XCTAssertGreaterThanOrEqual(Charging.chargeTime(car, c, from: 20, to: target).minutes, 25)
        XCTAssertLessThan(Charging.chargeTime(car, c, from: 20, to: target - 1).minutes, 25)
    }

    private func station(name: String, address: String, city: String) -> Station {
        let s = Fixtures.station("s", at: Fixtures.vilnius)
        return Station(id: s.id, name: name, address: address, city: city, lat: s.lat, lng: s.lng, operatorId: "op",
                       pricePerKwh: 0.3, connectors: s.connectors, hourlyOccupancy: [], amenities: [],
                       priceProvenance: s.priceProvenance, capabilities: s.capabilities)
    }

    func testSubtitleSkipsAddressAlreadyInName() {
        let s = station(name: "Norfa XL, Mokyklos g. 2C", address: "Mokyklos g. 2C", city: "Vilnius")
        XCTAssertEqual(StationDetailView.subtitle(s, operatorName: "Enefit"), "Enefit · Vilnius")
    }

    func testSubtitleKeepsAddressWhenNameIsDifferent() {
        let s = station(name: "Akropolis", address: "Ozo g. 25", city: "Vilnius")
        XCTAssertEqual(StationDetailView.subtitle(s, operatorName: "Ignitis"), "Ignitis · Ozo g. 25 · Vilnius")
    }
}
