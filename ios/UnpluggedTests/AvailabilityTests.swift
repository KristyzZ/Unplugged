import XCTest
@testable import Unplugged

/// Status freshness, "unknown is not available", station availability, validated occupancy history
/// and the one-connector filter. `now` is always `Fixtures.t0`; connectors are aged relative to it.
final class AvailabilityTests: XCTestCase {
    private let now = Fixtures.t0
    private let anywhere = Fixtures.vilnius

    private func station(_ connectors: [Connector], occupancy: [Double]? = nil) -> Station {
        Fixtures.station("s", at: anywhere, connectors: connectors, hourlyOccupancy: occupancy)
    }

    // MARK: Freshness of a single connector

    func testFreshAvailableConnectorIsConfirmed() {
        let c = Fixtures.connector(status: .available)
        XCTAssertEqual(c.effectiveStatus(at: now), .available)
        XCTAssertTrue(c.isConfirmedAvailable(at: now))
    }

    func testStatusIsStillFreshAtExactlyTheMaximumAgeAndStaleJustAfter() {
        let limit = Freshness.statusMaxAge / 60
        XCTAssertTrue(Fixtures.connector(ageMinutes: limit).isConfirmedAvailable(at: now))
        let stale = Fixtures.connector(ageMinutes: limit + 1.0 / 60) // one second older
        XCTAssertEqual(stale.effectiveStatus(at: now), .unknown)
        XCTAssertFalse(stale.isConfirmedAvailable(at: now))
    }

    func testStaleStatusBecomesUnknownWhateverItWas() {
        for status in [ConnectorStatus.available, .charging, .idle, .blocked, .offline] {
            let c = Fixtures.connector(status: status, ageMinutes: 60)
            XCTAssertEqual(c.effectiveStatus(at: now), .unknown, "\(status) should be unknown once stale")
        }
    }

    func testUnknownIsNeverAvailable() {
        let c = Fixtures.connector(status: .unknown)
        XCTAssertEqual(c.effectiveStatus(at: now), .unknown)
        XCTAssertFalse(c.isConfirmedAvailable(at: now))
    }

    func testPredictedAvailabilityIsNotConfirmed() {
        XCTAssertFalse(Fixtures.connector(status: .available, dataClass: .predicted).isConfirmedAvailable(at: now))
    }

    func testDemoAndObservedAvailabilityAreConfirmedFacts() {
        XCTAssertTrue(Fixtures.connector(status: .available, dataClass: .demo).isConfirmedAvailable(at: now))
        XCTAssertTrue(Fixtures.connector(status: .available, dataClass: .observed).isConfirmedAvailable(at: now))
    }

    func testStatusWithoutProvenanceIsNeverConfirmed() {
        let unlabelled = Connector(id: "x", type: .ccs2, powerKw: 50, status: .available) // default provenance
        XCTAssertFalse(unlabelled.isConfirmedAvailable(at: now))
        XCTAssertEqual(unlabelled.effectiveStatus(at: now), .unknown)
    }

    func testImplausibleFutureTimestampIsNotTrusted() {
        let tolerated = Fixtures.connector(ageMinutes: -(Freshness.clockSkewTolerance / 60) + 1)
        let wrongClock = Fixtures.connector(ageMinutes: -(Freshness.clockSkewTolerance / 60) - 1)
        XCTAssertTrue(tolerated.isConfirmedAvailable(at: now))
        XCTAssertFalse(wrongClock.isConfirmedAvailable(at: now))
    }

    // MARK: Counting at station level

    func testOnlyConfirmedConnectorsCountAsFree() {
        let s = station([
            Fixtures.connector(status: .available, id: "a"),
            Fixtures.connector(status: .available, id: "stale", ageMinutes: 30),
            Fixtures.connector(status: .unknown, id: "unknown"),
            Fixtures.connector(status: .available, id: "predicted", dataClass: .predicted),
            Fixtures.connector(status: .charging, id: "busy"),
        ])
        XCTAssertEqual(s.freeCount(at: now), 1)
    }

    func testWorkingCountExcludesOfflineButKeepsUnknown() {
        let s = station([
            Fixtures.connector(status: .available, id: "a"),
            Fixtures.connector(status: .offline, id: "off"),
            Fixtures.connector(status: .unknown, id: "unk"),
            Fixtures.connector(status: .offline, id: "stale-off", ageMinutes: 60), // stale offline is just unknown
        ])
        XCTAssertEqual(s.workingCount(at: now), 3)
        XCTAssertEqual(s.unknownCount(at: now), 2)
        XCTAssertEqual(s.count(.offline, at: now), 1)
    }

    // MARK: Station availability level

    func testAvailabilityLevels() {
        func level(_ statuses: [ConnectorStatus], ageMinutes: Double = 0) -> AvailabilityLevel {
            station(statuses.enumerated().map { Fixtures.connector(status: $1, id: "c\($0)", ageMinutes: ageMinutes) })
                .availability(at: now)
        }
        XCTAssertEqual(level([.available, .available, .charging]), .free)
        XCTAssertEqual(level([.available, .charging, .charging, .charging]), .limited) // 25 % free
        XCTAssertEqual(level([.charging, .idle, .blocked]), .full)
        XCTAssertEqual(level([.offline, .offline]), .offline)
        XCTAssertEqual(level([.available, .available], ageMinutes: 60), .unknown)      // all stale
        XCTAssertEqual(level([.unknown, .unknown]), .unknown)
    }

    func testNoFreeConnectorButSomeUnknownIsUnknownNotFull() {
        let s = station([Fixtures.connector(status: .charging, id: "a"), Fixtures.connector(status: .unknown, id: "b")])
        XCTAssertEqual(s.availability(at: now), .unknown)
    }

    func testAllOfflineExceptUnknownIsUnknown() {
        let s = station([Fixtures.connector(status: .offline, id: "a"), Fixtures.connector(status: .unknown, id: "b")])
        XCTAssertEqual(s.availability(at: now), .unknown)
    }

    func testStaleAvailableNextToBusyConnectorsIsNotFree() {
        let s = station([Fixtures.connector(status: .charging, id: "a"),
                         Fixtures.connector(status: .available, id: "b", ageMinutes: 45)])
        XCTAssertNotEqual(s.availability(at: now), .free)
        XCTAssertEqual(s.freeCount(at: now), 0)
    }

    func testStationWithoutConnectorsIsOffline() {
        XCTAssertEqual(station([]).availability(at: now), .offline)
    }

    // MARK: Probability of a free spot (audit bug)

    func testNoWorkingConnectorMeansZeroProbabilityNotAHistoricalGuess() {
        // Previously max(1, workingCount) turned "0 working connectors" into "1", giving 1 - p > 0.
        let allOffline = station([Fixtures.connector(status: .offline, id: "a"), Fixtures.connector(status: .offline, id: "b")])
        XCTAssertEqual(allOffline.probabilityFree(atHour: 12, at: now), 0)
    }

    func testProbabilityIsOneMinusOccupancyToThePowerOfWorkingConnectors() {
        let s = station([Fixtures.connector(id: "a"), Fixtures.connector(id: "b"), Fixtures.connector(status: .offline, id: "c")],
                        occupancy: Array(repeating: 0.5, count: 24))
        XCTAssertEqual(s.probabilityFree(atHour: 3, at: now) ?? -1, 1 - 0.25, accuracy: 1e-9) // two working
    }

    func testProbabilityHandlesAnyHourIndex() {
        var history = Array(repeating: 0.2, count: 24)
        history[23] = 0.9
        let s = station([Fixtures.connector()], occupancy: history)
        XCTAssertEqual(s.probabilityFree(atHour: -1, at: now) ?? -1, 1 - 0.9, accuracy: 1e-9) // wraps to 23
        XCTAssertEqual(s.probabilityFree(atHour: 47, at: now) ?? -1, 1 - 0.9, accuracy: 1e-9)
        XCTAssertEqual(s.probabilityFree(atHour: 24, at: now) ?? -1, 1 - 0.2, accuracy: 1e-9) // wraps to 0
    }

    // MARK: Occupancy history validation

    func testInvalidHistoryIsRejectedWithoutCrashing() {
        let c = [Fixtures.connector()]
        let bad: [[Double]] = [[], Array(repeating: 0.3, count: 23), Array(repeating: 0.3, count: 25),
                               Array(repeating: 1.2, count: 24), Array(repeating: -0.1, count: 24),
                               Array(repeating: .nan, count: 24)]
        for history in bad {
            let s = station(c, occupancy: history)
            XCTAssertFalse(s.hasValidOccupancyHistory)
            XCTAssertNil(s.occupancy(atHour: 5))
            XCTAssertNil(s.probabilityFree(atHour: 5, at: now), "unknown, not 'no chance'")
            XCTAssertEqual(s.peakHours(), [])
            XCTAssertEqual(s.bestHour(from: 5), 5)
            XCTAssertTrue((0...1).contains(s.demandLevel(hour: 5, at: now)))
        }
    }

    func testValidHistoryBoundariesAreAccepted() {
        XCTAssertTrue(station([Fixtures.connector()], occupancy: Array(repeating: 0, count: 24)).hasValidOccupancyHistory)
        XCTAssertTrue(station([Fixtures.connector()], occupancy: Array(repeating: 1, count: 24)).hasValidOccupancyHistory)
    }

    func testBestAndPeakHoursUseTheHistory() {
        var history = Array(repeating: 0.5, count: 24)
        history[2] = 0.1; history[20] = 0.9; history[8] = 0.8; history[9] = 0.85
        let s = station([Fixtures.connector()], occupancy: history)
        XCTAssertEqual(s.peakHours(top: 3), [8, 9, 20])
        XCTAssertEqual(s.bestHour(from: 22), 2)       // wraps past midnight within the 6-hour window
        XCTAssertEqual(s.bestHour(from: -2), 2)       // negative start hour normalised to 22
    }

    func testDemandBlendsLiveAndHistory() {
        let s = station([Fixtures.connector(status: .charging, id: "a"), Fixtures.connector(status: .available, id: "b")],
                        occupancy: Array(repeating: 0.4, count: 24))
        XCTAssertEqual(s.demandLevel(hour: 10, at: now), 0.7 * 0.5 + 0.3 * 0.4, accuracy: 1e-9)
    }

    // MARK: One connector must satisfy all filters

    func testFilterIsSatisfiedByASingleConnector() {
        let car = Fixtures.vehicle(connectors: [.ccs2, .type2])
        let s = station([
            Fixtures.connector(.ccs2, kw: 150, status: .charging, id: "fast-busy"),
            Fixtures.connector(.type2, kw: 22, status: .available, id: "slow-free"),
        ])
        XCTAssertTrue(s.hasConnector(matching: ConnectorFilter(onlyAvailable: true, vehicle: car), at: now))
        XCTAssertTrue(s.hasConnector(matching: ConnectorFilter(minPowerKw: 50, vehicle: car), at: now))
        // Separately each filter passes, but no single connector is both free and fast.
        XCTAssertFalse(s.hasConnector(matching: ConnectorFilter(onlyAvailable: true, minPowerKw: 50, vehicle: car), at: now))
    }

    func testFilterRequiresACompatibleFreeConnector() {
        let leaf = Fixtures.vehicle(maxDc: 50, maxAc: 6.6, connectors: [.chademo, .type2])
        let s = station([Fixtures.connector(.ccs2, kw: 150, id: "ccs"), Fixtures.connector(.chademo, kw: 50, status: .charging, id: "chad")])
        XCTAssertFalse(s.hasConnector(matching: ConnectorFilter(onlyAvailable: true, vehicle: leaf), at: now))
        XCTAssertTrue(s.hasConnector(matching: ConnectorFilter(vehicle: leaf), at: now)) // compatible, just busy
    }

    func testFilterDoesNotCountStaleAvailability() {
        let s = station([Fixtures.connector(status: .available, ageMinutes: 90)])
        XCTAssertFalse(s.hasConnector(matching: ConnectorFilter(onlyAvailable: true), at: now))
        XCTAssertTrue(s.hasConnector(matching: ConnectorFilter(), at: now))
    }
}
