import Foundation
import SwiftData
import XCTest
@testable import PersonalGrowthOS

@MainActor final class SleepReviewRegressionTests: XCTestCase {
    let zone = TimeZone(identifier: "Asia/Shanghai")!
    func date(_ day: String) -> Date { ImportantCivilDay(identifier: day)!.instant(minutes: 720, timeZone: zone)! }
    func testKnownCrossRecordRollbackDoesNotClaimSameDayEvidence() throws {
        let c = try PersistenceContainerFactory.makeInMemory(); var clock = date("2026-10-18")
        let service = SleepService(context: c.mainContext, now: { clock })
        var d = SleepDraft(day: "2026-10-18", zone: zone); d.values.feeling = 4; _ = try service.save(d)
        clock = date("2026-10-15"); d = SleepDraft(day: "2026-10-15", zone: zone); d.values.feeling = 3; _ = try service.save(d)
        let saved = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<SleepRecord>()).first { $0.wakeDay == d.wakeDay })
        XCTAssertNil(try saved.values().feelingFilledAt)
    }
    func testRollbackCannotOverwriteAlreadyEffectiveGoalAndNormalPendingEditsStillWork() throws {
        let c = try PersistenceContainerFactory.makeInMemory(); var clock = date("2026-10-15")
        let service = SleepService(context: c.mainContext, now: { clock })
        try service.setGoal(cutoffMinute: 1410, timeZone: zone)
        clock = date("2026-10-14")
        XCTAssertThrowsError(try service.setGoal(cutoffMinute: 60, timeZone: zone))
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<SleepGoalRule>()).first?.cutoffMinute, 1410)
        clock = date("2026-10-15"); try service.setGoal(cutoffMinute: 60, timeZone: zone); try service.setGoal(cutoffMinute: 90, timeZone: zone)
        let rules = try ModelContext(c).fetch(FetchDescriptor<SleepGoalRule>())
        XCTAssertEqual(rules.count, 2); XCTAssertEqual(rules.first { $0.effectiveDay == "2026-10-16" }?.cutoffMinute, 90)
    }
    func testAmbiguousCivilRangeSurvivesServiceReopenAndBackupWithoutInventedInterval() throws {
        let c = try PersistenceContainerFactory.makeInMemory(), ny = TimeZone(identifier: "America/New_York")!
        let now = ImportantCivilDay(identifier: "2026-11-01")!.instant(minutes: 720, timeZone: ny)!
        var d = SleepDraft(day: "2026-11-01", zone: ny)
        d.values.bedtime = .init(day: d.wakeDay, minute: 90, precision: 30)
        d.values.wake = .init(day: d.wakeDay, minute: 420, precision: 15); d.values.feeling = 4
        XCTAssertNoThrow(try SleepService(context: c.mainContext, now: { now }).save(d))
        let saved = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<SleepRecord>()).first)
        XCTAssertEqual(try saved.values().bedtime, d.values.bedtime)
        XCTAssertNil(SleepRules.interval(try saved.values(), zone: ny))
        let transfer = try SleepRecordTransfer(saved)
        let data = TransferData(entries: [], images: [], tags: [], links: [], habits: [], habitLogs: [], goals: [], goalEvents: [], sleepRecords: [transfer])
        XCTAssertNoThrow(try data.validateSleep(packageVersion: 9))
    }
}

@MainActor extension SleepReviewRegressionTests {
    func testWallClockPickerRoundTripsAcrossDSTDatesWithoutElapsedSecondShift() throws {
        for name in ["America/New_York", "Europe/Berlin", "Asia/Shanghai"] {
            let zone = TimeZone(identifier: name)!
            for minute in [0, 90, 540, 1410] {
                XCTAssertEqual(SleepWallClock.minutes(SleepWallClock.pickerDate(minutes: minute, zone: zone), zone: zone), minute)
            }
        }
    }
    func testElapsedMorningCannotBeMovedLaterButBeforeFireEditWorksAndSurvivesReload() async throws {
        let c = try PersistenceContainerFactory.makeInMemory(), client = TodoNotificationStub()
        let day = ImportantCivilDay(Date())
        var now = day.instant(minutes: 480, timeZone: .current)!
        var prefs = SleepReminderPreferences(enabled: true, minute: 540)
        let name = "SleepLedgerSynthetic-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var co = TodoReminderCoordinator(client: client, now: { now }, sleepPreferences: { prefs }, sleepHistory: SleepReminderHistory(defaults: defaults))
        await co.reconcile(context: c.mainContext)
        prefs.minute = 570; await co.reconcile(context: c.mainContext)
        XCTAssertEqual(client.pending[SleepReminderPlanner.prefix + day.identifier]?.fireAt, day.instant(minutes: 570, timeZone: .current))
        now = day.instant(minutes: 600, timeZone: .current)!
        client.pending.removeValue(forKey: SleepReminderPlanner.prefix + day.identifier) // system has delivered it
        prefs.minute = 660
        co = TodoReminderCoordinator(client: client, now: { now }, sleepPreferences: { prefs }, sleepHistory: SleepReminderHistory(defaults: defaults))
        await co.reconcile(context: c.mainContext)
        XCTAssertNil(client.pending[SleepReminderPlanner.prefix + day.identifier])
        XCTAssertEqual(co.sleepStatus().nextFire, day.adding(days: 1)!.instant(minutes: 660, timeZone: .current))
    }
}

@MainActor extension SleepReviewRegressionTests {
    func testEarlierDSTOccurrenceIsNotRejectedByLaterRepeatedWallClockAndOffsetMismatchIsInvalid() throws {
        let ny = TimeZone(identifier: "America/New_York")!
        let now = try SleepRange(day: "2026-11-01", minute: 90, precision: 0, utcOffset: -18000).bounds(zone: ny).lowerBound
        var values = SleepValues(); values.wake = .init(day: "2026-11-01", minute: 105, precision: 0, utcOffset: -14400)
        XCTAssertNoThrow(try SleepRules.validate(day: "2026-11-01", zoneID: ny.identifier, values: values, now: now))
        values.wake = .init(day: "2026-11-01", minute: 420, precision: 0, utcOffset: -14400)
        XCTAssertThrowsError(try SleepRules.validate(day: "2026-11-01", zoneID: ny.identifier, values: values))
    }
    func testDaytimeMainSleepIsNotForcedIntoNightGoal() throws {
        let day = "2026-10-15", rule = SleepGoalRule(effectiveDay: day, cutoffMinute: 1410, createdAt: date(day))
        var values = SleepValues(); values.bedtimeFilledAt = date(day)
        for (date, minute) in [("2026-10-14", 480), (day, 1200), (day, 720)] {
            values.bedtime = .init(day: date, minute: minute, precision: 30)
            XCTAssertEqual(SleepRules.goal(day: day, zone: zone, values: values, rules: [rule], now: self.date(day)), .nonNight)
        }
    }
}

@MainActor extension SleepReviewRegressionTests {
    func testTimezoneCivilDayRollbackCannotRewriteAnEffectiveGoal() throws {
        let c = try PersistenceContainerFactory.makeInMemory()
        let ny = TimeZone(identifier: "America/New_York")!, la = TimeZone(identifier: "America/Los_Angeles")!
        var clock = ImportantCivilDay(identifier: "2026-10-15")!.instant(minutes: 30, timeZone: ny)!
        let service = SleepService(context: c.mainContext, now: { clock })
        try service.setGoal(cutoffMinute: 1410, timeZone: ny)
        clock.addTimeInterval(60); try service.setGoal(cutoffMinute: 60, timeZone: la)
        let rules = try ModelContext(c).fetch(FetchDescriptor<SleepGoalRule>())
        XCTAssertEqual(rules.first { $0.effectiveDay == "2026-10-15" }?.cutoffMinute, 1410)
        XCTAssertEqual(rules.first { $0.effectiveDay == "2026-10-16" }?.cutoffMinute, 60)
    }
    func testAllPossibleDSTInterpretationsMustNotBeWhollyReversed() throws {
        let ny = TimeZone(identifier: "America/New_York")!
        var values = SleepValues(); values.bedtime = .init(day: "2026-11-01", minute: 90, precision: 30)
        values.wake = .init(day: "2026-11-01", minute: 30, precision: 15); values.feeling = 4
        XCTAssertThrowsError(try SleepRules.validate(day: "2026-11-01", zoneID: ny.identifier, values: values))
        values.wake = .init(day: "2026-11-01", minute: 420, precision: 15)
        XCTAssertNoThrow(try SleepRules.validate(day: "2026-11-01", zoneID: ny.identifier, values: values))
        XCTAssertNil(SleepRules.interval(values, zone: ny))
    }
    func testCancelledBeforeDeliveryDoesNotSuppressLaterUnelapsedReminderAfterDeleteAndReload() async throws {
        let c = try PersistenceContainerFactory.makeInMemory(), client = TodoNotificationStub()
        let day = ImportantCivilDay(Date()), name = "SleepCancelledSynthetic-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name)); defer { defaults.removePersistentDomain(forName: name) }
        var now = day.instant(minutes: 480, timeZone: .current)!, prefs = SleepReminderPreferences(enabled: true, minute: 540)
        var co = TodoReminderCoordinator(client: client, now: { now }, sleepPreferences: { prefs }, sleepHistory: SleepReminderHistory(defaults: defaults))
        await co.reconcile(context: c.mainContext)
        now.addTimeInterval(300)
        var draft = SleepDraft(day: day.identifier); draft.values.note = "Synthetic cancellation"
        let service = SleepService(context: c.mainContext, now: { now }); let id = try service.save(draft)
        await co.reconcile(context: c.mainContext)
        XCTAssertNil(client.pending[SleepReminderPlanner.prefix + day.identifier])
        now.addTimeInterval(300); prefs.minute = 600; await co.reconcile(context: c.mainContext)
        now = day.instant(minutes: 570, timeZone: .current)!
        let record = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<SleepRecord>()).first)
        try service.delete(id: id, revision: record.revision)
        co = TodoReminderCoordinator(client: client, now: { now }, sleepPreferences: { prefs }, sleepHistory: SleepReminderHistory(defaults: defaults))
        await co.reconcile(context: c.mainContext)
        XCTAssertEqual(client.pending[SleepReminderPlanner.prefix + day.identifier]?.fireAt, day.instant(minutes: 600, timeZone: .current))
    }
}

@MainActor extension SleepReviewRegressionTests {
    func testAmbiguousUpperEndpointKeepsEveryPossibleOrdering() throws {
        let ny = TimeZone(identifier: "America/New_York")!
        var values = SleepValues()
        values.bedtime = .init(day: "2026-11-01", minute: 105, precision: 0, utcOffset: -14400)
        values.wake = .init(day: "2026-11-01", minute: 30, precision: 60)
        XCTAssertNoThrow(try SleepRules.validate(day: "2026-11-01", zoneID: ny.identifier, values: values))
        XCTAssertEqual(values.wake!.possibleBounds(zone: ny).count, 2)
        XCTAssertNil(SleepRules.interval(values, zone: ny))
        let now = try SleepRange(day: "2026-11-01", minute: 90, precision: 0, utcOffset: -18000).bounds(zone: ny).lowerBound
        values.bedtime = nil; values.wake = .init(day: "2026-11-01", minute: 105, precision: 0)
        XCTAssertNoThrow(try SleepRules.validate(day: "2026-11-01", zoneID: ny.identifier, values: values, now: now))
    }
}
