import XCTest
@testable import Unplugged

final class ReportIntegrityTests: XCTestCase {
    @MainActor
    private func withModel(_ action: (AppModel) throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let keys = ["unplugged.state.v1", "unplugged.state.v2", "unplugged.lang"]
        let previous = keys.map { defaults.object(forKey: $0) }
        keys.forEach { defaults.removeObject(forKey: $0) }
        let model = AppModel(runLoops: false)
        model.lockScreenEnabled = false
        defer {
            model.resetDemo()
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        try action(model)
    }

    private func report(_ kind: ReportKind = .wrongUsage, byMe: Bool = false) -> AbuseReport {
        AbuseReport(id: "report-\(kind.rawValue)", stationId: "akropolis", plate: kind == .wrongUsage ? "ABC 123" : "",
                    description: "Test", hasPhoto: true, telemetryMatches: true, confirmations: 0,
                    createdAt: Fixtures.t0, byMe: byMe, kind: kind)
    }

    func testConfidenceNeverDeterminesReviewedOutcome() {
        var r = report()
        XCTAssertGreaterThanOrEqual(r.confidence, Reports.confirmThreshold)
        XCTAssertEqual(r.reviewStatus, .pendingReview)
        XCTAssertFalse(r.isConfirmed)
        r.reviewState = .reviewedRejected
        XCTAssertFalse(r.isConfirmed)
        r.reviewState = .reviewedAccepted
        XCTAssertTrue(r.isConfirmed)
    }

    @MainActor
    func testConfirmationIsOnceOnlyForAllCategoriesAndSurvivesReload() throws {
        try withModel { model in
            for kind in ReportKind.allCases {
                let r = report(kind)
                model.reports = [r]
                let before = model.points
                model.confirmReport(r.id)
                model.confirmReport(r.id)
                model.load()
                model.confirmReport(r.id)
                let restored = try XCTUnwrap(model.reports.first)
                XCTAssertEqual(restored.confirmations, 1)
                XCTAssertTrue(restored.confirmedByMe == true)
                XCTAssertFalse(restored.canConfirm)
                XCTAssertEqual(restored.reviewStatus, .pendingReview)
                XCTAssertEqual(model.points, before + (kind == .wrongUsage ? 5 : 0))
            }
        }
    }

    @MainActor
    func testOwnAndReviewedReportsCannotBeConfirmedForPoints() {
        withModel { model in
            var own = report(byMe: true)
            model.reports = [own]
            let before = model.points
            model.confirmReport(own.id)
            XCTAssertEqual(model.reports[0].confirmations, 0)
            own.reviewState = .reviewedRejected
            var foreign = report()
            foreign.reviewState = .reviewedAccepted
            model.reports = [own, foreign]
            model.confirmReport(foreign.id)
            XCTAssertEqual(model.points, before)
            XCTAssertEqual(model.reports[1].confirmations, 0)
        }
    }

    @MainActor
    func testSubmissionAndExplicitReviewAwardOwnerOnce() throws {
        try withModel { model in
            var station = model.stations[0]
            station.connectors[0].status = .blocked
            station.connectors[0].provenance = .demo(at: .now)
            let before = model.points
            model.submitReport(station: station, kind: .wrongUsage, connectorId: nil,
                               plate: "abc 123", description: "Test", hasPhoto: true)
            let id = try XCTUnwrap(model.reports.first?.id)
            XCTAssertEqual(model.reports[0].reviewStatus, .submitted)
            XCTAssertFalse(model.reports[0].isConfirmed)
            XCTAssertEqual(model.points, before)
            model.queueReportForReview(id)
            XCTAssertEqual(model.reports[0].reviewStatus, .pendingReview)
            model.reviewReport(id, accepted: true)
            model.reviewReport(id, accepted: true)
            model.load()
            model.reviewReport(id, accepted: true)
            XCTAssertEqual(model.points, before + 15)
            XCTAssertEqual(model.reports[0].reviewStatus, .reviewedAccepted)
            XCTAssertNotNil(model.reports[0].reviewedAt)
        }
    }

    @MainActor
    func testRejectedOrNonWrongUseReviewDoesNotAwardReportPoints() {
        withModel { model in
            let before = model.points
            for kind in ReportKind.allCases {
                let r = report(kind, byMe: true)
                model.reports = [r]
                model.reviewReport(r.id, accepted: kind != .wrongUsage)
                XCTAssertEqual(model.points, before)
            }
        }
    }

    @MainActor
    func testLegacyHighConfidenceOwnerRewardIsNotAwardedAgain() {
        withModel { model in
            let r = report(byMe: true)
            model.reports = [r]
            model.addPoints(.reportConfirmed, note: "Old reward")
            let rewarded = model.points
            model.load()
            XCTAssertEqual(model.reports[0].reviewStatus, .pendingReview)
            XCTAssertTrue(model.reports[0].reportRewardGranted == true)
            model.reviewReport(r.id, accepted: true)
            XCTAssertEqual(model.points, rewarded)
        }
    }

    func testOlderReportStillDecodesWithoutNewReviewFields() throws {
        let data = try JSONEncoder().encode(report())
        let restored = try JSONDecoder().decode(AbuseReport.self, from: data)
        XCTAssertNil(restored.reviewState)
        XCTAssertNil(restored.confirmedByMe)
        XCTAssertEqual(restored.reviewStatus, .pendingReview)
        XCTAssertTrue(restored.canConfirm)
    }

    @MainActor
    func testResetClearsLocalConfirmationAndReviewRecords() {
        withModel { model in
            let r = report()
            model.reports = [r]
            model.confirmReport(r.id)
            model.resetDemo()
            XCTAssertFalse(model.reports.contains { $0.id == r.id })
            XCTAssertEqual(model.points, 120)
        }
    }
}
