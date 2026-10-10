import XCTest
@testable import Unplugged

final class LeaderboardTests: XCTestCase {
    private func d(_ id: String, _ points: Int, _ co2: Double, you: Bool = false) -> Leaderboard.Driver {
        Leaderboard.Driver(id: id, name: id, points: points, co2Kg: co2, isYou: you)
    }

    func testRanksByChosenMetric() {
        let drivers = [d("a", 100, 10), d("b", 50, 90), d("c", 75, 40)]
        XCTAssertEqual(Leaderboard.ranked(drivers, by: .points).map(\.id), ["a", "c", "b"])
        XCTAssertEqual(Leaderboard.ranked(drivers, by: .co2).map(\.id), ["b", "c", "a"])
    }

    func testTiesShareRankAndYouComeFirst() {
        let rows = Leaderboard.ranked([d("a", 50, 0), d("me", 50, 0, you: true), d("b", 10, 0)], by: .points)
        XCTAssertEqual(rows.map(\.id), ["me", "a", "b"])
        XCTAssertEqual(rows.map(\.rank), [1, 1, 3])
    }

    func testCompactPinsYouBelowTop() {
        let drivers = (1...6).map { d("d\($0)", 100 - $0, 0) } + [d("me", 1, 0, you: true)]
        let c = Leaderboard.compact(Leaderboard.ranked(drivers, by: .points))
        XCTAssertEqual(c.top.map(\.id), ["d1", "d2", "d3"])
        XCTAssertEqual(c.you?.rank, 7)
    }

    func testCompactDoesNotRepeatYouInTop() {
        let c = Leaderboard.compact(Leaderboard.ranked([d("me", 999, 0, you: true), d("a", 1, 0)], by: .points))
        XCTAssertNil(c.you)
    }

    func testCO2FromChargedEnergy() {
        // 20 % → 80 % of a 77 kWh battery = 46.2 kWh.
        let s = ChargingSession(stationId: "s", stationName: "S", connectorLabel: "CCS2", startedAt: .now,
                                startSoc: 20, targetSoc: 80, minutesToTarget: 30, graceMinutes: 10,
                                pricePerKwh: 0.5, batteryKwh: 77)
        XCTAssertEqual(Leaderboard.co2Saved([s]), 46.2 * Leaderboard.co2KgPerKwh, accuracy: 0.001)
    }
}
