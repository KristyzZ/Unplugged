import XCTest
@testable import Unplugged

final class PricingTests: XCTestCase {
    private func tariff(operatorId: String = "ignitis", supportsPlans: Bool = true) -> Pricing.Tariff {
        .init(id: "test", operatorId: operatorId, operatorName: "Test operator", energyEurPerKwh: 0.50,
              startEur: 1, chargingEurPerMinute: 0.10, supportsAccountPricing: supportsPlans)
    }

    private func quote(_ id: String = "ignitis", active: Set<String> = [], supportsPlans: Bool = true,
                       isAC: Bool = false) -> Pricing.Estimate {
        Pricing.estimate(tariff: tariff(operatorId: id, supportsPlans: supportsPlans),
                         plans: PricingDemoFixtures.plans, activePlanIds: active, isAC: isAC,
                         kwh: 20, chargingMinutes: 30)
    }

    func testPublicTariffIncludesAllChargingComponentsButNoIdleFee() {
        let q = quote()
        XCTAssertEqual(q.terms.selection, .publicTariff)
        XCTAssertNil(q.terms.plan)
        XCTAssertEqual(q.charges.energy, 10)
        XCTAssertEqual(q.charges.sessionStart, 1)
        XCTAssertEqual(q.charges.chargingTime, 3)
        XCTAssertEqual(q.charges.total, 14)
        XCTAssertEqual(q.charges.savings, 0)
    }

    func testIgnitisAndEnefitDiscountEnergyOnly() {
        for (id, energy, savings) in [("ignitis", 9.0, 1.0), ("enefit", 9.2, 0.8)] {
            let q = quote(id, active: [id])
            XCTAssertEqual(q.terms.selection, .operatorPlan)
            XCTAssertEqual(q.charges.energy, energy)
            XCTAssertEqual(q.charges.savings, savings)
            XCTAssertEqual(q.charges.sessionStart, 1)
            XCTAssertEqual(q.charges.chargingTime, 3)
        }
    }

    func testEleportPlanWaivesOnlyTheStartFee() {
        let q = quote("eleport", active: ["eleport"])
        XCTAssertEqual(q.charges.energy, 10)
        XCTAssertEqual(q.charges.sessionStart, 0)
        XCTAssertEqual(q.charges.chargingTime, 3)
        XCTAssertEqual(q.charges.total, 13)
        XCTAssertEqual(q.charges.savings, 1)
    }

    func testInbalancePlanIsACOnly() {
        let ac = quote("inbalance", active: ["inbalance"], isAC: true)
        XCTAssertEqual(ac.charges.energy, 8.8)
        XCTAssertEqual(ac.terms.selection, .operatorPlan)
        let dc = quote("inbalance", active: ["inbalance"])
        XCTAssertEqual(dc.terms.selection, .planNotApplicable)
        XCTAssertEqual(dc.charges.total, 14)
        XCTAssertNil(dc.terms.plan)
    }

    func testWrongOperatorAndUnknownPlanNeverChangeThePublicQuote() {
        XCTAssertEqual(quote(active: ["eleport", "unknown"]), quote())
    }

    func testActivePlanWithoutAccountPricingSupportUsesPublicTariff() {
        let q = quote(active: ["ignitis"], supportsPlans: false)
        XCTAssertEqual(q.terms.selection, .accountPricingUnsupported)
        XCTAssertNil(q.terms.plan)
        XCTAssertEqual(q.charges.total, 14)
    }

    func testAccountPricingIsOptInOnTheReusableAPI() {
        let t = Pricing.Tariff(id: "observed", operatorId: "ignitis", operatorName: "Operator",
                              energyEurPerKwh: 0.5, startEur: 0, chargingEurPerMinute: 0)
        XCTAssertFalse(t.supportsAccountPricing)
        let terms = Pricing.freeze(tariff: t, plans: PricingDemoFixtures.plans,
                                   activePlanIds: ["ignitis"], isAC: false)
        XCTAssertNil(terms.plan)
    }

    func testTermsAreValueSnapshotsOfBothTariffAndPlan() throws {
        var plans = PricingDemoFixtures.plans
        let frozen = Pricing.freeze(tariff: tariff(), plans: plans, activePlanIds: ["ignitis"], isAC: false)
        plans[0].energyDiscount = 0.50
        let revised = Pricing.Tariff(id: "new", operatorId: "ignitis", operatorName: "Changed operator",
                                    energyEurPerKwh: 1, startEur: 2, chargingEurPerMinute: 0.2,
                                    supportsAccountPricing: true)
        let current = Pricing.estimate(tariff: revised, plans: plans, activePlanIds: [], isAC: false,
                                       kwh: 20, chargingMinutes: 30)
        XCTAssertEqual(current.charges.total, 28)
        let restored = try JSONDecoder().decode(Pricing.Terms.self, from: JSONEncoder().encode(frozen))
        XCTAssertEqual(restored, frozen)
        XCTAssertEqual(Pricing.charges(terms: restored, kwh: 20, chargingMinutes: 30).total, 13)
        XCTAssertEqual(restored.plan?.energyDiscount, 0.10)
    }

    func testMonetaryLinesRoundDecimalTiesToCents() {
        let t = Pricing.Tariff(id: "round", operatorId: "x", operatorName: "X",
                              energyEurPerKwh: 1.005, startEur: 0.305, chargingEurPerMinute: 0.005)
        let q = Pricing.estimate(tariff: t, plans: [], activePlanIds: [], isAC: true, kwh: 1, chargingMinutes: 1)
        XCTAssertEqual(q.charges.energy, 1.01)
        XCTAssertEqual(q.charges.sessionStart, 0.31)
        XCTAssertEqual(q.charges.chargingTime, 0.01)
        XCTAssertEqual(q.charges.total, 1.33)
        XCTAssertEqual(q.charges.savings, 0)
    }

    func testZeroEnergyStillHasOneStartFeeAndTimeCharge() {
        let terms = quote().terms
        let charge = Pricing.charges(terms: terms, kwh: 0, chargingMinutes: 10)
        XCTAssertEqual(charge.total, 2)
        XCTAssertEqual(charge.sessionStart, 1)
    }

    func testUnknownStationDoesNotInheritAccountPricingFromItsOperator() {
        let source = Fixtures.station("imported", at: Fixtures.vilnius)
        let station = Station(id: source.id, name: source.name, address: source.address, city: source.city,
                              lat: source.lat, lng: source.lng, operatorId: "ignitis", pricePerKwh: 0.5,
                              connectors: source.connectors, hourlyOccupancy: source.hourlyOccupancy, amenities: [])
        let t = PricingDemoFixtures.tariff(station: station, connector: source.connectors[0])
        XCTAssertFalse(t.supportsAccountPricing)
        XCTAssertEqual(t.startEur, 0)
        XCTAssertEqual(t.chargingEurPerMinute, 0)
    }

    func testPricingFixturesMatchExistingProfilePlans() {
        XCTAssertEqual(Set(PricingDemoFixtures.plans.map(\.id)), Set(DemoData.plans.map(\.id)))
    }
}
