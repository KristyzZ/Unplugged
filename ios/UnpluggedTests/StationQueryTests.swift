import XCTest
@testable import Unplugged

final class StationQueryTests: XCTestCase {
    private let car = Fixtures.vehicle()
    private let vilnius = Fixtures.vilnius

    private func station(_ id: String, _ p: LatLng, connectors: [Connector]? = nil, operatorId: String = "test", name: String? = nil) -> Station {
        var s = Fixtures.station(id, at: p, connectors: connectors)
        s = Station(id: s.id, name: name ?? id, address: "Gedimino pr. 1", city: "Vilnius", lat: s.lat, lng: s.lng, operatorId: operatorId,
                    pricePerKwh: s.pricePerKwh, connectors: s.connectors, hourlyOccupancy: [], amenities: [],
                    priceProvenance: s.priceProvenance, capabilities: s.capabilities)
        return s
    }

    private func at(km: Double, bearing: Double = 0) -> LatLng {
        LatLng(lat: vilnius.lat + km / 111.2 * cos(bearing), lng: vilnius.lng + km / (111.2 * cos(vilnius.lat * .pi / 180)) * sin(bearing))
    }

    func testNearestFirstFromTheGivenOrigin() {
        let list = [station("far", at(km: 20)), station("near", at(km: 1)), station("mid", at(km: 5))]
        XCTAssertEqual(StationQuery.items(list, origin: vilnius, vehicle: car, filter: .init(), now: Fixtures.t0).map(\.id), ["near", "mid", "far"])
        // Moving the origin re-orders the same stations.
        let nearFar = at(km: 20)
        XCTAssertEqual(StationQuery.items(list, origin: nearFar, vehicle: car, filter: .init(), now: Fixtures.t0).first?.id, "far")
    }

    func testDistancesAreRealKilometres() {
        let items = StationQuery.items([station("a", at(km: 10))], origin: vilnius, vehicle: car, filter: .init(), now: Fixtures.t0)
        XCTAssertEqual(items[0].distance, 10, accuracy: 0.1)
    }

    func testTiesAreBrokenByIdSoTheOrderIsStable() {
        let p = at(km: 2)
        let list = [station("b", p), station("a", p), station("c", p)]
        XCTAssertEqual(StationQuery.items(list, origin: vilnius, vehicle: car, filter: .init(), now: Fixtures.t0).map(\.id), ["a", "b", "c"])
    }

    func testFiltersCombineOnOneConnector() {
        let fastBusyAndSlowFree = [Fixtures.connector(.ccs2, kw: 150, status: .charging, id: "a"), Fixtures.connector(.type2, kw: 22, status: .available, id: "b")]
        let list = [station("mixed", at(km: 1), connectors: fastBusyAndSlowFree), station("fastFree", at(km: 2), connectors: [Fixtures.connector(.ccs2, kw: 150)])]
        let both = StationQuery.items(list, origin: vilnius, vehicle: car, filter: .init(onlyAvailable: true, fastOnly: true), now: Fixtures.t0)
        XCTAssertEqual(both.map(\.id), ["fastFree"])
    }

    func testOperatorAndTextFilters() {
        let list = [station("a", at(km: 1), operatorId: "ignitis", name: "Akropolis"), station("b", at(km: 2), operatorId: "enefit", name: "Europa")]
        XCTAssertEqual(StationQuery.items(list, origin: vilnius, vehicle: car, filter: .init(operatorId: "enefit"), now: Fixtures.t0).map(\.id), ["b"])
        XCTAssertEqual(StationQuery.items(list, origin: vilnius, vehicle: car, filter: .init(text: "  akro "), now: Fixtures.t0).map(\.id), ["a"])
        XCTAssertEqual(StationQuery.items(list, origin: vilnius, vehicle: car, filter: .init(text: "gedimino"), now: Fixtures.t0).count, 2, "address is searched too")
    }

    func testMyCarFilterUsesCompatibility() {
        let leaf = Fixtures.vehicle(maxDc: 50, maxAc: 6.6, connectors: [.chademo, .type2])
        let list = [station("ccs", at(km: 1), connectors: [Fixtures.connector(.ccs2)]), station("chad", at(km: 2), connectors: [Fixtures.connector(.chademo, kw: 50)])]
        XCTAssertEqual(StationQuery.items(list, origin: vilnius, vehicle: leaf, filter: .init(myCarOnly: true), now: Fixtures.t0).map(\.id), ["chad"])
    }

    // MARK: Pins

    private func grid(_ n: Int) -> [StationQuery.Item] {
        let list = (0..<n).map { i in station("s\(i)", LatLng(lat: 54.0 + Double(i % 100) * 0.01, lng: 24.0 + Double(i / 100) * 0.01)) }
        return StationQuery.items(list, origin: vilnius, vehicle: car, filter: .init(), now: Fixtures.t0)
    }

    func testOnlyStationsInTheVisibleRegionGetPins() {
        let items = grid(400)
        let region = StationQuery.Region(center: LatLng(lat: 54.5, lng: 24.2), latSpan: 0.2, lngSpan: 0.1)
        let pins = StationQuery.pins(items, region: region, selectedId: nil, limit: 1000, thin: false, now: Fixtures.t0)
        XCTAssertFalse(pins.truncated)
        XCTAssertTrue(pins.shown.allSatisfy { region.contains($0.station.latLng) })
        XCTAssertLessThan(pins.shown.count, items.count)
    }

    func testPinsAreCappedAndKeepTheMiddleOfTheScreen() {
        let items = grid(2000)
        let region = StationQuery.Region(center: LatLng(lat: 54.5, lng: 25), latSpan: 2, lngSpan: 2)
        let pins = StationQuery.pins(items, region: region, selectedId: nil, limit: 150, thin: false, now: Fixtures.t0)
        XCTAssertEqual(pins.shown.count, 150)
        XCTAssertTrue(pins.truncated)
        let farthestShown = pins.shown.map { Geo.haversineKm(region.center, $0.station.latLng) }.max() ?? 0
        let closestHidden = items.filter { i in !pins.shown.contains { $0.id == i.id } && region.contains(i.station.latLng) }
            .map { Geo.haversineKm(region.center, $0.station.latLng) }.min() ?? .infinity
        XCTAssertLessThanOrEqual(farthestShown, closestHidden + 1e-9)
    }

    func testTheSelectedStationAlwaysHasAPin() {
        let items = grid(2000)
        let region = StationQuery.Region(center: LatLng(lat: 54.5, lng: 24), latSpan: 0.05, lngSpan: 0.05)
        let far = items.last!.id
        XCTAssertTrue(StationQuery.pins(items, region: region, selectedId: far, now: Fixtures.t0).shown.contains { $0.id == far })
    }

    func testCrowdedPinsAreThinnedToOnePerCellKeepingTheMostUsefulStation() {
        // Twenty stations within a few metres of each other, one of them fast and free.
        let spot = at(km: 1)
        var list = (0..<20).map { i in station("s\(i)", LatLng(lat: spot.lat + Double(i) * 1e-6, lng: spot.lng), connectors: [Fixtures.connector(.type2, kw: 22, status: .charging)]) }
        list.append(station("fast", LatLng(lat: spot.lat + 5e-6, lng: spot.lng), connectors: [Fixtures.connector(.ccs2, kw: 150)]))
        let items = StationQuery.items(list, origin: vilnius, vehicle: car, filter: .init(), now: Fixtures.t0)
        let region = StationQuery.Region(center: vilnius, latSpan: 0.11, lngSpan: 0.11)
        let pins = StationQuery.pins(items, region: region, selectedId: nil, now: Fixtures.t0)
        XCTAssertEqual(pins.shown.map(\.id), ["fast"])
        XCTAssertTrue(pins.truncated)
    }

    func testZoomingInRevealsTheThinnedStations() {
        let spot = at(km: 1)
        let list = (0..<20).map { i in station("s\(i)", LatLng(lat: spot.lat + Double(i) * 0.0004, lng: spot.lng)) }
        let items = StationQuery.items(list, origin: vilnius, vehicle: car, filter: .init(), now: Fixtures.t0)
        let far = StationQuery.pins(items, region: .init(center: spot, latSpan: 0.11, lngSpan: 0.11), selectedId: nil, now: Fixtures.t0).shown.count
        let near = StationQuery.pins(items, region: .init(center: spot, latSpan: 0.01, lngSpan: 0.01), selectedId: nil, now: Fixtures.t0).shown.count
        XCTAssertLessThan(far, near)
    }

    func testWithoutARegionTheNearestAreShown() {
        let items = grid(500)
        XCTAssertEqual(StationQuery.pins(items, region: nil, selectedId: nil, limit: 150).shown.map(\.id), items.prefix(150).map(\.id))
    }

    func testFilteringAndPinningTheWholeCountryIsFast() throws {
        let snapshot = try XCTUnwrap(FeedSnapshot.bundled())
        let stations = StationBuilder.stations(from: snapshot)
        let region = StationQuery.Region(center: vilnius, latSpan: 0.1, lngSpan: 0.1)
        measure {
            let items = StationQuery.items(stations, origin: vilnius, vehicle: car, filter: .init(onlyAvailable: true, myCarOnly: true))
            _ = StationQuery.pins(items, region: region, selectedId: nil)
        }
    }
}
