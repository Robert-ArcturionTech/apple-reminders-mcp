import XCTest
@testable import RemindersCore

final class DateParsingTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let ny = TimeZone(identifier: "America/New_York")!

    func testParsesZonedIso8601() {
        let d = DateParsing.parse("2026-05-01T09:00:00Z", timeZone: ny)
        XCTAssertEqual(d?.date.timeIntervalSince1970, 1_777_626_000)
        XCTAssertEqual(d?.hasTime, true)
    }

    func testParsesOffsetIso8601() {
        let z = DateParsing.parse("2026-05-01T09:00:00Z")
        let off = DateParsing.parse("2026-05-01T05:00:00-04:00")
        XCTAssertEqual(z?.date, off?.date)
    }

    func testParsesFractionalSeconds() {
        XCTAssertNotNil(DateParsing.parse("2026-05-01T09:00:00.250Z"))
    }

    func testZonelessTimestampUsesSuppliedTimeZone() {
        let inUTC = DateParsing.parse("2026-05-01T09:00:00", timeZone: utc)!
        let inNY = DateParsing.parse("2026-05-01T09:00:00", timeZone: ny)!
        // 09:00 in New York (EDT, UTC-4) is 4 hours after 09:00 UTC.
        XCTAssertEqual(inNY.date.timeIntervalSince(inUTC.date), 4 * 3600)
        XCTAssertTrue(inNY.hasTime)
    }

    func testTimestampWithoutSeconds() {
        let a = DateParsing.parse("2026-05-01T09:30", timeZone: utc)
        let b = DateParsing.parse("2026-05-01T09:30:00", timeZone: utc)
        XCTAssertEqual(a?.date, b?.date)
    }

    func testBareDateIsAllDay() {
        let d = DateParsing.parse("2026-05-01", timeZone: utc)
        XCTAssertEqual(d?.hasTime, false)
        XCTAssertEqual(d?.date.timeIntervalSince1970, 1_777_593_600)
    }

    func testTrimsWhitespace() {
        XCTAssertNotNil(DateParsing.parse("  2026-05-01  "))
    }

    func testRejectsGarbage() {
        for bad in ["", "   ", "tomorrow", "05/01/2026", "2026-13-40", "2026-05-01T25:00:00", "not a date"] {
            XCTAssertNil(DateParsing.parse(bad, timeZone: utc), "should reject '\(bad)'")
        }
    }

    func testIsoRoundTripString() {
        let d = Date(timeIntervalSince1970: 1_777_626_000)
        XCTAssertEqual(DateParsing.iso8601String(d), "2026-05-01T09:00:00Z")
    }
}
