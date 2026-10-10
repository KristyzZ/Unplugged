import XCTest
@testable import Unplugged

/// Map grouping, the private-charger filter and the demo private chargers.
final class MapClusterTests: XCTestCase {
    private let vilnius = Fixtures.vilnius

    private func item(_ id: String, dLat: Double, dLng: Double = 0, operatorId: String = "test") -> StationQuery.Item {
        let s = Fixtures.station(id, at: LatLng(lat: vilnius.lat + dLat, lng: vilnius.lng + dLng))
        let station = Station(id: s.id, name: id, address: "", city: "Vilnius", lat: s.lat, lng: s.lng, operatorId: operatorId,
                              pricePerKwh: s.pricePerKwh, connectors: s.connectors, hourlyOccupancy: [], amenities: [],
                              priceProvenance: s.priceProvenance, capabilities: s.capabilities)
        return StationQuery.Item(station: station, distance: 0)
    }

    private func region(span: Double) -> StationQuery.Region {
        .init(center: vilnius, latSpan: span, lngSpan: span)
    }

    func testCloseStationsAreGroupedWhenZoomedOut() {
        let items = (0..<6).map { item("s\($0)", dLat: Double($0) * 0.0002) }
        let clusters = StationQuery.clusters(items, region: region(span: 0.2), selectedId: nil)
        XCTAssertLessThan(clusters.count, items.count)
        XCTAssertEqual(clusters.reduce(0) { $0 + $1.items.count }, items.count, "no station is lost")
    }

    func testEveryStationGetsAPinWhenZoomedIn() {
        let items = (0..<6).map { item("s\($0)", dLat: Double($0) * 0.0002) }
        let clusters = StationQuery.clusters(items, region: region(span: StationQuery.expandSpan), selectedId: nil)
        XCTAssertEqual(clusters.count, 6)
        XCTAssertTrue(clusters.allSatisfy { $0.single != nil })
    }

    func testFarApartStationsStaySeparate() {
        let items = [item("a", dLat: -0.08, dLng: -0.08), item("b", dLat: 0.08, dLng: 0.08)]
        XCTAssertEqual(StationQuery.clusters(items, region: region(span: 0.2), selectedId: nil).count, 2)
    }

    func testSelectedStationIsNeverHiddenInAGroup() {
        let items = (0..<4).map { item("s\($0)", dLat: Double($0) * 0.0001) }
        let clusters = StationQuery.clusters(items, region: region(span: 0.2), selectedId: "s2")
        XCTAssertTrue(clusters.contains { $0.single?.id == "s2" })
    }

    func testPrivateOnlyFilter() {
        let stations = [item("pub", dLat: 0).station, item("home", dLat: 0.01, operatorId: HostListing.operatorId).station]
        let ids = StationQuery.items(stations, origin: vilnius, vehicle: Fixtures.vehicle(),
                                     filter: .init(privateOnly: true), now: Fixtures.t0).map(\.id)
        XCTAssertEqual(ids, ["home"])
    }

    func testDemoPrivateChargersAcrossLithuania() {
        let listings = PrivateChargers.listings
        XCTAssertEqual(listings.count, 50)
        XCTAssertEqual(listings.filter { $0.city == "Vilnius" }.count, 30)
        XCTAssertEqual(Set(listings.map(\.id)).count, 50, "unique ids")
        // Inside Lithuania.
        XCTAssertTrue(listings.allSatisfy { (53.8...56.5).contains($0.location.lat) && (20.9...26.9).contains($0.location.lng) })
        XCTAssertTrue(PrivateChargers.stations().allSatisfy { $0.operatorId == HostListing.operatorId })
    }

    func testClusterFreeCountIsStationsNotPlugs() {
        // Fixture stations have several free plugs each; the bubble counts stations.
        let items = (0..<3).map { item("s\($0)", dLat: Double($0) * 0.0001) }
        let cluster = StationQuery.Cluster(items: items, center: vilnius)
        XCTAssertLessThanOrEqual(cluster.freeStations(at: Fixtures.t0), items.count)
    }
}
