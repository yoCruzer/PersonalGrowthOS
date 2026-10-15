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

@MainActor extension SleepReviewRegressionTests {
    func testCancellationEvidenceSurvivesGenerationChangeDuringNextDayAdd() async throws {
        let c = try PersistenceContainerFactory.makeInMemory(), client = TodoNotificationStub()
        let day = ImportantCivilDay(Date()), name = "SleepInterleavedSynthetic-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name)); defer { defaults.removePersistentDomain(forName: name) }
        var now = day.instant(minutes: 480, timeZone: .current)!, prefs = SleepReminderPreferences(enabled: true, minute: 540)
        var co = TodoReminderCoordinator(client: client, now: { now }, sleepPreferences: { prefs }, sleepHistory: SleepReminderHistory(defaults: defaults))
        await co.reconcile(context: c.mainContext)
        now.addTimeInterval(300)
        var draft = SleepDraft(day: day.identifier); draft.values.note = "Synthetic interleaved cancel"
        let service = SleepService(context: c.mainContext, now: { now }); let id = try service.save(draft)
        client.whileAdding = { Task { await co.reconcile(context: c.mainContext) } }
        await co.reconcile(context: c.mainContext); await Task.yield()
        XCTAssertNil(client.pending[SleepReminderPlanner.prefix + day.identifier])
        prefs.minute = 600; await co.reconcile(context: c.mainContext)
        now = day.instant(minutes: 570, timeZone: .current)!
        let record = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<SleepRecord>()).first)
        try service.delete(id: id, revision: record.revision)
        co = TodoReminderCoordinator(client: client, now: { now }, sleepPreferences: { prefs }, sleepHistory: SleepReminderHistory(defaults: defaults))
        await co.reconcile(context: c.mainContext)
        XCTAssertEqual(client.pending[SleepReminderPlanner.prefix + day.identifier]?.fireAt, day.instant(minutes: 600, timeZone: .current))
    }
}

@MainActor extension SleepReviewRegressionTests {
    func testR2InitialDisabledSavesAreNoopAndFirstActivationIsTodayAfterDiskReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("goal.sqlite"), clock = date("2026-10-15")
        try autoreleasepool {
            let c = try PersistenceContainerFactory.makeOnDisk(at: url)
            let service = SleepService(context: c.mainContext, now: { clock })
            for _ in 0..<3 { try service.setGoal(cutoffMinute: nil, timeZone: zone) }
            XCTAssertEqual(try ModelContext(c).fetchCount(FetchDescriptor<SleepGoalRule>()), 0)
            try service.setGoal(cutoffMinute: 1410, timeZone: zone)
        }
        let c = try PersistenceContainerFactory.makeOnDisk(at: url)
        let rules = try ModelContext(c).fetch(FetchDescriptor<SleepGoalRule>())
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.effectiveDay, "2026-10-15")
        XCTAssertEqual(rules.first?.cutoffMinute, 1410)
    }
    func testR3AcceptedMorningElapsedBeforeBatchConfirmationIsNotFailureAndSurvivesRestart() async throws {
        let c = try PersistenceContainerFactory.makeInMemory(), client = TodoNotificationStub()
        let day = ImportantCivilDay(Date()), fire = day.instant(minutes: 540, timeZone: .current)!
        var clock = fire.addingTimeInterval(-1), prefs = SleepReminderPreferences(enabled: true, minute: 540)
        let name = "SleepBatchElapsedSynthetic-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let history = SleepReminderHistory(defaults: defaults), id = SleepReminderPlanner.prefix + day.identifier
        var co = TodoReminderCoordinator(client: client, now: { clock }, sleepPreferences: { prefs }, sleepHistory: history)
        client.whileAdding = { clock = fire.addingTimeInterval(1); client.pending.removeValue(forKey: id) }
        await co.reconcile(context: c.mainContext)
        XCTAssertEqual(co.sleepStatus().status, .scheduled)
        XCTAssertEqual(co.sleepStatus().scheduledCount, 6)
        XCTAssertEqual(co.sleepStatus().nextFire, day.adding(days: 1)!.instant(minutes: 540, timeZone: .current))
        XCTAssertTrue(history.elapsedDays(now: clock).contains(day.identifier))
        prefs.minute = 660
        co = TodoReminderCoordinator(client: client, now: { clock }, sleepPreferences: { prefs }, sleepHistory: SleepReminderHistory(defaults: defaults))
        await co.reconcile(context: c.mainContext)
        XCTAssertNil(client.pending[id])
        XCTAssertTrue(SleepReminderHistory(defaults: defaults).elapsedDays(now: clock).contains(day.identifier))
    }
}

@MainActor extension SleepReviewRegressionTests {
    func testR1WorkspaceRefreshPairsNewFactsAndEvaluationTimeButNeverClampsFutureOrRecalled() throws {
        let c = try PersistenceContainerFactory.makeInMemory(); var clock = date("2026-10-15")
        let service = SleepService(context: c.mainContext, now: { clock }), workspace = SleepWorkspace(now: { clock })
        var draft = SleepDraft(day: "2026-10-15", zone: zone)
        draft.values.bedtime = .init(day: "2026-10-14", minute: 1380, precision: 30)
        draft.values.wake = .init(day: draft.wakeDay, minute: 420, precision: 15); draft.values.feeling = 4
        _ = try service.save(draft); workspace.refresh(c.mainContext)
        clock.addTimeInterval(60)
        var edit = try SleepDraft(XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<SleepRecord>()).first))
        edit.values.feeling = 2; _ = try service.save(edit); workspace.refresh(c.mainContext)
        XCTAssertEqual(workspace.reference, clock)
        XCTAssertEqual(workspace.review(windowDays: 7).feelingCount, 1)
        XCTAssertEqual(workspace.review(windowDays: 30).count(feeling: 2), 1)
        let stamp = workspace.records.first?.values.bedtimeFilledAt
        edit = try SleepDraft(XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<SleepRecord>()).first)); edit.values.note = "Synthetic note"
        clock.addTimeInterval(60); _ = try service.save(edit); workspace.refresh(c.mainContext)
        XCTAssertEqual(workspace.records.first?.values.bedtimeFilledAt, stamp)
        clock.addTimeInterval(-3600); workspace.advanceEvaluationClock()
        XCTAssertEqual(workspace.review(windowDays: 7).feelingCount, 0)
        XCTAssertEqual(workspace.records.first?.values.feeling, 2)
        clock = date("2026-10-18")
        edit = try SleepDraft(XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<SleepRecord>()).first)); edit.values.feeling = 1
        _ = try service.save(edit); workspace.refresh(c.mainContext)
        XCTAssertEqual(workspace.review(windowDays: 7).feelingCount, 0)
        XCTAssertEqual(workspace.review(windowDays: 7).bedtimeCount, 1)
        XCTAssertEqual(workspace.review(windowDays: 7).count(timing: .recalled), 1)
    }
    func testR3ElapsedAcceptanceSurvivesGenerationChangeBeforeConfirmation() async throws {
        let c = try PersistenceContainerFactory.makeInMemory(), client = TodoNotificationStub(), day = ImportantCivilDay(Date())
        let fire = day.instant(minutes: 540, timeZone: .current)!, id = SleepReminderPlanner.prefix + day.identifier
        var clock = fire.addingTimeInterval(-1), prefs = SleepReminderPreferences(enabled: true, minute: 540)
        let name = "SleepGenerationAccepted-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let history = SleepReminderHistory(defaults: defaults)
        let co = TodoReminderCoordinator(client: client, now: { clock }, sleepPreferences: { prefs }, sleepHistory: history)
        client.whileAdding = {
            clock = fire.addingTimeInterval(1); client.pending.removeValue(forKey: id); prefs.minute = 660
            Task { await co.reconcile(context: c.mainContext) }
        }
        await co.reconcile(context: c.mainContext); await Task.yield()
        XCTAssertNil(client.pending[id]); XCTAssertTrue(history.elapsedDays(now: clock).contains(day.identifier))
        XCTAssertEqual(co.sleepStatus().nextFire, day.adding(days: 1)!.instant(minutes: 660, timeZone: .current))
        XCTAssertEqual(co.sleepStatus().status, .scheduled)
    }
    func testR3FutureMissingIsFailureAndDoesNotCreateElapsedEvidence() async throws {
        let c = try PersistenceContainerFactory.makeInMemory(), client = TodoNotificationStub(), day = ImportantCivilDay(Date())
        let fire = day.instant(minutes: 540, timeZone: .current)!, id = SleepReminderPlanner.prefix + day.identifier
        var clock = fire.addingTimeInterval(-60), prefs = SleepReminderPreferences(enabled: true, minute: 540)
        let history = SleepReminderHistory(defaults: nil)
        let co = TodoReminderCoordinator(client: client, now: { clock }, sleepPreferences: { prefs }, sleepHistory: history)
        client.whileAdding = { client.pending.removeValue(forKey: id) }
        await co.reconcile(context: c.mainContext)
        XCTAssertEqual(co.sleepStatus().status, .failed)
        clock = fire.addingTimeInterval(60); XCTAssertFalse(history.elapsedDays(now: clock).contains(day.identifier))
        prefs.minute = 660; await co.reconcile(context: c.mainContext)
        XCTAssertNotNil(client.pending[id]); XCTAssertEqual(co.sleepStatus().status, .scheduled)
    }
    func testR3PrefireCancellationIsConfirmedBeforeLaterAddsCrossOldFireAndDeleteCanRequeue() async throws {
        let c = try PersistenceContainerFactory.makeInMemory(), client = TodoNotificationStub(), day = ImportantCivilDay(Date())
        let fire = day.instant(minutes: 540, timeZone: .current)!, id = SleepReminderPlanner.prefix + day.identifier
        var clock = fire.addingTimeInterval(-3600), prefs = SleepReminderPreferences(enabled: true, minute: 540)
        let history = SleepReminderHistory(defaults: nil)
        let co = TodoReminderCoordinator(client: client, now: { clock }, sleepPreferences: { prefs }, sleepHistory: history)
        await co.reconcile(context: c.mainContext)
        var draft = SleepDraft(day: day.identifier); draft.values.note = "Synthetic cancellation before fire"
        let service = SleepService(context: c.mainContext, now: { clock }); let saved = try service.save(draft)
        client.whileAdding = { clock = fire.addingTimeInterval(60) }
        await co.reconcile(context: c.mainContext)
        XCTAssertNil(client.pending[id]); XCTAssertFalse(history.elapsedDays(now: clock).contains(day.identifier))
        let record = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<SleepRecord>()).first)
        try service.delete(id: saved, revision: record.revision); prefs.minute = 660
        await co.reconcile(context: c.mainContext); XCTAssertNotNil(client.pending[id])
    }
    func testR3LegacyFutureReplacementAcceptedBeforeOldFireRemainsLegalAcrossBatchExpiry() async throws {
        let c = try PersistenceContainerFactory.makeInMemory(), client = TodoNotificationStub(), day = ImportantCivilDay(Date())
        let fire = day.instant(minutes: 540, timeZone: .current)!, id = SleepReminderPlanner.prefix + day.identifier
        var clock = fire.addingTimeInterval(-1)
        let name = "SleepLegacyFuture-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set([day.identifier: fire.timeIntervalSinceReferenceDate], forKey: "sleep.morningReminder.plannedFires")
        let old = SleepReminderPlanner.requests(preferences: .init(enabled: true, minute: 540), recordedDays: [], now: clock, zone: .current)
        for request in old { client.pending[request.id] = request }
        let history = SleepReminderHistory(defaults: defaults)
        let co = TodoReminderCoordinator(client: client, now: { clock }, sleepPreferences: { .init(enabled: true, minute: 660) }, sleepHistory: history)
        client.afterAdding = { request in if request.sleepWakeDay != day.identifier { clock = fire.addingTimeInterval(60) } }
        await co.reconcile(context: c.mainContext)
        XCTAssertEqual(client.pending[id]?.fireAt, day.instant(minutes: 660, timeZone: .current))
        XCTAssertFalse(SleepReminderHistory(defaults: defaults).elapsedDays(now: clock).contains(day.identifier))
        XCTAssertEqual(co.sleepStatus().scheduledCount, 7)
    }
    func testR3LateReplacementKeepsLegacyElapsedEvidenceAndRemovesLaterSameDayPrompt() async throws {
        let c = try PersistenceContainerFactory.makeInMemory(), client = TodoNotificationStub(), day = ImportantCivilDay(Date())
        let fire = day.instant(minutes: 540, timeZone: .current)!, id = SleepReminderPlanner.prefix + day.identifier
        var clock = fire.addingTimeInterval(-1)
        let name = "SleepLegacyElapsed-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set([day.identifier: fire.timeIntervalSinceReferenceDate], forKey: "sleep.morningReminder.plannedFires")
        let co = TodoReminderCoordinator(client: client, now: { clock }, sleepPreferences: { .init(enabled: true, minute: 660) }, sleepHistory: SleepReminderHistory(defaults: defaults))
        client.whileAdding = { clock = fire.addingTimeInterval(60) }
        await co.reconcile(context: c.mainContext)
        XCTAssertNil(client.pending[id]); XCTAssertEqual(co.sleepStatus().scheduledCount, 6)
        XCTAssertEqual(co.sleepStatus().status, .scheduled)
        let restarted = TodoReminderCoordinator(client: client, now: { clock }, sleepPreferences: { .init(enabled: true, minute: 720) }, sleepHistory: SleepReminderHistory(defaults: defaults))
        await restarted.reconcile(context: c.mainContext); XCTAssertNil(client.pending[id])
    }
    func testR3FailedReplacementRemovesPriorFutureLedgerInsteadOfLockingDate() async throws {
        let c = try PersistenceContainerFactory.makeInMemory(), client = TodoNotificationStub(), day = ImportantCivilDay(Date())
        let fire = day.instant(minutes: 540, timeZone: .current)!, id = SleepReminderPlanner.prefix + day.identifier
        var clock = fire.addingTimeInterval(-60), prefs = SleepReminderPreferences(enabled: true, minute: 540)
        let history = SleepReminderHistory(defaults: nil)
        let co = TodoReminderCoordinator(client: client, now: { clock }, sleepPreferences: { prefs }, sleepHistory: history)
        await co.reconcile(context: c.mainContext)
        client.shouldFail = true; prefs.minute = 600; await co.reconcile(context: c.mainContext)
        XCTAssertEqual(co.sleepStatus().status, .failed); XCTAssertNil(client.pending[id])
        clock = fire.addingTimeInterval(60); XCTAssertFalse(history.elapsedDays(now: clock).contains(day.identifier))
        client.shouldFail = false; prefs.minute = 660; await co.reconcile(context: c.mainContext); XCTAssertNotNil(client.pending[id])
    }
}

@MainActor extension SleepReviewRegressionTests {
    func testR3FailedPrefireReplacementCancellationSurvivesLaterAddCrossingOldFire() async throws {
        enum SyntheticFailure: Error { case add }
        let c = try PersistenceContainerFactory.makeInMemory(), client = TodoNotificationStub(), day = ImportantCivilDay(Date())
        let fire = day.instant(minutes: 540, timeZone: .current)!, id = SleepReminderPlanner.prefix + day.identifier
        var clock = fire.addingTimeInterval(-1), prefs = SleepReminderPreferences(enabled: true, minute: 540)
        let history = SleepReminderHistory(defaults: nil)
        let co = TodoReminderCoordinator(client: client, now: { clock }, sleepPreferences: { prefs }, sleepHistory: history)
        await co.reconcile(context: c.mainContext)
        prefs.minute = 660
        client.afterAdding = { request in
            if request.id == id { throw SyntheticFailure.add }
            clock = fire.addingTimeInterval(60)
        }
        await co.reconcile(context: c.mainContext)
        XCTAssertEqual(co.sleepStatus().status, .failed); XCTAssertNil(client.pending[id])
        XCTAssertFalse(history.elapsedDays(now: clock).contains(day.identifier))
        client.afterAdding = nil; prefs.minute = 720
        await co.reconcile(context: c.mainContext); XCTAssertNotNil(client.pending[id])
    }
}
