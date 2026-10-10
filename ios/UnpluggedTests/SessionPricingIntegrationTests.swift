import XCTest
@testable import Unplugged

/// Where frozen pricing terms meet the held-spot and Lock Screen session fields.
final class SessionPricingIntegrationTests: XCTestCase {
    private func terms() -> Pricing.Terms {
        let tariff = Pricing.Tariff(id: "test", operatorId: "ignitis", operatorName: "Test operator",
                                    energyEurPerKwh: 0.5, startEur: 1, chargingEurPerMinute: 0.1,
                                    supportsAccountPricing: true)
        return Pricing.freeze(tariff: tariff, plans: [], activePlanIds: [], isAC: false)
    }

    private func session(terms: Pricing.Terms?) -> ChargingSession {
        ChargingSession(stationId: "s", stationName: "S", connectorLabel: "CCS2", startedAt: Fixtures.t0,
                        startSoc: 20, targetSoc: 80, minutesToTarget: 30, graceMinutes: 10,
                        pricePerKwh: 0.5, batteryKwh: 60, connectorId: "s-1", handedOver: true,
                        pricingTerms: terms)
    }

    func testPlannedCostIncludesStartFeeAndTimeChargeFromFrozenTerms() {
        let s = session(terms: terms())
        let expected = Pricing.charges(terms: s.pricingTerms!, kwh: s.plannedKwh, chargingMinutes: 30).total
        XCTAssertEqual(s.plannedCost, expected)
        // 1 € start + 30 min × 0.10 € on top of the energy.
        XCTAssertEqual(s.plannedCost, (s.plannedKwh * 0.5 * 100).rounded() / 100 + 1 + 3, accuracy: 0.011)
    }

    func testPlannedCostWithoutTermsIsEnergyOnly() {
        let s = session(terms: nil)
        XCTAssertEqual(s.plannedCost, s.plannedKwh * 0.5, accuracy: 1e-9)
    }

    func testPlannedCostMatchesTheChargedTotalAtTheTarget() {
        let s = session(terms: terms())
        let atTarget = SessionSnapshot(s, now: Fixtures.at(minutes: 30))
        XCTAssertEqual(atTarget.chargingCost, s.plannedCost, accuracy: 0.011)
    }

    func testConnectorAndHandoverSurviveASaveWithPricingTerms() throws {
        let s = session(terms: terms())
        let decoded = try JSONDecoder().decode(ChargingSession.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded.connectorId, "s-1")
        XCTAssertEqual(decoded.handedOver, true)
        XCTAssertEqual(decoded.pricingTerms, s.pricingTerms)
    }
}
