import XCTest
@testable import Unplugged

/// Policy under test (SPEC.md): grace 5-15 min by demand, then 0.10 / 0.25 / 0.50 EUR per minute
/// from minute 0 / 10 / 30 after grace, capped at 40 EUR.
final class IdleFeeTests: XCTestCase {
    // MARK: Grace period

    func testGraceIsLongestWhenDemandIsLow() {
        XCTAssertEqual(IdleFee.graceMinutes(demand: 0), IdleFee.graceMax)
        XCTAssertEqual(IdleFee.graceMinutes(demand: 0.4), IdleFee.graceMax)
    }

    func testGraceIsShortestWhenDemandIsHigh() {
        XCTAssertEqual(IdleFee.graceMinutes(demand: 0.9), IdleFee.graceMin)
        XCTAssertEqual(IdleFee.graceMinutes(demand: 1), IdleFee.graceMin)
    }

    func testGraceInterpolatesBetweenTheBounds() {
        XCTAssertEqual(IdleFee.graceMinutes(demand: 0.5), 13)
        XCTAssertEqual(IdleFee.graceMinutes(demand: 0.65), 10) // midpoint
        XCTAssertEqual(IdleFee.graceMinutes(demand: 0.8), 7)
    }

    func testGraceClampsOutOfRangeDemand() {
        XCTAssertEqual(IdleFee.graceMinutes(demand: -3), IdleFee.graceMax)
        XCTAssertEqual(IdleFee.graceMinutes(demand: 7), IdleFee.graceMin)
    }

    func testGraceNeverIncreasesAsDemandGrows() {
        var previous = Int.max
        for step in 0...100 {
            let grace = IdleFee.graceMinutes(demand: Double(step) / 100)
            XCTAssertLessThanOrEqual(grace, previous, "grace grew at demand \(Double(step) / 100)")
            XCTAssertTrue((IdleFee.graceMin...IdleFee.graceMax).contains(grace))
            previous = grace
        }
    }

    // MARK: Tier boundaries

    func testNoFeeBeforeOrAtZeroMinutes() {
        XCTAssertEqual(IdleFee.fee(minutes: 0), 0)
        XCTAssertEqual(IdleFee.fee(minutes: -5), 0)
    }

    func testFirstTierChargesTenCentsPerMinute() {
        XCTAssertEqual(IdleFee.fee(minutes: 5), 0.50, accuracy: 1e-9)
        XCTAssertEqual(IdleFee.fee(minutes: 10), 1.00, accuracy: 1e-9) // end of tier 1
    }

    func testSecondTierStartsAfterTenMinutes() {
        XCTAssertEqual(IdleFee.fee(minutes: 20), 1.00 + 10 * 0.25, accuracy: 1e-9)
        XCTAssertEqual(IdleFee.fee(minutes: 30), 1.00 + 20 * 0.25, accuracy: 1e-9) // end of tier 2
    }

    func testThirdTierStartsAfterThirtyMinutes() {
        XCTAssertEqual(IdleFee.fee(minutes: 40), 6.00 + 10 * 0.50, accuracy: 1e-9)
    }

    func testFeeIsRoundedToCents() {
        let fee = IdleFee.fee(minutes: 0.333)
        XCTAssertEqual(fee, (fee * 100).rounded() / 100, accuracy: 1e-12)
    }

    // MARK: Cap

    func testFeeIsCappedAtForty() {
        XCTAssertEqual(IdleFee.capEur, 40)
        XCTAssertEqual(IdleFee.fee(minutes: 1_000), 40)
        XCTAssertEqual(IdleFee.fee(minutes: 100_000), 40)
    }

    func testCapIsReachedExactlyWhereTheTiersSayItIs() {
        // 6.00 at minute 30, then 0.50 per minute: 40.00 at minute 98.
        XCTAssertEqual(IdleFee.fee(minutes: 98), 40, accuracy: 1e-9)
        XCTAssertLessThan(IdleFee.fee(minutes: 97), 40)
        XCTAssertEqual(IdleFee.fee(minutes: 99), 40, accuracy: 1e-9)
    }

    func testFeeNeverDecreasesWithTime() {
        var previous = 0.0
        for minute in stride(from: 0.0, through: 150, by: 0.5) {
            let fee = IdleFee.fee(minutes: minute)
            XCTAssertGreaterThanOrEqual(fee, previous, "fee dropped at minute \(minute)")
            previous = fee
        }
    }

    // MARK: Current rate

    func testCurrentRateFollowsTheTiers() {
        XCTAssertEqual(IdleFee.currentRate(minutes: 0), 0.10)
        XCTAssertEqual(IdleFee.currentRate(minutes: 9.99), 0.10)
        XCTAssertEqual(IdleFee.currentRate(minutes: 10), 0.25)
        XCTAssertEqual(IdleFee.currentRate(minutes: 29.99), 0.25)
        XCTAssertEqual(IdleFee.currentRate(minutes: 30), 0.50)
        XCTAssertEqual(IdleFee.currentRate(minutes: 500), 0.50)
    }
}
