import Foundation
import SwiftData
import XCTest
@testable import PersonalGrowthOS

@MainActor final class SleepFoundationTests: XCTestCase {
    let zone = TimeZone(identifier: "Asia/Shanghai")!
    func instant(_ day: String, _ minute: Int = 720) -> Date { ImportantCivilDay(identifier: day)!.instant(minutes: minute, timeZone: zone)! }
    func draft(_ day: String = "2026-10-15") -> SleepDraft {
        var draft = SleepDraft(day: day, zone: zone)
        draft.values.bedtime = .init(day: ImportantCivilDay(identifier: day)!.adding(days: -1)!.identifier, minute: 1380, precision: 30)
        draft.values.wake = .init(day: day, minute: 420, precision: 15); draft.values.feeling = 4
        return draft
    }
    func records(_ container: ModelContainer) throws -> [SleepRecord] { try ModelContext(container).fetch(FetchDescriptor<SleepRecord>()) }
    func testIntervalsPreserveOriginalBoundsAndDoNotInventMidpointSleep() throws {
        let d = draft(); let range = try XCTUnwrap(SleepRules.interval(d.values, zone: zone))
        XCTAssertEqual(range.lowerBound, 7.5 * 3600); XCTAssertEqual(range.upperBound, 8.25 * 3600)
        for precision in [0, 30, 60] {
            var d = draft(); d.values.bedtime!.precision = precision
            try SleepRules.validate(day: d.wakeDay, zoneID: d.timeZoneID, values: d.values, now: instant(d.wakeDay))
            XCTAssertEqual(try JSONDecoder().decode(SleepValues.self, from: JSONEncoder().encode(d.values)), d.values)
        }
    }
    func testMidnightMonthYearLateAndDaytimeRemainOneWakeDay() throws {
        for day in ["2026-01-01", "2026-03-01", "2026-10-15"] {
            var d = draft(day); d.values.bedtime!.minute = 1410; d.values.bedtime!.precision = 60
            XCTAssertEqual(SleepRules.interval(d.values, zone: zone)?.lowerBound, 6.5 * 3600)
            d.values.bedtime = .init(day: day, minute: 30, precision: 30)
            d.values.wake = .init(day: day, minute: 900, precision: 15)
            try SleepRules.validate(day: day, zoneID: zone.identifier, values: d.values, now: instant(day, 1000))
            d.values.bedtime = .init(day: day, minute: 720, precision: 60)
            XCTAssertNotNil(SleepRules.interval(d.values, zone: zone))
        }
    }
    func testFutureBucketsOverlapMissingAndInverseHaveHonestResults() throws {
        var d = draft(); d.values.wake = .init(day: d.wakeDay, minute: 420, precision: 15)
        XCTAssertNoThrow(try SleepRules.validate(day: d.wakeDay, zoneID: zone.identifier, values: d.values, now: instant(d.wakeDay, 425)))
        XCTAssertThrowsError(try SleepRules.validate(day: d.wakeDay, zoneID: zone.identifier, values: d.values, now: instant(d.wakeDay, 400)))
        d.values.bedtime = .init(day: d.wakeDay, minute: 415, precision: 30)
        XCTAssertNil(SleepRules.interval(d.values, zone: zone))
        XCTAssertNoThrow(try SleepRules.validate(day: d.wakeDay, zoneID: zone.identifier, values: d.values))
        d.values.bedtime!.minute = 600
        XCTAssertThrowsError(try SleepRules.validate(day: d.wakeDay, zoneID: zone.identifier, values: d.values))
        d.values.bedtime = nil; XCTAssertNil(SleepRules.interval(d.values, zone: zone))
        d.values.wake!.precision = -1; XCTAssertThrowsError(try d.values.wake!.bounds(zone: zone))
    }
    func testPartialNoteOnlyEmptyUnknownAndServiceFailureRetry() throws {
        let c = try PersistenceContainerFactory.makeInMemory()
        var d = SleepDraft(day: "2026-10-15", zone: zone)
        let service = SleepService(context: c.mainContext, now: { self.instant("2026-10-15") })
        XCTAssertThrowsError(try service.save(d)); XCTAssertTrue(try records(c).isEmpty)
        d.values.note = "Synthetic note only"
        XCTAssertThrowsError(try SleepService(context: c.mainContext, now: { self.instant("2026-10-15") }, commit: { _ in throw CocoaError(.fileWriteOutOfSpace) }).save(d))
        XCTAssertTrue(try records(c).isEmpty); XCTAssertEqual(d.values.note, "Synthetic note only")
        _ = try service.save(d); XCTAssertEqual(try records(c).count, 1)
        XCTAssertThrowsError(try service.save(d)); XCTAssertEqual(try records(c).count, 1)
    }
    func testTwoContextsStaleRevisionAndDateCollisionPreserveBothDrafts() throws {
        let c = try PersistenceContainerFactory.makeInMemory()
        let service = SleepService(context: c.mainContext, now: { self.instant("2026-10-15") })
        _ = try service.save(draft())
        var a = try SleepDraft(XCTUnwrap(records(c).first)), b = a
        a.values.note = "First editor"; b.values.note = "Second editor"
        _ = try service.save(a)
        XCTAssertThrowsError(try SleepService(context: ModelContext(c), now: { self.instant("2026-10-15") }).save(b))
        _ = try service.save(draft("2026-10-14"))
        var collision = try SleepDraft(XCTUnwrap(records(c).first(where: { $0.wakeDay == "2026-10-14" })))
        collision.wakeDay = "2026-10-15"; collision.values = draft().values
        XCTAssertThrowsError(try service.save(collision)); XCTAssertEqual(try records(c).count, 2)
        XCTAssertEqual(b.values.note, "Second editor")
    }
    func testFieldTimingLateCorrectionsNoteNoopClearRefillAndRollback() throws {
        let c = try PersistenceContainerFactory.makeInMemory(); var clock = instant("2026-10-15")
        let service = SleepService(context: c.mainContext, now: { clock })
        var d = SleepDraft(day: "2026-10-15", zone: zone); d.values.wake = draft().values.wake
        _ = try service.save(d)
        let first = try XCTUnwrap(records(c).first), firstRevision = first.revision
        _ = try service.save(SleepDraft(first)); XCTAssertEqual(try records(c).first?.revision, firstRevision)
        clock = instant("2026-10-18")
        var edit = try SleepDraft(XCTUnwrap(records(c).first)); edit.values.bedtime = draft().values.bedtime; edit.values.feeling = 2
        _ = try service.save(edit)
        var saved = try XCTUnwrap(records(c).first), values = try saved.values()
        XCTAssertEqual(values.wakeFilledAt, instant("2026-10-15")); XCTAssertEqual(values.bedtimeFilledAt, clock)
        XCTAssertEqual(SleepRules.timing(values.bedtimeFilledAt, day: saved.wakeDay, zone: zone, now: clock), .recalled)
        edit = try SleepDraft(saved); edit.values.note = "Only a note"; _ = try service.save(edit)
        saved = try XCTUnwrap(records(c).first); XCTAssertEqual(try saved.values().wakeFilledAt, values.wakeFilledAt)
        edit = try SleepDraft(saved); edit.values.wake = nil; _ = try service.save(edit)
        saved = try XCTUnwrap(records(c).first); XCTAssertNil(try saved.values().wakeFilledAt)
        edit = try SleepDraft(saved); edit.values.wake = draft().values.wake; _ = try service.save(edit)
        saved = try XCTUnwrap(records(c).first); XCTAssertEqual(try saved.values().wakeFilledAt, clock)
        clock = instant("2026-10-16"); edit = try SleepDraft(saved); edit.values.feeling = 5; _ = try service.save(edit)
        values = try XCTUnwrap(records(c).first).values(); XCTAssertNil(values.feelingFilledAt)
    }
    func testGoalVersionsBoundaryUncertaintyDisableAndNoRetroactiveRewrite() throws {
        let c = try PersistenceContainerFactory.makeInMemory(); var clock = instant("2026-10-15")
        let service = SleepService(context: c.mainContext, now: { clock })
        try service.setGoal(cutoffMinute: 1410, timeZone: zone)
        var goals = try ModelContext(c).fetch(FetchDescriptor<SleepGoalRule>())
        var d = draft(); d.values.bedtimeFilledAt = clock
        XCTAssertEqual(SleepRules.goal(day: d.wakeDay, zone: zone, values: d.values, rules: goals, now: clock), .met)
        d.values.bedtime!.precision = 60
        XCTAssertEqual(SleepRules.goal(day: d.wakeDay, zone: zone, values: d.values, rules: goals, now: clock), .uncertain)
        d.values.bedtime!.minute = 1411
        XCTAssertEqual(SleepRules.goal(day: d.wakeDay, zone: zone, values: d.values, rules: goals, now: clock), .missed)
        try service.setGoal(cutoffMinute: 60, timeZone: zone); try service.setGoal(cutoffMinute: nil, timeZone: zone)
        goals = try ModelContext(c).fetch(FetchDescriptor<SleepGoalRule>())
        XCTAssertEqual(goals.count, 2); XCTAssertEqual(goals.first(where: { $0.effectiveDay == d.wakeDay })?.cutoffMinute, 1410)
        XCTAssertNil(goals.first(where: { $0.effectiveDay == "2026-10-16" })?.cutoffMinute)
        clock = instant("2026-10-16")
        XCTAssertEqual(SleepRules.goal(day: "2026-10-16", zone: zone, values: d.values, rules: goals, now: clock), .noGoal)
    }
    func testDSTGapRepeatExplicitOffsetAnd23or25HourCivilDays() throws {
        let ny = TimeZone(identifier: "America/New_York")!
        XCTAssertThrowsError(try SleepRange(day: "2026-03-08", minute: 150, precision: 0).bounds(zone: ny))
        XCTAssertThrowsError(try SleepRange(day: "2026-11-01", minute: 90, precision: 0).bounds(zone: ny))
        let early = try SleepRange(day: "2026-11-01", minute: 90, precision: 0, utcOffset: -14400).bounds(zone: ny)
        let late = try SleepRange(day: "2026-11-01", minute: 90, precision: 0, utcOffset: -18000).bounds(zone: ny)
        XCTAssertEqual(late.lowerBound.timeIntervalSince(early.lowerBound), 3600)
        for (day, hours) in [("2026-03-08", 23.0), ("2026-11-01", 25.0)] {
            let date = ImportantCivilDay(identifier: day)!, prev = date.adding(days: -1)!
            let a = try SleepRange(day: prev.identifier, minute: 1380, precision: 0).bounds(zone: ny).lowerBound
            let b = try SleepRange(day: day, minute: 1380, precision: 0).bounds(zone: ny).lowerBound
            XCTAssertEqual(b.timeIntervalSince(a), hours * 3600)
            XCTAssertEqual(prev.distance(to: date), 1)
        }
    }
    func testReviewIndependentDenominatorsCivilWindowAndCrossNightAxis() throws {
        let c = try PersistenceContainerFactory.makeInMemory(); var clock = instant("2026-10-15")
        let service = SleepService(context: c.mainContext, now: { clock })
        _ = try service.save(draft())
        clock = instant("2026-10-18")
        var edit = try SleepDraft(XCTUnwrap(records(c).first)); edit.values.feeling = 1; _ = try service.save(edit)
        var note = SleepDraft(day: "2026-10-18", zone: zone); note.values.note = "Partial"; _ = try service.save(note)
        let data = try records(c).map(SleepRecordTransfer.init)
        let review = SleepReviewSnapshot(records: data, goals: [], windowDays: 7, today: ImportantCivilDay(identifier: "2026-10-18")!, now: clock)
        XCTAssertEqual(review.recordedDays, 2); XCTAssertEqual(review.wakeCount, 1); XCTAssertEqual(review.bedtimeCount, 1)
        XCTAssertEqual(review.intervalCount, 1); XCTAssertEqual(review.feelingCount, 0); XCTAssertEqual(review.count(timing: .recalled), 1)
        let night = try XCTUnwrap(review.nights.first(where: { $0.record.wakeDay == "2026-10-15" }))
        XCTAssertEqual(night.axis(draft().values.bedtime!), -60 ... -30)
        XCTAssertEqual(SleepReviewSnapshot(records: [], goals: [], windowDays: 30, today: .init(year: 2026, month: 10, day: 18), now: clock).recordedDays, 0)
    }
    func testReviewAxisIncludesLateWakeBucketWithoutClippingItsNextDayEndpoint() throws {
        let c = try PersistenceContainerFactory.makeInMemory(), clock = instant("2026-10-15")
        let service = SleepService(context: c.mainContext, now: { clock })
        var late = draft("2026-10-14")
        late.values.bedtime = .init(day: late.wakeDay, minute: 1200, precision: 30)
        late.values.wake = .init(day: late.wakeDay, minute: 1410, precision: 60)
        _ = try service.save(late)
        let review = SleepReviewSnapshot(records: try records(c).map(SleepRecordTransfer.init), goals: [], windowDays: 7, today: ImportantCivilDay(identifier: "2026-10-15")!, now: clock)
        XCTAssertEqual(review.wakeCount, 1)
        XCTAssertEqual(review.axisHourDomain, -24...24.5)
        XCTAssertEqual(SleepFormatting.axisHour(-24), String(localized: "Previous day") + " 00:00")
        XCTAssertEqual(SleepFormatting.axisHour(0), String(localized: "Wake day") + " 00:00")
        XCTAssertEqual(SleepFormatting.axisHour(24), String(localized: "Next day") + " 00:00")
        XCTAssertEqual(review.nights.first?.axis(late.values.wake!), 1410...1470)
        let empty = SleepReviewSnapshot(records: [], goals: [], windowDays: 7, today: ImportantCivilDay(identifier: "2026-10-15")!, now: clock)
        XCTAssertEqual(empty.axisHourDomain, -24...24)
    }
    func testDiskSaveReopenEditDeleteAndTimezoneTravelNeverMovesWakeDay() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("sleep.sqlite")
        try autoreleasepool {
            let c = try PersistenceContainerFactory.makeOnDisk(at: url)
            _ = try SleepService(context: c.mainContext, now: { self.instant("2026-10-15") }).save(draft())
        }
        let c = try PersistenceContainerFactory.makeOnDisk(at: url), record = try XCTUnwrap(records(c).first)
        XCTAssertEqual(record.wakeDay, "2026-10-15"); XCTAssertEqual(record.timeZoneID, zone.identifier)
        XCTAssertEqual(try record.values().bedtime, draft().values.bedtime)
        try SleepIntegrity.validate(context: ModelContext(c))
        try SleepService(context: c.mainContext).delete(id: record.id, revision: record.revision)
        XCTAssertTrue(try records(c).isEmpty)
    }
}
