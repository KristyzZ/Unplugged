import XCTest
@testable import Unplugged

final class ProvenanceTests: XCTestCase {
    private let now = Fixtures.t0

    // MARK: Integration levels / capabilities

    func testEachLevelIncludesTheOnesBeforeIt() {
        XCTAssertTrue(IntegrationLevel.discovery < .liveData)
        XCTAssertTrue(IntegrationLevel.liveData < .accountPricing)
        XCTAssertTrue(IntegrationLevel.accountPricing < .fullCharging)
    }

    func testCapabilitiesDistinguishDiscoveryLiveDataAccountPricingAndSessionControl() {
        func caps(_ level: IntegrationLevel) -> [Bool] {
            let c = StationCapabilities(level: level, simulated: false)
            return [c.providesLiveStatus, c.supportsAccountPricing, c.supportsSessionControl]
        }
        XCTAssertEqual(caps(.discovery), [false, false, false])
        XCTAssertEqual(caps(.liveData), [true, false, false])
        XCTAssertEqual(caps(.accountPricing), [true, true, false])
        XCTAssertEqual(caps(.fullCharging), [true, true, true])
    }

    func testDemoCapabilitiesAreExplicitlySimulatedAndTheDefaultMakesNoClaims() {
        XCTAssertTrue(StationCapabilities.demo().simulated)
        XCTAssertEqual(StationCapabilities.demo().level, .fullCharging)
        XCTAssertFalse(StationCapabilities.discoveryOnly.simulated)
        XCTAssertFalse(StationCapabilities.discoveryOnly.supportsSessionControl)
        let plain = Station(id: "x", name: "x", address: "", city: "", lat: 0, lng: 0, operatorId: "t", pricePerKwh: 0.4,
                            connectors: [], hourlyOccupancy: [], amenities: [])
        XCTAssertEqual(plain.capabilities, .discoveryOnly)
        XCTAssertEqual(plain.priceProvenance, .unspecified)
    }

    // MARK: Provenance

    func testAgeIsNeverNegative() {
        XCTAssertEqual(Provenance.demo(at: Fixtures.at(minutes: 5)).age(at: now), 0)
        XCTAssertEqual(Provenance.demo(at: Fixtures.at(minutes: -5)).age(at: now), 300, accuracy: 1e-9)
    }

    func testPricesStayFreshLongerThanStatuses() {
        let sixHoursOld = Provenance.demo(at: Fixtures.at(minutes: -360))
        XCTAssertTrue(sixHoursOld.isStale(at: now)) // status threshold
        XCTAssertFalse(sixHoursOld.isStale(at: now, maxAge: Freshness.priceMaxAge))
    }

    func testProvenanceAndCapabilitiesSurviveACodableRoundTrip() throws {
        let p = Provenance(source: "Via Lietuva OCPI", timestamp: now, dataClass: .predicted)
        XCTAssertEqual(try JSONDecoder().decode(Provenance.self, from: JSONEncoder().encode(p)), p)
        let c = StationCapabilities(level: .accountPricing, simulated: true)
        XCTAssertEqual(try JSONDecoder().decode(StationCapabilities.self, from: JSONEncoder().encode(c)), c)
    }

    func testSavedStatusValuesFromOlderVersionsStillDecode() throws {
        // Persisted data written before `unknown` existed only contains the old raw values.
        for raw in ["available", "charging", "idle", "blocked", "offline", "unknown"] {
            XCTAssertNotNil(try? JSONDecoder().decode(ConnectorStatus.self, from: Data("\"\(raw)\"".utf8)), raw)
        }
    }

    // MARK: Demo fixtures

    func testDemoFixturesInitializeWithProvenanceOnEverythingAndSimulatedCapabilities() {
        let stations = DemoData.stations(at: now)
        XCTAssertEqual(stations.count, DemoData.seeds.count)
        for s in stations {
            XCTAssertEqual(s.priceProvenance.dataClass, .demo, s.id)
            XCTAssertEqual(s.priceProvenance.timestamp, now, s.id)
            XCTAssertTrue(s.capabilities.simulated, s.id)
            XCTAssertTrue(s.capabilities.supportsSessionControl, s.id)
            XCTAssertFalse(s.connectors.isEmpty, s.id)
            XCTAssertTrue(s.hasValidOccupancyHistory, s.id)
            for c in s.connectors {
                XCTAssertEqual(c.provenance.dataClass, .demo, c.id)
                XCTAssertEqual(c.provenance.timestamp, now, c.id)
                XCTAssertFalse(c.provenance.source.isEmpty, c.id)
            }
        }
    }

    func testDemoSnapshotsAreFreshWhenTakenAndGoStaleIfNotRefreshed() {
        let stations = DemoData.stations(at: now)
        XCTAssertTrue(stations.allSatisfy { $0.availability(at: now) != .unknown })
        let later = Fixtures.at(minutes: 11)
        XCTAssertTrue(stations.allSatisfy { $0.availability(at: later) == .unknown }, "an unrefreshed snapshot must not look current")
        XCTAssertTrue(stations.allSatisfy { $0.freeCount(at: later) == 0 })
    }

    func testDemoSnapshotsAreDeterministic() {
        let a = DemoData.stations(at: now, tick: 3)
        let b = DemoData.stations(at: now, tick: 3)
        XCTAssertEqual(a.map(\.connectors), b.map(\.connectors))
        XCTAssertEqual(a.map(\.pricePerKwh), b.map(\.pricePerKwh))
    }

    // MARK: Presentation

    func testStatusSummaryReportsStaleness() {
        let s = Fixtures.station("p", at: Fixtures.vilnius, connectors: [Fixtures.connector(ageMinutes: 0), Fixtures.connector(id: "old", ageMinutes: 30)])
        XCTAssertEqual(s.statusProvenance.timestamp, Fixtures.at(minutes: -30), "oldest connector decides")
        XCTAssertNotEqual(s.provenanceSummary(at: now), s.provenanceSummary(at: Fixtures.at(minutes: -29)))
    }

    func testEveryDataClassHasALabel() {
        for dataClass in DataClass.allCases { XCTAssertFalse(dataClass.label.isEmpty) }
    }
}
