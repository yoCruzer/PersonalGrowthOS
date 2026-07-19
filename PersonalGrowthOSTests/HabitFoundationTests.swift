import Foundation
import SwiftData
import XCTest
@testable import PersonalGrowthOS

@MainActor
final class HabitFoundationTests: XCTestCase {
    func testHabitNameAndLifecycleRules() throws {
        XCTAssertThrowsError(try HabitRules.validatedName("  ")) {
            XCTAssertEqual($0 as? HabitValidationError, .emptyName)
        }
        XCTAssertEqual(try HabitRules.validatedName("  Read  "), "Read")
        XCTAssertEqual(Set(HabitStatus.allCases), Set([.active, .paused, .completed, .archived]))
    }

    func testV2StoreMigratesToV3AndPreservesRelationships() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let entryID = UUID()
        do {
            let schema = Schema(versionedSchema: PersonalGrowthSchemaV2.self)
            let configuration = ModelConfiguration(
                "PersonalGrowthOSV1",
                schema: schema,
                url: fixture.storeURL,
                cloudKitDatabase: .none
            )
            let legacy = try ModelContainer(for: schema, configurations: [configuration])
            let entry = Entry(id: entryID, body: "Before S6", createdAt: Date())
            let tag = Tag(displayName: "Keep", normalizedName: "keep", createdAt: Date())
            legacy.mainContext.insert(entry)
            legacy.mainContext.insert(tag)
            legacy.mainContext.insert(ObjectLink(
                sourceType: .entry,
                sourceID: entry.id,
                targetType: .tag,
                targetID: tag.id,
                kind: .entryUsesTag,
                createdAt: Date()
            ))
            try legacy.mainContext.save()
        }

        do {
            let migrated = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
            XCTAssertNotNil(try EntryRepository(context: migrated.mainContext).fetch(id: entryID))
            XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<Tag>()).count, 1)
            XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<ObjectLink>()).count, 1)
            XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<Habit>()).count, 0)
            XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<HabitLog>()).count, 0)
            XCTAssertNoThrow(try LinkIntegrityService.validate(context: migrated.mainContext))
        }

        let reopened = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
        XCTAssertNotNil(try EntryRepository(context: reopened.mainContext).fetch(id: entryID))
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: reopened.mainContext))
    }

    func testSimpleCheckInStoresOnlyStructuredFact() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let habit = try HabitService(context: context).create(name: "Run")
        let occurredAt = Date(timeIntervalSince1970: 10_000)

        let log = try HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        ).checkIn(habit, draft: HabitLogDraft(
            occurredAt: occurredAt,
            quantity: 5,
            unit: "km",
            result: "Easy"
        ))

        XCTAssertEqual(log.habitID, habit.id)
        XCTAssertEqual(log.occurredAt, occurredAt)
        XCTAssertTrue(log.isCompleted)
        XCTAssertEqual(log.quantity, 5)
        XCTAssertEqual(log.unit, "km")
        XCTAssertEqual(log.result, "Easy")
        XCTAssertNil(log.linkedEntryID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Entry>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ObjectLink>()).count, 0)

        try HabitService(context: context).transition(habit, to: .paused)
        XCTAssertThrowsError(try HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        ).checkIn(habit)) {
            XCTAssertEqual($0 as? HabitCheckInError, .inactiveHabit)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<HabitLog>()).count, 1)
    }

    func testCheckInUsesPersistedHabitStateForSameIDDetachedInstance() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let sharedID = UUID()
        let persisted = Habit(
            id: sharedID,
            name: "Persisted",
            normalizedName: "persisted",
            status: .paused,
            createdAt: Date()
        )
        context.insert(persisted)
        try context.save()
        let detached = Habit(
            id: sharedID,
            name: "Stale",
            normalizedName: "stale",
            status: .active,
            createdAt: Date()
        )
        let service = HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        )

        XCTAssertThrowsError(try service.checkIn(detached)) {
            XCTAssertEqual($0 as? HabitCheckInError, .inactiveHabit)
        }
        XCTAssertThrowsError(try service.checkInWithInsight(
            detached,
            entryDraft: EntryCreationDraft(body: "Do not publish")
        )) {
            XCTAssertEqual($0 as? HabitCheckInError, .inactiveHabit)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<HabitLog>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Entry>()).count, 0)
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: context))
    }

    func testRichCheckInStoresEntryLogAndTypedLinkAtomically() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let habit = try HabitService(context: context).create(name: "Reflect")

        let result = try HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        ).checkInWithInsight(
            habit,
            entryDraft: EntryCreationDraft(body: "A useful insight")
        )

        XCTAssertEqual(result.log.linkedEntryID, result.entry.id)
        XCTAssertEqual(result.entry.status, .organized)
        XCTAssertEqual(result.entry.body, "A useful insight")
        let link = try XCTUnwrap(context.fetch(FetchDescriptor<ObjectLink>()).first)
        XCTAssertEqual(link.kind, .entryRelatesHabit)
        XCTAssertEqual(link.sourceID, result.entry.id)
        XCTAssertEqual(link.targetID, habit.id)
        XCTAssertTrue(HabitTimelineAggregator.summarize(
            logs: [result.log],
            habits: [habit]
        ).isEmpty)
        XCTAssertFalse(Mirror(reflecting: result.log).children.compactMap(\.label).contains {
            $0.localizedCaseInsensitiveContains("image")
        })
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: context))
    }

    func testRichImageInsightOwnsMediaThroughEntryOnly() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let source = try fixture.makeImageSource()
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let habit = try HabitService(context: context).create(name: "Notice")
        let mediaStore = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })

        let result = try HabitCheckInService(
            context: context,
            mediaStore: mediaStore
        ).checkInWithInsight(
            habit,
            entryDraft: EntryCreationDraft(images: [source])
        )

        XCTAssertEqual(result.entry.images.count, 1)
        XCTAssertEqual(result.log.linkedEntryID, result.entry.id)
        XCTAssertGreaterThan(try mediaStore.originalsByteCount(), 0)
    }

    func testFailedRichCheckInPublishesNothingAndRemovesMedia() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let source = try fixture.makeImageSource()
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let habit = try HabitService(context: context).create(name: "Keep Safe")
        let mediaStore = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        let service = HabitCheckInService(
            context: context,
            mediaStore: mediaStore,
            save: { throw InjectedHabitFailure.save }
        )

        XCTAssertThrowsError(try service.checkInWithInsight(
            habit,
            entryDraft: EntryCreationDraft(images: [source])
        ))

        XCTAssertEqual(try context.fetch(FetchDescriptor<Entry>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<HabitLog>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ObjectLink>()).count, 0)
        XCTAssertEqual(try mediaStore.originalsByteCount(), 0)
    }

    func testEntryDeleteClearsHabitLogReferenceAndPreservesFact() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let mediaStore = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        let habit = try HabitService(context: context).create(name: "Journal")
        let result = try HabitCheckInService(
            context: context,
            mediaStore: mediaStore
        ).checkInWithInsight(habit, entryDraft: EntryCreationDraft(body: "Temporary insight"))

        try EntryDeletionService(
            persistence: ModelContextEntryPersistence(context: context),
            mediaStore: mediaStore
        ).permanentlyDelete(result.entry)

        let remainingLog = try XCTUnwrap(context.fetch(FetchDescriptor<HabitLog>()).first)
        XCTAssertNil(remainingLog.linkedEntryID)
        XCTAssertEqual(remainingLog.habitID, habit.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ObjectLink>()).count, 0)
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: context))
    }

    func testHabitDeleteRemovesLogsAndLinksButPreservesEntries() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let habit = try HabitService(context: context).create(name: "Delete Habit")
        let result = try HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        ).checkInWithInsight(habit, entryDraft: EntryCreationDraft(body: "Keep Entry"))

        try HabitService(context: context).permanentlyDelete(habit)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Habit>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<HabitLog>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ObjectLink>()).count, 0)
        XCTAssertNotNil(try EntryRepository(context: context).fetch(id: result.entry.id))
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: context))
    }

    func testFailedHabitDeleteRollsBackHabitLogsAndLinks() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let habit = try HabitService(context: context).create(name: "Rollback")
        _ = try HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        ).checkInWithInsight(habit, entryDraft: EntryCreationDraft(body: "Keep all"))
        let failing = HabitService(context: context, save: { throw InjectedHabitFailure.save })

        XCTAssertThrowsError(try failing.permanentlyDelete(habit))

        XCTAssertEqual(try context.fetch(FetchDescriptor<Habit>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<HabitLog>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ObjectLink>()).count, 1)
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: context))
    }

    func testIntegrityRejectsDanglingHabitLogWithoutAnyObjectLink() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        context.insert(HabitLog(
            habitID: UUID(),
            occurredAt: Date(),
            isCompleted: true,
            createdAt: Date()
        ))
        try context.save()

        XCTAssertThrowsError(try LinkIntegrityService.validate(context: context)) {
            guard case LinkIntegrityError.danglingHabitLogs(let ids) = $0 else {
                return XCTFail("Expected dangling HabitLog error, got \($0)")
            }
            XCTAssertEqual(ids.count, 1)
        }
    }

    func testDenseHabitLogsAggregateIntoOneTimelineRowPerDay() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let habit = try HabitService(context: context).create(name: "Read")
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<500 {
            context.insert(HabitLog(
                habitID: habit.id,
                occurredAt: start.addingTimeInterval(Double(index)),
                isCompleted: true,
                createdAt: start
            ))
        }
        try context.save()

        let summaries = HabitTimelineAggregator.summarize(
            logs: try context.fetch(FetchDescriptor<HabitLog>()),
            habits: [habit],
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.logCount, 500)
        XCTAssertEqual(summaries.first?.habitNames, ["Read"])
    }

    func testTimelineMergesEntriesHabitActivityAndGoalEventsChronologically() {
        let entry = Entry(
            body: "Old Entry",
            createdAt: Date(timeIntervalSince1970: 1_000),
            occurredAt: Date(timeIntervalSince1970: 1_000)
        )
        let habit = HabitDaySummary(
            day: Date(timeIntervalSince1970: 0),
            latestOccurredAt: Date(timeIntervalSince1970: 3_000),
            logCount: 1,
            habitNames: ["Read"]
        )
        let event = GoalLifecycleEvent(
            goalID: UUID(),
            kind: .paused,
            occurredAt: Date(timeIntervalSince1970: 2_000),
            createdAt: Date(timeIntervalSince1970: 2_000)
        )

        let items = TimelineItem.chronologically(
            entries: [entry],
            habitActivity: [habit],
            goalEvents: [event]
        )

        XCTAssertEqual(items.map(\.occurredAt), [
            Date(timeIntervalSince1970: 3_000),
            Date(timeIntervalSince1970: 2_000),
            Date(timeIntervalSince1970: 1_000)
        ])
    }

    func testHabitLifecycleRollbackAndGlobalSearch() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let habit = try HabitService(context: context).create(name: "Ｍｅｄｉｔａｔｅ")
        let lifecycle = HabitService(context: context)
        try lifecycle.transition(habit, to: .paused)
        XCTAssertEqual(habit.status, .paused)
        try lifecycle.transition(habit, to: .completed)
        XCTAssertEqual(habit.status, .completed)
        try lifecycle.transition(habit, to: .archived)
        XCTAssertEqual(habit.status, .archived)
        try lifecycle.transition(habit, to: .active)
        XCTAssertEqual(habit.status, .active)
        let originalUpdatedAt = habit.updatedAt
        let failing = HabitService(
            context: context,
            now: { originalUpdatedAt.addingTimeInterval(100) },
            save: { throw InjectedHabitFailure.save }
        )

        XCTAssertThrowsError(try failing.transition(habit, to: .paused))
        XCTAssertEqual(habit.status, .active)
        XCTAssertEqual(habit.updatedAt, originalUpdatedAt)
        XCTAssertEqual(try LocalSearchService(context: context).search("meditate").habits.map(\.id), [habit.id])
    }
}

private enum InjectedHabitFailure: Error {
    case save
}

private struct HabitFixture {
    let root: URL
    let storeURL: URL
    let mediaRoot: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PGOS-S6-\(UUID().uuidString)", isDirectory: true)
        storeURL = root.appendingPathComponent("store.sqlite")
        mediaRoot = root.appendingPathComponent("MediaRoot", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func makeImageSource() throws -> MediaSource {
        let url = root.appendingPathComponent("source-\(UUID().uuidString).png")
        let data = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
        try data.write(to: url)
        return MediaSource(url: url, originalFilename: "insight.png", contentType: "image/png")
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
