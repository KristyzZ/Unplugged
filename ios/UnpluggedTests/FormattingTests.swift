import XCTest
@testable import Unplugged

/// Numbers people read follow the app language: comma in Lithuanian, dot in English.
final class FormattingTests: XCTestCase {
    private let en = Lang.en.locale
    private let lt = Lang.lt.locale

    func testDecimalSeparatorFollowsTheLanguage() {
        XCTAssertEqual(Fmt.number(38.46, decimals: 1, locale: en), "38.5")
        XCTAssertEqual(Fmt.number(38.46, decimals: 1, locale: lt), "38,5")
        XCTAssertEqual(Fmt.number(0.4, decimals: 2, locale: lt), "0,40")
    }

    func testUnitsAndCurrencyKeepTheirShape() {
        XCTAssertEqual(Fmt.kwh(48.5, locale: en), "48.5 kWh")
        XCTAssertEqual(Fmt.kwh(48.5, locale: lt), "48,5 kWh")
        XCTAssertEqual(Fmt.euros(0.43, locale: en), "0.43 €")
        XCTAssertEqual(Fmt.euros(0.43, locale: lt), "0,43 €")
        XCTAssertEqual(Fmt.eurPerMin(0.25, locale: lt), "0,25 €/min")
        XCTAssertEqual(Fmt.price(0.5, locale: lt), "0,50 €/kWh")
        XCTAssertEqual(Fmt.price(0.5, locale: en), "0.50 €/kWh")
    }

    func testLargeNumbersAreNotGrouped() {
        XCTAssertEqual(Fmt.number(1234.5, decimals: 1, locale: en), "1234.5")
        XCTAssertEqual(Fmt.number(1234.5, decimals: 1, locale: lt), "1234,5")
    }

    func testRoundingIsToTheRequestedDecimals() {
        XCTAssertEqual(Fmt.number(2.346, decimals: 2, locale: en), "2.35")
        XCTAssertEqual(Fmt.number(2.344, decimals: 2, locale: en), "2.34")
        XCTAssertEqual(Fmt.number(19, decimals: 0, locale: lt), "19")
    }
}
