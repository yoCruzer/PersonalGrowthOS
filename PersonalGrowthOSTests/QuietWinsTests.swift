import Foundation
import Darwin
import SwiftData
import UIKit
import XCTest
@testable import PersonalGrowthOS

final class QuietWinsTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var now: Date { date("2026-10-13T12:00:00Z") }
    private func window(_ days: Int = 30) -> QuietWinsWindow { .init(days: days, asOf: now, timeZone: utc) }

    func testEmptyAndOnlyUnfinishedOrExternalFactsHaveNoCards() {
        var input = QuietWinsInput()
        XCTAssertTrue(QuietWinsEngine.build(input, window: window()).cards.isEmpty)
        input.goals = [.init(id: UUID(), title: "unfinished", isCompleted: false, completedAt: now)]
        input.todos = [.init(id: UUID(), title: "reopened", isCompleted: false, completedAt: now)]
        input.entries = [.init(id: UUID(), title: "completed everything!", occurredAt: now,
            isOrdinary: true, hasContent: true, isExternal: true)]
        input.reviews = [.init(id: UUID(), weekIdentifier: "2026-W42", isCompleted: false)]
        XCTAssertTrue(QuietWinsEngine.build(input, window: window()).cards.isEmpty)
    }

    func testGoalCurrentStateLifecycleAndCompletionDateAreRequired() {
        let id = UUID()
        var input = QuietWinsInput(goals: [.init(id: id, title: "Swift", isCompleted: true, completedAt: now,
            latestLifecycleKind: "completed", latestLifecycleDate: now)])
        XCTAssertEqual(QuietWinsEngine.build(input, window: window()).cards.first?.sources.first?.sourceID, id)
        input.goals[0] = .init(id: id, title: "Swift", isCompleted: false, completedAt: now)
        XCTAssertTrue(QuietWinsEngine.build(input, window: window()).cards.isEmpty)
        input.goals[0] = .init(id: id, title: "Swift", isCompleted: true, completedAt: now,
            latestLifecycleKind: "reactivated", latestLifecycleDate: now)
        XCTAssertTrue(QuietWinsEngine.build(input, window: window()).cards.isEmpty)
        input.goals[0] = .init(id: id, title: "Swift", isCompleted: true, completedAt: window().start.addingTimeInterval(-1))
        XCTAssertTrue(QuietWinsEngine.build(input, window: window()).cards.isEmpty)
        input.goals[0] = .init(id: id, title: "archived", isCompleted: false, completedAt: nil)
        XCTAssertTrue(QuietWinsEngine.build(input, window: window()).cards.isEmpty)
    }

    func testTodoOccurrencesDeduplicateAndReopenCancelSkipFutureCannotCount() {
        let first = QuietWinsInput.Completion(id: UUID(), title: "period 1", isCompleted: true, completedAt: now)
        let second = QuietWinsInput.Completion(id: UUID(), title: "period 2", isCompleted: true, completedAt: now)
        var input = QuietWinsInput(todos: [first, first, second,
            .init(id: UUID(), title: "skipped", isCompleted: false, completedAt: nil),
            .init(id: UUID(), title: "canceled", isCompleted: false, completedAt: now),
            .init(id: UUID(), title: "future", isCompleted: true, completedAt: now.addingTimeInterval(1))])
        let card = QuietWinsEngine.build(input, window: window()).cards[0]
        XCTAssertEqual(card.count, 2)
        XCTAssertEqual(Set(card.sources.map(\.sourceID)), Set([first.id, second.id]))
        input.todos.removeAll { $0.id == first.id }
        XCTAssertEqual(QuietWinsEngine.build(input, window: window()).cards[0].count, 1)
        input.todos = []; XCTAssertTrue(QuietWinsEngine.build(input, window: window()).cards.isEmpty)
    }

    func testHabitDistinctWriteDaysFalseOrOrphanLogsAndTravel() {
        let habit = UUID(), instant = date("2026-10-12T23:30:00Z")
        let input = QuietWinsInput(habits: [.init(id: habit, title: "Tracking only")], logs: [
            .init(id: UUID(), habitID: habit, occurredAt: instant, isCompleted: true, localDay: "2026-10-13"),
            .init(id: UUID(), habitID: habit, occurredAt: instant, isCompleted: true, localDay: "2026-10-13"),
            .init(id: UUID(), habitID: habit, occurredAt: instant, isCompleted: true, localDay: "2026-10-12"),
            .init(id: UUID(), habitID: habit, occurredAt: instant, isCompleted: false, localDay: "2026-10-11"),
            .init(id: UUID(), habitID: UUID(), occurredAt: instant, isCompleted: true, localDay: "2026-10-11"),
            .init(id: UUID(), habitID: habit, occurredAt: instant, isCompleted: true, localDay: "2026-02-30")])
        let a = QuietWinsEngine.build(input, window: window()).cards[0]
        let b = QuietWinsEngine.build(input, window: .init(days: 30, asOf: now, timeZone: TimeZone(identifier: "America/Los_Angeles")!)).cards[0]
        XCTAssertEqual(a.count, 2); XCTAssertEqual(a.sources.count, 3)
        XCTAssertEqual(a.sources.map(\.day), b.sources.map(\.day))
        XCTAssertFalse(a.fact.lowercased().contains("achieved"))
    }

    func testUnknownHabitDayCannotBeGuessedAfterTravel() {
        let habit = UUID(), log = UUID(), instant = date("2026-10-12T23:30:00Z")
        var input = QuietWinsInput(habits: [.init(id: habit, title: "Travel")],
            logs: [.init(id: log, habitID: habit, occurredAt: instant, isCompleted: true, localDay: nil)])
        for zone in ["UTC", "Asia/Shanghai", "America/Los_Angeles"] {
            let w = QuietWinsWindow(days: 30, asOf: now, timeZone: TimeZone(identifier: zone)!)
            XCTAssertTrue(QuietWinsEngine.build(input, window: w).cards.isEmpty,
                "An absolute instant cannot prove the original local day in \(zone)")
        }
        input.logs = [.init(id: log, habitID: habit, occurredAt: instant, isCompleted: true, localDay: "2026-10-13")]
        for zone in ["UTC", "Asia/Shanghai", "America/Los_Angeles"] {
            let w = QuietWinsWindow(days: 30, asOf: now, timeZone: TimeZone(identifier: zone)!)
            let card = QuietWinsEngine.build(input, window: w).cards.first
            XCTAssertEqual(card?.count, 1)
            XCTAssertEqual(card?.sources.first?.day.description, "2026-10-13")
        }
    }

    func testEntryOccurredDayPicturesReviewAndTechnicalExternalExclusion() {
        let ordinary = QuietWinsInput.Record(id: UUID(), title: "photo", occurredAt: now,
            isOrdinary: true, hasContent: true, isExternal: false)
        let input = QuietWinsInput(entries: [ordinary, ordinary,
            .init(id: UUID(), title: "same day text", occurredAt: now, isOrdinary: true, hasContent: true, isExternal: false),
            .init(id: UUID(), title: "review", occurredAt: now, isOrdinary: false, hasContent: true, isExternal: false),
            .init(id: UUID(), title: "empty technical", occurredAt: now, isOrdinary: true, hasContent: false, isExternal: false),
            .init(id: UUID(), title: "saved web", occurredAt: now, isOrdinary: true, hasContent: true, isExternal: true),
            .init(id: UUID(), title: "old backfill", occurredAt: window().start.addingTimeInterval(-1), isOrdinary: true, hasContent: true, isExternal: false)])
        let card = QuietWinsEngine.build(input, window: window()).cards[0]
        XCTAssertEqual(card.count, 1); XCTAssertEqual(card.sources.count, 2)
    }

    func testWeeklyReviewCountsOverlappingWeekIdentitiesNotEditTime() {
        let input = QuietWinsInput(reviews: [
            .init(id: UUID(), weekIdentifier: "2026-W38", isCompleted: true), // starts on the window boundary
            .init(id: UUID(), weekIdentifier: "2026-W42", isCompleted: true),
            .init(id: UUID(), weekIdentifier: "2026-W43", isCompleted: true),
            .init(id: UUID(), weekIdentifier: "2026-W37", isCompleted: true),
            .init(id: UUID(), weekIdentifier: "2026-W41", isCompleted: false),
            .init(id: UUID(), weekIdentifier: "2026-W99", isCompleted: true)])
        let card = QuietWinsEngine.build(input, window: window()).cards[0]
        XCTAssertEqual(card.count, 2)
        XCTAssertEqual(Set(card.sources.compactMap(\.weekIdentifier)), Set(["2026-W38", "2026-W42"]))
        XCTAssertTrue(card.sources.allSatisfy { $0.date == nil })
        let crossing = QuietWinsInput(reviews: [
            .init(id: UUID(), weekIdentifier: "2026-W40", isCompleted: true),
            .init(id: UUID(), weekIdentifier: "2026-W41", isCompleted: true),
            .init(id: UUID(), weekIdentifier: "2026-W42", isCompleted: true),
            .init(id: UUID(), weekIdentifier: "2026-W43", isCompleted: true)])
        let recent = QuietWinsEngine.build(crossing, window: window(7)).cards[0]
        XCTAssertEqual(window(7).firstDay.description, "2026-10-07")
        XCTAssertEqual(Set(recent.sources.compactMap(\.weekIdentifier)), Set(["2026-W41", "2026-W42"]))
        XCTAssertEqual(recent.sources.first(where: { $0.weekIdentifier == "2026-W41" })?.day.description, "2026-10-05")

    }

    func testCivilWindowsLeapYearDSTYearBoundaryAndFutureInstants() {
        for (stamp, zone, expected) in [
            ("2024-03-01T12:00:00Z", "UTC", "2024-02-24"),
            ("2026-01-01T12:00:00Z", "UTC", "2025-12-26"),
            ("2026-03-10T12:00:00Z", "America/New_York", "2026-03-04"),
            ("2026-11-03T12:00:00Z", "America/New_York", "2026-10-28")
        ] {
            for days in [7, 30, 90] {
                let w = QuietWinsWindow(days: days, asOf: date(stamp), timeZone: TimeZone(identifier: zone)!)
                let calendar = WeeklyReviewCalendarPolicy.calendar(timeZone: w.timeZone)
                XCTAssertEqual(calendar.dateComponents([.day], from: w.start, to: calendar.startOfDay(for: w.asOf)).day, days - 1)
                XCTAssertTrue(w.contains(w.start)); XCTAssertFalse(w.contains(w.start.addingTimeInterval(-0.001)))
                XCTAssertTrue(w.contains(w.asOf)); XCTAssertFalse(w.contains(w.asOf.addingTimeInterval(0.001)))
                if days == 7 { XCTAssertEqual(w.firstDay.description, expected) }
            }
        }
    }

    func testStablePermutationAndDiverseFiveCardLimit() {
        let h = UUID()
        var input = QuietWinsInput(
            goals: (0..<9).map { .init(id: UUID(), title: "Goal \($0)", isCompleted: true, completedAt: now) },
            todos: [.init(id: UUID(), title: "Todo", isCompleted: true, completedAt: now)],
            habits: [.init(id: h, title: "Read")],
            logs: [.init(id: UUID(), habitID: h, occurredAt: now, isCompleted: true, localDay: "2026-10-13")],
            entries: [.init(id: UUID(), title: "Life", occurredAt: now, isOrdinary: true, hasContent: true, isExternal: false)],
            reviews: [.init(id: UUID(), weekIdentifier: "2026-W42", isCompleted: true)])
        let result = QuietWinsEngine.build(input, window: window())
        XCTAssertEqual(result.cards.map(\.kind), [.goal, .todos, .habit, .entries, .reviews])
        input.goals.reverse(); input.todos.reverse(); input.logs.reverse()
        XCTAssertEqual(QuietWinsEngine.build(input, window: window()), result)
        input.goals.append(.init(id: input.goals[0].id, title: "contradiction", isCompleted: false, completedAt: nil))
        XCTAssertFalse(QuietWinsEngine.build(input, window: window()).cards.flatMap(\.sources).contains { $0.sourceID == input.goals[0].id })
    }

    func testSyntheticProjectionPerformanceAndDeterminism() {
        let habits = (0..<25).map { _ in QuietWinsInput.HabitFact(id: UUID(), title: "Synthetic") }
        let input = QuietWinsInput(todos: (0..<4_000).map { _ in .init(id: UUID(), title: "Synthetic", isCompleted: true, completedAt: now) },
            habits: habits, logs: (0..<20_000).map { .init(id: UUID(), habitID: habits[$0 % 25].id,
                occurredAt: now, isCompleted: true, localDay: "2026-10-13") },
            entries: (0..<4_000).map { _ in .init(id: UUID(), title: "Synthetic", occurredAt: now, isOrdinary: true, hasContent: true, isExternal: false) })
        let start = ContinuousClock.now
        let result = QuietWinsEngine.build(input, window: window(90))
        let elapsed = start.duration(to: .now)
        print("QUIET_WINS_PROJECTION 4000 todos/4000 entries/20000 logs/25 habits elapsed=\(elapsed)")
        XCTAssertEqual(result.cards.first?.count, 4_000)
        XCTAssertEqual(result.cards.first(where: { $0.kind == .habit })?.count, 1)
        XCTAssertEqual(result, QuietWinsEngine.build(input, window: window(90)))
        XCTAssertLessThan(elapsed, .seconds(5))
    }
}

@MainActor
final class QuietWinsReaderTests: XCTestCase {
    func testPictureBackfillExternalReviewAndContinuationsPreserveCompleteExport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let container = try PersistenceContainerFactory.makeOnDisk(at: root.appendingPathComponent("facts.sqlite"))
        let context = container.mainContext
        let now = ISO8601DateFormatter().date(from: "2026-10-13T12:00:00Z")!
        let media = MediaStore(rootURL: root)
        let png = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { renderer in
            UIColor.blue.setFill(); renderer.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let sourceURL = root.appendingPathComponent("synthetic.png"); try png.write(to: sourceURL)
        let creation = EntryCreationService(persistence: ModelContextEntryPersistence(context: context), mediaStore: media, now: { now })
        let picture = try creation.create(.init(title: "Photo only", occurredAt: now.addingTimeInterval(-60),
            image: MediaSource(url: sourceURL, originalFilename: "synthetic.png", contentType: "image/png")))
        let backfill = Entry(body: "Backfill", createdAt: now.addingTimeInterval(-200 * 86_400), occurredAt: now.addingTimeInterval(-120))
        context.insert(backfill)
        context.insert(Entry(kind: .review, body: "Manual review", createdAt: now))
        let external = Entry(body: "Saved material", createdAt: now); context.insert(external)
        context.insert(try EntryExternalSource(entryID: external.id, source: CaptureSource(url: "https://example.invalid/fixture",
            capturedAt: now, captureMode: .metadataOnly)))
        context.insert(EntryPin(entryID: picture.id, pinnedAt: now))
        context.insert(EntryFollowUp(entryID: picture.id, body: "Later thought", createdAt: now))
        try context.save()
        func exportedData() async throws -> TransferData {
            let lease = try await ImportExportService(context: context, mediaStore: media, now: { now }).exportPackage()
            defer { lease.cleanup() }
            let target = root.appendingPathComponent(UUID().uuidString)
            try ZIPArchiveReader(archiveURL: lease.url, availableCapacity: .max).extractAll(to: target)
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
            return try decoder.decode(TransferData.self, from: Data(contentsOf: target.appendingPathComponent("data.json")))
        }
        let before = try await exportedData()
        let saveCounter = SaveCounter()
        let observer = NotificationCenter.default.addObserver(forName: ModelContext.willSave, object: nil, queue: nil) { _ in saveCounter.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }
        for days in [7, 30, 90] {
            let window = QuietWinsWindow(days: days, asOf: now, timeZone: TimeZone(secondsFromGMT: 0)!)
            let result = try await Task.detached { try await QuietWinsReader(modelContainer: container).read(window: window) }.value
            XCTAssertEqual(result.cards.map(\.kind), [.entries])
            XCTAssertEqual(result.cards[0].count, 1)
            XCTAssertEqual(Set(result.cards[0].sources.map(\.sourceID)), Set([picture.id, backfill.id]))
        }
        let after = try await exportedData()
        XCTAssertEqual(before, after)
        XCTAssertEqual(saveCounter.value, 0)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try Data(contentsOf: media.fileURL(for: picture.images[0].relativePath)), png)
    }

    func testGoalClockRollbackRemainsConservativeAndReadOnly() async throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let now = Date()
        let goal = try GoalService(context: container.mainContext, now: { now }).create(title: "Clock rollback", kind: .flag)
        let earlier = now.addingTimeInterval(-86_400)
        try GoalService(context: container.mainContext, now: { earlier }).transition(goal, to: .completed)
        let result = try await QuietWinsReader(modelContainer: container).read(window: .init(days: 30, asOf: now, timeZone: .current))
        XCTAssertTrue(result.cards.isEmpty) // A documented conservative omission, never a fabricated win.
        XCTAssertEqual(goal.status, .completed); XCTAssertEqual(goal.completedAt, earlier)
        XCTAssertFalse(container.mainContext.hasChanges)
    }

    func testBoundedPersistedSyntheticLoadStaysOffMainExecutor() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let container = try PersistenceContainerFactory.makeOnDisk(at: root.appendingPathComponent("load.sqlite"))
        let context = container.mainContext
        context.autosaveEnabled = false
        let now = Date(), old = now.addingTimeInterval(-400 * 86_400)
        let habit = Habit(name: "Synthetic", normalizedName: "synthetic", createdAt: old)
        context.insert(habit)
        for i in 0..<4_000 {
            let stamp = i < 2_000 ? now : old
            context.insert(Entry(body: "Synthetic", createdAt: stamp))
            let task = TodoTask(title: "Synthetic", createdAt: stamp)
            task.stateRawValue = "completed"; task.completedAt = stamp
            context.insert(task)
        }
        for i in 0..<20_000 {
            let stamp = i < 10_000 ? now : old
            let log = HabitLog(habitID: habit.id, occurredAt: stamp, isCompleted: true, createdAt: stamp)
            context.insert(log)
            context.insert(HabitLogDayMetadata(habitLogID: log.id, localDayIdentifier: HabitLocalDay(date: stamp).description,
                localTimeZoneIdentifier: TimeZone.current.identifier, provenance: .capturedAtWrite))
        }
        try context.save()
        var before = rusage(); getrusage(RUSAGE_SELF, &before)
        let window = QuietWinsWindow(days: 90, asOf: now, timeZone: .current)
        let started = ContinuousClock.now
        let work = Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            let reader = QuietWinsReader(modelContainer: container)
            return try await reader.read(window: window)
        }
        // An actual UI-executor task runs while the dedicated model actor fetches/aggregates.
        let heartbeat = Task { @MainActor in
            try await Task.sleep(for: .milliseconds(10))
            return ContinuousClock.now
        }
        let heartbeatAt = try await heartbeat.value
        let result = try await work.value
        let elapsed = started.duration(to: .now)
        var after = rusage(); getrusage(RUSAGE_SELF, &after)
        print("QUIET_WINS_READER 4000 entries/4000 todos/20000 logs elapsed=\(elapsed) peakRSSBefore=\(before.ru_maxrss) peakRSSAfter=\(after.ru_maxrss) mainHeartbeat=\(started.duration(to: heartbeatAt))")
        XCTAssertEqual(result.cards.first(where: { $0.kind == .todos })?.count, 2_000)
        XCTAssertEqual(result.cards.first(where: { $0.kind == .entries })?.sources.count, 2_000)
        XCTAssertEqual(result.cards.first(where: { $0.kind == .habit })?.sources.count, 10_000)
        XCTAssertLessThan(elapsed, .seconds(10))
        XCTAssertLessThan(started.duration(to: heartbeatAt), .seconds(1))
        XCTAssertLessThan(after.ru_maxrss - before.ru_maxrss, 128 * 1_024 * 1_024)
        XCTAssertFalse(context.hasChanges)
    }

    func testPersistedReadRefreshTravelAndNoWrites() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let container = try PersistenceContainerFactory.makeOnDisk(at: root.appendingPathComponent("test.sqlite"))
        let context = container.mainContext
        let now = ISO8601DateFormatter().date(from: "2026-10-13T12:00:00Z")!
        var clock = now.addingTimeInterval(-20)
        let service = TodoTaskService(context: context, now: { clock })
        let task = try service.create(TodoDraft(title: "Actual task"))
        clock = now.addingTimeInterval(-10); try service.transition(id: task.id, to: .completed)
        let habit = Habit(name: "Actual habit", normalizedName: "actual habit", status: .paused, createdAt: now)
        context.insert(habit)
        // Absolute timestamp lies outside the 7-day fetch but stored civil day lies inside.
        let log = HabitLog(habitID: habit.id, occurredAt: now.addingTimeInterval(-100 * 86_400), isCompleted: true, createdAt: now)
        context.insert(log)
        context.insert(HabitLogDayMetadata(habitLogID: log.id, localDayIdentifier: "2026-10-13",
            localTimeZoneIdentifier: "Asia/Shanghai", provenance: .capturedAtWrite))
        let unknownDay = HabitLog(habitID: habit.id, occurredAt: now, isCompleted: true, createdAt: now)
        context.insert(unknownDay) // Do not bootstrap or reinterpret it while reading evidence.
        let entry = Entry(body: "Actual life", createdAt: now, occurredAt: now.addingTimeInterval(-60))
        context.insert(entry)
        let week = try WeeklyReviewPeriod(containing: now)
        context.insert(WeeklyReview(weekIdentifier: week.identifier, periodStart: week.start, periodEnd: week.end,
            isCompleted: true, createdAt: now))
        try context.save()
        let oldTimes = [entry.updatedAt, task.updatedAt, habit.updatedAt]
        let oldEvents = try context.fetchCount(FetchDescriptor<TodoTaskEvent>())
        let saveCounter = SaveCounter()
        let token = NotificationCenter.default.addObserver(forName: ModelContext.willSave, object: nil, queue: nil) { _ in saveCounter.increment() }
        defer { NotificationCenter.default.removeObserver(token) }
        for zone in ["UTC", "America/Los_Angeles"] {
            let window = QuietWinsWindow(days: 7, asOf: now, timeZone: TimeZone(identifier: zone)!)
            let projection = try await Task.detached { try await QuietWinsReader(modelContainer: container).read(window: window) }.value
            XCTAssertEqual(projection.cards.map(\.kind), [.todos, .habit, .entries, .reviews])
            XCTAssertEqual(projection.cards.first(where: { $0.kind == .habit })?.sources[0].day.description, "2026-10-13")
            XCTAssertEqual(projection.cards.first(where: { $0.kind == .habit })?.sources.count, 1)
            XCTAssertFalse(projection.cards.flatMap(\.sources).contains { $0.sourceID == unknownDay.id })
        }
        XCTAssertEqual(saveCounter.value, 0)
        XCTAssertEqual([entry.updatedAt, task.updatedAt, habit.updatedAt], oldTimes)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTaskEvent>()), oldEvents)
        XCTAssertFalse(context.hasChanges)
        clock = now; try service.transition(id: task.id, to: .open)
        context.delete(log); context.delete(entry); try context.save()
        let refreshed = try await QuietWinsReader(modelContainer: container).read(window: .init(days: 7, asOf: now, timeZone: .current))
        XCTAssertEqual(refreshed.cards.map(\.kind), [.reviews])
    }
}

private final class SaveCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
