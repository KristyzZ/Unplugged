import XCTest
@testable import Unplugged

final class ReportTests: XCTestCase {
    // MARK: Licence plates

    func testStandardLithuanianPlate() {
        XCTAssertEqual(PlateReader.match("abc123")?.plate, "ABC 123")
        XCTAssertEqual(PlateReader.match("ABC 123")?.lithuanian, true)
    }

    func testLookAlikeCharactersAreFixedByPosition() {
        // 0 read as a letter → O; O and I read as digits → 0 and 1.
        XCTAssertEqual(PlateReader.match("K0M 4I0")?.plate, "KOM 410")
    }

    func testCountryBandIsDropped() {
        XCTAssertEqual(PlateReader.match("LT KLM482")?.plate, "KLM 482")
    }

    func testTaxiPlate() {
        XCTAssertEqual(PlateReader.match("T12345")?.plate, "T 12345")
    }

    func testOtherPlateLikeTextIsKeptButNotLithuanian() {
        let match = PlateReader.match("B AB 1234")
        XCTAssertEqual(match?.plate, "BAB1234")
        XCTAssertEqual(match?.lithuanian, false)
    }

    func testTextThatIsNotAPlate() {
        XCTAssertNil(PlateReader.match("PARKING"))
        XCTAssertNil(PlateReader.match("12"))
    }

    func testFormatPlate() {
        XCTAssertEqual(Reports.formatPlate("klm482"), "KLM 482")
        XCTAssertEqual(Reports.normalizePlate("klm 482"), "KLM482")
    }

    // MARK: Confidence

    func testChargerDataAloneConfirmsABlockedSpot() {
        // Photo with the plate read on the phone, and the spot sensor says
        // occupied with no session: confirmed without anyone else.
        XCTAssertEqual(Reports.confirmationsNeeded(hasPhoto: true, plateFromPhoto: true, evidence: .occupiedNoSession), 0)
    }

    func testWeakerEvidenceNeedsOtherDrivers() {
        let needed = Reports.confirmationsNeeded(hasPhoto: false, plateFromPhoto: false, evidence: .noSession)
        XCTAssertNotNil(needed)
        XCTAssertGreaterThan(needed!, 0)
    }

    func testAChargingCarContradictsTheReport() {
        let charging = Reports.confidence(hasPhoto: true, plateFromPhoto: true, evidence: .charging, confirmations: 0)
        let unknown = Reports.confidence(hasPhoto: true, plateFromPhoto: true, evidence: .unknown, confirmations: 0)
        XCTAssertLessThan(charging, unknown)
        XCTAssertLessThan(charging, Reports.confirmThreshold)
    }

    func testEvidenceFromConnectorStatus() {
        XCTAssertEqual(StationEvidence(.blocked), .occupiedNoSession)
        XCTAssertEqual(StationEvidence(.idle), .finishedParked)
        XCTAssertEqual(StationEvidence(.charging), .charging)
        XCTAssertEqual(StationEvidence(.reserved), .noSession)
    }
}
