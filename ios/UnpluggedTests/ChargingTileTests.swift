import XCTest
@testable import Unplugged

/// The charging tile's decision: always visible while a session exists, except on the Charging tab.
final class ChargingTileTests: XCTestCase {
    func testSessionTileShowsOnEveryTabExceptCharging() {
        for tab in AppTab.allCases where tab != .charging {
            XCTAssertEqual(ChargingTile.kind(hasSession: true, hasHold: false, tab: tab), .session, "\(tab)")
            XCTAssertEqual(ChargingTile.kind(hasSession: true, hasHold: true, tab: tab), .session, "\(tab)")
        }
    }

    func testNothingOnChargingTabDuringSession() {
        XCTAssertNil(ChargingTile.kind(hasSession: true, hasHold: false, tab: .charging))
        XCTAssertNil(ChargingTile.kind(hasSession: true, hasHold: true, tab: .charging))
    }

    func testHeldSpotShowsWithoutSessionOnEveryTab() {
        for tab in AppTab.allCases {
            XCTAssertEqual(ChargingTile.kind(hasSession: false, hasHold: true, tab: tab), .hold, "\(tab)")
        }
    }

    func testNothingWithoutSessionOrHold() {
        for tab in AppTab.allCases {
            XCTAssertNil(ChargingTile.kind(hasSession: false, hasHold: false, tab: tab))
        }
    }
}
