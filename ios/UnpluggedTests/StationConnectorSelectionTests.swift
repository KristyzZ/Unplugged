import XCTest
@testable import Unplugged

final class StationConnectorSelectionTests: XCTestCase {
    func testSelectRetapAndSwitch() {
        let ids = ["first", "second"]
        let first = StationConnectorSelection.tapping("first", currentID: nil, selectableIDs: ids)
        XCTAssertEqual(first, "first")
        XCTAssertNil(StationConnectorSelection.tapping("first", currentID: first, selectableIDs: ids))
        XCTAssertEqual(StationConnectorSelection.tapping("second", currentID: first, selectableIDs: ids), "second")
    }

    func testRefreshInvalidatesSelectionAndDoesNotReopenItWhenAvailableAgain() {
        var connector = Fixtures.connector(id: "selected")
        let vehicle = Fixtures.vehicle()
        let before = StationConnectorSelection.selectableIDs(connectors: [connector], vehicle: vehicle, heldID: nil, now: Fixtures.t0)
        let selected = StationConnectorSelection.tapping(connector.id, currentID: nil, selectableIDs: before)
        connector.status = .charging
        let after = StationConnectorSelection.selectableIDs(connectors: [connector], vehicle: vehicle, heldID: nil, now: Fixtures.at(minutes: 1.0 / 3))
        let cleared = StationConnectorSelection.visibleID(selected, selectableIDs: after, busy: false)
        XCTAssertNil(cleared)
        XCTAssertNil(StationConnectorSelection.visibleID(cleared, selectableIDs: before, busy: false))
    }

    func testOwnHeldConnectorIsSelectableAndPreselectionShowsOnlyItsCard() {
        let connectors = [Fixtures.connector(status: .reserved, id: "mine"), Fixtures.connector(status: .reserved, id: "other")]
        let ids = StationConnectorSelection.selectableIDs(connectors: connectors, vehicle: Fixtures.vehicle(), heldID: "mine", now: Fixtures.t0)
        XCTAssertEqual(ids, ["mine"])
        XCTAssertEqual(StationConnectorSelection.visibleID("mine", selectableIDs: ids, busy: false), "mine")
        XCTAssertNil(StationConnectorSelection.visibleID("other", selectableIDs: ids, busy: false))
        XCTAssertEqual(StationConnectorSelection.tapping("other", currentID: "mine", selectableIDs: ids), "mine")
    }

    func testHeldConnectorMustStillBeCompatibleAndWorking() {
        let connectors = [Fixtures.connector(status: .offline, id: "offline"), Fixtures.connector(.chademo, status: .reserved, id: "incompatible")]
        for id in ["offline", "incompatible"] {
            XCTAssertTrue(StationConnectorSelection.selectableIDs(connectors: connectors, vehicle: Fixtures.vehicle(), heldID: id, now: Fixtures.t0).isEmpty)
        }
    }

    func testUnknownStaleBusyAndRemovedConnectorsDoNotShowCards() {
        let connectors = [Fixtures.connector(status: .unknown, id: "unknown"), Fixtures.connector(id: "stale", ageMinutes: 60), Fixtures.connector(status: .blocked, id: "blocked")]
        let ids = StationConnectorSelection.selectableIDs(connectors: connectors, vehicle: Fixtures.vehicle(), heldID: nil, now: Fixtures.t0)
        XCTAssertTrue(ids.isEmpty)
        XCTAssertNil(StationConnectorSelection.visibleID("removed", selectableIDs: ids, busy: false))
        XCTAssertNil(StationConnectorSelection.visibleID("available", selectableIDs: ["available"], busy: true))
    }

    func testUnselectableTapCannotCreateSelection() {
        XCTAssertNil(StationConnectorSelection.tapping("other", currentID: nil, selectableIDs: ["available"]))
    }
}
