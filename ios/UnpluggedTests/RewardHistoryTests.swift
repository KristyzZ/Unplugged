import XCTest
@testable import Unplugged

final class RewardHistoryTests: XCTestCase {
    @MainActor
    private func withModel(_ action: (AppModel, Station, Connector) throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let keys = ["unplugged.state.v1", "unplugged.state.v2", "unplugged.lang"]
        let previous = keys.map { defaults.object(forKey: $0) }
        let language = L10n.current
        keys.forEach { defaults.removeObject(forKey: $0) }
        let model = AppModel(runLoops: false)
        model.lockScreenEnabled = false
        defer {
            model.resetDemo()
            L10n.set(language)
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        var station = model.stations.first { $0.id == "akropolis" }!
        station.connectors[0].status = .available
        station.connectors[0].provenance = .demo(at: .now)
        try action(model, station, station.connectors[0])
    }

    @MainActor
    func testRedemptionRequestIsOnceOnlyAcrossRepeatAndReload() throws {
        try withModel { model, _, _ in
            let reward = Points.rewards[0]
            let before = model.points
            let lifetime = model.lifetimePoints
            XCTAssertTrue(model.redeem(reward, requestId: "one-request"))
            for _ in 0..<10 { XCTAssertFalse(model.redeem(reward, requestId: "one-request")) }
            model.load()
            XCTAssertFalse(model.redeem(reward, requestId: "one-request"))
            XCTAssertEqual(model.points, before - reward.cost)
            XCTAssertEqual(model.lifetimePoints, lifetime)
            XCTAssertEqual(model.rewardRedemptions.count, 1)
            XCTAssertEqual(model.history.filter { $0.redemptionId == "one-request" }.count, 1)
            let record = try XCTUnwrap(model.rewardRedemptions.first)
            XCTAssertEqual(record.rewardId, reward.id)
            XCTAssertEqual(record.cost, reward.cost)
            XCTAssertEqual(record.id, "one-request")
        }
    }

    @MainActor
    func testDistinctExplicitRequestsCanRedeemAgainButCannotOverdraw() {
        withModel { model, _, _ in
            model.points = 200
            let reward = Points.rewards[0]
            XCTAssertTrue(model.redeem(reward, requestId: "first"))
            XCTAssertTrue(model.redeem(reward, requestId: "second"))
            XCTAssertFalse(model.redeem(reward, requestId: "third"))
            XCTAssertEqual(model.points, 40)
            XCTAssertEqual(Set(model.rewardRedemptions.map(\.id)), ["first", "second"])
        }
    }

    @MainActor
    func testForgedTermsCannotMintPointsOrCreateUnknownRewards() {
        withModel { model, _, _ in
            let before = model.points
            let forged = Points.Reward(id: "coffee", title: "Forged", partner: "X", cost: -100)
            XCTAssertTrue(model.redeem(forged, requestId: "canonical"))
            XCTAssertEqual(model.points, before - 80)
            let unknown = Points.Reward(id: "not-in-catalog", title: "Fake", partner: "X", cost: 0)
            XCTAssertFalse(model.redeem(unknown, requestId: "unknown"))
            XCTAssertFalse(model.redeem(Points.rewards[0], requestId: ""))
            XCTAssertEqual(model.rewardRedemptions.count, 1)
        }
    }

    @MainActor
    func testDefaultRequestAndReusedRequestForDifferentRewardAreIdempotent() {
        withModel { model, _, _ in
            model.points = 600
            XCTAssertTrue(model.redeem(Points.rewards[0]))
            XCTAssertFalse(model.redeem(Points.rewards[0]))
            XCTAssertTrue(model.redeem(Points.rewards[0], requestId: "shared"))
            XCTAssertFalse(model.redeem(Points.rewards[1], requestId: "shared"))
            XCTAssertEqual(model.points, 440)
        }
    }

    @MainActor
    func testRewardTitlesFollowLanguageWithoutChangingRecordOrCost() throws {
        try withModel { model, _, _ in
            model.setLang(.en)
            XCTAssertTrue(model.redeem(Points.rewards[1], requestId: "localized"))
            let record = try XCTUnwrap(model.rewardRedemptions.first)
            let english = record.title
            model.setLang(.lt)
            let lithuanian = record.title
            XCTAssertNotEqual(english, lithuanian)
            XCTAssertEqual(lithuanian, "−5 % kitam įkrovimui")
            XCTAssertEqual(Points.rewards[3].title, "−50 % automobilio plovimui")
            XCTAssertEqual(Points.rewards[4].title, "−20 % visiems įkrovimams savaitę")
            XCTAssertEqual(lithuanian, Points.rewards[1].title)
            XCTAssertEqual(model.rewardRedemptions.first, record)
            XCTAssertEqual(model.points, 20)
        }
    }

    @MainActor
    func testReleaseImmediatelyArchivesAndReceiptDismissalDoesNotDuplicate() throws {
        try withModel { model, station, connector in
            let before = model.sessionHistory.count
            let points = model.points
            model.startCharging(at: station, connector: connector, targetSoc: 80)
            let started = try XCTUnwrap(model.session)
            model.checkSession(at: started.scheduledDoneAt)
            model.leaveSpot(at: started.scheduledDoneAt.addingTimeInterval(60))
            let archived = try XCTUnwrap(model.sessionHistory.first)
            XCTAssertEqual(model.sessionHistory.count, before + 1)
            XCTAssertEqual(archived.id, started.id)
            XCTAssertEqual(archived.historyOrigin, .simulatedDemo)
            XCTAssertNotNil(archived.settledEnergyKwh)
            XCTAssertNotNil(archived.settledCharges)
            let receipt = SessionSnapshot(archived, now: archived.endedAt!)
            for _ in 0..<3 {
                _ = SessionSnapshot(archived, now: Fixtures.t0.addingTimeInterval(100_000))
                model.archiveCompletedSession(archived)
            }
            model.load()
            model.hideTile()
            model.finishSession()
            XCTAssertEqual(model.sessionHistory.filter { $0.id == started.id }.count, 1)
            XCTAssertEqual(model.points, points + 30)
            let reloaded = try XCTUnwrap(model.sessionHistory.first)
            let later = SessionSnapshot(reloaded, now: Fixtures.t0.addingTimeInterval(1_000_000))
            XCTAssertEqual(later.chargingCost, receipt.chargingCost)
            XCTAssertEqual(later.kwh, receipt.kwh)
            XCTAssertEqual(later.idleFee, receipt.idleFee)
        }
    }

    @MainActor
    func testRepeatedSessionsAtSameStationHaveDifferentIDsAndPreserveFirstReceipt() throws {
        try withModel { model, station, connector in
            model.startCharging(at: station, connector: connector, targetSoc: 80)
            let first = try XCTUnwrap(model.session)
            model.checkSession(at: first.scheduledDoneAt)
            model.leaveSpot(at: first.scheduledDoneAt.addingTimeInterval(60))
            model.setSoc(34)
            model.startCharging(at: station, connector: connector, targetSoc: 80)
            let second = try XCTUnwrap(model.session)
            XCTAssertNotEqual(first.id, second.id)
            XCTAssertEqual(model.sessionHistory.filter { $0.id == first.id }.count, 1)
            XCTAssertFalse(model.sessionHistory.contains { $0.id == second.id })
        }
    }

    @MainActor
    func testLoadedDuplicateHistoryIsDeduplicatedWithoutAdditionalPoints() {
        withModel { model, _, _ in
            let seeded = model.sessionHistory[0]
            model.sessionHistory = [seeded, seeded]
            let points = model.points
            model.save()
            model.load()
            XCTAssertEqual(model.sessionHistory.count, 1)
            XCTAssertEqual(model.points, points)
        }
    }

    @MainActor
    func testLegacyProfileMissingRewardRecordsKeepsBalanceAndHistory() throws {
        try withModel { model, _, _ in
            XCTAssertTrue(model.redeem(Points.rewards[0], requestId: "old"))
            let points = model.points
            let history = model.history
            let data = try XCTUnwrap(UserDefaults.standard.data(forKey: "unplugged.state.v2"))
            var sections = try JSONDecoder().decode([String: Data].self, from: data)
            var profile = try JSONSerialization.jsonObject(with: sections["profile"]!) as! [String: Any]
            profile.removeValue(forKey: "rewardRedemptions")
            sections["profile"] = try JSONSerialization.data(withJSONObject: profile)
            UserDefaults.standard.set(try JSONEncoder().encode(sections), forKey: "unplugged.state.v2")
            model.load()
            XCTAssertEqual(model.points, points)
            XCTAssertEqual(model.history, history)
            XCTAssertTrue(model.rewardRedemptions.isEmpty)
        }
    }

    @MainActor
    func testResetRestoresSeededHistoryAndClearsRewardRecords() {
        withModel { model, _, _ in
            XCTAssertTrue(model.redeem(Points.rewards[0], requestId: "reset"))
            model.resetDemo()
            model.load()
            XCTAssertTrue(model.rewardRedemptions.isEmpty)
            XCTAssertEqual(model.points, 120)
            XCTAssertEqual(model.sessionHistory.map(\.historyOrigin), [.seededDemo, .seededDemo])
            XCTAssertEqual(model.sessionHistory.map(\.id), ["seed:akropolis", "seed:ozas"])
        }
    }

    func testOlderSessionWithoutOriginOrSettlementStillDecodes() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Fixtures.session())) as! [String: Any]
        for key in ["origin", "settledCharges", "settledEnergyKwh", "settledLegacyEnergyCost"] { json.removeValue(forKey: key) }
        let restored = try JSONDecoder().decode(ChargingSession.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.historyOrigin, .legacyDemo)
        XCTAssertEqual(SessionSnapshot(restored, now: Fixtures.at(minutes: 30)).chargingCost, 36 / 0.92 * 0.5, accuracy: 1e-9)
    }
}
