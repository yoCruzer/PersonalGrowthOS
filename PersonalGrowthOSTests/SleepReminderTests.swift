import Foundation
import SwiftData
import XCTest
@testable import PersonalGrowthOS

@MainActor final class SleepReminderTests: XCTestCase {
    func testSleepUsesSharedBudgetAndDoesNotDisplaceOtherCategoriesSilently() async throws {
        let c = try PersistenceContainerFactory.makeInMemory(), client = TodoNotificationStub()
        let now = Date().addingTimeInterval(-300), prefs = SleepReminderPreferences(enabled: true, minute: 1439)
        client.otherIdentifiers = Set((0..<57).map { "reserved-\($0)" })
        let task = try TodoTaskService(context: c.mainContext).create(.init(title: "Synthetic todo", remindAt: now.addingTimeInterval(600)))
        var p = ImportantDayPreferences(); p.reminderOffsets = [0]
        let next = ImportantCivilDay(Date()).adding(days: 1)!
        let day = try ImportantDay(title: "Synthetic day", rule: .init(year: next.year, month: next.month, day: next.day), preferences: p)
        c.mainContext.insert(day); try c.mainContext.save()
        let co = TodoReminderCoordinator(client: client, now: { now }, sleepPreferences: { prefs }, sleepHistory: SleepReminderHistory(defaults: nil))
        await co.reconcile(context: c.mainContext)
        XCTAssertEqual(client.pending.count, 3)
        XCTAssertEqual(co.status(for: task), .scheduled); XCTAssertEqual(co.status(for: day).status, .scheduled)
        XCTAssertEqual(co.sleepStatus().scheduledCount, 1); XCTAssertEqual(co.sleepStatus().status, .queueFull)
        XCTAssertTrue(client.removed.allSatisfy { !$0.hasPrefix("reserved-") })
    }
    func testRecordedDayCancelDeleteBeforeTimeRestoreChangeAndOffPreserveOthers() async throws {
        let c = try PersistenceContainerFactory.makeInMemory(), client = TodoNotificationStub()
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let today = ImportantCivilDay(Date()), now = today.instant(minutes: 60, timeZone: .current)!
        var prefs = SleepReminderPreferences(enabled: true, minute: 540)
        let co = TodoReminderCoordinator(client: client, now: { now }, sleepPreferences: { prefs }, sleepHistory: SleepReminderHistory(defaults: nil))
        await co.reconcile(context: c.mainContext)
        let id = SleepReminderPlanner.prefix + today.identifier
        XCTAssertNotNil(client.pending[id]); XCTAssertEqual(co.sleepStatus().scheduledCount, 7)
        var draft = SleepDraft(day: today.identifier); draft.values.note = "Any valid partial record cancels today's prompt"
        let saved = try SleepService(context: c.mainContext, now: { now }).save(draft)
        await co.reconcile(context: c.mainContext); XCTAssertNil(client.pending[id]); XCTAssertEqual(co.sleepStatus().scheduledCount, 6)
        let record = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<SleepRecord>()).first)
        try SleepService(context: c.mainContext).delete(id: saved, revision: record.revision)
        await co.reconcile(context: c.mainContext); XCTAssertNotNil(client.pending[id])
        prefs.minute = 600; await co.reconcile(context: c.mainContext)
        XCTAssertEqual(client.pending[id]?.fireAt, today.instant(minutes: 600, timeZone: .current))
        prefs.enabled = false; await co.reconcile(context: c.mainContext)
        XCTAssertTrue(client.pending.isEmpty); XCTAssertEqual(co.sleepStatus().status, .none)
        XCTAssertFalse(client.removed.contains(LocalReminderScheduler.dailyIdentifier)); XCTAssertFalse(client.removed.contains(LocalReminderScheduler.weeklyIdentifier))
    }
    func testDeniedFailureStaleGenerationAndPastTimesAreHonest() async throws {
        let c = try PersistenceContainerFactory.makeInMemory(), client = TodoNotificationStub()
        let today = ImportantCivilDay(Date()), now = today.instant(minutes: 600, timeZone: .current)!
        var prefs = SleepReminderPreferences(enabled: true, minute: 540)
        let co = TodoReminderCoordinator(client: client, now: { now }, sleepPreferences: { prefs }, sleepHistory: SleepReminderHistory(defaults: nil))
        client.authorization = .notDetermined; await co.reconcile(context: c.mainContext)
        XCTAssertEqual(client.permissionCalls, 0); XCTAssertEqual(co.sleepStatus().status, .permissionRequired)
        client.authorization = .denied; await co.reconcile(context: c.mainContext)
        XCTAssertEqual(co.sleepStatus().status, .denied); XCTAssertTrue(client.pending.isEmpty)
        client.authorization = .allowed; client.shouldFail = true; await co.reconcile(context: c.mainContext)
        XCTAssertEqual(co.sleepStatus().status, .failed)
        client.shouldFail = false
        client.whileAdding = { prefs.enabled = false; Task { await co.reconcile(context: c.mainContext) } }
        await co.reconcile(context: c.mainContext); await Task.yield(); await co.reconcile(context: c.mainContext)
        XCTAssertTrue(client.pending.isEmpty); XCTAssertEqual(co.sleepStatus().status, .none)
        prefs.enabled = true; await co.reconcile(context: c.mainContext)
        XCTAssertNil(client.pending[SleepReminderPlanner.prefix + today.identifier])
        XCTAssertEqual(co.sleepStatus().nextFire, today.adding(days: 1)!.instant(minutes: 540, timeZone: .current))
        XCTAssertTrue(client.pending.values.allSatisfy { $0.sleepWakeDay != nil && !$0.title.contains("Synthetic") })
    }
    func testExpiredRouteKeepsExplicitWakeDayAndRejectsMalformedPayload() {
        let router = SleepExternalRouter(); router.receive(day: "2026-01-01")
        XCTAssertEqual(router.pending?.id, "2026-01-01"); router.receive(day: "2026-02-30")
        XCTAssertEqual(router.pending?.id, "2026-01-01")
    }
}
