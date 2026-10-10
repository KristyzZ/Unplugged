import XCTest
@testable import Unplugged

/// `SessionSnapshot` takes the current time as input, so every phase boundary is tested
/// against fixed instants (no wall clock, no sleeping).
final class SessionTimelineTests: XCTestCase {
    private func finished(_ s: ChargingSession) -> ChargingSession {
        var done = s
        done.doneAt = s.scheduledDoneAt
        return done
    }

    func testProgressIsLinearWhileCharging() {
        let s = Fixtures.session() // 20 -> 80 % over 30 min
        let start = SessionSnapshot(s, now: Fixtures.t0)
        XCTAssertEqual(start.phase, .charging)
        XCTAssertEqual(start.soc, 20, accuracy: 1e-9)

        let half = SessionSnapshot(s, now: Fixtures.at(minutes: 15))
        XCTAssertEqual(half.phase, .charging)
        XCTAssertEqual(half.soc, 50, accuracy: 1e-9)
        XCTAssertEqual(half.minutesLeft, 15, accuracy: 1e-9)
    }

    func testEnergyAndCostIncludeChargingLosses() {
        let snap = SessionSnapshot(Fixtures.session(), now: Fixtures.at(minutes: 30))
        // 60 % of 60 kWh = 36 kWh delivered, /0.92 drawn from the grid.
        XCTAssertEqual(snap.kwh, 36 / 0.92, accuracy: 1e-9)
        XCTAssertEqual(snap.energyCost, 36 / 0.92 * 0.5, accuracy: 1e-9)
    }

    func testSocStopsAtTheTargetEvenIfTimeKeepsRunning() {
        let snap = SessionSnapshot(Fixtures.session(), now: Fixtures.at(minutes: 90))
        XCTAssertEqual(snap.soc, 80, accuracy: 1e-9)
    }

    func testGraceStartsWhenChargingIsDone() {
        let s = finished(Fixtures.session())
        let snap = SessionSnapshot(s, now: Fixtures.at(minutes: 30))
        XCTAssertEqual(snap.phase, .grace)
        XCTAssertEqual(snap.graceLeft, 600, accuracy: 1e-9)
        XCTAssertEqual(snap.idleFee, 0)
    }

    func testLastSecondOfGraceIsStillGraceThenIdleBegins() {
        let s = finished(Fixtures.session(grace: 10))
        let justBefore = SessionSnapshot(s, now: Fixtures.at(minutes: 30).addingTimeInterval(599))
        XCTAssertEqual(justBefore.phase, .grace)
        XCTAssertEqual(justBefore.graceLeft, 1, accuracy: 1e-9)

        let atBoundary = SessionSnapshot(s, now: Fixtures.at(minutes: 40))
        XCTAssertEqual(atBoundary.phase, .idle)
        XCTAssertEqual(atBoundary.idleMinutes, 0, accuracy: 1e-9)
        XCTAssertEqual(atBoundary.idleFee, 0)
    }

    func testIdleFeeMatchesThePolicyAtTierBoundaries() {
        let s = finished(Fixtures.session(grace: 10))
        // Idle time counts from the end of grace: minute 40 is 0 idle minutes.
        for (idle, expected) in [(5.0, 0.50), (10.0, 1.00), (30.0, 6.00)] {
            let snap = SessionSnapshot(s, now: Fixtures.at(minutes: 40 + idle))
            XCTAssertEqual(snap.phase, .idle)
            XCTAssertEqual(snap.idleMinutes, idle, accuracy: 1e-9)
            XCTAssertEqual(snap.idleFee, expected, accuracy: 1e-9, "after \(idle) idle minutes")
        }
    }

    func testIdleFeeIsCappedInTheSnapshot() {
        let s = finished(Fixtures.session(grace: 10))
        let snap = SessionSnapshot(s, now: Fixtures.at(minutes: 40 + 600))
        XCTAssertEqual(snap.idleFee, IdleFee.capEur)
    }

    func testEndedSessionIsFrozenAtTheMomentTheCarLeft() {
        var s = finished(Fixtures.session(grace: 10))
        s.endedAt = Fixtures.at(minutes: 45) // 5 idle minutes
        let early = SessionSnapshot(s, now: Fixtures.at(minutes: 46))
        let late = SessionSnapshot(s, now: Fixtures.at(minutes: 600))
        XCTAssertEqual(early.phase, .ended)
        XCTAssertEqual(late.phase, .ended)
        XCTAssertEqual(early.idleFee, 0.50, accuracy: 1e-9)
        XCTAssertEqual(late.idleFee, early.idleFee, accuracy: 1e-9)
        XCTAssertEqual(late.idleMinutes, early.idleMinutes, accuracy: 1e-9)
    }

    func testStoredSettledFeeWinsOverARecomputation() {
        var s = finished(Fixtures.session())
        s.endedAt = Fixtures.at(minutes: 45)
        s.idleFeeEur = 3.21
        XCTAssertEqual(SessionSnapshot(s, now: Fixtures.at(minutes: 99)).idleFee, 3.21, accuracy: 1e-9)
    }

    func testStoppingEarlyCutsTheEnergyDelivered() {
        var s = Fixtures.session()
        s.doneAt = Fixtures.at(minutes: 15) // stopped halfway
        let snap = SessionSnapshot(s, now: Fixtures.at(minutes: 20))
        XCTAssertEqual(snap.soc, 50, accuracy: 1e-9)
        XCTAssertEqual(snap.phase, .grace)
    }
}
