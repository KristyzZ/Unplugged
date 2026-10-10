import XCTest
@testable import Unplugged

/// How the app model uses the live feed: success, failure, switching sources, hosted chargers and
/// starting a (simulated) session at a real station.
@MainActor
final class AppModelStationsTests: XCTestCase {
    typealias F = FeedFixtures

    struct StubFeed: StationFeeding {
        var result: Result<FeedSnapshot, Error>
        func fetch() async throws -> FeedSnapshot { try result.get() }
    }

    private func snapshot(status: String = "AVAILABLE", price: String = "0.40", at date: Date = Date()) throws -> FeedSnapshot {
        let page = F.page([F.location(id: 9, party: "IGN", name: "Test | Ignitis", evses: [F.evse("A", status: status, connectors: [F.connector(id: 90, watts: 150_000)])])])
        let tariffs = F.tariffPage([F.tariff(id: "t1", elements: [F.element([("ENERGY", price), ("FLAT", "0.50")])])])
        return F.snapshot(try OCPIDecoder.locations(from: page), tariffs: try OCPIDecoder.tariffs(from: tariffs), at: date)
    }

    private func clean(_ body: (UserDefaults) -> Void = { _ in }) {
        let d = UserDefaults.standard
        ["unplugged.state.v1", "unplugged.state.v2", "unplugged.lang", AppModel.stationSourceKey].forEach { d.removeObject(forKey: $0) }
        body(d)
    }

    func testLiveStationsReplaceTheSnapshotAndStatusSaysLive() async throws {
        clean()
        let date = Date()
        let model = AppModel(runLoops: false, stationSource: .real, feed: StubFeed(result: .success(try snapshot(at: date))))
        XCTAssertEqual(model.feedStatus, .loading)
        let bundled = model.stations.count
        XCTAssertGreaterThan(bundled, 1500, "the bundled snapshot is on screen immediately, before the first fetch")
        await model.refreshLiveStations()
        XCTAssertEqual(model.stations.count, 1)
        XCTAssertEqual(model.stations[0].id, "ocpi-9")
        XCTAssertEqual(model.feedStatus, .live(at: date))
        XCTAssertTrue(model.stations[0].connectors[0].isConfirmedAvailable())
    }

    func testAFailedRefreshKeepsTheDataAndSaysOffline() async throws {
        clean()
        let model = AppModel(runLoops: false, stationSource: .real, feed: StubFeed(result: .failure(URLError(.notConnectedToInternet))))
        let before = model.stations.map(\.id)
        await model.refreshLiveStations()
        XCTAssertEqual(model.stations.map(\.id), before, "never an empty map")
        guard case .offline(let from) = model.feedStatus else { return XCTFail("expected offline, got \(model.feedStatus)") }
        XCTAssertNotNil(from, "the bundled snapshot has a date")
    }

    func testARefreshAfterAnOutageRecovers() async throws {
        clean()
        let model = AppModel(runLoops: false, stationSource: .real, feed: StubFeed(result: .failure(URLError(.timedOut))))
        await model.refreshLiveStations()
        model.feed = StubFeed(result: .success(try snapshot()))
        await model.refreshLiveStations()
        if case .live = model.feedStatus {} else { XCTFail("expected live, got \(model.feedStatus)") }
    }

    func testAFeedWithoutTariffsKeepsTheEarlierPrices() async throws {
        clean()
        let model = AppModel(runLoops: false, stationSource: .real, feed: StubFeed(result: .success(try snapshot())))
        await model.refreshLiveStations()
        var noTariffs = try snapshot()
        noTariffs.tariffs = []
        model.feed = StubFeed(result: .success(noTariffs))
        await model.refreshLiveStations()
        XCTAssertEqual(model.stations[0].pricePerKwh, 0.40)
        XCTAssertTrue(model.stations[0].priceKnown)
    }

    func testDemoSourceNeverTouchesTheFeed() async {
        clean()
        struct Boom: StationFeeding { func fetch() async throws -> FeedSnapshot { XCTFail("the demo must not fetch"); throw URLError(.badURL) } }
        let model = AppModel(runLoops: false, stationSource: .demo, feed: Boom())
        await model.refreshLiveStations()
        XCTAssertEqual(model.feedStatus, .demo)
        XCTAssertEqual(model.stations.count, DemoData.seeds.count)
    }

    func testSwitchingSourceChangesTheStationsAndIsRemembered() async throws {
        clean()
        defer { UserDefaults.standard.removeObject(forKey: AppModel.stationSourceKey) }
        let model = AppModel(runLoops: false, stationSource: .real, feed: StubFeed(result: .success(try snapshot())))
        await model.refreshLiveStations()
        model.setStationSource(.demo)
        XCTAssertEqual(model.stations.count, DemoData.seeds.count)
        XCTAssertEqual(model.feedStatus, .demo)
        XCTAssertEqual(AppModel.savedStationSource, .demo)
        model.setStationSource(.real)
        XCTAssertEqual(AppModel.savedStationSource, .real)
    }

    func testHostedChargersAppearNextToRealStations() async throws {
        clean()
        let model = AppModel(runLoops: false, stationSource: .real, feed: StubFeed(result: .success(try snapshot())))
        await model.refreshLiveStations()
        var hosted = HostListing(); hosted.title = "Home charger"; hosted.pricePerKwh = 0.30; hosted.schedule = .always
        model.hostListings = [hosted]
        model.refreshStations()
        XCTAssertEqual(model.stations.count, 2)
        XCTAssertTrue(model.stations.contains { $0.operatorId == HostListing.operatorId })
        XCTAssertTrue(model.stations.contains { $0.id == "ocpi-9" })
    }

    func testASessionAtARealStationUsesTheOperatorsOwnTariffAndMarksTheConnectorCharging() async throws {
        clean()
        let model = AppModel(runLoops: false, stationSource: .real, feed: StubFeed(result: .success(try snapshot(price: "0.40"))))
        model.activePlanIds = []
        await model.refreshLiveStations()
        let station = try XCTUnwrap(model.stations.first)
        let connector = station.connectors[0]
        model.startCharging(at: station, connector: connector, targetSoc: 80)
        let session = try XCTUnwrap(model.session, "a real station must be startable (as a simulated session)")
        let terms = try XCTUnwrap(session.pricingTerms)
        XCTAssertEqual(terms.tariff.energyEurPerKwh, 0.40)
        XCTAssertEqual(terms.startEur, 0.50, "the real session fee, not the demo's")
        let live = try XCTUnwrap(model.stations.first?.connectors.first)
        XCTAssertEqual(live.status, .charging, "the session overlays the real connector")
    }

    func testTheDistanceOriginFollowsTheUser() throws {
        clean()
        let model = AppModel(runLoops: false, stationSource: .demo)
        XCTAssertEqual(model.origin, DemoData.vilniusCenter)
        let kaunas = LatLng(lat: 54.8985, lng: 23.9036)
        model.setOrigin(kaunas)
        XCTAssertEqual(model.origin, kaunas)
        model.setOrigin(LatLng(lat: kaunas.lat + 0.0001, lng: kaunas.lng))   // 11 m: not worth a refresh
        XCTAssertEqual(model.origin, kaunas)
    }
}
