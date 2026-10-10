import XCTest
@testable import Unplugged

/// An estimate must never read as a promise (SPEC: availability is shown as an estimate).
final class EstimateFormatTests: XCTestCase {
    func testCertaintyIsNeverShown() {
        XCTAssertEqual(Fmt.estimatePct(1), "≈ 99 %")
        XCTAssertEqual(Fmt.estimatePct(0.9999), "≈ 99 %")
        XCTAssertEqual(Fmt.estimatePct(0), "≈ 1 %")
        XCTAssertEqual(Fmt.estimatePct(-0.5), "≈ 1 %")
        XCTAssertEqual(Fmt.estimatePct(7), "≈ 99 %")
    }

    func testOrdinaryValuesAreRoundedAndMarkedApproximate() {
        XCTAssertEqual(Fmt.estimatePct(0.5), "≈ 50 %")
        XCTAssertEqual(Fmt.estimatePct(0.123), "≈ 12 %")
        XCTAssertEqual(Fmt.estimatePct(0.987), "≈ 99 %")
    }

    func testPlainPercentIsUnchangedForMeasuredValues() {
        XCTAssertEqual(Fmt.pct(1), "100 %")
        XCTAssertEqual(Fmt.pct(0.39), "39 %")
    }
}
