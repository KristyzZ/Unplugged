import XCTest
@testable import Unplugged

final class PricingSessionTests: XCTestCase {
    private func session(plan: Bool = true) -> ChargingSession {
        let tariff = Pricing.Tariff(id: "test", operatorId: "ignitis", operatorName: "Test operator",
                                   energyEurPerKwh: 0.5, startEur: 1, chargingEurPerMinute: 0.1,
                                   supportsAccountPricing: true)
        let terms = Pricing.freeze(tariff: tariff, plans: PricingDemoFixtures.plans,
                                   activePlanIds: plan ? ["ignitis"] : [], isAC: false)
        return ChargingSession(stationId: "s", stationName: "S", connectorLabel: "CCS2", startedAt: Fixtures.t0,
                               startSoc: 20, targetSoc: 80, minutesToTarget: 30, graceMinutes: 10,
                               pricePerKwh: terms.energyEurPerKwh, batteryKwh: 60, pricingTerms: terms)
    }

    func testSessionSubtotalUsesFrozenTermsAndActualElapsedChargingTime() {
        let s = session()
        let half = SessionSnapshot(s, now: Fixtures.at(minutes: 15))
        XCTAssertEqual(half.pricingCharges?.chargingTime, 1.5)
        XCTAssertEqual(half.pricingCharges?.sessionStart, 1)
        let expected = Pricing.charges(terms: s.pricingTerms!, kwh: half.kwh, chargingMinutes: 15)
        XCTAssertEqual(half.chargingCost, expected.total)
        XCTAssertEqual(half.energyCost, expected.energy)
        XCTAssertEqual(half.idleFee, 0)
    }

    func testStoppingEarlyStopsBothEnergyAndChargingTimeCharges() {
        var s = session()
        s.doneAt = Fixtures.at(minutes: 15)
        let early = SessionSnapshot(s, now: Fixtures.at(minutes: 16))
        let late = SessionSnapshot(s, now: Fixtures.at(minutes: 200))
        XCTAssertEqual(late.chargingCost, early.chargingCost)
        XCTAssertEqual(late.pricingCharges?.chargingTime, 1.5)
        XCTAssertGreaterThan(late.idleFee, 0)
    }

    func testCompletionAndIdleDoNotExtendTheChargingTimeFee() {
        var s = session()
        s.doneAt = s.scheduledDoneAt
        let completed = SessionSnapshot(s, now: Fixtures.at(minutes: 30))
        let idle = SessionSnapshot(s, now: Fixtures.at(minutes: 45))
        XCTAssertEqual(completed.chargingCost, idle.chargingCost)
        XCTAssertEqual(idle.pricingCharges?.chargingTime, 3)
        XCTAssertEqual(idle.idleFee, 0.50)
    }

    func testPlanDoesNotDiscountIdleFees() {
        var publicSession = session(plan: false)
        var memberSession = session()
        publicSession.doneAt = publicSession.scheduledDoneAt
        memberSession.doneAt = memberSession.scheduledDoneAt
        let publicSnap = SessionSnapshot(publicSession, now: Fixtures.at(minutes: 60))
        let memberSnap = SessionSnapshot(memberSession, now: Fixtures.at(minutes: 60))
        XCTAssertEqual(publicSnap.idleFee, memberSnap.idleFee)
        XCTAssertGreaterThan(publicSnap.chargingCost, memberSnap.chargingCost)
    }

    func testStoredTermsSurviveRelaunchAndPreserveFinishedReceipt() throws {
        var s = session()
        s.doneAt = s.scheduledDoneAt
        s.endedAt = Fixtures.at(minutes: 45)
        let restored = try JSONDecoder().decode(ChargingSession.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(restored.pricingTerms, s.pricingTerms)
        let first = SessionSnapshot(s, now: Fixtures.at(minutes: 46))
        let later = SessionSnapshot(restored, now: Fixtures.at(minutes: 600))
        XCTAssertEqual(later.chargingCost, first.chargingCost)
        XCTAssertEqual(later.idleFee, first.idleFee)
    }

    func testLegacySessionWithoutPricingTermsKeepsOriginalEnergyOnlyCost() throws {
        let original = Fixtures.session()
        let data = try JSONEncoder().encode(original)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(object["pricingTerms"])
        let restored = try JSONDecoder().decode(ChargingSession.self, from: data)
        XCTAssertNil(restored.pricingTerms)
        let snap = SessionSnapshot(restored, now: Fixtures.at(minutes: 30))
        XCTAssertEqual(snap.energyCost, 36 / 0.92 * 0.5, accuracy: 1e-9)
        XCTAssertEqual(snap.chargingCost, snap.energyCost)
        XCTAssertNil(snap.pricingCharges)
    }

    @MainActor
    func testProfileTogglesChangeEstimateButNotAnAlreadyStartedSession() throws {
        let defaults = UserDefaults.standard
        let keys = ["unplugged.state.v1", "unplugged.state.v2", "unplugged.lang"]
        let saved = keys.map { defaults.object(forKey: $0) }
        keys.forEach { defaults.removeObject(forKey: $0) }
        let model = AppModel()
        model.setLockScreen(false)
        defer {
            model.resetDemo()
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        var station = DemoData.stations().first { $0.id == "akropolis" }!
        station.connectors[0].status = .available
        station.connectors[0].provenance = .demo(at: .now)
        let connector = station.connectors[0]
        model.setPlan("ignitis", active: false)
        let publicPrice = model.chargingEstimate(at: station, connector: connector, targetSoc: 80)
        model.setPlan("ignitis", active: true)
        let memberPrice = model.chargingEstimate(at: station, connector: connector, targetSoc: 80)
        XCTAssertLessThan(memberPrice.charges.total, publicPrice.charges.total)
        XCTAssertNil(publicPrice.terms.plan)
        XCTAssertEqual(memberPrice.terms.plan?.id, "ignitis")
        model.startCharging(at: station, connector: connector, targetSoc: 80)
        let started = try XCTUnwrap(model.session)
        XCTAssertEqual(started.pricingTerms, memberPrice.terms)
        model.setPlan("ignitis", active: false)
        XCTAssertEqual(model.session?.pricingTerms, started.pricingTerms)
        let before = SessionSnapshot(started, now: started.scheduledDoneAt)
        let after = SessionSnapshot(try XCTUnwrap(model.session), now: started.scheduledDoneAt)
        XCTAssertEqual(before.chargingCost, memberPrice.charges.total)
        XCTAssertEqual(after.chargingCost, before.chargingCost)
        XCTAssertEqual(model.chargingEstimate(at: station, connector: connector, targetSoc: 80).terms.selection, .publicTariff)
    }
}
