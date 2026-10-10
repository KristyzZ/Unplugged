import XCTest
@testable import Unplugged

/// Real stations from the open OCPI feed: parsing, mapping, deduplication, tariffs, provenance and
/// paging. Everything runs offline against fixtures shaped like the real feed.
enum FeedFixtures {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A page of locations as the feed sends it (snake_case, string coordinates and prices).
    static func location(
        id: Int, party: String = "IBG", name: String = "L3 | Inbalance grid", city: String? = "Vilnius",
        lat: String = "54.6745570", lng: String = "25.2243550", publish: Bool = true, evses: [String]
    ) -> String {
        let cityJSON = city.map { "\"\($0)\"" } ?? "null"
        return """
        {"country_code":"LT","party_id":"\(party)","id":\(id),"publish":\(publish),"name":"\(name)","address":"Laisvės pr. 3",
         "city":\(cityJSON),"coordinates":{"latitude":"\(lat)","longitude":"\(lng)"},"evses":[\(evses.joined(separator: ","))]}
        """
    }

    static func evse(
        _ id: String, status: String = "AVAILABLE", updated: String = "2026-10-10T00:01:05",
        connectors: [String]? = nil, uid: Int = 1
    ) -> String {
        let c = (connectors ?? [connector(id: uid * 10)]).joined(separator: ",")
        return "{\"uid\":\(uid),\"evse_id\":\"\(id)\",\"status\":\"\(status)\",\"last_updated\":\"\(updated)\",\"connectors\":[\(c)]}"
    }

    static func connector(id: Int, standard: String = "IEC_62196_T2_COMBO", watts: Int = 50_000, tariff: String? = "t1") -> String {
        let t = tariff.map { "[\"\($0)\"]" } ?? "[]"
        return "{\"id\":\(id),\"standard\":\"\(standard)\",\"format\":\"CABLE\",\"power_type\":\"DC\",\"max_electric_power\":\(watts),\"tariff_ids\":\(t)}"
    }

    static func page(_ locations: [String]) -> Data {
        Data("{\"timestamp\":\"2026-10-10T13:00:00Z\",\"status_code\":1000,\"data\":[\(locations.joined(separator: ","))]}".utf8)
    }

    static func tariffPage(_ tariffs: [String]) -> Data {
        Data("{\"status_code\":1000,\"data\":[\(tariffs.joined(separator: ","))]}".utf8)
    }

    static func tariff(id: String, currency: String = "EUR", elements: [String]) -> String {
        "{\"id\":\"\(id)\",\"currency\":\"\(currency)\",\"elements\":[\(elements.joined(separator: ","))]}"
    }

    static func element(_ components: [(String, String)], restrictions: String? = nil) -> String {
        let c = components.map { "{\"type\":\"\($0.0)\",\"price\":\"\($0.1)\",\"step_size\":1}" }.joined(separator: ",")
        let r = restrictions.map { ",\"restrictions\":\($0)" } ?? ""
        return "{\"price_components\":[\(c)]\(r)}"
    }

    static func snapshot(_ stations: [FeedStation], tariffs: [FeedTariff] = [], at date: Date = now) -> FeedSnapshot {
        FeedSnapshot(generatedAt: date, stations: stations, tariffs: tariffs)
    }
}

/// Serves canned responses by URL, and records what was asked. Pages are fetched concurrently, so
/// the recorded requests are guarded by a lock.
final class StubHTTP: HTTPFetching, @unchecked Sendable {
    struct Reply { var data: Data; var headers: [String: String] = [:]; var status = 200 }
    var replies: [(match: (URL) -> Bool, reply: Reply)] = []
    var failing: [(URL) -> Bool] = []
    private let lock = NSLock()
    private var recorded: [URL] = []

    var requests: [URL] { lock.lock(); defer { lock.unlock() }; return recorded }

    func on(_ match: @escaping (URL) -> Bool, _ reply: Reply) { replies.append((match, reply)) }

    func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        lock.lock(); recorded.append(url); lock.unlock()
        if failing.contains(where: { $0(url) }) { throw URLError(.notConnectedToInternet) }
        guard let hit = replies.first(where: { $0.match(url) }) else { throw URLError(.badServerResponse) }
        let response = HTTPURLResponse(url: url, statusCode: hit.reply.status, httpVersion: nil, headerFields: hit.reply.headers)!
        return (hit.reply.data, response)
    }

    func offset(_ url: URL) -> Int {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "offset" }?.value.flatMap(Int.init) ?? -1
    }
}

final class StationFeedParsingTests: XCTestCase {
    typealias F = FeedFixtures

    func testLocationsAreDecodedWithCoordinatesAndEvses() throws {
        let data = F.page([F.location(id: 258, evses: [F.evse("IBG-1-A")])])
        let stations = try OCPIDecoder.locations(from: data)
        XCTAssertEqual(stations.count, 1)
        let s = stations[0]
        XCTAssertEqual(s.id, 258)
        XCTAssertEqual(s.party, "IBG")
        XCTAssertEqual(s.city, "Vilnius")
        XCTAssertEqual(s.lat, 54.674557, accuracy: 1e-9)
        XCTAssertEqual(s.evses.first?.connectors.first, FeedConnector(id: 10, standard: "IEC_62196_T2_COMBO", watts: 50_000, tariff: "t1"))
    }

    func testAMalformedRecordDoesNotFailThePage() throws {
        let bad = "{\"id\":\"not-a-number\",\"party_id\":\"IBG\"}"
        let data = F.page([F.location(id: 1, evses: [F.evse("A")]), bad, F.location(id: 2, evses: [F.evse("B", uid: 2)])])
        XCTAssertEqual(try OCPIDecoder.locations(from: data).map(\.id), [1, 2])
    }

    func testUnpublishedAndImpossibleLocationsAreSkipped() throws {
        let data = F.page([
            F.location(id: 1, publish: false, evses: [F.evse("A")]),
            F.location(id: 2, lat: "0", lng: "0", evses: [F.evse("B", uid: 2)]),
            F.location(id: 3, lat: "abc", evses: [F.evse("C", uid: 3)]),
            F.location(id: 4, lat: "123", evses: [F.evse("D", uid: 4)]),
            F.location(id: 5, evses: [F.evse("E", uid: 5)]),
        ])
        XCTAssertEqual(try OCPIDecoder.locations(from: data).map(\.id), [5])
    }

    func testMissingCityBecomesEmpty() throws {
        let data = F.page([F.location(id: 1, city: nil, evses: [F.evse("A")])])
        XCTAssertEqual(try OCPIDecoder.locations(from: data)[0].city, "")
    }

    func testTariffRestrictionsAreReducedToAFlag() throws {
        let t = F.tariff(id: "t", elements: [
            F.element([("ENERGY", "0.18")], restrictions: "{\"start_time\":\"00:00:00\",\"end_time\":\"00:15:00\"}"),
            F.element([("ENERGY", "0.39"), ("FLAT", "0.20")]),
        ])
        let parsed = try OCPIDecoder.tariffs(from: F.tariffPage([t]))
        XCTAssertEqual(parsed[0].elements.map(\.restricted), [true, false])
        XCTAssertEqual(parsed[0].elements[1].components.map(\.price), [0.39, 0.20])
    }

    func testGarbageThrowsInsteadOfReturningAnEmptyMap() {
        XCTAssertThrowsError(try OCPIDecoder.locations(from: Data("<html>502 Bad Gateway</html>".utf8)))
    }
}

final class StationMappingTests: XCTestCase {
    typealias F = FeedFixtures
    private let now = F.now

    private func stations(_ locations: [String], tariffs: [String] = [], fetchedAt: Date? = nil) throws -> [Station] {
        let feed = try OCPIDecoder.locations(from: F.page(locations))
        let t = try OCPIDecoder.tariffs(from: F.tariffPage(tariffs))
        return StationBuilder.stations(from: F.snapshot(feed, tariffs: t, at: fetchedAt ?? now), now: now)
    }

    func testStatusTable() {
        XCTAssertEqual(StationBuilder.status("AVAILABLE"), .available)
        XCTAssertEqual(StationBuilder.status("CHARGING"), .charging)
        XCTAssertEqual(StationBuilder.status("INOPERATIVE"), .offline)
        XCTAssertEqual(StationBuilder.status("OUTOFORDER"), .offline)
        XCTAssertEqual(StationBuilder.status("UNKNOWN"), .unknown)
        XCTAssertEqual(StationBuilder.status("BLOCKED"), .blocked)
        XCTAssertEqual(StationBuilder.status("SOMETHING_NEW"), .unknown, "an unfamiliar status is unknown, never available")
        XCTAssertNil(StationBuilder.status("REMOVED"), "removed chargers are dropped")
    }

    func testConnectorTypesPowerAndUnsupportedPlugs() throws {
        let evse = F.evse("A", connectors: [
            F.connector(id: 1, standard: "IEC_62196_T2", watts: 22_000),
            F.connector(id: 2, standard: "IEC_62196_T2_COMBO", watts: 150_000),
            F.connector(id: 3, standard: "CHADEMO", watts: 50_000),
            F.connector(id: 4, standard: "DOMESTIC_F", watts: 3_700),    // Schuko: the app cannot model it
            F.connector(id: 5, standard: "IEC_62196_T2", watts: 0),       // no power given
        ])
        let s = try stations([F.location(id: 1, evses: [evse])])[0]
        XCTAssertEqual(s.connectors.map(\.type), [.type2, .ccs2, .chademo])
        XCTAssertEqual(s.connectors.map(\.powerKw), [22, 150, 50])
        XCTAssertEqual(s.maxPower, 150)
    }

    func testRemovedChargersAndEmptyStationsAreDropped() throws {
        let list = try stations([
            F.location(id: 1, evses: [F.evse("A", status: "REMOVED")]),
            F.location(id: 2, evses: [F.evse("B", uid: 2), F.evse("C", status: "REMOVED", uid: 3)]),
        ])
        XCTAssertEqual(list.map(\.id), ["ocpi-2"])
        XCTAssertEqual(list[0].connectors.count, 1)
    }

    func testSystemIdsAreNotUsedAsStationNames() {
        XCTAssertEqual(StationBuilder.cleanName("PLTKAUJO60_EDLT-1", fallback: "Jonavos g. 2"), "Jonavos g. 2")
        XCTAssertEqual(StationBuilder.cleanName("L3 | Inbalance grid", fallback: "x"), "L3")
        XCTAssertEqual(StationBuilder.cleanName("Moxy Kaunas Center", fallback: "x"), "Moxy Kaunas Center")
        XCTAssertEqual(StationBuilder.cleanName("IKEA", fallback: "x"), "IKEA", "a short plain name stays")
        XCTAssertEqual(StationBuilder.cleanName("   ", fallback: "Gedimino pr. 1"), "Gedimino pr. 1")
    }

    func testStationFieldsAndOperatorMapping() throws {
        let s = try stations([F.location(id: 258, party: "IGN", name: "Akropolis | Ignitis", evses: [F.evse("A")])])[0]
        XCTAssertEqual(s.id, "ocpi-258")
        XCTAssertEqual(s.name, "Akropolis")
        XCTAssertEqual(s.operatorId, "ignitis", "keeps the id the demo plans refer to")
        XCTAssertEqual(OperatorCatalog.operatorId(partyId: "IBG"), "inbalance")
        XCTAssertEqual(OperatorCatalog.operatorId(partyId: "008"), "eleport")
        XCTAssertEqual(OperatorCatalog.operatorId(partyId: "E85"), "enefit")
        XCTAssertEqual(OperatorCatalog.operatorId(partyId: "XYZ"), "xyz")
        XCTAssertEqual(DemoData.chargeOperator("ignitis").name, "Ignitis ON")
        XCTAssertEqual(DemoData.operators.count, 13)
        XCTAssertEqual(Set(DemoData.operators.map(\.id)).count, 13)
    }

    func testRealStationsAreObservedDataWithSimulatedSessions() throws {
        let s = try stations([F.location(id: 1, evses: [F.evse("A")])], tariffs: [F.tariff(id: "t1", elements: [F.element([("ENERGY", "0.31")])])])[0]
        XCTAssertEqual(s.connectors[0].provenance.dataClass, .observed)
        XCTAssertEqual(s.connectors[0].provenance.source, "Via Lietuva OCPI")
        XCTAssertEqual(s.priceProvenance.dataClass, .observed)
        XCTAssertTrue(s.capabilities.simulated)
        XCTAssertTrue(s.capabilities.supportsSessionControl)
    }

    func testNoBusyHourHistoryMeansNoData() throws {
        let s = try stations([F.location(id: 1, evses: [F.evse("A")])])[0]
        XCTAssertTrue(s.hourlyOccupancy.isEmpty)
        XCTAssertNil(s.probabilityFree(atHour: 12, at: now), "no history is 'no data', not 'no chance'")
    }

    // MARK: Provenance uses the fetch time

    func testAChargerUnchangedForHoursIsStillConfirmedAvailable() throws {
        // The feed's last_updated is the last *change*: 14 hours ago here. Judging freshness by it
        // would make every quiet charger look stale.
        let s = try stations([F.location(id: 1, evses: [F.evse("A", updated: "2026-10-09T09:00:00")])])[0]
        let c = s.connectors[0]
        XCTAssertEqual(c.provenance.timestamp, now)
        XCTAssertTrue(c.isConfirmedAvailable(at: now.addingTimeInterval(60)))
        XCTAssertNotNil(c.changedAt, "the change time is kept separately")
    }

    func testDataBecomesUnknownWhenNotRefreshed() throws {
        let s = try stations([F.location(id: 1, evses: [F.evse("A")])])[0]
        XCTAssertTrue(s.connectors[0].isConfirmedAvailable(at: now.addingTimeInterval(9 * 60)))
        XCTAssertEqual(s.connectors[0].effectiveStatus(at: now.addingTimeInterval(11 * 60)), .unknown)
        XCTAssertEqual(s.availability(at: now.addingTimeInterval(11 * 60)), .unknown)
    }

    func testAnImpossibleChangeDateIsIgnored() throws {
        let s = try stations([F.location(id: 1, evses: [F.evse("A", updated: "2031-01-03T14:17:54")])])[0]
        XCTAssertNil(s.connectors[0].changedAt)
        XCTAssertTrue(s.connectors[0].isConfirmedAvailable(at: now), "a bogus date must not make the status stale")
    }

    func testFeedDatesAreLocalLithuanianTime() throws {
        // 2026-10-10 00:01:05 in Vilnius (UTC+3 in October, before the clocks change) is 21:01:05 UTC the day before.
        let date = try XCTUnwrap(StationBuilder.parseLocal("2026-10-10T00:01:05"))
        XCTAssertEqual(date, ISO8601DateFormatter().date(from: "2026-10-09T21:01:05Z"))
    }

    // MARK: Deduplication

    func testDuplicateChargerKeepsTheMostRecentRecord() throws {
        let s = try stations([F.location(id: 1, evses: [
            F.evse("DUP", status: "INOPERATIVE", updated: "2026-07-29T09:27:16", connectors: [F.connector(id: 1)], uid: 1),
            F.evse("DUP", status: "AVAILABLE", updated: "2026-10-09T14:42:30", connectors: [F.connector(id: 2)], uid: 2),
        ])])[0]
        XCTAssertEqual(s.connectors.count, 1)
        XCTAssertEqual(s.connectors[0].id, "ocpi-2")
        XCTAssertEqual(s.connectors[0].status, .available)
    }

    func testABogusFutureDateLosesTheDuplicateContest() throws {
        let s = try stations([F.location(id: 1, evses: [
            F.evse("DUP", status: "INOPERATIVE", updated: "2031-01-03T14:17:54", connectors: [F.connector(id: 1)], uid: 1),
            F.evse("DUP", status: "AVAILABLE", updated: "2026-10-09T14:42:30", connectors: [F.connector(id: 2)], uid: 2),
        ])])[0]
        XCTAssertEqual(s.connectors.map(\.status), [.available])
    }

    func testTheSameChargerInTwoStationsIsKeptOnceAndEmptiedStationsAreDropped() throws {
        let list = try stations([
            F.location(id: 1, evses: [F.evse("DUP", updated: "2026-10-01T10:00:00", connectors: [F.connector(id: 1)], uid: 1)]),
            F.location(id: 2, evses: [F.evse("DUP", updated: "2026-10-09T10:00:00", connectors: [F.connector(id: 2)], uid: 2)]),
        ])
        XCTAssertEqual(list.map(\.id), ["ocpi-2"])
    }

    func testConnectorIdsAreUnique() throws {
        let list = try stations([
            F.location(id: 1, evses: [F.evse("A", connectors: [F.connector(id: 7)], uid: 1)]),
            F.location(id: 2, evses: [F.evse("B", connectors: [F.connector(id: 7)], uid: 2)]),
        ])
        let ids = list.flatMap(\.connectors).map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    // MARK: Prices

    func testEveryDayPriceStartFeeAndTimeFee() {
        let t = FeedTariff(id: "t", currency: "EUR", elements: [
            .init(restricted: true, components: [.init(type: "ENERGY", price: 0.18, step: 1)]),
            .init(restricted: false, components: [.init(type: "ENERGY", price: 0.39, step: 1), .init(type: "FLAT", price: 0.25, step: 1),
                                                  .init(type: "TIME", price: 0.60, step: 60), .init(type: "PARKING_TIME", price: 5, step: 60)]),
        ])
        let r = TariffResolver.resolve(t)
        XCTAssertEqual(r?.energyEurPerKwh, 0.39)
        XCTAssertEqual(r?.startEur, 0.25)
        XCTAssertEqual(try XCTUnwrap(r).perMinuteEur, 0.01, accuracy: 1e-12, "OCPI TIME is per hour")
    }

    func testOnlyRestrictedElementsFallBackToTheFirstEnergyElementWithNoFees() {
        let t = FeedTariff(id: "t", currency: "EUR", elements: [
            .init(restricted: true, components: [.init(type: "FLAT", price: 0.25, step: 1)]),
            .init(restricted: true, components: [.init(type: "ENERGY", price: 0.18, step: 1)]),
        ])
        let r = TariffResolver.resolve(t)
        XCTAssertEqual(r?.energyEurPerKwh, 0.18)
        XCTAssertEqual(r?.startEur, 0, "a restricted FLAT is not a session fee")
    }

    func testForeignCurrencyAndEnergyLessTariffsGiveNoPrice() {
        XCTAssertNil(TariffResolver.resolve(FeedTariff(id: "t", currency: "PLN", elements: [.init(restricted: false, components: [.init(type: "ENERGY", price: 1, step: 1)])])))
        XCTAssertNil(TariffResolver.resolve(FeedTariff(id: "t", currency: "EUR", elements: [.init(restricted: false, components: [.init(type: "FLAT", price: 1, step: 1)])])))
        XCTAssertNil(TariffResolver.resolve(FeedTariff(id: "t", currency: "EUR", elements: [])))
    }

    func testUnknownPriceIsUnknownNotZero() throws {
        let s = try stations([F.location(id: 1, evses: [F.evse("A", connectors: [F.connector(id: 1, tariff: nil)])])])[0]
        XCTAssertFalse(s.priceKnown)
        XCTAssertNil(s.connectors[0].tariff)
    }

    func testPriceIsJoinedByTariffIdAndTheFastestConnectorSetsTheHeadline() throws {
        let evse = F.evse("A", connectors: [
            F.connector(id: 1, standard: "IEC_62196_T2", watts: 22_000, tariff: "ac"),
            F.connector(id: 2, standard: "IEC_62196_T2_COMBO", watts: 150_000, tariff: "dc"),
        ])
        let s = try stations([F.location(id: 1, evses: [evse])], tariffs: [
            F.tariff(id: "ac", elements: [F.element([("ENERGY", "0.29")])]),
            F.tariff(id: "dc", elements: [F.element([("ENERGY", "0.49"), ("FLAT", "0.30")])]),
        ])[0]
        XCTAssertEqual(s.pricePerKwh, 0.49)
        XCTAssertTrue(s.priceKnown)
        XCTAssertEqual(s.connectors[0].tariff?.energyEurPerKwh, 0.29)
        XCTAssertEqual(s.connectors[1].tariff?.startEur, 0.30)
    }

    func testRealTariffReachesTheSessionPricing() throws {
        let s = try stations([F.location(id: 1, party: "IGN", evses: [F.evse("A")])], tariffs: [
            F.tariff(id: "t1", elements: [F.element([("ENERGY", "0.40"), ("FLAT", "0.50"), ("TIME", "0.60")])]),
        ])[0]
        let tariff = PricingDemoFixtures.tariff(station: s, connector: s.connectors[0])
        XCTAssertEqual(tariff.energyEurPerKwh, 0.40)
        XCTAssertEqual(tariff.startEur, 0.50, "the operator's session fee, not the demo's 0.30")
        XCTAssertEqual(tariff.chargingEurPerMinute, 0.01, accuracy: 1e-12)
        XCTAssertTrue(tariff.supportsAccountPricing, "the fictional Ignitis demo plan may apply at a (simulated) real Ignitis station")
    }
}

final class StationFeedFetchTests: XCTestCase {
    typealias F = FeedFixtures

    private func isLocations(_ u: URL) -> Bool { u.path.hasSuffix("/locations") }
    private func isTariffs(_ u: URL) -> Bool { u.path.hasSuffix("/tariffs") }

    private func location(_ id: Int) -> String { F.location(id: id, evses: [F.evse("E\(id)", connectors: [F.connector(id: id)], uid: id)]) }

    func testPagesByOffsetUntilTheTotalIsCoveredIgnoringTheBrokenLinkHeader() async throws {
        let http = StubHTTP()
        http.on({ u in self.isLocations(u) && http.offset(u) == 0 },
                .init(data: F.page([location(1), location(2)]), headers: ["X-Total-Count": "2500", "Link": "</ocpi/2.3.0/locations?limit=100?&limit=100>; rel=\"next\""]))
        http.on({ u in self.isLocations(u) && http.offset(u) == 1000 }, .init(data: F.page([location(3)]), headers: ["X-Total-Count": "2500"]))
        http.on({ u in self.isLocations(u) && http.offset(u) == 2000 }, .init(data: F.page([location(4)]), headers: ["X-Total-Count": "2500"]))
        http.on(isTariffs, .init(data: F.tariffPage([F.tariff(id: "t1", elements: [F.element([("ENERGY", "0.3")])])])))
        let snapshot = try await OCPIStationFeed(http: http, now: { F.now }).fetch()
        XCTAssertEqual(snapshot.stations.map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(snapshot.tariffs.map(\.id), ["t1"])
        XCTAssertEqual(snapshot.generatedAt, F.now)
        XCTAssertEqual(http.requests.filter(isLocations).map(http.offset).sorted(), [0, 1000, 2000])
        XCTAssertEqual(http.requests.filter(isTariffs).count, 1, "tariffs come in one response")
        XCTAssertTrue(http.requests.filter(isLocations).allSatisfy { $0.query?.contains("limit=1000") == true })
    }

    func testWithoutACountHeaderItKeepsGoingUntilAPageIsEmpty() async throws {
        let http = StubHTTP()
        http.on({ u in self.isLocations(u) && http.offset(u) == 0 }, .init(data: F.page([location(1)])))
        http.on({ u in self.isLocations(u) && http.offset(u) == 1000 }, .init(data: F.page([location(2)])))
        http.on({ u in self.isLocations(u) && http.offset(u) == 2000 }, .init(data: F.page([])))
        http.on(isTariffs, .init(data: F.tariffPage([])))
        let snapshot = try await OCPIStationFeed(http: http, now: { F.now }).fetch()
        XCTAssertEqual(snapshot.stations.map(\.id), [1, 2])
    }

    func testAFailedPageFailsTheWholeRefreshInsteadOfShowingHalfTheMap() async {
        let http = StubHTTP()
        http.on({ u in self.isLocations(u) && http.offset(u) == 0 }, .init(data: F.page([location(1)]), headers: ["X-Total-Count": "2500"]))
        http.on(isTariffs, .init(data: F.tariffPage([])))
        http.failing = [{ u in self.isLocations(u) && http.offset(u) == 1000 }]
        do {
            _ = try await OCPIStationFeed(http: http, now: { F.now }).fetch()
            XCTFail("expected the refresh to fail")
        } catch {}
    }

    func testATransientFailureIsRetriedOnce() async throws {
        final class Flaky: HTTPFetching {
            var calls = 0
            let inner: StubHTTP
            init(_ inner: StubHTTP) { self.inner = inner }
            func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
                calls += 1
                if calls == 1 { throw URLError(.timedOut) }
                return try await inner.get(url)
            }
        }
        let http = StubHTTP()
        http.on({ self.isLocations($0) }, .init(data: F.page([location(1)]), headers: ["X-Total-Count": "1"]))
        http.on(isTariffs, .init(data: F.tariffPage([])))
        let snapshot = try await OCPIStationFeed(http: Flaky(http), now: { F.now }).fetch()
        XCTAssertEqual(snapshot.stations.count, 1)
    }

    func testAFailedTariffCallStillReturnsTheStations() async throws {
        let http = StubHTTP()
        http.on({ self.isLocations($0) }, .init(data: F.page([location(1)]), headers: ["X-Total-Count": "1"]))
        http.failing = [isTariffs]
        let snapshot = try await OCPIStationFeed(http: http, now: { F.now }).fetch()
        XCTAssertEqual(snapshot.stations.count, 1)
        XCTAssertTrue(snapshot.tariffs.isEmpty)
    }

    func testNotJSONFails() async {
        let http = StubHTTP()
        http.on({ self.isLocations($0) }, .init(data: Data("<html>".utf8), headers: ["X-Total-Count": "1"]))
        do { _ = try await OCPIStationFeed(http: http).fetch(); XCTFail("expected an error") } catch {}
    }
}

final class BundledSnapshotTests: XCTestCase {
    func testTheBundledSnapshotDecodesAndIsAWholeCountry() throws {
        let snapshot = try XCTUnwrap(FeedSnapshot.bundled(), "Data/stations.json must be bundled (python3 pipeline/run.py export-app)")
        XCTAssertGreaterThan(snapshot.stations.count, 1500)
        XCTAssertFalse(snapshot.tariffs.isEmpty)
        XCTAssertEqual(snapshot.source, "Via Lietuva OCPI (snapshot)")
        let stations = StationBuilder.stations(from: snapshot)
        XCTAssertGreaterThan(stations.count, 1500)
        // Lithuania, not the world.
        XCTAssertTrue(stations.allSatisfy { (53.5...56.6).contains($0.lat) && (20.5...27).contains($0.lng) })
        XCTAssertTrue(stations.contains { $0.city == "Vilnius" })
        XCTAssertTrue(stations.contains { $0.city == "Kaunas" })
        XCTAssertGreaterThan(stations.filter(\.priceKnown).count, stations.count * 9 / 10)
        let ids = stations.flatMap(\.connectors).map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testAnOldSnapshotReadsAsUnknownNotAvailable() throws {
        let snapshot = try XCTUnwrap(FeedSnapshot.bundled())
        let stations = StationBuilder.stations(from: snapshot)
        let later = snapshot.generatedAt.addingTimeInterval(3600)
        XCTAssertTrue(stations.allSatisfy { $0.freeCount(at: later) == 0 })
        XCTAssertTrue(stations.allSatisfy { $0.availability(at: later) == .unknown })
    }

    func testBuildingAllStationsIsFast() throws {
        let snapshot = try XCTUnwrap(FeedSnapshot.bundled())
        measure { _ = StationBuilder.stations(from: snapshot) }
    }

    func testReadingTheSnapshotAndBuildingTheMapIsFast() {
        // What happens at launch: decode the bundled JSON and build every station.
        measure { _ = FeedSnapshot.bundled().map { StationBuilder.stations(from: $0) } }
    }

    func testDateParsingMatchesTheFormatterAndRejectsGarbage() throws {
        XCTAssertEqual(StationBuilder.parseLocal("2026-10-10T00:01:05"), ISO8601DateFormatter().date(from: "2026-10-09T21:01:05Z"))
        XCTAssertEqual(StationBuilder.parseLocal("2026-01-15T08:00:00"), ISO8601DateFormatter().date(from: "2026-01-15T06:00:00Z"), "winter time is UTC+2")
        XCTAssertEqual(StationBuilder.parseLocal("2026-10-10 00:01:05"), StationBuilder.parseLocal("2026-10-10T00:01:05"))
        for bad in [nil, "", "2026-10-10", "not a date at all!!", "2026-13-10T00:00:00", "2026-10-10T25:00:00", "2026-1a-10T00:00:00"] {
            XCTAssertNil(StationBuilder.parseLocal(bad), bad ?? "nil")
        }
    }
}
