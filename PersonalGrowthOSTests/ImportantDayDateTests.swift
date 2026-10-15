import XCTest
@testable import PersonalGrowthOS

final class ImportantDayDateTests: XCTestCase {
    private func civil(_ year: Int, _ month: Int, _ day: Int) -> ImportantCivilDay { .init(year: year, month: month, day: day) }
    private func annual(_ month: Int, _ day: Int, year: Int? = nil) -> ImportantDayDateRule {
        ImportantDayDateRule(preset: .anniversary, year: year, month: month, day: day)
    }
    func testCivilDatesRejectOverflowAndCountNaturalDaysAcrossDST() throws {
        XCTAssertNil(civil(2025, 2, 29).date); XCTAssertNil(civil(2024, 13, 1).date)
        XCTAssertEqual(civil(2024, 2, 28).distance(to: civil(2024, 3, 1)), 2)
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        for (a, b, hours) in [(civil(2026, 3, 8), civil(2026, 3, 9), 23), (civil(2026, 11, 1), civil(2026, 11, 2), 25)] {
            let first = try XCTUnwrap(a.instant(minutes: 0, timeZone: zone))
            let second = try XCTUnwrap(b.instant(minutes: 0, timeZone: zone))
            XCTAssertEqual(second.timeIntervalSince(first), Double(hours * 3600))
            XCTAssertEqual(a.distance(to: b), 1)
        }
    }
    func testOneTimeFutureTodayAndPastRetainsIntention() throws {
        let rule = ImportantDayDateRule(year: 2026, month: 12, day: 31)
        XCTAssertEqual(try ImportantDayDateEngine.evaluate(rule, today: civil(2026, 12, 30)).signedDays, 1)
        XCTAssertEqual(try ImportantDayDateEngine.evaluate(rule, today: civil(2026, 12, 31)).signedDays, 0)
        let past = try ImportantDayDateEngine.evaluate(rule, today: civil(2027, 1, 1))
        XCTAssertEqual(past.signedDays, -1); XCTAssertNil(past.next)
        XCTAssertEqual(rule.preset, .anticipated)
        var beginning = rule; beginning.preset = .beginning; beginning.perspective = .elapsed
        XCTAssertEqual(try ImportantDayDateEngine.evaluate(beginning, today: civil(2027, 1, 1)).signedDays, -1)
    }
    func testAnniversaryRemainsTodayAndUnknownYearHasNoInventedFacts() throws {
        let rule = annual(6, 20)
        let today = try ImportantDayDateEngine.evaluate(rule, today: civil(2026, 6, 20))
        XCTAssertEqual(today.signedDays, 0); XCTAssertNil(today.original); XCTAssertNil(today.anniversaryNumber)
        XCTAssertEqual(try ImportantDayDateEngine.evaluate(rule, today: civil(2026, 6, 21)).next, civil(2027, 6, 20))
        var invalid = rule; invalid.perspective = .elapsed
        XCTAssertThrowsError(try invalid.validate())
        let known = try ImportantDayDateEngine.evaluate(annual(6, 20, year: 2000), today: civil(2026, 6, 20))
        XCTAssertEqual(known.anniversaryNumber, 26)
    }
    func testLeapDayRequiresExplicitPolicyAndAllThreePoliciesWork() throws {
        var rule = annual(2, 29, year: 2000)
        XCTAssertThrowsError(try rule.validate())
        for (policy, expected) in [(ImportantLeapDayRule.february28, civil(2025, 2, 28)), (.march1, civil(2025, 3, 1)), (.leapYearsOnly, civil(2028, 2, 29))] {
            rule.leapDayRule = policy
            XCTAssertEqual(try ImportantDayDateEngine.evaluate(rule, today: civil(2025, 1, 1)).next, expected)
        }
    }
    // Independent golden values: Hong Kong Observatory's published 2023/2024 conversion tables.
    // https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2023e.pdf
    // https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2024e.pdf
    func testLunarNewYearAndLeapMonthAgainstIndependentHKOExamples() throws {
        var rule = annual(1, 1); rule.calendar = .chinese
        XCTAssertEqual(try ImportantDayDateEngine.occurrence(rule, in: 2023), civil(2023, 1, 22))
        XCTAssertEqual(try ImportantDayDateEngine.occurrence(rule, in: 2024), civil(2024, 2, 10))
        rule.month = 2; rule.isLeapMonth = true
        XCTAssertThrowsError(try rule.validate())
        rule.leapMonthRule = .regularFallback
        XCTAssertEqual(try ImportantDayDateEngine.occurrence(rule, in: 2023), civil(2023, 3, 22))
        XCTAssertEqual(try ImportantDayDateEngine.occurrence(rule, in: 2024), civil(2024, 3, 10))
        XCTAssertEqual(try ImportantDayDateEngine.evaluate(rule, today: civil(2023, 3, 23)).next, civil(2024, 3, 10))
        rule.leapMonthRule = .leapYearsOnly
        XCTAssertNil(try ImportantDayDateEngine.occurrence(rule, in: 2024))
    }
    func testLunarShortMonthDoesNotOverflowAndOriginalDateIsNotFabricated() throws {
        var rule = annual(1, 30); rule.calendar = .chinese
        XCTAssertThrowsError(try rule.validate())
        rule.shortMonthRule = .lastDay
        XCTAssertEqual(try ImportantDayDateEngine.occurrence(rule, in: 2024), civil(2024, 3, 9)) // lunar 1/29
        rule.shortMonthRule = .skip
        XCTAssertNil(try ImportantDayDateEngine.occurrence(rule, in: 2024))
        rule.year = 2024
        XCTAssertThrowsError(try rule.validate()) // 2024 lunar 1/30 never happened
        rule.year = 2025 // HKO: 2025-02-27 is lunar 1/30
        XCTAssertEqual(try ImportantDayDateEngine.original(rule, in: 2025), civil(2025, 2, 27))
        XCTAssertNoThrow(try rule.validate())
    }
    func testLunarYearCrossingAndTravelNeverRewriteOriginal() throws {
        var rule = annual(12, 30, year: 2023); rule.calendar = .chinese; rule.shortMonthRule = .lastDay
        XCTAssertEqual(try ImportantDayDateEngine.original(rule, in: 2023), civil(2024, 2, 9))
        let before = rule
        let instant = try XCTUnwrap(civil(2024, 2, 9).instant(minutes: 23 * 60, timeZone: .init(identifier: "America/Los_Angeles")!))
        _ = try ImportantDayDateEngine.evaluate(rule, today: .init(instant, timeZone: .init(identifier: "Asia/Shanghai")!))
        _ = try ImportantDayDateEngine.evaluate(rule, today: .init(instant, timeZone: .init(identifier: "America/Los_Angeles")!))
        XCTAssertEqual(rule, before)
    }
    func testSupportedRangeBoundariesAndNoFutureOccurrence() throws {
        for year in [1901, 2100] {
            var rule = annual(1, 1); rule.calendar = .chinese
            XCTAssertNotNil(try ImportantDayDateEngine.occurrence(rule, in: year))
        }
        XCTAssertThrowsError(try ImportantDayDateEngine.evaluate(annual(1, 1), today: civil(2100, 12, 31)))
        XCTAssertThrowsError(try ImportantDayDateEngine.evaluate(annual(1, 1), today: civil(1900, 1, 1)))
        var invalid = annual(1, 1, year: 1900)
        XCTAssertThrowsError(try invalid.validate())
        invalid.year = nil; invalid.preset = .beginning
        XCTAssertThrowsError(try invalid.validate())
    }
    func testTodayPriorityVisibilityLimitsAndStableTies() {
        let today = civil(2026, 6, 20)
        let old = UUID(), now = UUID(), soon = UUID(), hidden = UUID(), archived = UUID(), outside = UUID()
        let candidates = [
            ImportantDayTodayCandidate(id: old, rule: .init(preset: .beginning, year: 2000, month: 1, day: 1), policy: .always, archived: false, stableOrder: 0),
            .init(id: now, rule: annual(6, 20), policy: .automatic, archived: false, stableOrder: 9),
            .init(id: soon, rule: annual(6, 27), policy: .automatic, archived: false, stableOrder: 1),
            .init(id: hidden, rule: annual(6, 20), policy: .hidden, archived: false, stableOrder: 0),
            .init(id: archived, rule: annual(6, 20), policy: .always, archived: true, stableOrder: 0),
            .init(id: outside, rule: annual(6, 28), policy: .automatic, archived: false, stableOrder: 0)
        ]
        XCTAssertEqual(ImportantDayTodaySelector.select(candidates, today: today), [now, old])
        XCTAssertEqual(ImportantDayTodaySelector.select(Array(candidates.dropFirst()), today: today), [now, soon])
        XCTAssertEqual(ImportantDayTodaySelector.select([candidates[0]].map { .init(id: $0.id, rule: $0.rule, policy: .automatic, archived: false, stableOrder: 0) }, today: today), [])
        XCTAssertEqual(ImportantDayTodaySelector.select(candidates.reversed(), today: today), [now, old])
    }
    func testEverySupportedLunarYearHasOneRegularNewYearAndRoundTrips() throws {
        var rule = annual(1, 1); rule.calendar = .chinese
        for year in ImportantDayDateEngine.years {
            let result = try XCTUnwrap(ImportantDayDateEngine.occurrence(rule, in: year))
            XCTAssertEqual(result.year, year)
            XCTAssertTrue([1, 2].contains(result.month))
            var c = Calendar(identifier: .chinese); c.timeZone = ImportantDayDateEngine.lunarTimeZone
            let instant = try XCTUnwrap(result.instant(minutes: 12 * 60, timeZone: c.timeZone))
            XCTAssertEqual(c.component(.month, from: instant), 1)
            XCTAssertEqual(c.component(.day, from: instant), 1)
            XCTAssertFalse(c.dateComponents([.isLeapMonth], from: instant).isLeapMonth == true)
        }
    }
}
