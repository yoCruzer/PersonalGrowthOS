import Foundation
import SwiftData
import SwiftUI
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
        XCTAssertEqual(Set(HabitRecordingMode.allCases), Set([.oncePerDay, .multiplePerDay]))
        XCTAssertThrowsError(try HabitRules.validatedDailyTarget(0, mode: .multiplePerDay)) {
            XCTAssertEqual($0 as? HabitValidationError, .invalidDailyTarget)
        }
        XCTAssertEqual(try HabitRules.validatedDailyTarget(8, mode: .multiplePerDay), 8)
        XCTAssertNil(try HabitRules.validatedDailyTarget(8, mode: .oncePerDay))
    }

    func testLegacyHabitDefaultsToMultiplePerDayWithoutChangingIdentityOrHistory() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let habitID = UUID()
        let logID = UUID()
        context.insert(Habit(
            id: habitID,
            name: "Legacy Water",
            normalizedName: "legacy water",
            createdAt: Date()
        ))
        context.insert(HabitLog(
            id: logID,
            habitID: habitID,
            occurredAt: Date(),
            isCompleted: true,
            createdAt: Date()
        ))
        try context.save()

        let settings = try HabitSettingsResolver.settings(for: habitID, context: context)

        XCTAssertEqual(settings, .legacyDefault)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Habit>()).first?.id, habitID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<HabitLog>()).first?.id, logID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<HabitConfiguration>()).count, 0)
    }

    func testV4StoreMigratesToV5AndLegacyHabitRemainsMultiplePerDay() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let habitID = UUID()
        let logID = UUID()
        do {
            let schema = Schema(versionedSchema: PersonalGrowthSchemaV4.self)
            let configuration = ModelConfiguration(
                "PersonalGrowthOSV1",
                schema: schema,
                url: fixture.storeURL,
                cloudKitDatabase: .none
            )
            let legacy = try ModelContainer(for: schema, configurations: [configuration])
            legacy.mainContext.insert(Habit(
                id: habitID,
                name: "Legacy Read",
                normalizedName: "legacy read",
                createdAt: Date()
            ))
            legacy.mainContext.insert(HabitLog(
                id: logID,
                habitID: habitID,
                occurredAt: Date(),
                isCompleted: true,
                createdAt: Date()
            ))
            try legacy.mainContext.save()
        }

        let migrated = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<Habit>()).first?.id, habitID)
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<HabitLog>()).first?.id, logID)
        XCTAssertEqual(
            try HabitSettingsResolver.settings(for: habitID, context: migrated.mainContext),
            .legacyDefault
        )
    }

    func testOncePerDayCheckInRejectsSameLocalDayAndAllowsNextDay() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let calendar = Calendar(identifier: .gregorian)
        let dayOne = Date(timeIntervalSince1970: 1_700_035_200)
        var clock = dayOne
        let habit = try HabitService(context: context, now: { clock }).create(
            name: "Vitamin",
            recordingMode: .oncePerDay
        )
        let service = HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max }),
            now: { clock },
            calendar: calendar
        )

        _ = try service.checkIn(habit, draft: HabitLogDraft(occurredAt: dayOne))
        clock = dayOne.addingTimeInterval(60)
        XCTAssertThrowsError(try service.checkIn(
            habit,
            draft: HabitLogDraft(occurredAt: dayOne.addingTimeInterval(60))
        )) {
            XCTAssertEqual($0 as? HabitCheckInError, .alreadyCheckedInToday)
        }
        clock = dayOne.addingTimeInterval(86_400)
        XCTAssertNoThrow(try service.checkIn(
            habit,
            draft: HabitLogDraft(occurredAt: clock)
        ))
        XCTAssertEqual(try context.fetch(FetchDescriptor<HabitLog>()).count, 2)
    }

    func testMultiplePerDayAllowsRepeatedCheckInsAfterDebounceWindow() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_700_035_200)
        var clock = base
        let habit = try HabitService(context: context, now: { clock }).create(
            name: "Water",
            recordingMode: .multiplePerDay,
            dailyTargetCount: 8
        )
        let service = HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max }),
            now: { clock }
        )

        _ = try service.checkIn(habit, draft: HabitLogDraft(occurredAt: base))
        clock = base.addingTimeInterval(1)
        XCTAssertThrowsError(try service.checkIn(
            habit,
            draft: HabitLogDraft(occurredAt: clock)
        )) {
            XCTAssertEqual($0 as? HabitCheckInError, .recentlyCheckedIn)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<HabitLog>()).count, 1)

        clock = base.addingTimeInterval(HabitCheckInPolicy.duplicatePreventionInterval + 0.1)
        XCTAssertNoThrow(try service.checkIn(
            habit,
            draft: HabitLogDraft(occurredAt: clock)
        ))
        XCTAssertEqual(try context.fetch(FetchDescriptor<HabitLog>()).count, 2)
        XCTAssertEqual(
            try HabitSettingsResolver.settings(for: habit.id, context: context).dailyTargetCount,
            8
        )
    }

    func testRepeatableCounterRecordsEveryRapidIncrement() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_035_200)
        let habit = try HabitService(context: context, now: { timestamp }).create(
            name: "Water",
            recordingMode: .multiplePerDay
        )
        let service = HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max }),
            now: { timestamp }
        )

        _ = try service.incrementCount(habit, occurredAt: timestamp)
        _ = try service.incrementCount(habit, occurredAt: timestamp)
        _ = try service.incrementCount(habit, occurredAt: timestamp)

        let logs = try context.fetch(FetchDescriptor<HabitLog>())
        XCTAssertEqual(logs.count, 3)
        XCTAssertEqual(HabitTodayProgress(
            habitID: habit.id,
            logs: logs,
            settings: HabitSettings(recordingMode: .multiplePerDay, dailyTargetCount: nil),
            now: timestamp,
            calendar: Calendar(identifier: .gregorian)
        ).count, 3)
    }

    func testRepeatableCounterRemovesLatestCheckInOnlyForSelectedDay() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let calendar = Calendar(identifier: .gregorian)
        let dayOne = Date(timeIntervalSince1970: 1_700_035_200)
        let dayTwo = dayOne.addingTimeInterval(86_400)
        var clock = dayOne
        let habit = try HabitService(context: context, now: { clock }).create(
            name: "Water",
            recordingMode: .multiplePerDay
        )
        let service = HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max }),
            now: { clock },
            calendar: calendar
        )
        let dayOneLog = try service.incrementCount(habit, occurredAt: dayOne)
        clock = dayTwo
        let earlierDayTwoLog = try service.incrementCount(habit, occurredAt: dayTwo)
        let latestDayTwoLog = try service.incrementCount(
            habit,
            occurredAt: dayTwo.addingTimeInterval(60)
        )

        let removed = try service.removeLatestStructuredCheckIn(habitID: habit.id, on: dayTwo)
        XCTAssertEqual(removed?.id, latestDayTwoLog.id)
        XCTAssertEqual(
            Set(try context.fetch(FetchDescriptor<HabitLog>()).map(\.id)),
            Set([dayOneLog.id, earlierDayTwoLog.id])
        )
        XCTAssertEqual(try service.removeLatestStructuredCheckIn(habitID: habit.id, on: dayTwo)?.id, earlierDayTwoLog.id)
        XCTAssertNil(try service.removeLatestStructuredCheckIn(habitID: habit.id, on: dayTwo))
        XCTAssertEqual(try context.fetch(FetchDescriptor<HabitLog>()).map(\.id), [dayOneLog.id])
    }

    func testRepeatableCounterKeepsDetailedCheckInWhenCounterAddsAndRemoves() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_035_200)
        let habit = try HabitService(context: context, now: { timestamp }).create(
            name: "Run",
            recordingMode: .multiplePerDay
        )
        let service = HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max }),
            now: { timestamp }
        )

        let detailed = try service.checkIn(habit, draft: HabitLogDraft(
            occurredAt: timestamp,
            quantity: 5,
            unit: "km",
            result: "Easy"
        ))
        let counterLog = try service.incrementCount(
            habit,
            occurredAt: timestamp.addingTimeInterval(60)
        )

        XCTAssertEqual(
            try service.removeLatestStructuredCheckIn(habitID: habit.id, on: timestamp)?.id,
            counterLog.id
        )
        let remaining = try XCTUnwrap(context.fetch(FetchDescriptor<HabitLog>()).first)
        XCTAssertEqual(remaining.id, detailed.id)
        XCTAssertEqual(remaining.quantity, 5)
        XCTAssertEqual(remaining.unit, "km")
        XCTAssertEqual(remaining.result, "Easy")
    }

    func testRepeatableCounterKeepsInsightCheckInWhenCounterAddsAndRemoves() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_035_200)
        let habit = try HabitService(context: context, now: { timestamp }).create(
            name: "Reflect",
            recordingMode: .multiplePerDay
        )
        let service = HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max }),
            now: { timestamp }
        )

        let insight = try service.checkInWithInsight(
            habit,
            logDraft: HabitLogDraft(occurredAt: timestamp),
            entryDraft: EntryCreationDraft(body: "A useful insight")
        )
        let counterLog = try service.incrementCount(
            habit,
            occurredAt: timestamp.addingTimeInterval(60)
        )

        XCTAssertEqual(
            try service.removeLatestStructuredCheckIn(habitID: habit.id, on: timestamp)?.id,
            counterLog.id
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<HabitLog>()).map(\.id), [insight.log.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Entry>()).map(\.id), [insight.entry.id])
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: context))
    }

    func testRepeatableCounterDecrementPreservesLinkedEntryAndHabitRelation() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_035_200)
        let habit = try HabitService(context: context, now: { timestamp }).create(
            name: "Journal",
            recordingMode: .multiplePerDay
        )
        let service = HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max }),
            now: { timestamp }
        )
        let insight = try service.checkInWithInsight(
            habit,
            logDraft: HabitLogDraft(occurredAt: timestamp),
            entryDraft: EntryCreationDraft(body: "Keep this note")
        )

        XCTAssertEqual(
            try service.removeLatestStructuredCheckIn(habitID: habit.id, on: timestamp)?.id,
            insight.log.id
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<HabitLog>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Entry>()).map(\.id), [insight.entry.id])
        let relation = try XCTUnwrap(context.fetch(FetchDescriptor<ObjectLink>()).first)
        XCTAssertEqual(relation.kind, .entryRelatesHabit)
        XCTAssertEqual(relation.sourceID, insight.entry.id)
        XCTAssertEqual(relation.targetID, habit.id)
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: context))
    }

    func testRepeatableProgressUsesCurrentLocalDayAndSurvivesReopen() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let calendar = Calendar(identifier: .gregorian)
        let dayOne = Date(timeIntervalSince1970: 1_700_035_200)
        let dayTwo = dayOne.addingTimeInterval(86_400)
        let habitID: UUID
        do {
            let container = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
            let habit = try HabitService(context: container.mainContext, now: { dayOne }).create(
                name: "Water",
                recordingMode: .multiplePerDay
            )
            habitID = habit.id
            let service = HabitCheckInService(
                context: container.mainContext,
                mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max }),
                now: { dayOne },
                calendar: calendar
            )
            _ = try service.incrementCount(habit, occurredAt: dayOne)
            _ = try service.incrementCount(habit, occurredAt: dayOne.addingTimeInterval(60))
        }

        let reopened = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
        let logs = try reopened.mainContext.fetch(FetchDescriptor<HabitLog>())
        let configurations = try reopened.mainContext.fetch(FetchDescriptor<HabitConfiguration>())
        let settings = HabitSettingsResolver.settings(
            for: habitID,
            configurations: configurations
        )
        XCTAssertEqual(HabitTodayProgress(
            habitID: habitID,
            logs: logs,
            settings: settings,
            now: dayOne,
            calendar: calendar
        ).count, 2)
        XCTAssertEqual(HabitTodayProgress(
            habitID: habitID,
            logs: logs,
            settings: settings,
            now: dayTwo,
            calendar: calendar
        ).count, 0)
    }

    func testUndoRemovesOnlyLatestCheckIn() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_700_035_200)
        var clock = base
        let habit = try HabitService(context: context, now: { clock }).create(name: "Stand")
        let service = HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max }),
            now: { clock }
        )
        let first = try service.checkIn(habit, draft: HabitLogDraft(occurredAt: clock))
        clock = base.addingTimeInterval(10)
        let second = try service.checkIn(habit, draft: HabitLogDraft(occurredAt: clock))

        XCTAssertThrowsError(try service.undoLatestCheckIn(habitID: habit.id, logID: first.id)) {
            XCTAssertEqual($0 as? HabitCheckInError, .checkInIsNotLatest)
        }
        try service.undoLatestCheckIn(habitID: habit.id, logID: second.id)

        let remaining = try context.fetch(FetchDescriptor<HabitLog>())
        XCTAssertEqual(remaining.map(\.id), [first.id])
    }

    func testOncePerDayCheckInStillUsesLatestUndoSemantics() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_035_200)
        let habit = try HabitService(context: context, now: { timestamp }).create(
            name: "Vitamin",
            recordingMode: .oncePerDay
        )
        let service = HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max }),
            now: { timestamp }
        )
        let log = try service.checkIn(habit, draft: HabitLogDraft(occurredAt: timestamp))

        try service.undoLatestCheckIn(habitID: habit.id, logID: log.id)

        XCTAssertEqual(try context.fetch(FetchDescriptor<HabitLog>()).count, 0)
    }

    func testHabitEditKeepsIDHistoryAndModeChangesDoNotRewriteLogs() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_700_035_200)
        var clock = base
        let service = HabitService(context: context, now: { clock })
        let habit = try service.create(name: "  Water  ", recordingMode: .multiplePerDay)
        let checkInService = HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max }),
            now: { clock }
        )
        let log = try checkInService.checkIn(habit, draft: HabitLogDraft(occurredAt: clock))
        clock = base.addingTimeInterval(20)

        try service.update(
            habit,
            name: "  Morning Water  ",
            recordingMode: .oncePerDay,
            dailyTargetCount: 9
        )

        XCTAssertEqual(habit.name, "Morning Water")
        XCTAssertEqual(habit.id, log.habitID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<HabitLog>()).map(\.id), [log.id])
        XCTAssertEqual(
            try HabitSettingsResolver.settings(for: habit.id, context: context),
            HabitSettings(recordingMode: .oncePerDay, dailyTargetCount: nil)
        )
        XCTAssertThrowsError(try service.update(
            habit,
            name: " ",
            recordingMode: .multiplePerDay,
            dailyTargetCount: 1
        )) {
            XCTAssertEqual($0 as? HabitValidationError, .emptyName)
        }
        XCTAssertEqual(habit.id, log.habitID)
    }

    func testTodayProgressRestoresModeCountAndCompletionAfterStoreReopens() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let base = Date(timeIntervalSince1970: 1_700_035_200)
        let habitID: UUID
        do {
            let container = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
            let context = container.mainContext
            let habit = try HabitService(context: context, now: { base }).create(
                name: "Read",
                recordingMode: .oncePerDay
            )
            habitID = habit.id
            _ = try HabitCheckInService(
                context: context,
                mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max }),
                now: { base }
            ).checkIn(habit, draft: HabitLogDraft(occurredAt: base))
        }

        let reopened = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
        let logs = try reopened.mainContext.fetch(FetchDescriptor<HabitLog>())
        let configurations = try reopened.mainContext.fetch(FetchDescriptor<HabitConfiguration>())
        let progress = HabitTodayProgress(
            habitID: habitID,
            logs: logs,
            settings: HabitSettingsResolver.settings(
                for: habitID,
                configurations: configurations
            ),
            now: base,
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertEqual(progress.count, 1)
        XCTAssertTrue(progress.isCompletedForOncePerDay)
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

    func testTimelineImagePresentationFitsLandscapePortraitSquareAndLongImagesWithoutCropping() {
        XCTAssertEqual(TimelineImagePresentation.contentMode, .fit)
        XCTAssertEqual(
            TimelineImagePresentation.fittedSize(
                pixelWidth: 1_600,
                pixelHeight: 900,
                containerWidth: 320
            ),
            CGSize(width: 320, height: 180)
        )
        XCTAssertEqual(
            TimelineImagePresentation.fittedSize(
                pixelWidth: 1_000,
                pixelHeight: 1_000,
                containerWidth: 200
            ),
            CGSize(width: 200, height: 200)
        )
        XCTAssertEqual(
            TimelineImagePresentation.fittedSize(
                pixelWidth: 900,
                pixelHeight: 1_600,
                containerWidth: 320
            ).height,
            TimelineImagePresentation.maximumHeight
        )
        XCTAssertEqual(
            TimelineImagePresentation.fittedSize(
                pixelWidth: 400,
                pixelHeight: 8_000,
                containerWidth: 320
            ).height,
            TimelineImagePresentation.maximumHeight
        )
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
