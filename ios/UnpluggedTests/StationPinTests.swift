import XCTest
@testable import Unplugged

/// The map pin shows free connectors, and "?" rather than 0 when nothing is known.
final class StationPinTests: XCTestCase {
    func testShowsFreeCount() {
        XCTAssertEqual(StationPin.label(free: 3, availability: .free), "3")
        XCTAssertEqual(StationPin.label(free: 1, availability: .limited), "1")
    }

    func testFullAndOfflineShowZero() {
        XCTAssertEqual(StationPin.label(free: 0, availability: .full), "0")
        XCTAssertEqual(StationPin.label(free: 0, availability: .offline), "0")
    }

    func testUnknownShowsQuestionMark() {
        XCTAssertEqual(StationPin.label(free: 0, availability: .unknown), "?")
    }
}
