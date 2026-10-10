import Foundation
import SwiftData
import SQLite3
import XCTest
@testable import PersonalGrowthOS

@MainActor
final class TodoFoundationTests: XCTestCase {
    private let zone = TimeZone(identifier: "Asia/Shanghai")!
    private func date(_ day: String) -> Date { TodoDay(day)!.date(timeZone: zone)!.addingTimeInterval(12 * 3600) }

    func testUndatedMultilineInputIsPreservedAndStateHistoryUsesRealClock() throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        var clock = date("2026-10-09")
        let service = TodoTaskService(context: context, now: { clock })
        XCTAssertThrowsError(try service.create(TodoDraft(title: " \n ")))
        let title = "买电池 🔋\n明天检查 TestFlight"
        let task = try service.create(TodoDraft(title: title, notes: "中文长备注"))
        XCTAssertEqual(task.title, title)
        XCTAssertNil(task.plannedDay); XCTAssertNil(task.remindAt)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()), 0)
        XCTAssertFalse(TodoQuery.matches(task, filter: .today, now: clock))
        clock = date("2026-10-08") // A wall-clock rollback must not lose the action.
        try service.transition(id: task.id, to: .completed)
        XCTAssertEqual(task.completedAt, clock)
        XCTAssertEqual(task.updatedAt, date("2026-10-09"))
        XCTAssertTrue(TodoQuery.matches(task, filter: .completedToday, now: clock, timeZone: zone))
        try service.transition(id: task.id, to: .open)
        XCTAssertNil(task.completedAt)
        try service.transition(id: task.id, to: .canceled)
        XCTAssertFalse(TodoQuery.matches(task, filter: .completedWeek, now: clock))
        try service.transition(id: task.id, to: .open)
        XCTAssertNil(task.canceledAt)
        let events = try context.fetch(FetchDescriptor<TodoTaskEvent>()).sorted { $0.sequence < $1.sequence }
        XCTAssertEqual(events.map(\.kindRawValue), ["created", "completed", "reopened", "canceled", "reopened"])
        XCTAssertEqual(events.map(\.sequence), [0, 1, 2, 3, 4])
        XCTAssertEqual(try JSONDecoder().decode(TodoEventValue.self, from: events.last!.afterValue), try TodoEventValue(task))
    }

    func testCivilDayFiltersSeparatePlanFromHardDeadlineAcrossTimeZones() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let service = TodoTaskService(context: container.mainContext)
        let plan = try service.create(TodoDraft(title: "计划未处理", plannedDay: "2026-10-08"))
        let deadline = try service.create(TodoDraft(title: "报销", deadlineDay: "2026-10-08"))
        let future = try service.create(TodoDraft(title: "明天", plannedDay: "2026-10-10"))
        for zone in [TimeZone(identifier: "Asia/Shanghai")!, TimeZone(identifier: "America/Los_Angeles")!] {
            let now = TodoDay("2026-10-09")!.date(timeZone: zone)!.addingTimeInterval(12 * 3600)
            XCTAssertTrue(TodoQuery.matches(plan, filter: .today, now: now, timeZone: zone))
            XCTAssertFalse(TodoQuery.matches(plan, filter: .overdue, now: now, timeZone: zone))
            XCTAssertTrue(TodoQuery.matches(deadline, filter: .overdue, now: now, timeZone: zone))
            XCTAssertTrue(TodoQuery.matches(future, filter: .upcoming, now: now, timeZone: zone))
            XCTAssertEqual(plan.plannedDay, "2026-10-08")
        }
        XCTAssertThrowsError(try service.create(TodoDraft(title: "bad", plannedDay: "2026-02-29")))
    }

    func testFixedAnchorsDoNotDriftAndDSTReminderIsExplicit() throws {
        XCTAssertEqual(try TodoRecurrence.day(anchor: "2026-01-31", frequency: .monthly, index: 1).description, "2026-02-28")
        XCTAssertEqual(try TodoRecurrence.day(anchor: "2026-01-31", frequency: .monthly, index: 2).description, "2026-03-31")
        XCTAssertEqual(try TodoRecurrence.day(anchor: "2024-02-29", frequency: .yearly, index: 1).description, "2025-02-28")
        XCTAssertEqual(try TodoRecurrence.day(anchor: "2024-02-29", frequency: .yearly, index: 4).description, "2028-02-29")
        XCTAssertEqual(try TodoRecurrence.day(anchor: "2026-10-09", frequency: .weekly, index: 1).description, "2026-10-16")
        XCTAssertEqual(try TodoRecurrence.day(anchor: "2026-10-09", frequency: .daily, index: 1).description, "2026-10-10")
        let ny = TimeZone(identifier: "America/New_York")!
        let reminder = try XCTUnwrap(TodoRecurrence.reminder(day: TodoDay("2026-03-08")!, minutes: 150, timeZone: ny))
        let parts = WeeklyReviewCalendarPolicy.calendar(timeZone: ny).dateComponents([.day, .hour, .minute], from: reminder)
        XCTAssertEqual(parts.day, 8); XCTAssertEqual(parts.hour, 3); XCTAssertEqual(parts.minute, 0)
        XCTAssertEqual(try TodoRecurrence.nextIndex(anchor: "2020-01-01", frequency: .daily, after: 0, today: TodoDay("2026-10-09")!), 2474)
    }

    func testRecurrenceCompleteRetryUndoSkipAndStopPreserveOccurrenceIdentity() throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let service = TodoTaskService(context: context, now: { self.date("2026-01-31") }, timeZone: { self.zone })
        let first = try service.create(TodoDraft(title: "交费", plannedDay: "2026-01-31", frequency: .monthly))
        try service.transition(id: first.id, to: .completed)
        try service.transition(id: first.id, to: .completed)
        var tasks = try context.fetch(FetchDescriptor<TodoTask>())
        XCTAssertEqual(tasks.count, 2)
        let next = try XCTUnwrap(tasks.first { $0.occurrenceIndex == 1 })
        let nextID = next.id
        XCTAssertEqual(next.plannedDay, "2026-02-28")
        try service.transition(id: first.id, to: .open)
        XCTAssertEqual(next.state, .canceled)
        try service.transition(id: first.id, to: .completed)
        XCTAssertEqual(next.state, .open); XCTAssertEqual(next.id, nextID)
        try service.transition(id: next.id, to: .canceled, skip: true)
        try service.transition(id: next.id, to: .canceled, skip: true)
        tasks = try context.fetch(FetchDescriptor<TodoTask>())
        let third = try XCTUnwrap(tasks.first { $0.occurrenceIndex == 2 })
        XCTAssertEqual(third.plannedDay, "2026-03-31")
        XCTAssertEqual(tasks.filter { $0.state == .open }.count, 1)
        try service.stopSeries(taskID: third.id)
        try service.transition(id: third.id, to: .completed)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTask>()), 3)
        XCTAssertEqual(tasks.filter { TodoQuery.matches($0, filter: .completedToday, now: self.date("2026-01-31"), timeZone: zone) }.count, 2)
        XCTAssertEqual(Set(tasks.compactMap(\.occurrenceKey)).count, 3)
        try TodoIntegrity.validate(context: context)
    }

    func testSourceAndListDeletionDoNotDeleteOtherObjectsOrChangeEntryTimes() throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let entry = Entry(body: "原始记录", createdAt: date("2026-10-09"))
        context.insert(entry); try context.save()
        let service = TodoTaskService(context: context)
        let list = try service.createList(name: "工作")
        let task = try service.create(TodoDraft(title: "行动", listID: list.id), sourceEntryID: entry.id)
        let independentlyDeleted = try service.create(TodoDraft(title: "只删除待办"), sourceEntryID: entry.id)
        try service.delete(id: independentlyDeleted.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()), 1)
        XCTAssertEqual(entry.body, "原始记录")
        try service.renameList(id: list.id, name: "生活")
        try service.deleteList(id: list.id)
        XCTAssertNil(task.listID)
        XCTAssertEqual(entry.updatedAt, date("2026-10-09"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try EntryDeletionService(persistence: ModelContextEntryPersistence(context: context), mediaStore: MediaStore(rootURL: root)).permanentlyDelete(entry)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTask>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTaskSource>()), 0)
        try service.delete(id: task.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTaskEvent>()), 0)
    }

    func testAtomicSaveFailureRollsBackTaskEventAndSuccessor() throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let good = TodoTaskService(context: context)
        let task = try good.create(TodoDraft(title: "每日事项", plannedDay: "2026-10-09", frequency: .daily))
        enum Injected: Error { case fail }
        let bad = TodoTaskService(context: context, save: { throw Injected.fail })
        XCTAssertThrowsError(try bad.transition(id: task.id, to: .completed))
        XCTAssertEqual(try good.task(id: task.id).state, .open)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTask>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTaskEvent>()), 1)
        XCTAssertThrowsError(try bad.create(TodoDraft(title: "不应保存")))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTask>()), 1)
    }

    func testTaskPersistsAcrossReopenWithEventsAndSeries() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("store.sqlite")
        var id: UUID!
        try autoreleasepool {
            let container = try PersistenceContainerFactory.makeOnDisk(at: url)
            let service = TodoTaskService(context: container.mainContext, now: { self.date("2026-10-09") })
            let task = try service.create(TodoDraft(title: "每日行动", notes: "原文\n多行", plannedDay: "2026-10-09", frequency: .daily))
            id = task.id; try service.transition(id: id, to: .completed)
        }
        for _ in 0..<2 {
            try autoreleasepool {
                let container = try PersistenceContainerFactory.makeOnDisk(at: url), context = container.mainContext
                XCTAssertEqual(try TodoTaskService(context: context).task(id: id).state, .completed)
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTask>()), 2)
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTaskEvent>()), 3)
            }
        }
    }
}

@MainActor
extension TodoFoundationTests {
    func testIntegrityRequiresCreationFirstAndStoppedSeriesCannotBeReactivatedByBackup() throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let service = TodoTaskService(context: context)
        _ = try service.create(TodoDraft(title: "合法创建"))
        try TodoIntegrity.validate(context: context)
        let initial = try XCTUnwrap(context.fetch(FetchDescriptor<TodoTaskEvent>()).first)
        initial.kindRawValue = TodoEventKind.reopened.rawValue
        XCTAssertThrowsError(try TodoIntegrity.validate(context: context))
        context.rollback()
        try TodoIntegrity.validate(context: context)
        let task = try XCTUnwrap(context.fetch(FetchDescriptor<TodoTask>()).first)
        task.revision = Int.max
        XCTAssertThrowsError(try TodoIntegrity.validate(context: context))
        context.rollback()
        try TodoIntegrity.validate(context: context)
        let repeating = try service.create(TodoDraft(title: "已停止", plannedDay: "2026-10-09", frequency: .daily))
        try service.stopSeries(taskID: repeating.id)
        try TodoIntegrity.validate(context: context)
        let rule = try XCTUnwrap(context.fetch(FetchDescriptor<TodoSeries>()).first)
        rule.isStopped = false
        XCTAssertThrowsError(try TodoIntegrity.validate(context: context))
        context.rollback()
        try TodoIntegrity.validate(context: context)
    }

    func testIntegrityRejectsUnknownStateDanglingEventAndInconsistentFinalFact() throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let service = TodoTaskService(context: context)
        let task = try service.create(TodoDraft(title: "合法"))
        try TodoIntegrity.validate(context: context)
        task.stateRawValue = "unknown"
        XCTAssertThrowsError(try TodoIntegrity.validate(context: context))
        context.rollback()
        let reloaded = try service.task(id: task.id)
        reloaded.plannedDay = "2026-10-10"
        XCTAssertThrowsError(try TodoIntegrity.validate(context: context))
        context.rollback()
        context.insert(TodoTaskEvent(taskID: UUID(), sequence: 0, kind: .created, occurredAt: Date(), createdAt: Date(), beforeValue: nil, afterValue: Data()))
        XCTAssertThrowsError(try TodoIntegrity.validate(context: context))
    }
}

@MainActor
extension TodoFoundationTests {
    func testExactBuild12V10FixtureMigratesAndReopensPreservingAllOldFactsAndMedia() async throws {
        let source = try XCTUnwrap(Bundle(for: TodoFoundationTests.self).url(forResource: "Build12V10Fixture", withExtension: nil))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let expectedRoot = root.appendingPathComponent("Expected")
        try ZIPArchiveReader(archiveURL: root.appendingPathComponent("expected-v6.zip"), availableCapacity: .max).extractAll(to: expectedRoot)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let expected = try decoder.decode(TransferData.self, from: Data(contentsOf: expectedRoot.appendingPathComponent("data.json")))
        let store = root.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
        try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: root.appendingPathComponent("PersonalGrowthOS.sqlite"), to: store)
        let originalBytes = try Data(contentsOf: store)
        let configuration = AppConfiguration(launchMode: .uiTesting, resetDataOnLaunch: false)
        for pass in 0..<2 {
            let manager = pass == 0 ? FileManager.default : FailingStartupCopyManager(28)
            let app = try AppContainer.make(configuration: configuration, fileManager: manager, rootURLOverride: root)
            let container = app.modelContainer, context = container.mainContext
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Recovery/BeforeMigration/Store/PersonalGrowthOS.sqlite")), originalBytes)
            if let failing = manager as? FailingStartupCopyManager { XCTAssertEqual(failing.copyAttempts, 0) }
            try LinkIntegrityService.validate(context: context)
            try TodoIntegrity.validate(context: context)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTask>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoSeries>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<CaptureImportReceipt>()), 1)
            let media = MediaStore(rootURL: root)
            let lease = try await ImportExportService(context: context, mediaStore: media).exportPackage()
            defer { lease.cleanup() }
            let exported = root.appendingPathComponent("Export-\(pass)")
            try ZIPArchiveReader(archiveURL: lease.url, availableCapacity: .max).extractAll(to: exported)
            let actual = try decoder.decode(TransferData.self, from: Data(contentsOf: exported.appendingPathComponent("data.json")))
            XCTAssertEqual(actual, expected) // Every old transferred identity/field, not merely counts.
            let image = try XCTUnwrap(context.fetch(FetchDescriptor<ImageMetadata>()).first)
            let original = try Data(contentsOf: media.fileURL(for: image.relativePath))
            let sourceMedia = MediaStore(rootURL: source)
            XCTAssertEqual(original, try Data(contentsOf: sourceMedia.fileURL(for: image.relativePath)))
        }
        var taskID: UUID!
        try autoreleasepool {
            let container = try PersistenceContainerFactory.makeOnDisk(at: store)
            let entry = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<Entry>()).first)
            taskID = try TodoTaskService(context: container.mainContext).create(TodoDraft(title: "迁移后行动"), sourceEntryID: entry.id).id
        }
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: store)
        XCTAssertEqual(try TodoTaskService(context: reopened.mainContext).task(id: taskID).title, "迁移后行动")
        try TodoIntegrity.validate(context: reopened.mainContext)
    }
}

@MainActor
extension TodoFoundationTests {
    func testRepeatingReminderKeepsChosenLocalDayAndClockAcrossTimeZoneChange() throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let shanghai = TimeZone(identifier: "Asia/Shanghai")!, ny = TimeZone(identifier: "America/New_York")!
        let day = TodoDay("2026-11-01")!
        let reminder = try XCTUnwrap(TodoRecurrence.reminder(day: day, minutes: 90, timeZone: shanghai))
        let old = TodoTaskService(context: context, timeZone: { shanghai })
        let task = try old.create(TodoDraft(title: "每日提醒", plannedDay: day.description, remindAt: reminder, frequency: .daily))
        let new = TodoTaskService(context: context, timeZone: { ny })
        try new.refreshRepeatingReminderTimes()
        XCTAssertEqual(task.reminderTimeZoneID, ny.identifier)
        XCTAssertEqual(task.plannedDay, day.description)
        let actual = try XCTUnwrap(task.remindAt)
        XCTAssertEqual(TodoDay(date: actual, timeZone: ny), day)
        let parts = WeeklyReviewCalendarPolicy.calendar(timeZone: ny).dateComponents([.hour, .minute], from: actual)
        XCTAssertEqual(parts.hour, 1); XCTAssertEqual(parts.minute, 30)
        let revision = task.revision
        try new.refreshRepeatingReminderTimes()
        XCTAssertEqual(task.revision, revision)
        try TodoIntegrity.validate(context: context)
    }
    func testGlobalSearchIncludesEveryTaskStateWithoutChangingEntryFollowUpResults() throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let entry = Entry(body: "匹配原文", createdAt: Date()); context.insert(entry); try context.save()
        let followUp = try EntryContinuationService(context: context).add(entryID: entry.id, body: "匹配补充")
        let service = TodoTaskService(context: context)
        let first = try service.create(TodoDraft(title: "匹配待办"))
        let second = try service.create(TodoDraft(title: "其他标题", notes: "匹配备注"))
        let third = try service.create(TodoDraft(title: "匹配取消"))
        try service.transition(id: second.id, to: .completed)
        try service.transition(id: third.id, to: .canceled)
        let results = try LocalSearchService(context: context).search("匹配")
        XCTAssertEqual(Set(results.todos.map(\.id)), Set([first.id, second.id, third.id]))
        XCTAssertEqual(results.entries.map(\.id), [entry.id])
        XCTAssertEqual(results.followUpMatches[entry.id]?.id, followUp.id)
    }

    func testDSTGapResolutionDoesNotChangeIntendedRepeatClockAfterTravel() throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        var zone = TimeZone(identifier: "America/New_York")!
        let now = TodoDay("2026-03-07")!.date(timeZone: zone)!.addingTimeInterval(12 * 3600)
        let service = TodoTaskService(context: context, now: { now }, timeZone: { zone })
        let reminder = try XCTUnwrap(TodoRecurrence.reminder(day: TodoDay("2026-03-07")!, minutes: 150, timeZone: zone))
        let first = try service.create(TodoDraft(title: "固定 02:30", plannedDay: "2026-03-07", remindAt: reminder, frequency: .daily))
        try service.transition(id: first.id, to: .completed)
        let next = try XCTUnwrap(context.fetch(FetchDescriptor<TodoTask>()).first { $0.state == .open })
        XCTAssertEqual(next.reminderLocalDay, "2026-03-08"); XCTAssertEqual(next.reminderMinutes, 150)
        XCTAssertEqual(WeeklyReviewCalendarPolicy.calendar(timeZone: zone).component(.hour, from: try XCTUnwrap(next.remindAt)), 3)
        var edit = TodoDraft(next); edit.notes = "编辑备注不改变原始提醒时间"
        try service.edit(id: next.id, draft: edit, futureSeries: true)
        zone = self.zone
        try service.refreshRepeatingReminderTimes()
        let parts = WeeklyReviewCalendarPolicy.calendar(timeZone: zone).dateComponents([.hour, .minute], from: try XCTUnwrap(next.remindAt))
        XCTAssertEqual(parts.hour, 2); XCTAssertEqual(parts.minute, 30)
        try TodoIntegrity.validate(context: context)
    }

    func testTodoTransferPreservesExactSubmicrosecondInstantsUnderLegacyOuterEncoder() throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let instant = Date(timeIntervalSinceReferenceDate: 812_345_678.1234567)
        let service = TodoTaskService(context: context, now: { instant })
        let task = try service.create(TodoDraft(title: "精确时间", remindAt: instant.addingTimeInterval(3600)))
        try service.transition(id: task.id, to: .completed)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let dto = TodoTaskTransfer(task)
        let restored = try decoder.decode(TodoTaskTransfer.self, from: encoder.encode(dto))
        XCTAssertEqual(restored, dto)
        XCTAssertEqual(restored.completedAt?.timeIntervalSinceReferenceDate, instant.timeIntervalSinceReferenceDate)
        let events = try context.fetch(FetchDescriptor<TodoTaskEvent>()).map(TodoTaskEventTransfer.init)
        let restoredEvents = try decoder.decode([TodoTaskEventTransfer].self, from: encoder.encode(events))
        XCTAssertEqual(restoredEvents, events)
        try TodoIntegrity.validate(tasks: [restored.model()], events: restoredEvents.map { try $0.model() }, lists: [], series: [], sources: [], entryIDs: [])
    }

    func testStatisticsAndStableImportantOrderUseFinalFactsAtDayAndWeekBoundaries() throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        var clock = date("2026-10-11")
        let service = TodoTaskService(context: context, now: { clock }, timeZone: { self.zone })
        let important = try service.create(TodoDraft(title: "重要", isImportant: true, plannedDay: "2026-10-12"))
        let planOnly = try service.create(TodoDraft(title: "仅过去计划", plannedDay: "2026-10-01"))
        let overdue = try service.create(TodoDraft(title: "硬逾期", deadlineDay: "2026-10-01"))
        let canceled = try service.create(TodoDraft(title: "取消", deadlineDay: "2026-10-01"))
        try service.transition(id: canceled.id, to: .canceled)
        try service.transition(id: important.id, to: .completed)
        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        XCTAssertEqual(TodoQuery.sorted(tasks).first?.id, important.id)
        XCTAssertEqual(tasks.filter { TodoQuery.matches($0, filter: .completedToday, now: clock, timeZone: zone) }.map(\.id), [important.id])
        XCTAssertEqual(tasks.filter { TodoQuery.matches($0, filter: .overdue, now: clock, timeZone: zone) }.map(\.id), [overdue.id])
        clock = date("2026-10-12") // Monday: last Sunday's completion falls outside this week.
        XCTAssertFalse(TodoQuery.matches(important, filter: .completedToday, now: clock, timeZone: zone))
        XCTAssertFalse(TodoQuery.matches(important, filter: .completedWeek, now: clock, timeZone: zone))
        try service.transition(id: important.id, to: .open)
        XCTAssertEqual(tasks.filter { TodoQuery.matches($0, filter: .open, now: clock, timeZone: zone) }.count, 3)
        XCTAssertFalse(TodoQuery.matches(planOnly, filter: .overdue, now: clock, timeZone: zone))
        try service.transition(id: important.id, to: .completed)
        XCTAssertTrue(TodoQuery.matches(important, filter: .completedWeek, now: clock, timeZone: zone))
        try service.transition(id: important.id, to: .canceled)
        XCTAssertFalse(TodoQuery.matches(important, filter: .completedWeek, now: clock, timeZone: zone))
        try TodoIntegrity.validate(context: context)
    }

    func testBoundedThousandTodoIntegritySearchAndStatisticsPerformance() throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let clock = date("2026-10-09")
        // Batch synthetic setup only; the measured production reads still use the normal persisted context.
        let service = TodoTaskService(context: context, now: { clock }, save: {})
        for index in 0..<1_000 {
            let task = try service.create(TodoDraft(title: "任务 \(index)", notes: index == 999 ? "唯一 needle" : "原始备注",
                isImportant: index == 500, plannedDay: "2026-10-09"))
            if index < 100 { try service.transition(id: task.id, to: .completed) }
        }
        try context.save()
        let search = LocalSearchService(context: context), options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            do {
                try TodoIntegrity.validate(context: context)
                XCTAssertEqual(try search.search("needle").todos.count, 1)
                let tasks = try context.fetch(FetchDescriptor<TodoTask>())
                XCTAssertEqual(tasks.filter { TodoQuery.matches($0, filter: .open, now: clock, timeZone: zone) }.count, 900)
                XCTAssertEqual(tasks.filter { TodoQuery.matches($0, filter: .completedToday, now: clock, timeZone: zone) }.count, 100)
                XCTAssertTrue(TodoQuery.sorted(tasks).first?.isImportant == true)
            } catch { XCTFail("Bounded Todo reads failed: \(error)") }
        }
    }
}

@MainActor
extension TodoFoundationTests {
    func testSaveReminderValidationAllowsHistoricalFutureTemplateReferenceButRejectsNewPastNotifications() throws {
        let clock = date("2026-02-10"), old = date("2026-01-09"), changed = date("2026-01-08")
        var draft = TodoDraft(title: "Template", remindAt: changed)
        XCTAssertNoThrow(try draft.validateReminderForSave(now: clock, existingReminder: old, usesExistingFutureTemplate: true))
        XCTAssertThrowsError(try draft.validateReminderForSave(now: clock, existingReminder: old, usesExistingFutureTemplate: false))
        XCTAssertThrowsError(try draft.validateReminderForSave(now: clock, existingReminder: nil, usesExistingFutureTemplate: false))
        draft.remindAt = old
        XCTAssertNoThrow(try draft.validateReminderForSave(now: clock, existingReminder: old, usesExistingFutureTemplate: false))
        draft.remindAt = date("2026-02-11")
        XCTAssertNoThrow(try draft.validateReminderForSave(now: clock, existingReminder: old, usesExistingFutureTemplate: false))
        draft.remindAt = nil
        XCTAssertNoThrow(try draft.validateReminderForSave(now: clock, existingReminder: old, usesExistingFutureTemplate: false))
    }

    func testReviewReminderKeepsOneDayLeadAcrossShortMonthAndLeapYear() throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let service = TodoTaskService(context: context, now: { self.date("2026-01-31") }, timeZone: { self.zone })
        let reminder = TodoRecurrence.reminder(day: TodoDay("2026-01-30")!, minutes: 1200, timeZone: zone)!
        let first = try service.create(TodoDraft(title: "Monthly", plannedDay: "2026-01-31", remindAt: reminder, frequency: .monthly))
        try service.transition(id: first.id, to: .completed)
        let next = try XCTUnwrap(context.fetch(FetchDescriptor<TodoTask>()).first { $0.state == .open })
        XCTAssertEqual(next.plannedDay, "2026-02-28")
        XCTAssertEqual(next.reminderLocalDay, "2026-02-27")
        XCTAssertEqual(next.remindAt, TodoRecurrence.reminder(day: TodoDay("2026-02-27")!, minutes: 1200, timeZone: zone))
        let sameDay = try service.create(TodoDraft(title: "Control", plannedDay: "2026-01-31", remindAt: TodoRecurrence.reminder(day: TodoDay("2026-01-31")!, minutes: 1200, timeZone: zone), frequency: .monthly))
        try service.transition(id: sameDay.id, to: .completed)
        let control = try XCTUnwrap(context.fetch(FetchDescriptor<TodoTask>()).first { $0.seriesID == sameDay.seriesID && $0.state == .open })
        XCTAssertEqual(control.reminderLocalDay, "2026-02-28")
    }

    func testReviewFutureTemplateUpdatesMaterializedOpenButKeepsHistory() throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let service = TodoTaskService(context: context, now: { self.date("2026-10-09") }, timeZone: { self.zone })
        let first = try service.create(TodoDraft(title: "Old", plannedDay: "2026-10-09", frequency: .daily))
        try service.transition(id: first.id, to: .completed)
        let next = try XCTUnwrap(context.fetch(FetchDescriptor<TodoTask>()).first { $0.state == .open })
        let nextID = next.id, nextKey = next.occurrenceKey
        var own = TodoDraft(next); own.title = "Individually edited"
        try service.edit(id: next.id, draft: own)
        var draft = TodoDraft(first); draft.title = "Future"; draft.notes = "new note"; draft.isImportant = true
        try service.edit(id: first.id, draft: draft, futureSeries: false)
        XCTAssertEqual(next.title, "Individually edited")
        let list = try service.createList(name: "Future list"); draft.listID = list.id
        let completedAt = first.completedAt
        try service.edit(id: first.id, draft: draft, futureSeries: true)
        XCTAssertEqual(next.title, "Future"); XCTAssertEqual(next.notes, "new note"); XCTAssertTrue(next.isImportant); XCTAssertEqual(next.listID, list.id)
        XCTAssertEqual(next.id, nextID); XCTAssertEqual(next.occurrenceKey, nextKey)
        XCTAssertEqual(first.completedAt, completedAt); XCTAssertEqual(first.state, .completed)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTask>()), 2)
        try TodoIntegrity.validate(context: context)
    }


}

@MainActor
extension TodoFoundationTests {
    func testOriginalV11CandidateMigratesWithoutLosingTaskEventBytesAndInfersReminderLead() throws {
        let source = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent("OriginalV11Fixture"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try XCTUnwrap(UUID(uuidString: String(contentsOf: root.appendingPathComponent("task-id.txt"), encoding: .utf8)))
        var events: [TodoTaskEventTransfer] = []
        for pass in 0..<2 {
            try autoreleasepool {
                let container = try PersistenceContainerFactory.makeOnDisk(at: root.appendingPathComponent("store.sqlite")), context = container.mainContext
                try TodoIntegrity.validate(context: context)
                let first = try TodoTaskService(context: context).task(id: id)
                XCTAssertEqual(first.title, "Original V11"); XCTAssertEqual(first.state, .completed)
                let facts = try context.fetch(FetchDescriptor<TodoTaskEvent>()).map(TodoTaskEventTransfer.init).sorted { $0.id.uuidString < $1.id.uuidString }
                if pass == 0 { events = facts } else { XCTAssertEqual(facts, events) }
                let next = try XCTUnwrap(context.fetch(FetchDescriptor<TodoTask>()).first { $0.state == .open })
                if pass == 1 {
                    let service = TodoTaskService(context: context, now: { self.date("2026-02-28") }, timeZone: { self.zone })
                    try service.transition(id: next.id, to: .completed)
                    let third = try XCTUnwrap(context.fetch(FetchDescriptor<TodoTask>()).first { $0.state == .open })
                    XCTAssertEqual(third.plannedDay, "2026-03-31"); XCTAssertEqual(third.reminderLocalDay, "2026-03-30")
                    try TodoIntegrity.validate(context: context)
                }
            }
        }
    }

    func testReminderLeadMonthlyTenthLeapYearDSTAndTravelUseCivilAnchor() throws {
        for (anchor, reminderDay, frequency, clockDay, expectedPlan, expectedReminder) in [
            ("2026-01-10", "2026-01-09", TodoFrequency.monthly, "2026-01-10", "2026-02-10", "2026-02-09"),
            ("2028-01-31", "2028-01-30", .monthly, "2028-01-31", "2028-02-29", "2028-02-28"),
            ("2024-02-29", "2024-02-28", .yearly, "2024-02-29", "2025-02-28", "2025-02-27"),
            ("2026-03-08", "2026-03-07", .daily, "2026-03-08", "2026-03-09", "2026-03-08"),
            ("2026-11-01", "2026-10-31", .daily, "2026-11-01", "2026-11-02", "2026-11-01")
        ] {
            let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
            var currentZone = TimeZone(identifier: "America/New_York")!
            let service = TodoTaskService(context: context, now: { TodoDay(clockDay)!.date(timeZone: currentZone)!.addingTimeInterval(12*3600) }, timeZone: { currentZone })
            let minutes = anchor == "2026-11-01" ? 90 : 150
            let first = try service.create(TodoDraft(title: anchor, plannedDay: anchor, deadlineDay: TodoDay(anchor)!.description, remindAt: TodoRecurrence.reminder(day: TodoDay(reminderDay)!, minutes: minutes, timeZone: currentZone), frequency: frequency))
            try service.transition(id: first.id, to: .completed)
            let next = try XCTUnwrap(context.fetch(FetchDescriptor<TodoTask>()).first { $0.state == .open })
            XCTAssertEqual(next.plannedDay, expectedPlan); XCTAssertEqual(next.reminderLocalDay, expectedReminder)
            XCTAssertEqual(next.reminderMinutes, minutes)
            let nyExpected = TodoRecurrence.reminder(day: TodoDay(expectedReminder)!, minutes: minutes, timeZone: currentZone)
            XCTAssertEqual(next.remindAt, nyExpected)
            if expectedReminder == "2026-11-01" {
                XCTAssertEqual(next.remindAt, ISO8601DateFormatter().date(from: "2026-11-01T05:30:00Z"))
            }
            currentZone = zone; try service.refreshRepeatingReminderTimes()
            XCTAssertEqual(next.remindAt, TodoRecurrence.reminder(day: TodoDay(expectedReminder)!, minutes: minutes, timeZone: zone))
            currentZone = TimeZone(identifier: "America/New_York")!; try service.refreshRepeatingReminderTimes()
            XCTAssertEqual(next.remindAt, nyExpected)
            try TodoIntegrity.validate(context: context)
        }
        let container = try PersistenceContainerFactory.makeInMemory()
        let service = TodoTaskService(context: container.mainContext, timeZone: { self.zone })
        XCTAssertThrowsError(try service.create(TodoDraft(title: "Too far", plannedDay: "2026-01-10", remindAt: date("2024-01-01"), frequency: .monthly)))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TodoTask>()), 0)
    }

    func testFutureEditRollbackAndWithdrawnReuseDoNotResurrectCanceledHistory() throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let service = TodoTaskService(context: context, now: { self.date("2026-01-10") }, timeZone: { self.zone })
        let first = try service.create(TodoDraft(title: "Old", plannedDay: "2026-01-10", remindAt: TodoRecurrence.reminder(day: TodoDay("2026-01-09")!, minutes: 1200, timeZone: zone), frequency: .monthly))
        try service.transition(id: first.id, to: .completed)
        let next = try XCTUnwrap(context.fetch(FetchDescriptor<TodoTask>()).first { $0.state == .open })
        let nextID = next.id
        var draft = TodoDraft(first); draft.title = "New"; draft.remindAt = TodoRecurrence.reminder(day: TodoDay("2026-01-08")!, minutes: 600, timeZone: zone)
        enum Injected: Error { case fail }
        let bad = TodoTaskService(context: context, timeZone: { self.zone }, save: { throw Injected.fail })
        XCTAssertThrowsError(try bad.edit(id: first.id, draft: draft, futureSeries: true))
        XCTAssertEqual(try service.task(id: nextID).title, "Old")
        XCTAssertEqual(try context.fetch(FetchDescriptor<TodoSeries>()).first?.reminderDayOffset, -1)
        try service.edit(id: first.id, draft: draft, futureSeries: true)
        XCTAssertEqual(next.reminderLocalDay, "2026-02-08"); XCTAssertEqual(next.reminderMinutes, 600)
        try service.transition(id: first.id, to: .open)
        var newer = TodoDraft(first); newer.title = "Newest"
        try service.edit(id: first.id, draft: newer, futureSeries: true)
        try service.transition(id: first.id, to: .completed)
        XCTAssertEqual(next.id, nextID); XCTAssertEqual(next.title, "Newest"); XCTAssertEqual(next.state, .open)
        try service.transition(id: next.id, to: .canceled)
        let canceledEvents = try context.fetch(FetchDescriptor<TodoTaskEvent>()).filter { $0.taskID == nextID }.map(TodoTaskEventTransfer.init)
        newer.title = "After cancellation"; try service.edit(id: first.id, draft: newer, futureSeries: true)
        XCTAssertEqual(next.title, "Newest"); XCTAssertEqual(next.state, .canceled)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TodoTaskEvent>()).filter { $0.taskID == nextID }.map(TodoTaskEventTransfer.init), canceledEvents)
        try service.transition(id: first.id, to: .open); try service.transition(id: first.id, to: .completed)
        XCTAssertEqual(next.state, .canceled)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TodoTask>()).filter { $0.state == .open }.count, 1)
        try TodoIntegrity.validate(context: context)
    }

    func testTodoIntegrityFailureOffersRawByteRecoveryAndDoesNotReconcileMedia() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
        try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        let media = root.appendingPathComponent("Media/Originals/unreferenced-original.bin")
        try FileManager.default.createDirectory(at: media.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("PRIVATE original immutable bytes".utf8); try original.write(to: media)
        let orphanTaskID = UUID()
        try autoreleasepool {
            let container = try PersistenceContainerFactory.makeOnDisk(at: store)
            let entry = Entry(body: "PRIVATE retained entry", createdAt: date("2026-10-09")); container.mainContext.insert(entry)
            let task = try TodoTaskService(context: container.mainContext).create(TodoDraft(title: "corrupt"))
            task.revision = 99
            let event = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TodoTaskEvent>()).first)
            event.taskID = orphanTaskID
            try container.mainContext.save()
        }
        var sourceReader: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(store.path, &sourceReader, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(sourceReader) }
        sqlite3_busy_timeout(sourceReader, 1_000)
        XCTAssertEqual(sqlite3_exec(sourceReader, "BEGIN; SELECT Z_PLIST FROM Z_METADATA", nil, nil, nil), SQLITE_OK)
        let originalSQLite = try Data(contentsOf: store)
        let config = AppConfiguration(launchMode: .uiTesting, resetDataOnLaunch: false)
        do { _ = try AppContainer.make(configuration: config, rootURLOverride: root); XCTFail("Must stop normal startup") }
        catch let failure as StartupRetainedDataFailure {
            let retained = try XCTUnwrap(failure.retained)
            XCTAssertFalse(failure.diagnostic.report.contains("PRIVATE"))
            let frozenBytes = try Data(contentsOf: retained.snapshotURL.appendingPathComponent("Store/PersonalGrowthOS.sqlite"))
            XCTAssertEqual(frozenBytes, originalSQLite)
            XCTAssertEqual(try Data(contentsOf: media), original)
            let archive = try retained.archive(diagnostic: failure.diagnostic.report)
            let extracted = root.appendingPathComponent("Extracted")
            try ZIPArchiveReader(archiveURL: archive, availableCapacity: .max).extractAll(to: extracted)
            XCTAssertEqual(try Data(contentsOf: extracted.appendingPathComponent("Store/PersonalGrowthOS.sqlite")), originalSQLite)
            XCTAssertEqual(try Data(contentsOf: extracted.appendingPathComponent("Media/Originals/unreferenced-original.bin")), original)
            let restored = try PersistenceContainerFactory.makeOnDisk(at: extracted.appendingPathComponent("Store/PersonalGrowthOS.sqlite"))
            XCTAssertEqual(try restored.mainContext.fetch(FetchDescriptor<Entry>()).first?.body, "PRIVATE retained entry")
            XCTAssertEqual(try restored.mainContext.fetch(FetchDescriptor<TodoTask>()).first?.revision, 99)
            XCTAssertEqual(try restored.mainContext.fetch(FetchDescriptor<TodoTaskEvent>()).first?.taskID, orphanTaskID)
            XCTAssertThrowsError(try TodoIntegrity.validate(context: restored.mainContext))
        }
        catch { XCTFail("Wrong recovery failure: \(error)") }
    }
}

@MainActor
extension TodoFoundationTests {
    func testConvertOpenTaskKeepsIdentitySourceHistoryAndRetryIsIdempotentForEveryFrequency() throws {
        for frequency in TodoFrequency.allCases {
            let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
            let service = TodoTaskService(context: context, now: { self.date("2026-01-31") }, timeZone: { self.zone })
            let entry = Entry(body: "Original untouched", createdAt: date("2026-01-30")); context.insert(entry); try context.save()
            let list = try service.createList(name: "Personal")
            let task = try service.create(TodoDraft(title: "Keep title", notes: "Keep notes", isImportant: true, plannedDay: "2026-01-31", deadlineDay: "2026-02-01", remindAt: TodoRecurrence.reminder(day: TodoDay("2026-01-30")!, minutes: 1200, timeZone: zone), listID: list.id), sourceEntryID: entry.id)
            let id = task.id, created = task.createdAt
            try service.transition(id: id, to: .canceled); try service.transition(id: id, to: .open)
            let oldHistory = try context.fetch(FetchDescriptor<TodoTaskEvent>()).map(TodoTaskEventTransfer.init)
            let source = try XCTUnwrap(context.fetch(FetchDescriptor<TodoTaskSource>()).first)
            var draft = TodoDraft(task); draft.frequency = frequency
            try service.edit(id: id, draft: draft)
            XCTAssertEqual(task.id, id); XCTAssertEqual(task.createdAt, created)
            XCTAssertEqual(task.title, "Keep title"); XCTAssertEqual(task.notes, "Keep notes"); XCTAssertTrue(task.isImportant)
            XCTAssertEqual(task.listID, list.id); XCTAssertEqual(task.occurrenceIndex, 0)
            XCTAssertEqual(task.occurrenceKey, "\(task.seriesID!.uuidString)/0")
            XCTAssertEqual(source.entryID, entry.id); XCTAssertEqual(source.taskID, id)
            let allHistory = try context.fetch(FetchDescriptor<TodoTaskEvent>()).map(TodoTaskEventTransfer.init)
            XCTAssertTrue(oldHistory.allSatisfy { allHistory.contains($0) })
            XCTAssertEqual(task.revision, 3)
            try service.edit(id: id, draft: draft)
            XCTAssertEqual(task.revision, 3); XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoSeries>()), 1)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTask>()), 1)
            try service.transition(id: id, to: .completed)
            let next = try XCTUnwrap(context.fetch(FetchDescriptor<TodoTask>()).first { $0.state == .open })
            let nextID = next.id
            XCTAssertEqual(try TodoRecurrence.reminderOffset(localDay: next.reminderLocalDay!, anchor: next.plannedDay!), -1)
            try service.transition(id: id, to: .open); try service.transition(id: id, to: .completed)
            XCTAssertEqual(next.id, nextID); XCTAssertEqual(next.state, .open)
            try service.transition(id: nextID, to: .canceled, skip: true)
            let third = try XCTUnwrap(context.fetch(FetchDescriptor<TodoTask>()).first { $0.state == .open })
            try service.stopSeries(taskID: third.id)
            try service.transition(id: id, to: .open); try service.transition(id: id, to: .completed)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTask>()), 3)
            XCTAssertEqual(try context.fetch(FetchDescriptor<TodoTask>()).filter { $0.state == .open }.count, 0)
            XCTAssertEqual(entry.body, "Original untouched"); XCTAssertEqual(entry.updatedAt, date("2026-01-30"))
            try TodoIntegrity.validate(context: context)
        }
    }

    func testConversionRejectsMissingDayClosedTaskRuleChangeAndRollsBackBeforeSave() throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let service = TodoTaskService(context: context, now: { self.date("2026-01-31") }, timeZone: { self.zone })
        let task = try service.create(TodoDraft(title: "Undated"))
        var draft = TodoDraft(task); draft.frequency = .daily
        XCTAssertThrowsError(try service.edit(id: task.id, draft: draft))
        XCTAssertNil(task.seriesID); XCTAssertEqual(task.revision, 0)
        draft.deadlineDay = "2026-01-31"
        for state in [TodoTaskState.completed, .canceled] {
            try service.transition(id: task.id, to: state)
            XCTAssertThrowsError(try service.edit(id: task.id, draft: draft)) { XCTAssertEqual($0 as? TodoFailure, .conversionRequiresOpen) }
            XCTAssertNil(task.seriesID); try service.transition(id: task.id, to: .open)
        }
        let count = try context.fetchCount(FetchDescriptor<TodoTaskEvent>())
        enum Injected: Error { case fail }
        let bad = TodoTaskService(context: context, save: { throw Injected.fail })
        XCTAssertThrowsError(try bad.edit(id: task.id, draft: draft))
        XCTAssertNil(try service.task(id: task.id).seriesID)
        XCTAssertNil(task.deadlineDay)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoSeries>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTaskEvent>()), count)
        try service.edit(id: task.id, draft: draft)
        var changed = draft; changed.frequency = .weekly
        XCTAssertThrowsError(try service.edit(id: task.id, draft: changed))
        XCTAssertEqual(try context.fetch(FetchDescriptor<TodoSeries>()).first?.frequencyRawValue, "daily")
        try TodoIntegrity.validate(context: context)
    }

    func testConvertedTaskAndOriginalEventsSurviveDiskRestartAndGenerateOnce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("store.sqlite")
        var id: UUID!, created: Date!, history: [TodoTaskEventTransfer] = []
        try autoreleasepool {
            let container = try PersistenceContainerFactory.makeOnDisk(at: url), context = container.mainContext
            let service = TodoTaskService(context: context, now: { self.date("2026-01-31") })
            let task = try service.create(TodoDraft(title: "Original", plannedDay: "2026-01-31"))
            id = task.id; created = task.createdAt
            var draft = TodoDraft(task); draft.frequency = .weekly
            try service.edit(id: id, draft: draft)
            history = try context.fetch(FetchDescriptor<TodoTaskEvent>()).map(TodoTaskEventTransfer.init)
        }
        for _ in 0..<2 {
            try autoreleasepool {
                let container = try PersistenceContainerFactory.makeOnDisk(at: url), context = container.mainContext
                let service = TodoTaskService(context: context, now: { self.date("2026-01-31") })
                let task = try service.task(id: id)
                XCTAssertEqual(task.createdAt, created); XCTAssertNotNil(task.seriesID)
                XCTAssertTrue(history.allSatisfy { event in (try? context.fetch(FetchDescriptor<TodoTaskEvent>()).map(TodoTaskEventTransfer.init).contains(event)) == true })
                try service.transition(id: id, to: .completed)
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTask>()), 2)
                XCTAssertEqual(try context.fetch(FetchDescriptor<TodoTask>()).first { $0.state == .open }?.plannedDay, "2026-02-07")
                XCTAssertEqual(task.state, .completed); XCTAssertEqual(task.revision, 2)
                try TodoIntegrity.validate(context: context)
            }
        }
    }
}

@MainActor
extension TodoFoundationTests {
    func testAllStatusDateListKeywordCompositionAndStatisticsRemainExact() throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let clock = date("2026-10-09")
        let service = TodoTaskService(context: context, now: { clock }, timeZone: { self.zone })
        let list = try service.createList(name: "A")
        let open = try service.create(TodoDraft(title: "Match open", listID: list.id))
        let done = try service.create(TodoDraft(title: "Match done", listID: list.id))
        let canceled = try service.create(TodoDraft(title: "Match canceled", listID: list.id))
        let overdue = try service.create(TodoDraft(title: "Match overdue", isImportant: true, plannedDay: "2026-10-10", deadlineDay: "2026-10-08"))
        let upcoming = try service.create(TodoDraft(title: "Unrelated", plannedDay: "2026-10-10"))
        try service.transition(id: done.id, to: .completed); try service.transition(id: canceled.id, to: .canceled)
        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        for (state, ids) in [(TodoStatusFilter.open, [open.id, overdue.id, upcoming.id]), (.all, tasks.map(\.id)), (.completed, [done.id]), (.canceled, [canceled.id])] {
            XCTAssertEqual(Set(tasks.filter { TodoQuery.matches($0, filter: .all, now: clock, timeZone: zone, status: state) }.map(\.id)), Set(ids))
        }
        XCTAssertEqual(tasks.filter { TodoQuery.matches($0, filter: .all, now: clock, status: .all, listID: list.id, keyword: "MATCH") }.count, 3)
        XCTAssertEqual(tasks.filter { TodoQuery.matches($0, filter: .all, now: clock, status: .completed, listID: list.id, keyword: "done") }.map(\.id), [done.id])
        XCTAssertTrue(tasks.filter { TodoQuery.matches($0, filter: .all, now: clock, status: .completed, unclassifiedOnly: true, keyword: "match") }.isEmpty)
        XCTAssertEqual(tasks.filter { TodoQuery.matches($0, filter: .all, now: clock, status: .all, unclassifiedOnly: true, keyword: "match") }.map(\.id), [overdue.id])
        XCTAssertEqual(tasks.filter { TodoQuery.matches($0, filter: .today, now: clock, timeZone: zone, status: .completed) }.map(\.id), [overdue.id])
        XCTAssertEqual(tasks.filter { TodoQuery.matches($0, filter: .upcoming, now: clock, timeZone: zone) }.map(\.id), [upcoming.id])
        for (filter, ids) in [(TodoFilter.completedToday, [done.id]), (.completedWeek, [done.id]), (.open, [open.id, overdue.id, upcoming.id]), (.overdue, [overdue.id])] {
            XCTAssertEqual(Set(tasks.filter { TodoQuery.matches($0, filter: filter, now: clock, timeZone: zone, status: .open) }.map(\.id)), Set(ids))
        }
        XCTAssertEqual(TodoQuery.sorted(tasks).first?.id, overdue.id)
        try service.transition(id: done.id, to: .open)
        XCTAssertFalse(TodoQuery.matches(done, filter: .all, now: clock, status: .completed))
        XCTAssertFalse(TodoQuery.matches(done, filter: .completedToday, now: clock))
        XCTAssertTrue(TodoQuery.matches(done, filter: .all, now: clock, status: .open))
        XCTAssertEqual(Set(try LocalSearchService(context: context).search("Match").todos.map(\.id)), Set([open.id, done.id, canceled.id, overdue.id]))
    }
}

private final class FailingStartupCopyManager: FileManager, @unchecked Sendable {
    let failureCode: Int
    var copyAttempts = 0
    init(_ code: Int) { failureCode = code; super.init() }
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        copyAttempts += 1
        throw NSError(domain: NSPOSIXErrorDomain, code: failureCode)
    }
}

extension TodoFoundationTests {
    func testHealthyStartupDoesNotRequireCopyUnderIOErrorOrNoSpace() throws {
        for code in [5, 28] { // EIO / ENOSPC at the protective copy boundary.
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let config = AppConfiguration(launchMode: .uiTesting, resetDataOnLaunch: false)
            try autoreleasepool {
                let app = try AppContainer.make(configuration: config, rootURLOverride: root)
                app.modelContainer.mainContext.insert(Entry(body: "healthy preserved", createdAt: Date()))
                try app.modelContainer.mainContext.save()
            }
            let manager = FailingStartupCopyManager(code)
            do {
                let reopened = try AppContainer.make(configuration: config, fileManager: manager, rootURLOverride: root)
                XCTAssertEqual(manager.copyAttempts, 0)
                XCTAssertEqual(try reopened.modelContainer.mainContext.fetch(FetchDescriptor<Entry>()).first?.body, "healthy preserved")
            } catch { XCTFail("Healthy startup blocked by copy errno \(code): \(error)") }
        }
    }

    func testRecoveryCaptureReusesDurableSnapshotAcrossRetryAndRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
        try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try autoreleasepool {
            let container = try PersistenceContainerFactory.makeOnDisk(at: store)
            _ = try TodoTaskService(context: container.mainContext).create(TodoDraft(title: "retained"))
        }
        let first = try StartupRetainedData.capture(rootURL: root)
        XCTAssertTrue(first.snapshotURL.path.hasPrefix(root.path + "/"), "Recovery must live in Application Support, beside the source root")
        for _ in 0..<4 {
            let retry = try StartupRetainedData.capture(rootURL: root)
            XCTAssertEqual(retry.snapshotURL, first.snapshotURL)
        }
    }
}

extension TodoFoundationTests {
    func testMigrationCopyFailureStopsBeforeOpeningOriginalV10() throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Build12V10Fixture", withExtension: nil))
        for code in [5, 28] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = root.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
            try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: fixture.appendingPathComponent("PersonalGrowthOS.sqlite"), to: store)
            let bytes = try Data(contentsOf: store)
            XCTAssertFalse(StartupStoreProtection.isCurrentStore(at: store))
            let manager = FailingStartupCopyManager(code)
            XCTAssertThrowsError(try AppContainer.make(configuration: AppConfiguration(launchMode: .uiTesting, resetDataOnLaunch: false), fileManager: manager, rootURLOverride: root)) { error in
                XCTAssertEqual((error as? AppDiagnosticFailure)?.diagnostic.startupStep, .preMigrationProtection)
                XCTAssertEqual((error as? AppDiagnosticFailure)?.diagnostic.protectionStep, .storeCopy)
            }
            XCTAssertEqual(manager.copyAttempts, 1)
            XCTAssertEqual(try Data(contentsOf: store), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Recovery/BeforeMigration").path))
        }
    }

    func testRecoveryWALBytesAreConsistentAndConcurrentWriterIsExcluded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
        try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(store.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE Z_METADATA (Z_PLIST BLOB); INSERT INTO Z_METADATA VALUES (X'01'); CREATE TABLE evidence (value TEXT); INSERT INTO evidence VALUES ('committed WAL fact');", nil, nil, nil), SQLITE_OK)
        let wal = URL(fileURLWithPath: store.path + "-wal")
        let sqliteBytes = try Data(contentsOf: store), walBytes = try Data(contentsOf: wal)
        XCTAssertGreaterThan(walBytes.count, 32)
        try StartupStoreProtection.withFrozenStore(at: store) {
            XCTAssertEqual(sqlite3_exec(db, "INSERT INTO evidence VALUES ('must not write')", nil, nil, nil), SQLITE_BUSY)
        }
        let retained = try StartupRetainedData.capture(rootURL: root)
        XCTAssertEqual(try Data(contentsOf: retained.snapshotURL.appendingPathComponent("Store/PersonalGrowthOS.sqlite")), sqliteBytes)
        XCTAssertEqual(try Data(contentsOf: retained.snapshotURL.appendingPathComponent("Store/PersonalGrowthOS.sqlite-wal")), walBytes)
        XCTAssertEqual(try Data(contentsOf: store), sqliteBytes)
        XCTAssertEqual(try Data(contentsOf: wal), walBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: retained.snapshotURL.appendingPathComponent("Store/PersonalGrowthOS.sqlite-shm").path))
        let archive = try retained.archive(diagnostic: "synthetic WAL")
        let extracted = root.appendingPathComponent("Extracted")
        try ZIPArchiveReader(archiveURL: archive, availableCapacity: .max).extractAll(to: extracted)
        var recovered: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(extracted.appendingPathComponent("Store/PersonalGrowthOS.sqlite").path, &recovered, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(recovered) }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(recovered, "SELECT value FROM evidence", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(String(cString: sqlite3_column_text(statement, 0)), "committed WAL fact")
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
    }

    func testCorruptStartupRetryRestartTempPurgeAndExportFailurePreserveOnlySnapshot() async throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let root = support.appendingPathComponent("P1-Synthetic-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = AppConfiguration(launchMode: .uiTesting, resetDataOnLaunch: false)
        try autoreleasepool {
            let app = try AppContainer.make(configuration: config, rootURLOverride: root)
            let task = try TodoTaskService(context: app.modelContainer.mainContext).create(TodoDraft(title: "broken identity"))
            task.revision = 90
            try app.modelContainer.mainContext.save()
        }
        var snapshot: URL?
        for attempt in 0..<5 {
            try autoreleasepool {
                do { _ = try AppContainer.make(configuration: config, rootURLOverride: root); XCTFail("Normal writers must stop") }
                catch let failure as StartupRetainedDataFailure {
                    XCTAssertNil(failure.snapshotFailure)
                    let retained = try XCTUnwrap(failure.retained)
                    if let snapshot { XCTAssertEqual(retained.snapshotURL, snapshot) }
                    else { snapshot = retained.snapshotURL }
                    let bytes = try Data(contentsOf: retained.snapshotURL.appendingPathComponent("Store/PersonalGrowthOS.sqlite"))
                    if attempt == 0 {
                        let archive = try retained.archive(diagnostic: "test")
                        let firstArchive = try Data(contentsOf: archive)
                        for code in [5, 28] {
                            XCTAssertThrowsError(try retained.archive(diagnostic: "retry", write: { _, partial in
                                try Data("partial".utf8).write(to: partial)
                                throw NSError(domain: NSPOSIXErrorDomain, code: code)
                            }))
                            XCTAssertEqual(try Data(contentsOf: archive), firstArchive)
                            XCTAssertEqual(try Data(contentsOf: retained.snapshotURL.appendingPathComponent("Store/PersonalGrowthOS.sqlite")), bytes)
                            XCTAssertFalse(FileManager.default.fileExists(atPath: retained.snapshotURL.appendingPathComponent(".export-building.zip").path))
                        }
                        XCTAssertThrowsError(try retained.archive(diagnostic: "cancel", write: { _, partial in
                            try Data("partial cancellation".utf8).write(to: partial)
                            throw CancellationError()
                        })) { XCTAssertTrue($0 is CancellationError) }
                        XCTAssertEqual(try Data(contentsOf: archive), firstArchive)
                        XCTAssertEqual(try Data(contentsOf: retained.snapshotURL.appendingPathComponent("Store/PersonalGrowthOS.sqlite")), bytes)
                        let disposableTemp = FileManager.default.temporaryDirectory.appendingPathComponent("P1-Disposable-" + UUID().uuidString)
                        try FileManager.default.createDirectory(at: disposableTemp, withIntermediateDirectories: true)
                        try firstArchive.write(to: disposableTemp.appendingPathComponent("temporary-export.zip"))
                        try FileManager.default.removeItem(at: disposableTemp)
                        XCTAssertTrue(FileManager.default.fileExists(atPath: retained.snapshotURL.path))
                    }
                }
            }
        }
        let slots = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Recovery").path).filter { !$0.hasPrefix(".") }
        XCTAssertEqual(slots.count, 1)
        let retained = StartupRetainedData(rootURL: root, snapshotURL: try XCTUnwrap(snapshot))
        let archive = try retained.archive(diagnostic: "final")
        let empty = try PersistenceContainerFactory.makeInMemory()
        do {
            _ = try await ImportExportService(context: empty.mainContext, mediaStore: MediaStore(rootURL: root.appendingPathComponent("EmptyMedia")), availableCapacity: { .max }).previewPackage(from: archive)
            XCTFail("raw recovery ZIP must not be accepted as v7")
        } catch { XCTAssertEqual((error as? AppDiagnosticFailure)?.underlying as? ZIPArchiveError ?? error as? ZIPArchiveError, .missingMember("manifest.json/data.json")) }
        XCTAssertEqual(try empty.mainContext.fetchCount(FetchDescriptor<TodoTask>()), 0)
    }
}

extension TodoFoundationTests {
    func testRealLowSpaceVolumeHealthyOpenMigrationAndCorruptCopyFailure() throws {
        let fm = FileManager.default
        let volume = URL(fileURLWithPath: "/private/tmp/pgos-p1-low-space")
        guard fm.fileExists(atPath: volume.appendingPathComponent("RUN_LOW_SPACE_TEST").path) else {
            throw XCTSkip("Requires the isolated 32MB HFS+ test image; never fill the primary volume")
        }
        let root = volume.appendingPathComponent("Synthetic-" + UUID().uuidString)
        let filler = volume.appendingPathComponent("Filler-" + UUID().uuidString)
        defer { try? fm.removeItem(at: filler); try? fm.removeItem(at: root) }
        let healthy = root.appendingPathComponent("Healthy"), legacy = root.appendingPathComponent("Legacy"), broken = root.appendingPathComponent("Broken")
        let config = AppConfiguration(launchMode: .uiTesting, resetDataOnLaunch: false)
        try autoreleasepool {
            let app = try AppContainer.make(configuration: config, rootURLOverride: healthy)
            app.modelContainer.mainContext.insert(Entry(body: "low-space evidence", createdAt: Date()))
            try app.modelContainer.mainContext.save()
            let corrupt = try AppContainer.make(configuration: config, rootURLOverride: broken)
            let task = try TodoTaskService(context: corrupt.modelContainer.mainContext).create(TodoDraft(title: "invalid"))
            task.revision = 99; try corrupt.modelContainer.mainContext.save()
        }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Build12V10Fixture", withExtension: nil))
        try fm.createDirectory(at: legacy.appendingPathComponent("Store"), withIntermediateDirectories: true)
        try fm.copyItem(at: fixture.appendingPathComponent("PersonalGrowthOS.sqlite"), to: legacy.appendingPathComponent("Store/PersonalGrowthOS.sqlite"))
        // Non-cloneable real bytes on HFS+: each full Store copy needs >4MiB.
        let block = Data(repeating: 0x5a, count: 4 * 1_024 * 1_024)
        for directory in [healthy, legacy, broken] { try block.write(to: directory.appendingPathComponent("Store/large-fixture.bin")) }
        let legacyBytes = try Data(contentsOf: legacy.appendingPathComponent("Store/PersonalGrowthOS.sqlite"))
        XCTAssertTrue(fm.createFile(atPath: filler.path, contents: nil))
        let handle = try FileHandle(forWritingTo: filler)
        func freeBytes() throws -> Int64 { (try fm.attributesOfFileSystem(forPath: volume.path)[.systemFreeSize] as! NSNumber).int64Value }
        while try freeBytes() > 1_500_000 { try handle.write(contentsOf: Data(repeating: 0x67, count: 256 * 1_024)) }
        try handle.close()
        XCTAssertLessThan(try freeBytes(), 4 * 1_024 * 1_024)
        let duplicate = root.appendingPathComponent("ImpossibleCopy")
        XCTAssertThrowsError(try fm.copyItem(at: healthy.appendingPathComponent("Store"), to: duplicate)) { error in
            let ns = error as NSError
            XCTAssertTrue(ns.code == NSFileWriteOutOfSpaceError || (ns.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == Int(ENOSPC), "\(ns)")
        }
        try? fm.removeItem(at: duplicate)
        try autoreleasepool {
            let app = try AppContainer.make(configuration: config, rootURLOverride: healthy)
            XCTAssertEqual(try app.modelContainer.mainContext.fetch(FetchDescriptor<Entry>()).first?.body, "low-space evidence")
            app.modelContainer.mainContext.insert(Entry(body: "writes still usable", createdAt: Date()))
            try app.modelContainer.mainContext.save()
            XCTAssertEqual(try app.modelContainer.mainContext.fetchCount(FetchDescriptor<Entry>()), 2)
        }
        XCTAssertThrowsError(try AppContainer.make(configuration: config, rootURLOverride: legacy))
        XCTAssertEqual(try Data(contentsOf: legacy.appendingPathComponent("Store/PersonalGrowthOS.sqlite")), legacyBytes)
        do { _ = try AppContainer.make(configuration: config, rootURLOverride: broken); XCTFail("Never allow normal writes when snapshot fails") }
        catch let failure as StartupRetainedDataFailure {
            XCTAssertNil(failure.retained)
            XCTAssertEqual(failure.snapshotFailure?.category, .capacity, failure.snapshotFailure?.report ?? "No snapshot diagnostic")
        }
        try fm.removeItem(at: filler)
        do { _ = try AppContainer.make(configuration: config, rootURLOverride: broken); XCTFail("Still corrupt after space returns") }
        catch let failure as StartupRetainedDataFailure {
            XCTAssertNotNil(failure.retained)
            XCTAssertNil(failure.snapshotFailure)
        }
    }
}

private final class Cocoa259StartupCopyManager: FileManager, @unchecked Sendable {
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        throw NSError(domain: NSCocoaErrorDomain, code: 259, userInfo: [NSFilePathErrorKey: "PRIVATE-COPY-PATH", NSLocalizedDescriptionKey: "PRIVATE-COPY-PATH"])
    }
}

private final class CheckpointStartupCopyManager: FileManager, @unchecked Sendable {
    let checkpoint: () -> Void
    init(checkpoint: @escaping () -> Void) { self.checkpoint = checkpoint; super.init() }
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        checkpoint()
        try super.copyItem(at: srcURL, to: dstURL)
    }
}

extension TodoFoundationTests {
    func testAliasedProtectionRawArchiveKeepsNamesAndRejectsInternalSymlinks() throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: work) }
        let physical = work.appendingPathComponent("Physical"), alias = work.appendingPathComponent("DifferentLengthAlias")
        let config = AppConfiguration(launchMode: .uiTesting, resetDataOnLaunch: false)
        try autoreleasepool {
            let app = try AppContainer.make(configuration: config, rootURLOverride: physical)
            app.modelContainer.mainContext.insert(Entry(body: "synthetic alias recovery", createdAt: Date()))
            try app.modelContainer.mainContext.save()
        }
        try fm.createSymbolicLink(at: alias, withDestinationURL: physical)
        let media = physical.appendingPathComponent("Media/synthetic.bin")
        try fm.createDirectory(at: media.deletingLastPathComponent(), withIntermediateDirectories: true)
        let mediaBytes = Data("synthetic raw media".utf8)
        try mediaBytes.write(to: media)
        let first = try StartupRetainedData.capture(rootURL: alias, purpose: .beforeMigration)
        let expectedStore = try Data(contentsOf: first.snapshotURL.appendingPathComponent("Store/PersonalGrowthOS.sqlite"))
        XCTAssertEqual(try StartupRetainedData.capture(rootURL: physical, purpose: .beforeMigration).snapshotURL.resolvingSymlinksInPath(), first.snapshotURL.resolvingSymlinksInPath())
        let archive = try first.archive(diagnostic: "synthetic alias")
        let extracted = work.appendingPathComponent("Extracted")
        try ZIPArchiveReader(archiveURL: archive, availableCapacity: .max).extractAll(to: extracted)
        XCTAssertEqual(try Data(contentsOf: extracted.appendingPathComponent("Store/PersonalGrowthOS.sqlite")), expectedStore)
        XCTAssertEqual(try Data(contentsOf: extracted.appendingPathComponent("Media/synthetic.bin")), mediaBytes)
        XCTAssertFalse(fm.fileExists(atPath: extracted.appendingPathComponent("Recovery").path))
        XCTAssertFalse(fm.fileExists(atPath: extracted.appendingPathComponent("DifferentLengthAlias").path))
        let outside = work.appendingPathComponent("Outside.bin")
        try Data("synthetic outside".utf8).write(to: outside)
        let unsafe = physical.appendingPathComponent("Store/linked.bin")
        try fm.createSymbolicLink(at: unsafe, withDestinationURL: outside)
        XCTAssertThrowsError(try StartupRetainedData.capture(rootURL: alias, purpose: .beforeMigration)) { error in
            XCTAssertEqual((error as? AppDiagnosticFailure)?.underlying as? ZIPArchiveError, .unsafePath)
            XCTAssertEqual((error as? AppDiagnosticFailure)?.diagnostic.protectionStep, .sourceSignature)
        }
        XCTAssertEqual(try Data(contentsOf: first.snapshotURL.appendingPathComponent("Store/PersonalGrowthOS.sqlite")), expectedStore)
        try fm.removeItem(at: unsafe) // Only this test's deliberate link.
        try fm.createSymbolicLink(at: physical.appendingPathComponent("linked-media.bin"), withDestinationURL: outside)
        XCTAssertThrowsError(try first.archive(diagnostic: "synthetic alias")) { error in
            XCTAssertEqual(error as? ZIPArchiveError, .unsafePath)
        }
        XCTAssertEqual(try Data(contentsOf: extracted.appendingPathComponent("Media/synthetic.bin")), mediaBytes)
    }

    func testCocoa259DuringCopyIsLocatedAndDoesNotMigrateOrPublish() throws {
        let fm = FileManager.default
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Build12V10Fixture", withExtension: nil))
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        try fm.copyItem(at: fixture, to: root)
        let store = root.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
        try fm.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: root.appendingPathComponent("PersonalGrowthOS.sqlite"), to: store)
        let before = try Data(contentsOf: store)
        XCTAssertThrowsError(try AppContainer.make(configuration: AppConfiguration(launchMode: .uiTesting, resetDataOnLaunch: false), fileManager: Cocoa259StartupCopyManager(), rootURLOverride: root)) { error in
            let diagnostic = (error as? AppDiagnosticFailure)?.diagnostic
            XCTAssertEqual(diagnostic?.startupStep, .preMigrationProtection)
            XCTAssertEqual(diagnostic?.protectionStep, .storeCopy)
            XCTAssertEqual(diagnostic?.domain, NSCocoaErrorDomain)
            XCTAssertEqual(diagnostic?.code, 259)
            XCTAssertFalse(diagnostic?.report.contains("PRIVATE-COPY-PATH") ?? true)
        }
        XCTAssertEqual(try Data(contentsOf: store), before)
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("Recovery/BeforeMigration").path))
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("Recovery/.BeforeMigration-building").path))
        XCTAssertFalse(StartupStoreProtection.isCurrentStore(at: store))
        let app = try AppContainer.make(configuration: AppConfiguration(launchMode: .uiTesting, resetDataOnLaunch: false), rootURLOverride: root)
        XCTAssertFalse(try app.modelContainer.mainContext.fetch(FetchDescriptor<Entry>()).isEmpty)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Recovery/BeforeMigration/Store/PersonalGrowthOS.sqlite")), before)
    }

    func testBuild12V10ContainerAliasMigratesWithoutFalseMissingStore259() async throws {
        let fm = FileManager.default
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Build12V10Fixture", withExtension: nil))
        let work = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: work) }
        let physical = work.appendingPathComponent("Physical")
        let alias = work.appendingPathComponent("LongContainerAlias")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        try fm.copyItem(at: fixture, to: physical)
        try fm.createSymbolicLink(at: alias, withDestinationURL: physical)
        let store = physical.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
        try fm.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: physical.appendingPathComponent("PersonalGrowthOS.sqlite"), to: store)
        let before = try Data(contentsOf: store)
        let expectedRoot = work.appendingPathComponent("Expected")
        try ZIPArchiveReader(archiveURL: fixture.appendingPathComponent("expected-v6.zip"), availableCapacity: .max).extractAll(to: expectedRoot)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let expected = try decoder.decode(TransferData.self, from: Data(contentsOf: expectedRoot.appendingPathComponent("data.json")))
        // Foundation returns physical child URLs even when enumeration starts
        // from an alias. The old signature code truncated using alias length.
        let aliasStore = alias.appendingPathComponent("Store", isDirectory: true)
        let children = try XCTUnwrap(fm.enumerator(at: aliasStore, includingPropertiesForKeys: nil)?.allObjects as? [URL])
        let child = try XCTUnwrap(children.first { $0.lastPathComponent == "PersonalGrowthOS.sqlite" })
        XCTAssertFalse(child.path.hasPrefix(aliasStore.path + "/"))
        let config = AppConfiguration(launchMode: .uiTesting, resetDataOnLaunch: false)
        for (pass, root) in [alias, physical].enumerated() {
            let app: AppContainer
            do { app = try AppContainer.make(configuration: config, rootURLOverride: root) }
            catch let failure as AppDiagnosticFailure {
                XCTAssertEqual(failure.diagnostic.startupStep, .preMigrationProtection)
                XCTAssertEqual(failure.diagnostic.domain, NSCocoaErrorDomain)
                XCTAssertEqual(failure.diagnostic.code, 259)
                XCTAssertEqual(try Data(contentsOf: store), before)
                XCTFail("Healthy V10 falsely rejected by path alias: \(failure.diagnostic.report)")
                return
            }
            XCTAssertEqual(try Data(contentsOf: physical.appendingPathComponent("Recovery/BeforeMigration/Store/PersonalGrowthOS.sqlite")), before)
            let lease = try await app.importExportService.exportPackage()
            defer { lease.cleanup() }
            let exported = work.appendingPathComponent("Export-\(pass)")
            try ZIPArchiveReader(archiveURL: lease.url, availableCapacity: .max).extractAll(to: exported)
            XCTAssertEqual(try decoder.decode(TransferData.self, from: Data(contentsOf: exported.appendingPathComponent("data.json"))), expected)
            for image in try app.modelContainer.mainContext.fetch(FetchDescriptor<ImageMetadata>()) {
                XCTAssertEqual(try Data(contentsOf: app.mediaStore.fileURL(for: image.relativePath)),
                               try Data(contentsOf: MediaStore(rootURL: fixture).fileURL(for: image.relativePath)))
            }
            try TodoIntegrity.validate(context: app.modelContainer.mainContext)
            try LinkIntegrityService.validate(context: app.modelContainer.mainContext)
        }
    }

    func testCorruptV10MetadataIsDistinguishedFromInvalidProtectionAndRetainsBytes() throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Build12V10Fixture", withExtension: nil))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
        try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture.appendingPathComponent("PersonalGrowthOS.sqlite"), to: store)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(store.path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "UPDATE Z_METADATA SET Z_PLIST=X'01';", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_close(db), SQLITE_OK)
        let before = try Data(contentsOf: store)
        for _ in 0..<2 {
            do {
                _ = try AppContainer.make(configuration: AppConfiguration(launchMode: .uiTesting, resetDataOnLaunch: false), rootURLOverride: root)
                XCTFail("Malformed metadata must not permit normal startup")
            } catch let failure as AppDiagnosticFailure {
                XCTAssertEqual(failure.diagnostic.stage, .storeOpen)
                XCTAssertEqual(failure.diagnostic.startupStep, .storeWritableOpen)
                XCTAssertTrue(failure.underlying is SwiftDataError)
                XCTAssertNil(failure.diagnostic.domain, "Unknown SwiftData domains must remain excluded from the diagnostic allowlist")
                XCTAssertNil(failure.diagnostic.code)
            }
            XCTAssertEqual(try Data(contentsOf: store), before)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Recovery/BeforeMigration/Store/PersonalGrowthOS.sqlite")), before)
        }
    }

    func testBuild12CommittedWALProtectionRetryAndMigrationPreserveEntryAndMedia() throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Build12V10Fixture", withExtension: nil))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: fixture, to: root)
        let store = root.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
        try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: root.appendingPathComponent("PersonalGrowthOS.sqlite"), to: store)
        let mainBefore = try Data(contentsOf: store)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(store.path, &db), SQLITE_OK)
        defer { if let db { sqlite3_close(db) } }
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA wal_autocheckpoint=0; UPDATE ZENTRY SET ZBODY='Synthetic committed WAL entry';", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(try Data(contentsOf: store), mainBefore, "Fact must still live in WAL, not the main database")
        let wal = store.deletingLastPathComponent().appendingPathComponent("PersonalGrowthOS.sqlite-wal")
        let walBefore = try Data(contentsOf: wal)
        XCTAssertGreaterThan(walBefore.count, 32)
        let first = try StartupRetainedData.capture(rootURL: root, purpose: .beforeMigration)
        XCTAssertEqual(try Data(contentsOf: store), mainBefore)
        XCTAssertEqual(try Data(contentsOf: wal), walBefore)
        let retainedStore = first.snapshotURL.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
        XCTAssertEqual(try Data(contentsOf: retainedStore), mainBefore)
        XCTAssertEqual(try Data(contentsOf: first.snapshotURL.appendingPathComponent("Store/PersonalGrowthOS.sqlite-wal")), walBefore)
        var retainedDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(retainedStore.path, &retainedDB, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { if let retainedDB { sqlite3_close(retainedDB) } }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(retainedDB, "SELECT ZBODY FROM ZENTRY", -1, &statement, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(String(cString: sqlite3_column_text(statement, 0)), "Synthetic committed WAL entry")
        sqlite3_finalize(statement)
        XCTAssertEqual(sqlite3_close(retainedDB), SQLITE_OK); retainedDB = nil
        XCTAssertEqual(try StartupRetainedData.capture(rootURL: root, purpose: .beforeMigration).snapshotURL, first.snapshotURL)
        XCTAssertEqual(sqlite3_close(db), SQLITE_OK); db = nil
        let app = try AppContainer.make(configuration: AppConfiguration(launchMode: .uiTesting, resetDataOnLaunch: false), rootURLOverride: root)
        XCTAssertEqual(try app.modelContainer.mainContext.fetch(FetchDescriptor<Entry>()).map(\.body), ["Synthetic committed WAL entry"])
        let images = try app.modelContainer.mainContext.fetch(FetchDescriptor<ImageMetadata>())
        XCTAssertFalse(images.isEmpty)
        for image in images {
            XCTAssertEqual(try Data(contentsOf: app.mediaStore.fileURL(for: image.relativePath)),
                           try Data(contentsOf: MediaStore(rootURL: fixture).fileURL(for: image.relativePath)))
        }
        try TodoIntegrity.validate(context: app.modelContainer.mainContext)
        try LinkIntegrityService.validate(context: app.modelContainer.mainContext)
    }

    func testInvalidBeforeMigrationSnapshotProduces259BeforeSwiftDataAndPreservesSource() throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Build12V10Fixture", withExtension: nil))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
        try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture.appendingPathComponent("PersonalGrowthOS.sqlite"), to: store)
        let retained = try StartupRetainedData.capture(rootURL: root, purpose: .beforeMigration)
        let snapshotStore = retained.snapshotURL.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
        let damaged = Data("synthetic damaged snapshot".utf8)
        try damaged.write(to: snapshotStore)
        let before = try Data(contentsOf: store)
        for _ in 0..<3 {
            do {
                _ = try AppContainer.make(configuration: AppConfiguration(launchMode: .uiTesting, resetDataOnLaunch: false), rootURLOverride: root)
                XCTFail("Invalid protection must not permit migration")
            } catch let failure as AppDiagnosticFailure {
                XCTAssertEqual(failure.diagnostic.stage, .storeOpen)
                XCTAssertEqual(failure.diagnostic.domain, NSCocoaErrorDomain)
                XCTAssertEqual(failure.diagnostic.code, 259)
                XCTAssertTrue(failure.diagnostic.report.contains("startupStep=snapshotValidation"))
                XCTAssertFalse(failure.diagnostic.report.contains("storeSchema=10"))
            }
            XCTAssertEqual(try Data(contentsOf: store), before)
            XCTAssertEqual(try Data(contentsOf: snapshotStore), damaged)
            XCTAssertFalse(StartupStoreProtection.isCurrentStore(at: store))
        }
    }
}

extension TodoFoundationTests {
    func testPassiveCheckpointRaceIsRejectedAndRetryCapturesConsistentRawFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
        try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(store.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE Z_METADATA (Z_PLIST BLOB); CREATE TABLE evidence (value TEXT); INSERT INTO evidence VALUES ('checkpoint fact');", nil, nil, nil), SQLITE_OK)
        let before = try Data(contentsOf: store)
        let manager = CheckpointStartupCopyManager {
            XCTAssertEqual(sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_PASSIVE, nil, nil), SQLITE_OK)
        }
        XCTAssertThrowsError(try StartupRetainedData.capture(rootURL: root, fileManager: manager))
        XCTAssertNotEqual(try Data(contentsOf: store), before, "Real passive checkpoint must change main database pages")
        let paths = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Recovery").path)
        XCTAssertEqual(paths.filter { !$0.hasPrefix(".") }.count, 0)
        XCTAssertFalse(paths.contains(".IntegrityFailure-building"))
        let retained = try StartupRetainedData.capture(rootURL: root)
        XCTAssertEqual(try Data(contentsOf: retained.snapshotURL.appendingPathComponent("Store/PersonalGrowthOS.sqlite")), try Data(contentsOf: store))
        XCTAssertEqual(try StartupRetainedData.capture(rootURL: root).snapshotURL, retained.snapshotURL)
    }

    func testDifferentFailurePreservesEarlierSnapshotAndIncompleteSnapshotIsNeverOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = AppConfiguration(launchMode: .uiTesting, resetDataOnLaunch: false)
        let app = try AppContainer.make(configuration: config, rootURLOverride: root)
        let task = try TodoTaskService(context: app.modelContainer.mainContext).create(TodoDraft(title: "first evidence"))
        let first = try StartupRetainedData.capture(rootURL: root)
        let original = try Data(contentsOf: first.snapshotURL.appendingPathComponent("Store/PersonalGrowthOS.sqlite"))
        task.title = "different evidence"; try app.modelContainer.mainContext.save()
        let second = try StartupRetainedData.capture(rootURL: root)
        XCTAssertNotEqual(first.snapshotURL, second.snapshotURL)
        XCTAssertEqual(try Data(contentsOf: first.snapshotURL.appendingPathComponent("Store/PersonalGrowthOS.sqlite")), original)
        try FileManager.default.removeItem(at: second.snapshotURL.appendingPathComponent("COMPLETE"))
        let manager = FailingStartupCopyManager(28)
        XCTAssertThrowsError(try StartupRetainedData.capture(rootURL: root, fileManager: manager))
        XCTAssertEqual(manager.copyAttempts, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.snapshotURL.appendingPathComponent("Store/PersonalGrowthOS.sqlite").path))
        XCTAssertEqual(try Data(contentsOf: first.snapshotURL.appendingPathComponent("Store/PersonalGrowthOS.sqlite")), original)
    }
}
