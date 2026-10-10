import XCTest
@testable import Unplugged

/// Private charger hosting: market price, suggested price, open hours,
/// earnings estimate and how a listing shows up as a station.
final class HostingTests: XCTestCase {
    /// UTC, so Fixtures.t0 is Friday 2027-01-15 08:00.
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func ac(_ id: String, at p: LatLng, price: Double) -> Station {
        Fixtures.station(id, at: p, connectors: [Fixtures.connector(.type2, kw: 22)], price: price)
    }

    private func dc(_ id: String, at p: LatLng, price: Double) -> Station {
        Fixtures.station(id, at: p, connectors: [Fixtures.connector(.ccs2, kw: 150)], price: price)
    }

    // MARK: Market price

    func testQuoteUsesNearbyStationsOfTheSameKind() {
        let v = Fixtures.vilnius
        let stations = [
            ac("a", at: v, price: 0.40), ac("b", at: v, price: 0.50), ac("c", at: v, price: 0.60),
            dc("fast", at: v, price: 0.90),             // DC: not comparable with an AC charger
            ac("far", at: Fixtures.kaunas, price: 0.10), // ~90 km away
        ]
        let quote = Hosting.marketQuote(at: v, powerKw: 11, stations: stations)
        XCTAssertEqual(quote.sampleCount, 3)
        XCTAssertEqual(quote.low, 0.40, accuracy: 1e-9)
        XCTAssertEqual(quote.median, 0.50, accuracy: 1e-9)
        XCTAssertEqual(quote.high, 0.60, accuracy: 1e-9)
        XCTAssertEqual(quote.radiusKm, Hosting.marketRadiusKm)
    }

    func testQuoteWidensWhenTooFewStationsAreClose() {
        let stations = [ac("a", at: Fixtures.vilnius, price: 0.40), ac("b", at: Fixtures.kaunas, price: 0.50)]
        let quote = Hosting.marketQuote(at: Fixtures.vilnius, powerKw: 7.4, stations: stations)
        XCTAssertEqual(quote.sampleCount, 2)
        XCTAssertEqual(quote.median, 0.45, accuracy: 1e-9)
        XCTAssertGreaterThan(quote.radiusKm, Hosting.marketRadiusKm)
    }

    func testQuoteIgnoresOtherHostedChargers() {
        var hosted = HostListing()
        hosted.location = Fixtures.vilnius
        hosted.pricePerKwh = 0.05
        let station = Hosting.station(for: hosted, at: Fixtures.t0)
        let stations = [ac("a", at: Fixtures.vilnius, price: 0.40)] + [station].compactMap { $0 }
        let quote = Hosting.marketQuote(at: Fixtures.vilnius, powerKw: 11, stations: stations)
        XCTAssertEqual(quote.sampleCount, 1)
        XCTAssertEqual(quote.low, 0.40, accuracy: 1e-9)
    }

    func testQuoteFallsBackToATypicalPriceWithNoStations() {
        let quote = Hosting.marketQuote(at: Fixtures.vilnius, powerKw: 11, stations: [])
        XCTAssertEqual(quote.sampleCount, 0)
        XCTAssertEqual(quote.median, 0.45, accuracy: 1e-9)
    }

    // MARK: Suggested price

    func testSuggestionSitsUnderTheMarket() {
        XCTAssertEqual(Hosting.suggest(median: 0.50, fast: false), 0.45, accuracy: 1e-9) // −10 % AC
        XCTAssertEqual(Hosting.suggest(median: 0.60, fast: true), 0.57, accuracy: 1e-9)  // −5 % DC
    }

    func testSuggestionNeverGoesBelowTheFloor() {
        XCTAssertEqual(Hosting.suggest(median: 0.10, fast: false), Hosting.minPrice, accuracy: 1e-9)
    }

    func testFloorCoversElectricityAfterTheFee() {
        XCTAssertGreaterThanOrEqual(Hosting.minPrice * (1 - Hosting.serviceFee), Hosting.homeEnergyCost)
    }

    func testPositionAgainstTheMarket() {
        let quote = MarketQuote(low: 0.4, median: 0.5, high: 0.6, suggested: 0.45, sampleCount: 3, radiusKm: 10)
        XCTAssertEqual(Hosting.position(of: 0.40, in: quote), .below)
        XCTAssertEqual(Hosting.position(of: 0.50, in: quote), .inLine)
        XCTAssertEqual(Hosting.position(of: 0.60, in: quote), .above)
    }

    // MARK: Schedule

    func testHoursPerWeek() {
        XCTAssertEqual(HostSchedule.always.hoursPerWeek, 168)
        XCTAssertEqual(HostSchedule.workdays.hoursPerWeek, 50)    // 5 × 10 h
        XCTAssertEqual(HostSchedule.evenings.hoursPerWeek, 98)    // 7 × 14 h overnight
    }

    func testDaytimeWindow() {
        let s = HostSchedule.workdays // Mon–Fri 08–18
        XCTAssertTrue(s.isOpen(at: Fixtures.t0, calendar: utc))                          // Fri 08:00
        XCTAssertFalse(s.isOpen(at: Fixtures.at(minutes: 10 * 60), calendar: utc))       // Fri 18:00
        XCTAssertFalse(s.isOpen(at: Fixtures.at(minutes: 24 * 60), calendar: utc))       // Sat 08:00
    }

    func testOvernightWindowBelongsToTheDayItStarts() {
        let s = HostSchedule(days: [5], fromHour: 18, toHour: 8) // Friday night only
        XCTAssertFalse(s.isOpen(at: Fixtures.at(minutes: -60), calendar: utc))           // Fri 07:00 (Thu night)
        XCTAssertTrue(s.isOpen(at: Fixtures.at(minutes: 11 * 60), calendar: utc))        // Fri 19:00
        XCTAssertTrue(s.isOpen(at: Fixtures.at(minutes: 22 * 60), calendar: utc))        // Sat 06:00
        XCTAssertFalse(s.isOpen(at: Fixtures.at(minutes: 24 * 60), calendar: utc))       // Sat 08:00
    }

    // MARK: Earnings

    func testEarningsGrowWithOpenHoursAndShrinkWithPrice() {
        let quote = MarketQuote(low: 0.4, median: 0.5, high: 0.6, suggested: 0.45, sampleCount: 3, radiusKm: 10)
        func payout(_ s: HostSchedule, _ price: Double) -> Double {
            Hosting.earnings(schedule: s, powerKw: 11, spots: 1, price: price, quote: quote, nearbyOccupancy: 0.5).payoutEur
        }
        XCTAssertGreaterThan(payout(.always, 0.45), payout(.workdays, 0.45))
        let cheapKwh = Hosting.earnings(schedule: .always, powerKw: 11, spots: 1, price: 0.40, quote: quote, nearbyOccupancy: 0.5).kwhPerMonth
        let dearKwh = Hosting.earnings(schedule: .always, powerKw: 11, spots: 1, price: 0.60, quote: quote, nearbyOccupancy: 0.5).kwhPerMonth
        XCTAssertGreaterThan(cheapKwh, dearKwh)
    }

    func testPayoutTakesTheServiceFee() {
        let quote = MarketQuote(low: 0.4, median: 0.5, high: 0.6, suggested: 0.45, sampleCount: 3, radiusKm: 10)
        let e = Hosting.earnings(schedule: .evenings, powerKw: 22, spots: 1, price: 0.45, quote: quote, nearbyOccupancy: 0.4)
        XCTAssertEqual(e.grossEur, e.kwhPerMonth * 0.45, accuracy: 1e-9)
        XCTAssertEqual(e.payoutEur, e.grossEur * (1 - Hosting.serviceFee), accuracy: 1e-9)
        XCTAssertEqual(e.profitEur, e.payoutEur - e.kwhPerMonth * Hosting.homeEnergyCost, accuracy: 1e-9)
    }

    // MARK: On the map

    func testListingBecomesABookableStationWhileOpen() {
        var listing = HostListing()
        listing.title = "Driveway"
        listing.spots = 2
        listing.schedule = .always
        let station = Hosting.station(for: listing, at: Fixtures.t0)
        XCTAssertEqual(station?.id, listing.id)
        XCTAssertEqual(station?.operatorId, HostListing.operatorId)
        XCTAssertEqual(station?.connectors.count, 2)
        XCTAssertEqual(station?.freeCount, 2)
    }

    func testPausedOrClosedListingIsHidden() {
        var listing = HostListing()
        listing.schedule = .always
        listing.paused = true
        XCTAssertNil(Hosting.station(for: listing, at: Fixtures.t0))
        listing.paused = false
        listing.schedule = HostSchedule(days: [], fromHour: 0, toHour: 24)
        XCTAssertNil(Hosting.station(for: listing, at: Fixtures.t0))
    }
}
