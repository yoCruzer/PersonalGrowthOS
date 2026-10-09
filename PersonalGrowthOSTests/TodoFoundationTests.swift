import Foundation
import SwiftData
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
        let store = root.appendingPathComponent("PersonalGrowthOS.sqlite")
        for pass in 0..<2 {
            let container = try PersistenceContainerFactory.makeOnDisk(at: store), context = container.mainContext
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
