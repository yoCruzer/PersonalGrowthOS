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
