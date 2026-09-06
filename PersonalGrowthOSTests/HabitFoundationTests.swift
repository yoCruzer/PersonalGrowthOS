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
        XCTAssertThrowsError(try HabitRules.validatedDailyTarget(nil, mode: .multiplePerDay)) {
            XCTAssertEqual($0 as? HabitValidationError, .invalidDailyTarget)
        }
        XCTAssertEqual(try HabitRules.validatedDailyTarget(8, mode: .multiplePerDay), 8)
        XCTAssertNil(try HabitRules.validatedDailyTarget(8, mode: .oncePerDay))
    }

    func testLegacyHabitDefaultsToMultiplePerDayWithoutChangingIdentityOrHistory() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
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
        XCTAssertNoThrow(try HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        ).incrementCount(try XCTUnwrap(context.fetch(FetchDescriptor<Habit>()).first)))
        XCTAssertEqual(try context.fetch(FetchDescriptor<HabitLog>()).count, 2)
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

    func testOncePerDayFalseLogDoesNotBlockImmediateTrueCompletion() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let timestamp = Date(timeIntervalSince1970: 1_700_035_200)
        let habit = try HabitService(context: context, now: { timestamp }).create(
            name: "Vitamin",
            recordingMode: .oncePerDay
        )
        let service = HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max }),
            now: { timestamp },
            calendar: calendar
        )

        _ = try service.checkIn(habit, draft: HabitLogDraft(
            occurredAt: timestamp,
            isCompleted: false
        ))
        let falseOnlyProgress = HabitTodayProgress(
            habitID: habit.id,
            logs: try context.fetch(FetchDescriptor<HabitLog>()),
            settings: HabitSettings(recordingMode: .oncePerDay, dailyTargetCount: nil),
            now: timestamp,
            calendar: calendar
        )
        XCTAssertEqual(falseOnlyProgress.count, 0)
        XCTAssertFalse(falseOnlyProgress.isCompletedForOncePerDay)

        XCTAssertNoThrow(try service.checkIn(habit, draft: HabitLogDraft(occurredAt: timestamp)))

        let logs = try context.fetch(FetchDescriptor<HabitLog>())
        XCTAssertEqual(logs.count, 2)
        let dayMetadata = try context.fetch(FetchDescriptor<HabitLogDayMetadata>())
        XCTAssertEqual(dayMetadata.count, 2)
        XCTAssertEqual(Set(dayMetadata.map(\.habitLogID)), Set(logs.map(\.id)))
        XCTAssertTrue(dayMetadata.allSatisfy { $0.provenance == .capturedAtWrite })
        let progress = HabitTodayProgress(
            habitID: habit.id,
            logs: logs,
            settings: HabitSettings(recordingMode: .oncePerDay, dailyTargetCount: nil),
            now: timestamp,
            calendar: calendar
        )
        XCTAssertEqual(progress.count, 1)
        XCTAssertTrue(progress.isCompletedForOncePerDay)
    }

    func testPersistedLocalDayControlsOncePerDayDuplicateAndTodayProgress() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = Date(timeIntervalSince1970: 1_700_035_200)
        let yesterday = today.addingTimeInterval(-86_400)
        let habit = try HabitService(context: context, now: { today }).create(
            name: "Read",
            recordingMode: .oncePerDay
        )
        let migratedLog = HabitLog(
            habitID: habit.id,
            occurredAt: yesterday,
            isCompleted: true,
            createdAt: yesterday
        )
        let migratedDayMetadata = HabitLogDayMetadata(
            habitLogID: migratedLog.id,
            localDayIdentifier: HabitLocalDay(date: today, timeZone: calendar.timeZone).description,
            localTimeZoneIdentifier: calendar.timeZone.identifier,
            provenance: .legacyBootstrap
        )
        context.insert(migratedLog)
        context.insert(migratedDayMetadata)
        try context.save()

        let logs = try context.fetch(FetchDescriptor<HabitLog>())
        XCTAssertEqual(HabitTodayProgress(
            habitID: habit.id,
            logs: logs,
            dayMetadata: [migratedDayMetadata],
            settings: HabitSettings(recordingMode: .oncePerDay, dailyTargetCount: nil),
            now: today,
            calendar: calendar
        ).count, 1)
        let service = HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max }),
            now: { today },
            calendar: calendar
        )
        XCTAssertThrowsError(try service.checkIn(habit, draft: HabitLogDraft(occurredAt: today))) {
            XCTAssertEqual($0 as? HabitCheckInError, .alreadyCheckedInToday)
        }
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
            recordingMode: .multiplePerDay,
            dailyTargetCount: 2
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
            settings: HabitSettings(recordingMode: .multiplePerDay, dailyTargetCount: 2),
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
            recordingMode: .multiplePerDay,
            dailyTargetCount: 2
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

    func testRepeatableCounterDecrementUsesPersistedLocalDayAndSkipsFalseLogs() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = Date(timeIntervalSince1970: 1_700_035_200)
        let yesterday = today.addingTimeInterval(-86_400)
        let habit = try HabitService(context: context, now: { today }).create(
            name: "Water",
            recordingMode: .multiplePerDay,
            dailyTargetCount: 2
        )
        let todayIdentifier = HabitLocalDay(date: today, timeZone: calendar.timeZone).description
        let positive = HabitLog(
            habitID: habit.id,
            occurredAt: yesterday,
            isCompleted: true,
            createdAt: yesterday
        )
        let negative = HabitLog(
            habitID: habit.id,
            occurredAt: today,
            isCompleted: false,
            createdAt: today
        )
        context.insert(positive)
        context.insert(negative)
        context.insert(HabitLogDayMetadata(
            habitLogID: positive.id,
            localDayIdentifier: todayIdentifier,
            localTimeZoneIdentifier: calendar.timeZone.identifier,
            provenance: .legacyBootstrap
        ))
        context.insert(HabitLogDayMetadata(
            habitLogID: negative.id,
            localDayIdentifier: todayIdentifier,
            localTimeZoneIdentifier: calendar.timeZone.identifier,
            provenance: .capturedAtWrite
        ))
        try context.save()

        let removed = try HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max }),
            now: { today },
            calendar: calendar
        ).removeLatestStructuredCheckIn(habitID: habit.id, on: today)

        XCTAssertEqual(removed?.id, positive.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<HabitLog>()).map(\.id), [negative.id])
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<HabitLogDayMetadata>()).map(\.habitLogID),
            [negative.id]
        )
    }

    func testRepeatableCounterKeepsDetailedCheckInWhenCounterAddsAndRemoves() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_035_200)
        let habit = try HabitService(context: context, now: { timestamp }).create(
            name: "Run",
            recordingMode: .multiplePerDay,
            dailyTargetCount: 2
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
            recordingMode: .multiplePerDay,
            dailyTargetCount: 2
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
            recordingMode: .multiplePerDay,
            dailyTargetCount: 2
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
                recordingMode: .multiplePerDay,
                dailyTargetCount: 2
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
        let dayMetadata = try reopened.mainContext.fetch(FetchDescriptor<HabitLogDayMetadata>())
        let configurations = try reopened.mainContext.fetch(FetchDescriptor<HabitConfiguration>())
        let settings = HabitSettingsResolver.settings(
            for: habitID,
            configurations: configurations
        )
        XCTAssertEqual(HabitTodayProgress(
            habitID: habitID,
            logs: logs,
            dayMetadata: dayMetadata,
            settings: settings,
            now: dayOne,
            calendar: calendar
        ).count, 2)
        XCTAssertEqual(HabitTodayProgress(
            habitID: habitID,
            logs: logs,
            dayMetadata: dayMetadata,
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
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<HabitLogDayMetadata>()).map(\.habitLogID),
            [first.id]
        )
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
        XCTAssertEqual(try context.fetch(FetchDescriptor<HabitLogDayMetadata>()).count, 0)
    }

    func testHabitEditKeepsIDHistoryAndModeChangesDoNotRewriteLogs() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_700_035_200)
        var clock = base
        let service = HabitService(context: context, now: { clock })
        let habit = try service.create(
            name: "  Water  ",
            recordingMode: .multiplePerDay,
            dailyTargetCount: 2
        )
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
            name: "Morning Water",
            recordingMode: .multiplePerDay,
            dailyTargetCount: nil
        )) {
            XCTAssertEqual($0 as? HabitValidationError, .invalidDailyTarget)
        }
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
        let dayMetadata = try reopened.mainContext.fetch(FetchDescriptor<HabitLogDayMetadata>())
        let configurations = try reopened.mainContext.fetch(FetchDescriptor<HabitConfiguration>())
        let progress = HabitTodayProgress(
            habitID: habitID,
            logs: logs,
            dayMetadata: dayMetadata,
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
        XCTAssertEqual(try context.fetch(FetchDescriptor<HabitLogDayMetadata>()).count, 0)
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
        XCTAssertEqual(try context.fetch(FetchDescriptor<HabitLogDayMetadata>()).count, 1)
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
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<HabitLifecycleEvent>())
                .sorted { $0.occurredAt < $1.occurredAt }
                .map(\.kind),
            [.created, .paused, .completed, .archived, .restored]
        )
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

    func testAnalyticsCapsDailyCreditAndKeepsOpenPeriodOutOfStrictMetrics() {
        let start = HabitLocalDay(year: 2026, month: 9, day: 1)
        let plan = HabitPlanSnapshot(
            effectiveDay: start,
            plan: HabitPlan(recordingMode: .oncePerDay, period: .day, goal: .everyDay, targetCount: 1, weekdays: []),
            trustStartDay: start
        )
        let logs = [
            HabitAnalyticsLog(id: UUID(), localDay: start, isCompleted: false, occurredAt: Date()),
            HabitAnalyticsLog(id: UUID(), localDay: start, isCompleted: true, occurredAt: Date()),
            HabitAnalyticsLog(id: UUID(), localDay: start, isCompleted: true, occurredAt: Date())
        ]
        let result = HabitAnalyticsEngine.evaluate(
            createdAt: start, logs: logs, plans: [plan], lifecycle: [
                HabitLifecycleSnapshot(day: start, kind: .created)
            ], asOf: start
        )
        XCTAssertEqual(result.current?.actual, 1)
        XCTAssertEqual(result.current?.outcome, .achieved)
        XCTAssertNil(result.adherence, "The current open period must not enter adherence.")
    }

    func testWeeklyCreditUsesHistoricalRecordingModeIndependentlyFromSchedule() {
        let monday = HabitLocalDay(year: 2026, month: 9, day: 7)
        let tuesday = HabitLocalDay(year: 2026, month: 9, day: 8)
        let wednesday = HabitLocalDay(year: 2026, month: 9, day: 9)
        let followingMonday = HabitLocalDay(year: 2026, month: 9, day: 14)
        let lifecycle = [HabitLifecycleSnapshot(day: monday, kind: .created)]

        func summary(mode: HabitRecordingMode, logDays: [HabitLocalDay]) -> HabitAnalyticsSummary {
            HabitAnalyticsEngine.evaluate(
                createdAt: monday,
                logs: logDays.map {
                    HabitAnalyticsLog(id: UUID(), localDay: $0, isCompleted: true, occurredAt: Date())
                },
                plans: [HabitPlanSnapshot(
                    effectiveDay: monday,
                    plan: HabitPlan(
                        recordingMode: mode,
                        period: .week,
                        goal: .count,
                        targetCount: 3,
                        weekdays: []
                    ),
                    trustStartDay: monday
                )],
                lifecycle: lifecycle,
                asOf: followingMonday,
                timeZone: TimeZone(secondsFromGMT: 0)!
            )
        }

        let onceSameDay = summary(mode: .oncePerDay, logDays: [monday, monday, monday])
        XCTAssertEqual(onceSameDay.evaluations.first { $0.start == monday }?.actual, 1)
        XCTAssertEqual(onceSameDay.evaluations.first { $0.start == monday }?.outcome, .missed)

        let onceDistinctDays = summary(mode: .oncePerDay, logDays: [monday, tuesday, wednesday])
        XCTAssertEqual(onceDistinctDays.evaluations.first { $0.start == monday }?.actual, 3)
        XCTAssertEqual(onceDistinctDays.evaluations.first { $0.start == monday }?.outcome, .achieved)

        let multipleSameDay = summary(mode: .multiplePerDay, logDays: [monday, monday, monday])
        XCTAssertEqual(multipleSameDay.evaluations.first { $0.start == monday }?.actual, 3)
        XCTAssertEqual(multipleSameDay.evaluations.first { $0.start == monday }?.outcome, .achieved)
    }

    func testTrackingOnlyPlanRetainsExplicitRecordingMode() throws {
        XCTAssertEqual(
            try HabitRules.validatedPlan(.trackingOnly(recordingMode: .oncePerDay)).recordingMode,
            .oncePerDay
        )
        XCTAssertEqual(
            try HabitRules.validatedPlan(.trackingOnly(recordingMode: .multiplePerDay)).recordingMode,
            .multiplePerDay
        )
    }

    func testAnalyticsBootstrapFreezesLegacyLocalDaysAndStartsConservativeCoverage() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let habit = Habit(name: "Legacy", normalizedName: "legacy", createdAt: created)
        context.insert(habit)
        context.insert(HabitConfiguration(habitID: habit.id, recordingMode: .multiplePerDay, dailyTargetCount: nil, updatedAt: created))
        let log = HabitLog(habitID: habit.id, occurredAt: created, isCompleted: true, createdAt: created)
        context.insert(log)
        try context.save()

        let now = created.addingTimeInterval(86_400 * 30)
        XCTAssertTrue(try HabitAnalyticsMigrationBootstrap.apply(context: context, now: now, timeZone: TimeZone(identifier: "Asia/Tokyo")!))
        let dayMetadata = try XCTUnwrap(context.fetch(FetchDescriptor<HabitLogDayMetadata>()).first)
        XCTAssertEqual(dayMetadata.habitLogID, log.id)
        XCTAssertEqual(dayMetadata.localDayIdentifier, HabitLocalDay(date: created, timeZone: TimeZone(identifier: "Asia/Tokyo")!).description)
        XCTAssertEqual(dayMetadata.provenance, .legacyBootstrap)
        let plans = try context.fetch(FetchDescriptor<HabitPlanRevision>())
        let plan = try XCTUnwrap(plans.first)
        XCTAssertEqual(plan.plan, .trackingOnly(recordingMode: .multiplePerDay))
        XCTAssertEqual(plan.effectiveLocalDay, HabitLocalDay(date: now, timeZone: TimeZone(identifier: "Asia/Tokyo")!).description)
        XCTAssertEqual(plan.trustCoverageStartLocalDay, HabitLocalDay(date: now, timeZone: TimeZone(identifier: "Asia/Tokyo")!).description)
        let baseline = try XCTUnwrap(context.fetch(FetchDescriptor<HabitLifecycleEvent>()).first)
        XCTAssertEqual(baseline.kind, .migrationBaseline)
        XCTAssertEqual(baseline.knownStatus, .active)
    }

    func testV7StoreMigratesAndBootstrapsHabitAnalyticsWithoutChangingHistory() throws {
        let fixture = try HabitFixture()
        defer { fixture.remove() }
        let habitID = UUID()
        let logID = UUID()
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        do {
            let schema = Schema(versionedSchema: PersonalGrowthSchemaV7.self)
            let configuration = ModelConfiguration(
                "PersonalGrowthOSV1",
                schema: schema,
                url: fixture.storeURL,
                cloudKitDatabase: .none
            )
            let legacy = try ModelContainer(for: schema, configurations: [configuration])
            let habit = Habit(id: habitID, name: "Migrated", normalizedName: "migrated", createdAt: created)
            legacy.mainContext.insert(habit)
            legacy.mainContext.insert(HabitLog(
                id: logID,
                habitID: habitID,
                occurredAt: created,
                isCompleted: true,
                createdAt: created
            ))
            try legacy.mainContext.save()
        }

        let migrated = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
        let timeZone = TimeZone(identifier: "Asia/Shanghai")!
        XCTAssertTrue(try HabitAnalyticsMigrationBootstrap.apply(
            context: migrated.mainContext,
            now: created.addingTimeInterval(86_400),
            timeZone: timeZone
        ))

        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<Habit>()).map(\.id), [habitID])
        let log = try XCTUnwrap(migrated.mainContext.fetch(FetchDescriptor<HabitLog>()).first)
        XCTAssertEqual(log.id, logID)
        let dayMetadata = try XCTUnwrap(migrated.mainContext.fetch(FetchDescriptor<HabitLogDayMetadata>()).first)
        XCTAssertEqual(dayMetadata.habitLogID, logID)
        XCTAssertEqual(dayMetadata.localDayIdentifier, HabitLocalDay(date: created, timeZone: timeZone).description)
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<HabitPlanRevision>()).count, 1)
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<HabitLifecycleEvent>()).count, 1)
    }

    func testExactBuild7V7FixtureMigratesBootstrapsAndReopensWithoutDataLoss() throws {
        let fixtureResource = try XCTUnwrap(Bundle(for: HabitFoundationTests.self).url(
            forResource: "Build7V7Fixture",
            withExtension: nil
        ))
        let temporaryParent = FileManager.default.temporaryDirectory
            .appendingPathComponent("PGOS-RealV7-\(UUID().uuidString)", isDirectory: true)
        let fixtureRoot = temporaryParent.appendingPathComponent("Build7V7Fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryParent, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixtureResource, to: fixtureRoot)
        defer { try? FileManager.default.removeItem(at: temporaryParent) }

        let storeURL = fixtureRoot.appendingPathComponent("PersonalGrowthOS.store")
        let mediaURL = fixtureRoot
            .appendingPathComponent("Media/originals/22222222-2222-4222-8222-222222222222.png")
        let expectedImageData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
        let entryID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let imageID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let tagID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let onceHabitID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        let multipleHabitID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
        let targetlessHabitID = UUID(uuidString: "66666666-6666-4666-8666-666666666666")!
        let archivedHabitID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
        let goalID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
        let weightID = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
        let reviewID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        let expectedLogIDs: Set<UUID> = [
            UUID(uuidString: "F1111111-1111-4111-8111-111111111111")!,
            UUID(uuidString: "F2222222-2222-4222-8222-222222222222")!,
            UUID(uuidString: "F3333333-3333-4333-8333-333333333333")!,
            UUID(uuidString: "F4444444-4444-4444-8444-444444444444")!,
            UUID(uuidString: "F5555555-5555-4555-8555-555555555555")!,
            UUID(uuidString: "F6666666-6666-4666-8666-666666666666")!
        ]
        let expectedLinkIDs: Set<UUID> = [
            UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!,
            UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!,
            UUID(uuidString: "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD")!
        ]

        func assertSourceFacts(_ context: ModelContext) throws {
            let entries = try context.fetch(FetchDescriptor<Entry>())
            let entry = try XCTUnwrap(entries.first { $0.id == entryID })
            XCTAssertEqual(entries.count, 1)
            XCTAssertEqual(entry.body, "Exact 95076bf source fact")
            XCTAssertEqual(entry.images.map(\.id), [imageID])
            let image = try XCTUnwrap(context.fetch(FetchDescriptor<ImageMetadata>()).first)
            XCTAssertEqual(image.id, imageID)
            XCTAssertEqual(image.entry?.id, entryID)
            XCTAssertEqual(image.relativePath, "originals/22222222-2222-4222-8222-222222222222.png")
            XCTAssertEqual(try Data(contentsOf: mediaURL), expectedImageData)
            XCTAssertEqual(Set(try context.fetch(FetchDescriptor<Tag>()).map(\.id)), [tagID])
            XCTAssertEqual(Set(try context.fetch(FetchDescriptor<ObjectLink>()).map(\.id)), expectedLinkIDs)

            let habits = try context.fetch(FetchDescriptor<Habit>())
            XCTAssertEqual(Set(habits.map(\.id)), [onceHabitID, multipleHabitID, targetlessHabitID, archivedHabitID])
            XCTAssertEqual(habits.first { $0.id == archivedHabitID }?.status, .archived)
            XCTAssertEqual(
                try HabitSettingsResolver.settings(for: onceHabitID, context: context),
                HabitSettings(recordingMode: .oncePerDay, dailyTargetCount: nil)
            )
            XCTAssertEqual(
                try HabitSettingsResolver.settings(for: multipleHabitID, context: context),
                HabitSettings(recordingMode: .multiplePerDay, dailyTargetCount: 3)
            )
            XCTAssertEqual(
                try HabitSettingsResolver.settings(for: targetlessHabitID, context: context),
                HabitSettings(recordingMode: .multiplePerDay, dailyTargetCount: nil)
            )
            let logs = try context.fetch(FetchDescriptor<HabitLog>())
            XCTAssertEqual(Set(logs.map(\.id)), expectedLogIDs)
            XCTAssertEqual(logs.filter(\.isCompleted).count, 5)
            let linkedLog = try XCTUnwrap(logs.first { $0.id == UUID(uuidString: "F1111111-1111-4111-8111-111111111111")! })
            XCTAssertEqual(linkedLog.linkedEntryID, entryID)
            XCTAssertEqual(linkedLog.quantity, 1)
            XCTAssertEqual(linkedLog.unit, "session")
            XCTAssertEqual(linkedLog.result, "done")

            XCTAssertEqual(Set(try context.fetch(FetchDescriptor<Goal>()).map(\.id)), [goalID])
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<GoalLifecycleEvent>()), 1)
            let weight = try XCTUnwrap(context.fetch(FetchDescriptor<WeightRecord>()).first)
            XCTAssertEqual(weight.id, weightID)
            XCTAssertEqual(weight.weightKilograms, 72.5)
            let review = try XCTUnwrap(context.fetch(FetchDescriptor<WeeklyReview>()).first)
            XCTAssertEqual(review.id, reviewID)
            XCTAssertEqual(review.rememberedText, "Build 7 memory")
            XCTAssertTrue(review.isCompleted)
            XCTAssertNoThrow(try LinkIntegrityService.validate(context: context))
        }

        let bootstrapDate = Date(timeIntervalSince1970: 1_730_000_000)
        let bootstrapTimeZone = TimeZone(identifier: "Asia/Tokyo")!
        let bootstrapDay = HabitLocalDay(date: bootstrapDate, timeZone: bootstrapTimeZone)
        var planIDs: Set<UUID> = []
        var lifecycleIDs: Set<UUID> = []
        var metadataIDs: Set<UUID> = []
        var frozenLocalDays: [UUID: String] = [:]
        do {
            let migrated = try PersistenceContainerFactory.makeOnDisk(at: storeURL)
            let context = migrated.mainContext
            try assertSourceFacts(context)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<HabitLogDayMetadata>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<HabitPlanRevision>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<HabitLifecycleEvent>()), 0)

            XCTAssertTrue(try HabitAnalyticsMigrationBootstrap.apply(
                context: context,
                now: bootstrapDate,
                timeZone: bootstrapTimeZone
            ))
            XCTAssertFalse(try HabitAnalyticsMigrationBootstrap.apply(
                context: context,
                now: bootstrapDate,
                timeZone: bootstrapTimeZone
            ))
            let plans = try context.fetch(FetchDescriptor<HabitPlanRevision>())
            XCTAssertEqual(plans.count, 4)
            let plansByHabit = Dictionary(uniqueKeysWithValues: plans.map { ($0.habitID, $0) })
            XCTAssertEqual(plansByHabit[onceHabitID]?.plan, HabitPlan.legacy(mode: .oncePerDay, target: nil))
            XCTAssertEqual(plansByHabit[multipleHabitID]?.plan, HabitPlan.legacy(mode: .multiplePerDay, target: 3))
            XCTAssertEqual(plansByHabit[targetlessHabitID]?.plan, .trackingOnly(recordingMode: .multiplePerDay))
            XCTAssertTrue(plans.allSatisfy { $0.effectiveLocalDay == bootstrapDay.description })
            XCTAssertTrue(plans.allSatisfy { $0.trustCoverageStartLocalDay == bootstrapDay.description })
            planIDs = Set(plans.map(\.id))
            let lifecycle = try context.fetch(FetchDescriptor<HabitLifecycleEvent>())
            XCTAssertEqual(lifecycle.count, 4)
            let statusByHabitID = Dictionary(uniqueKeysWithValues: lifecycle.map {
                ($0.habitID, $0.knownStatus)
            })
            XCTAssertTrue(lifecycle.allSatisfy { $0.kind == .migrationBaseline })
            XCTAssertEqual(statusByHabitID[onceHabitID], .active)
            XCTAssertEqual(statusByHabitID[multipleHabitID], .active)
            XCTAssertEqual(statusByHabitID[targetlessHabitID], .active)
            XCTAssertEqual(statusByHabitID[archivedHabitID], .archived)
            lifecycleIDs = Set(lifecycle.map(\.id))
            let metadataAfterBootstrap = try context.fetch(FetchDescriptor<HabitLogDayMetadata>())
            XCTAssertEqual(metadataAfterBootstrap.count, expectedLogIDs.count)
            XCTAssertTrue(metadataAfterBootstrap.allSatisfy {
                $0.localTimeZoneIdentifier == bootstrapTimeZone.identifier
                    && $0.provenance == .legacyBootstrap
            })
            metadataIDs = Set(metadataAfterBootstrap.map(\.id))
            frozenLocalDays = Dictionary(uniqueKeysWithValues: metadataAfterBootstrap.map {
                ($0.habitLogID, $0.localDayIdentifier)
            })
            XCTAssertTrue(frozenLocalDays.values.allSatisfy { HabitLocalDay($0) != nil })
        }

        do {
            let reopened = try PersistenceContainerFactory.makeOnDisk(at: storeURL)
            let context = reopened.mainContext
            try assertSourceFacts(context)
            XCTAssertFalse(try HabitAnalyticsMigrationBootstrap.apply(
                context: context,
                now: bootstrapDate.addingTimeInterval(86_400),
                timeZone: TimeZone(identifier: "America/New_York")!
            ))
            XCTAssertEqual(Set(try context.fetch(FetchDescriptor<HabitPlanRevision>()).map(\.id)), planIDs)
            XCTAssertEqual(Set(try context.fetch(FetchDescriptor<HabitLifecycleEvent>()).map(\.id)), lifecycleIDs)
            XCTAssertEqual(Set(try context.fetch(FetchDescriptor<HabitLogDayMetadata>()).map(\.id)), metadataIDs)
            XCTAssertEqual(
                Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<HabitLogDayMetadata>()).map {
                    ($0.habitLogID, $0.localDayIdentifier)
                }),
                frozenLocalDays
            )
        }
    }

    func testAnalyticsMakesPauseResumeTransitionDaysNeutralAndStartsNewStreakSegment() {
        let day1 = HabitLocalDay(year: 2026, month: 9, day: 1)
        let day2 = HabitLocalDay(year: 2026, month: 9, day: 2)
        let day3 = HabitLocalDay(year: 2026, month: 9, day: 3)
        let day4 = HabitLocalDay(year: 2026, month: 9, day: 4)
        let plan = HabitPlanSnapshot(
            effectiveDay: day1,
            plan: HabitPlan(recordingMode: .oncePerDay, period: .day, goal: .everyDay, targetCount: 1, weekdays: []),
            trustStartDay: day1
        )
        let logs = [day1, day2, day4].map {
            HabitAnalyticsLog(id: UUID(), localDay: $0, isCompleted: true, occurredAt: Date())
        }
        let result = HabitAnalyticsEngine.evaluate(
            createdAt: day1, logs: logs, plans: [plan], lifecycle: [
                HabitLifecycleSnapshot(day: day1, kind: .created),
                HabitLifecycleSnapshot(day: day2, kind: .paused),
                HabitLifecycleSnapshot(day: day3, kind: .resumed)
            ], asOf: day4
        )
        XCTAssertEqual(result.evaluations.first { $0.start == day2 }?.outcome, .notEvaluated(.lifecycleTransition))
        XCTAssertEqual(result.evaluations.first { $0.start == day3 }?.outcome, .notEvaluated(.lifecycleTransition))
        XCTAssertEqual(result.currentStreak, 1)
    }

    func testCheckInRejectsFutureOccurrence() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let habit = try HabitService(context: context, now: { now }).create(name: "Future guard", recordingMode: .oncePerDay)
        let service = HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            now: { now }
        )
        XCTAssertThrowsError(try service.checkIn(habit, draft: HabitLogDraft(occurredAt: now.addingTimeInterval(301)))) {
            XCTAssertEqual($0 as? HabitCheckInError, .futureOccurrence)
        }
    }

    func testSelectedWeekdayPlanAllowsRestDayActivityWithoutCreatingExpectation() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 12))!
        let habit = try HabitService(context: context, now: { monday }).create(
            name: "Wednesday only",
            plan: HabitPlan(recordingMode: .oncePerDay, period: .day, goal: .selectedWeekdays, targetCount: 1, weekdays: [4])
        )
        let service = HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            now: { monday },
            calendar: calendar
        )
        XCTAssertNoThrow(try service.checkIn(habit, draft: HabitLogDraft(occurredAt: monday)))
        let logs = try context.fetch(FetchDescriptor<HabitLog>())
        XCTAssertEqual(logs.count, 1)
        let metadataByLogID = HabitLogDayResolver.metadataByLogID(
            try context.fetch(FetchDescriptor<HabitLogDayMetadata>())
        )

        let mondayLocalDay = HabitLocalDay(date: monday, timeZone: calendar.timeZone)
        let analytics = HabitAnalyticsEngine.evaluate(
            createdAt: mondayLocalDay,
            logs: logs.map {
                HabitAnalyticsLog(
                    id: $0.id,
                    localDay: HabitLogDayResolver.localDay(
                        for: $0,
                        metadataByLogID: metadataByLogID,
                        fallbackTimeZone: calendar.timeZone
                    ),
                    isCompleted: $0.isCompleted,
                    occurredAt: $0.occurredAt
                )
            },
            plans: [HabitPlanSnapshot(
                effectiveDay: mondayLocalDay,
                plan: HabitPlan(recordingMode: .oncePerDay, period: .day, goal: .selectedWeekdays, targetCount: 1, weekdays: [4]),
                trustStartDay: mondayLocalDay
            )],
            lifecycle: [HabitLifecycleSnapshot(day: mondayLocalDay, kind: .created)],
            asOf: mondayLocalDay,
            timeZone: calendar.timeZone
        )
        XCTAssertEqual(analytics.activityByDay[mondayLocalDay], 1)
        XCTAssertEqual(analytics.current?.outcome, .notEvaluated(.notScheduled))
    }

    func testSelectedWeekdayPlanUsesStableSundayWeekdayIdentity() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12))!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 12))!
        let plan = try HabitRules.validatedPlan(HabitPlan(
            recordingMode: .oncePerDay,
            period: .day,
            goal: .selectedWeekdays,
            targetCount: 1,
            weekdays: [1]
        ))

        XCTAssertTrue(HabitPlanResolver.isScheduled(plan, on: sunday, timeZone: calendar.timeZone))
        XCTAssertFalse(HabitPlanResolver.isScheduled(plan, on: monday, timeZone: calendar.timeZone))
    }

    func testCrossPeriodPlanEditUsesCoarserCleanBoundary() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 12))!
        let service = HabitService(context: context, now: { wednesday })
        let habit = try service.create(name: "Cross period", plan: HabitPlan(recordingMode: .oncePerDay, period: .day, goal: .everyDay, targetCount: 1, weekdays: []))
        try service.update(habit, name: habit.name, plan: HabitPlan(recordingMode: .oncePerDay, period: .week, goal: .count, targetCount: 3, weekdays: []))
        let revisions = try context.fetch(FetchDescriptor<HabitPlanRevision>()).filter { $0.habitID == habit.id }
        XCTAssertEqual(revisions.map(\.effectiveLocalDay).sorted(), ["2026-09-09", "2026-09-14"])
    }

    func testEffectivePlanControlsRuntimeBeforeAndAfterFutureBoundary() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dayOne = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 12))!
        let dayTwo = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 12))!
        var clock = dayOne
        let habitService = HabitService(context: context, now: { clock })
        let habit = try habitService.create(
            name: "Effective source",
            plan: HabitPlan(
                recordingMode: .oncePerDay,
                period: .day,
                goal: .everyDay,
                targetCount: 1,
                weekdays: []
            )
        )
        try habitService.update(
            habit,
            name: habit.name,
            plan: HabitPlan(
                recordingMode: .multiplePerDay,
                period: .day,
                goal: .everyDay,
                targetCount: 5,
                weekdays: []
            )
        )

        let plans = try context.fetch(FetchDescriptor<HabitPlanRevision>())
        let configuration = try XCTUnwrap(context.fetch(FetchDescriptor<HabitConfiguration>()).first)
        XCTAssertEqual(configuration.recordingMode, .multiplePerDay)
        XCTAssertEqual(
            HabitRuntimeResolver.settings(
                for: habit.id,
                on: dayOne,
                plans: plans,
                legacyConfigurations: [configuration],
                timeZone: calendar.timeZone
            ),
            HabitSettings(recordingMode: .oncePerDay, dailyTargetCount: nil)
        )

        let checkInService = HabitCheckInService(
            context: context,
            mediaStore: MediaStore(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            now: { clock },
            calendar: calendar
        )
        XCTAssertNoThrow(try checkInService.incrementCount(habit, occurredAt: dayOne))
        XCTAssertThrowsError(try checkInService.incrementCount(habit, occurredAt: dayOne)) {
            XCTAssertEqual($0 as? HabitCheckInError, .alreadyCheckedInToday)
        }

        configuration.recordingMode = .oncePerDay
        configuration.dailyTargetCount = nil
        try context.save()
        clock = dayTwo
        XCTAssertEqual(
            HabitRuntimeResolver.settings(
                for: habit.id,
                on: dayTwo,
                plans: plans,
                legacyConfigurations: [configuration],
                timeZone: calendar.timeZone
            ),
            HabitSettings(recordingMode: .multiplePerDay, dailyTargetCount: 5)
        )
        XCTAssertNoThrow(try checkInService.incrementCount(habit, occurredAt: dayTwo))
        XCTAssertNoThrow(try checkInService.incrementCount(habit, occurredAt: dayTwo))

        let logs = try context.fetch(FetchDescriptor<HabitLog>())
        let metadata = try context.fetch(FetchDescriptor<HabitLogDayMetadata>())
        XCTAssertEqual(HabitTodayProgress(
            habitID: habit.id,
            logs: logs,
            dayMetadata: metadata,
            settings: HabitRuntimeResolver.settings(
                for: habit.id,
                on: dayTwo,
                plans: plans,
                legacyConfigurations: [configuration],
                timeZone: calendar.timeZone
            ),
            now: dayTwo,
            calendar: calendar
        ).count, 2)
    }

    func testNameOnlyEditPreservesPendingPlanAndPlanEditReplacesIt() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 12))!
        let service = HabitService(context: context, now: { wednesday })
        let habit = try service.create(
            name: "Run",
            plan: HabitPlan(
                recordingMode: .oncePerDay,
                period: .day,
                goal: .everyDay,
                targetCount: 1,
                weekdays: []
            )
        )
        let firstPendingPlan = HabitPlan(
            recordingMode: .oncePerDay,
            period: .week,
            goal: .count,
            targetCount: 3,
            weekdays: []
        )
        try service.updatePlan(habit, plan: firstPendingPlan)

        var revisions = try context.fetch(FetchDescriptor<HabitPlanRevision>())
        let firstPending = try XCTUnwrap(HabitPlanResolver.pendingPlanRevision(
            for: habit.id,
            on: wednesday,
            plans: revisions,
            timeZone: calendar.timeZone
        ))
        XCTAssertEqual(firstPending.plan, firstPendingPlan)
        XCTAssertEqual(firstPending.effectiveLocalDay, "2026-09-14")
        let revisionIDsBeforeNameEdit = Set(revisions.map(\.id))

        try service.updateName(habit, name: "Morning Run")
        revisions = try context.fetch(FetchDescriptor<HabitPlanRevision>())
        XCTAssertEqual(habit.name, "Morning Run")
        XCTAssertEqual(Set(revisions.map(\.id)), revisionIDsBeforeNameEdit)
        XCTAssertEqual(
            HabitPlanResolver.pendingPlanRevision(
                for: habit.id,
                on: wednesday,
                plans: revisions,
                timeZone: calendar.timeZone
            )?.plan,
            firstPendingPlan
        )

        let replacementPlan = HabitPlan(
            recordingMode: .oncePerDay,
            period: .week,
            goal: .count,
            targetCount: 5,
            weekdays: []
        )
        try service.updatePlan(habit, plan: replacementPlan)
        revisions = try context.fetch(FetchDescriptor<HabitPlanRevision>())
        let replacement = try XCTUnwrap(HabitPlanResolver.pendingPlanRevision(
            for: habit.id,
            on: wednesday,
            plans: revisions,
            timeZone: calendar.timeZone
        ))
        XCTAssertEqual(revisions.count, 2)
        XCTAssertFalse(revisions.contains { $0.id == firstPending.id })
        XCTAssertEqual(replacement.plan, replacementPlan)
        XCTAssertEqual(replacement.effectiveLocalDay, "2026-09-14")
    }

    func testMultiplePerDayAnalyticsPreservesEachPositiveCompletion() {
        let day = HabitLocalDay(year: 2026, month: 9, day: 7)
        let plan = HabitPlanSnapshot(
            effectiveDay: day,
            plan: HabitPlan(recordingMode: .multiplePerDay, period: .day, goal: .everyDay, targetCount: 5, weekdays: []),
            trustStartDay: day
        )
        let result = HabitAnalyticsEngine.evaluate(
            createdAt: day,
            logs: [day, day, day].map {
                HabitAnalyticsLog(id: UUID(), localDay: $0, isCompleted: true, occurredAt: Date())
            },
            plans: [plan],
            lifecycle: [HabitLifecycleSnapshot(day: day, kind: .created)],
            asOf: day,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(result.current?.actual, 3)
        XCTAssertEqual(result.current?.progress, 0.6)
        XCTAssertEqual(result.current?.outcome, .open)
    }

    func testPlanChangeInsideWeekKeepsThatWeekNeutral() {
        let monday = HabitLocalDay(year: 2026, month: 9, day: 7)
        let wednesday = HabitLocalDay(year: 2026, month: 9, day: 9)
        let followingMonday = HabitLocalDay(year: 2026, month: 9, day: 14)
        let result = HabitAnalyticsEngine.evaluate(
            createdAt: monday,
            logs: [],
            plans: [
                HabitPlanSnapshot(
                    effectiveDay: monday,
                    plan: HabitPlan(recordingMode: .multiplePerDay, period: .week, goal: .count, targetCount: 3, weekdays: []),
                    trustStartDay: monday
                ),
                HabitPlanSnapshot(
                    effectiveDay: wednesday,
                    plan: HabitPlan(recordingMode: .oncePerDay, period: .day, goal: .everyDay, targetCount: 1, weekdays: []),
                    trustStartDay: wednesday
                )
            ],
            lifecycle: [HabitLifecycleSnapshot(day: monday, kind: .created)],
            asOf: followingMonday,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(
            result.evaluations.first { $0.start == monday && $0.period == .week }?.outcome,
            .notEvaluated(.partialCoverage)
        )
    }

    func testCurrentDailyMetricsDoNotBridgeAcrossWeeklyPlanSegment() {
        let firstDay = HabitLocalDay(year: 2026, month: 9, day: 1)
        let firstSaturday = HabitLocalDay(year: 2026, month: 9, day: 5)
        let firstSunday = HabitLocalDay(year: 2026, month: 9, day: 6)
        let weeklyStart = HabitLocalDay(year: 2026, month: 9, day: 7)
        let currentStart = HabitLocalDay(year: 2026, month: 9, day: 14)
        let currentDay = HabitLocalDay(year: 2026, month: 9, day: 15)
        let dailyPlan = HabitPlan(
            recordingMode: .oncePerDay,
            period: .day,
            goal: .everyDay,
            targetCount: 1,
            weekdays: []
        )
        let weeklyPlan = HabitPlan(
            recordingMode: .oncePerDay,
            period: .week,
            goal: .count,
            targetCount: 3,
            weekdays: []
        )
        let summary = HabitAnalyticsEngine.evaluate(
            createdAt: firstDay,
            logs: [firstSaturday, firstSunday, currentStart, currentDay].map {
                HabitAnalyticsLog(id: UUID(), localDay: $0, isCompleted: true, occurredAt: Date())
            },
            plans: [
                HabitPlanSnapshot(effectiveDay: firstDay, plan: dailyPlan, trustStartDay: firstDay),
                HabitPlanSnapshot(effectiveDay: weeklyStart, plan: weeklyPlan, trustStartDay: weeklyStart),
                HabitPlanSnapshot(effectiveDay: currentStart, plan: dailyPlan, trustStartDay: currentStart)
            ],
            lifecycle: [HabitLifecycleSnapshot(day: firstDay, kind: .created)],
            asOf: currentDay,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(summary.adherence, 1)
        XCTAssertEqual(summary.consistency, 1)
        XCTAssertEqual(summary.currentStreak, 2)
        XCTAssertEqual(summary.bestStreak, 2)
    }

    func testCurrentWeeklyMetricsDoNotBridgeAcrossMonthlyPlanSegment() {
        let firstWeek = HabitLocalDay(year: 2026, month: 8, day: 3)
        let monthStart = HabitLocalDay(year: 2026, month: 9, day: 1)
        let currentWeek = HabitLocalDay(year: 2026, month: 10, day: 5)
        let afterCurrentWeek = HabitLocalDay(year: 2026, month: 10, day: 12)
        let weeklyPlan = HabitPlan(
            recordingMode: .oncePerDay,
            period: .week,
            goal: .count,
            targetCount: 3,
            weekdays: []
        )
        let monthlyPlan = HabitPlan(
            recordingMode: .oncePerDay,
            period: .month,
            goal: .count,
            targetCount: 3,
            weekdays: []
        )
        let summary = HabitAnalyticsEngine.evaluate(
            createdAt: firstWeek,
            logs: [currentWeek, currentWeek.adding(days: 1)!, currentWeek.adding(days: 2)!].map {
                HabitAnalyticsLog(id: UUID(), localDay: $0, isCompleted: true, occurredAt: Date())
            },
            plans: [
                HabitPlanSnapshot(effectiveDay: firstWeek, plan: weeklyPlan, trustStartDay: firstWeek),
                HabitPlanSnapshot(effectiveDay: monthStart, plan: monthlyPlan, trustStartDay: monthStart),
                HabitPlanSnapshot(effectiveDay: currentWeek, plan: weeklyPlan, trustStartDay: currentWeek)
            ],
            lifecycle: [HabitLifecycleSnapshot(day: firstWeek, kind: .created)],
            asOf: afterCurrentWeek,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(summary.adherence, 1)
        XCTAssertEqual(summary.consistency, 1)
        XCTAssertEqual(summary.currentStreak, 1)
        XCTAssertEqual(summary.bestStreak, 1)
    }

    func testLifecycleRestartStartsNewCurrentMetricsSegment() {
        let day1 = HabitLocalDay(year: 2026, month: 9, day: 1)
        let day2 = HabitLocalDay(year: 2026, month: 9, day: 2)
        let day3 = HabitLocalDay(year: 2026, month: 9, day: 3)
        let day4 = HabitLocalDay(year: 2026, month: 9, day: 4)
        let day5 = HabitLocalDay(year: 2026, month: 9, day: 5)
        let day6 = HabitLocalDay(year: 2026, month: 9, day: 6)
        let plan = HabitPlan(
            recordingMode: .oncePerDay,
            period: .day,
            goal: .everyDay,
            targetCount: 1,
            weekdays: []
        )
        let transitions: [(HabitLifecycleEventKind, HabitLifecycleEventKind)] = [
            (.paused, .resumed),
            (.completed, .restarted),
            (.archived, .restarted)
        ]

        for (stop, restart) in transitions {
            let summary = HabitAnalyticsEngine.evaluate(
                createdAt: day1,
                logs: [day2, day5, day6].map {
                    HabitAnalyticsLog(id: UUID(), localDay: $0, isCompleted: true, occurredAt: Date())
                },
                plans: [HabitPlanSnapshot(effectiveDay: day1, plan: plan, trustStartDay: day1)],
                lifecycle: [
                    HabitLifecycleSnapshot(day: day1, kind: .created),
                    HabitLifecycleSnapshot(day: day3, kind: stop),
                    HabitLifecycleSnapshot(day: day4, kind: restart)
                ],
                asOf: day6,
                timeZone: TimeZone(secondsFromGMT: 0)!
            )

            XCTAssertEqual(summary.adherence, 1, "Failed transition \(stop) → \(restart)")
            XCTAssertEqual(summary.consistency, 1, "Failed transition \(stop) → \(restart)")
            XCTAssertEqual(summary.currentStreak, 2, "Failed transition \(stop) → \(restart)")
        }
    }

    func testTrackingOnlyToDailyStartsStrictMetricsAtDailyBoundary() {
        let day1 = HabitLocalDay(year: 2026, month: 9, day: 1)
        let day3 = HabitLocalDay(year: 2026, month: 9, day: 3)
        let day4 = HabitLocalDay(year: 2026, month: 9, day: 4)
        let summary = HabitAnalyticsEngine.evaluate(
            createdAt: day1,
            logs: [day1, day3, day4].map {
                HabitAnalyticsLog(id: UUID(), localDay: $0, isCompleted: true, occurredAt: Date())
            },
            plans: [
                HabitPlanSnapshot(
                    effectiveDay: day1,
                    plan: .trackingOnly(recordingMode: .oncePerDay),
                    trustStartDay: day1
                ),
                HabitPlanSnapshot(
                    effectiveDay: day3,
                    plan: HabitPlan(
                        recordingMode: .oncePerDay,
                        period: .day,
                        goal: .everyDay,
                        targetCount: 1,
                        weekdays: []
                    ),
                    trustStartDay: day3
                )
            ],
            lifecycle: [HabitLifecycleSnapshot(day: day1, kind: .created)],
            asOf: day4,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(summary.adherence, 1)
        XCTAssertEqual(summary.currentStreak, 2)
    }

    func testWeeklyAndMonthlyCurrentEvaluationsUseWholePeriodActivity() {
        let monday = HabitLocalDay(year: 2026, month: 9, day: 7)
        let tuesday = HabitLocalDay(year: 2026, month: 9, day: 8)
        let wednesday = HabitLocalDay(year: 2026, month: 9, day: 9)
        let weeklyPlan = HabitPlanSnapshot(
            effectiveDay: monday,
            plan: HabitPlan(
                recordingMode: .oncePerDay,
                period: .week,
                goal: .count,
                targetCount: 3,
                weekdays: []
            ),
            trustStartDay: monday
        )
        let weekly = HabitAnalyticsEngine.evaluate(
            createdAt: monday,
            logs: [monday, tuesday].map {
                HabitAnalyticsLog(id: UUID(), localDay: $0, isCompleted: true, occurredAt: Date())
            },
            plans: [weeklyPlan],
            lifecycle: [HabitLifecycleSnapshot(day: monday, kind: .created)],
            asOf: wednesday,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        XCTAssertEqual(weekly.current?.start, monday)
        XCTAssertEqual(weekly.current?.actual, 2)
        XCTAssertEqual(weekly.current?.target, 3)

        let monthStart = HabitLocalDay(year: 2026, month: 9, day: 1)
        let monthNow = HabitLocalDay(year: 2026, month: 9, day: 15)
        let monthlyPlan = HabitPlanSnapshot(
            effectiveDay: monthStart,
            plan: HabitPlan(
                recordingMode: .multiplePerDay,
                period: .month,
                goal: .count,
                targetCount: 5,
                weekdays: []
            ),
            trustStartDay: monthStart
        )
        let monthly = HabitAnalyticsEngine.evaluate(
            createdAt: monthStart,
            logs: [monthStart, monthStart, HabitLocalDay(year: 2026, month: 9, day: 10)].map {
                HabitAnalyticsLog(id: UUID(), localDay: $0, isCompleted: true, occurredAt: Date())
            },
            plans: [monthlyPlan],
            lifecycle: [HabitLifecycleSnapshot(day: monthStart, kind: .created)],
            asOf: monthNow,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        XCTAssertEqual(monthly.current?.start, monthStart)
        XCTAssertEqual(monthly.current?.actual, 3)
        XCTAssertEqual(monthly.current?.target, 5)
    }

    func testDailyMonthCalendarDistinguishesRestActivityMissNeutralAndFuture() {
        let monthStart = HabitLocalDay(year: 2026, month: 9, day: 1)
        let wednesday = HabitLocalDay(year: 2026, month: 9, day: 2)
        let sunday = HabitLocalDay(year: 2026, month: 9, day: 6)
        let pauseDay = HabitLocalDay(year: 2026, month: 9, day: 10)
        let resumeDay = HabitLocalDay(year: 2026, month: 9, day: 11)
        let asOf = HabitLocalDay(year: 2026, month: 9, day: 15)
        let summary = HabitAnalyticsEngine.evaluate(
            createdAt: monthStart,
            logs: [HabitAnalyticsLog(id: UUID(), localDay: sunday, isCompleted: true, occurredAt: Date())],
            plans: [HabitPlanSnapshot(
                effectiveDay: monthStart,
                plan: HabitPlan(
                    recordingMode: .oncePerDay,
                    period: .day,
                    goal: .selectedWeekdays,
                    targetCount: 1,
                    weekdays: [4]
                ),
                trustStartDay: monthStart
            )],
            lifecycle: [
                HabitLifecycleSnapshot(day: monthStart, kind: .created),
                HabitLifecycleSnapshot(day: pauseDay, kind: .paused),
                HabitLifecycleSnapshot(day: resumeDay, kind: .resumed)
            ],
            asOf: asOf,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let cells = HabitMonthCalendarBuilder.cells(
            containing: asOf,
            evaluations: summary.evaluations,
            activityByDay: summary.activityByDay,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(cells.count, 30)
        XCTAssertEqual(cells.first { $0.day == sunday }?.state, .rest)
        XCTAssertEqual(cells.first { $0.day == sunday }?.activityCount, 1)
        XCTAssertEqual(cells.first { $0.day == wednesday }?.state, .missed)
        XCTAssertEqual(cells.first { $0.day == pauseDay }?.state, .neutral)
        XCTAssertEqual(cells.first { $0.day == HabitLocalDay(year: 2026, month: 9, day: 30) }?.state, .future)
    }

    func testDailyWeekdayPatternUsesScheduledEligibleSuccessRate() {
        let sunday = HabitLocalDay(year: 2026, month: 9, day: 6)
        let monday = HabitLocalDay(year: 2026, month: 9, day: 7)
        let tuesday = HabitLocalDay(year: 2026, month: 9, day: 8)
        let wednesday = HabitLocalDay(year: 2026, month: 9, day: 9)
        let thursday = HabitLocalDay(year: 2026, month: 9, day: 10)
        let plan = HabitPlan(
            recordingMode: .oncePerDay,
            period: .day,
            goal: .selectedWeekdays,
            targetCount: 1,
            weekdays: [2, 3]
        )
        func evaluation(_ day: HabitLocalDay, _ outcome: HabitPeriodOutcome) -> HabitPeriodEvaluation {
            HabitPeriodEvaluation(
                id: day.description,
                start: day,
                end: day,
                period: .day,
                actual: outcome == .achieved ? 1 : 0,
                target: 1,
                progress: outcome == .achieved ? 1 : 0,
                outcome: outcome,
                plan: plan
            )
        }
        let pattern = HabitWeekdayPatternBuilder.make(
            period: .day,
            evaluations: [
                evaluation(sunday, .notEvaluated(.notScheduled)),
                evaluation(monday, .achieved),
                evaluation(tuesday, .missed),
                evaluation(wednesday, .open),
                evaluation(thursday, .notEvaluated(.lifecycleTransition))
            ],
            activityByDay: [sunday: 3],
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(pattern.metric, .scheduledDaySuccessRate)
        XCTAssertEqual(pattern.buckets.first { $0.weekday == 1 }?.eligibleCount, 0)
        XCTAssertNil(pattern.buckets.first { $0.weekday == 1 }?.successRate)
        XCTAssertEqual(pattern.buckets.first { $0.weekday == 2 }?.successRate, 1)
        XCTAssertEqual(pattern.buckets.first { $0.weekday == 3 }?.successRate, 0)
        XCTAssertNil(pattern.buckets.first { $0.weekday == 4 }?.successRate)
        XCTAssertNil(pattern.buckets.first { $0.weekday == 5 }?.successRate)
    }

    func testNonDailyWeekdayPatternUsesActivityDistribution() {
        let sunday = HabitLocalDay(year: 2026, month: 9, day: 6)
        let monday = HabitLocalDay(year: 2026, month: 9, day: 7)

        for period in [HabitPlanPeriod.week, .month, .trackingOnly] {
            let pattern = HabitWeekdayPatternBuilder.make(
                period: period,
                evaluations: [],
                activityByDay: [sunday: 2, monday: 1],
                timeZone: TimeZone(secondsFromGMT: 0)!
            )
            XCTAssertEqual(pattern.metric, .activityDistribution)
            XCTAssertEqual(pattern.buckets.first { $0.weekday == 1 }?.activityCount, 2)
            XCTAssertEqual(pattern.buckets.first { $0.weekday == 2 }?.activityCount, 1)
            XCTAssertTrue(pattern.buckets.allSatisfy { $0.eligibleCount == 0 && $0.successRate == nil })
        }
    }

    func testLocalDayUsesCivilCalendarAcrossDSTChanges() {
        let timeZone = TimeZone(identifier: "America/New_York")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let spring = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let autumn = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!

        XCTAssertEqual(HabitLocalDay(date: spring, timeZone: timeZone).adding(days: 1, timeZone: timeZone), HabitLocalDay(year: 2026, month: 3, day: 9))
        XCTAssertEqual(HabitLocalDay(date: autumn, timeZone: timeZone).adding(days: 1, timeZone: timeZone), HabitLocalDay(year: 2026, month: 11, day: 2))
    }

    func testLocalDayRejectsImpossibleDatesAndAcceptsLeapDay() {
        XCTAssertNil(HabitLocalDay("2026-02-31"))
        XCTAssertNil(HabitLocalDay("2027-02-29"))
        XCTAssertNil(HabitLocalDay("2026-2-03"))
        XCTAssertEqual(
            HabitLocalDay("2028-02-29"),
            HabitLocalDay(year: 2028, month: 2, day: 29)
        )
    }

    func testBackdatedPositiveActivityRecomputesHistoricalOutcome() {
        let day1 = HabitLocalDay(year: 2026, month: 9, day: 1)
        let day3 = HabitLocalDay(year: 2026, month: 9, day: 3)
        let plan = HabitPlanSnapshot(
            effectiveDay: day1,
            plan: HabitPlan(
                recordingMode: .oncePerDay,
                period: .day,
                goal: .everyDay,
                targetCount: 1,
                weekdays: []
            ),
            trustStartDay: day1
        )
        let lifecycle = [HabitLifecycleSnapshot(day: day1, kind: .created)]
        let before = HabitAnalyticsEngine.evaluate(
            createdAt: day1,
            logs: [],
            plans: [plan],
            lifecycle: lifecycle,
            asOf: day3
        )
        let after = HabitAnalyticsEngine.evaluate(
            createdAt: day1,
            logs: [HabitAnalyticsLog(id: UUID(), localDay: day1, isCompleted: true, occurredAt: Date())],
            plans: [plan],
            lifecycle: lifecycle,
            asOf: day3
        )

        XCTAssertEqual(before.evaluations.first { $0.start == day1 }?.outcome, .missed)
        XCTAssertEqual(after.evaluations.first { $0.start == day1 }?.outcome, .achieved)
    }

    func testLifecycleTransitionsDistinguishResumeRestartAndRestore() throws {
        let transitions: [(HabitStatus, HabitLifecycleEventKind)] = [
            (.paused, .resumed),
            (.completed, .restarted),
            (.archived, .restored)
        ]
        for (status, expectedKind) in transitions {
            let container = try PersistenceContainerFactory.makeInMemory()
            let context = container.mainContext
            var clock = Date(timeIntervalSince1970: 1_800_000_000)
            let service = HabitService(context: context, now: { clock })
            let habit = try service.create(name: "Lifecycle \(status.rawValue)")
            clock.addTimeInterval(10)
            try service.transition(habit, to: status)
            clock.addTimeInterval(10)
            try service.transition(habit, to: .active)
            let latest = try XCTUnwrap(context.fetch(FetchDescriptor<HabitLifecycleEvent>())
                .sorted { $0.createdAt > $1.createdAt }
                .first)
            XCTAssertEqual(latest.kind, expectedKind)
        }
    }

    func testJourneyMergesPlanAndLifecycleChronologicallyAndHidesMigrationBaseline() {
        let day1 = HabitLocalDay(year: 2026, month: 9, day: 1)
        let day2 = HabitLocalDay(year: 2026, month: 9, day: 2)
        let day3 = HabitLocalDay(year: 2026, month: 9, day: 3)
        let day4 = HabitLocalDay(year: 2026, month: 9, day: 4)
        let day5 = HabitLocalDay(year: 2026, month: 9, day: 5)
        let dailyPlan = HabitPlan(
            recordingMode: .oncePerDay,
            period: .day,
            goal: .everyDay,
            targetCount: 1,
            weekdays: []
        )
        let weeklyPlan = HabitPlan(
            recordingMode: .oncePerDay,
            period: .week,
            goal: .count,
            targetCount: 3,
            weekdays: []
        )
        let habitID = UUID()
        let plans = [
            HabitPlanRevision(
                habitID: habitID,
                effectiveLocalDay: day1.description,
                plan: dailyPlan,
                trustCoverageStartLocalDay: day1.description,
                createdAt: day1.date()!
            ),
            HabitPlanRevision(
                habitID: habitID,
                effectiveLocalDay: day3.description,
                plan: weeklyPlan,
                trustCoverageStartLocalDay: day3.description,
                createdAt: day2.date()!
            )
        ]
        let events = [
            HabitLifecycleEvent(
                habitID: habitID,
                kind: .paused,
                occurredLocalDay: day2.description,
                occurredAt: day2.date()!
            ),
            HabitLifecycleEvent(
                habitID: habitID,
                kind: .restored,
                occurredLocalDay: day4.description,
                occurredAt: day4.date()!
            ),
            HabitLifecycleEvent(
                habitID: habitID,
                kind: .migrationBaseline,
                occurredLocalDay: day5.description,
                occurredAt: day5.date()!,
                knownStatus: .active
            )
        ]

        let items = HabitJourneyBuilder.items(
            plans: plans,
            lifecycleEvents: events,
            asOf: day5.date()!
        )
        XCTAssertEqual(items.map(\.day), [day4, day3, day2, day1])
        XCTAssertEqual(items.map(\.kind), [
            .lifecycle(.restored),
            .plan(weeklyPlan),
            .lifecycle(.paused),
            .plan(dailyPlan)
        ])
    }

    func testAnalyticsIsIndependentOfInputOrdering() {
        let first = HabitLocalDay(year: 2026, month: 9, day: 1)
        let second = HabitLocalDay(year: 2026, month: 9, day: 2)
        let third = HabitLocalDay(year: 2026, month: 9, day: 3)
        let plan = HabitPlanSnapshot(
            effectiveDay: first,
            plan: HabitPlan(recordingMode: .oncePerDay, period: .day, goal: .everyDay, targetCount: 1, weekdays: []),
            trustStartDay: first
        )
        let logs = [first, second].map {
            HabitAnalyticsLog(id: UUID(), localDay: $0, isCompleted: true, occurredAt: Date())
        }
        let events = [HabitLifecycleSnapshot(day: first, kind: .created)]
        let normal = HabitAnalyticsEngine.evaluate(createdAt: first, logs: logs, plans: [plan], lifecycle: events, asOf: third)
        let shuffled = HabitAnalyticsEngine.evaluate(createdAt: first, logs: Array(logs.reversed()), plans: [plan], lifecycle: Array(events.reversed()), asOf: third)

        XCTAssertEqual(normal, shuffled)
    }

    func testMonthlyMidMonthCreationIsNeutralAndTrackingOnlyHasNoStrictMetrics() {
        let midMonth = HabitLocalDay(year: 2026, month: 9, day: 15)
        let monthEnd = HabitLocalDay(year: 2026, month: 9, day: 30)
        let monthly = HabitPlanSnapshot(
            effectiveDay: midMonth,
            plan: HabitPlan(recordingMode: .oncePerDay, period: .month, goal: .count, targetCount: 3, weekdays: []),
            trustStartDay: midMonth
        )
        let monthlySummary = HabitAnalyticsEngine.evaluate(
            createdAt: midMonth,
            logs: [], plans: [monthly],
            lifecycle: [HabitLifecycleSnapshot(day: midMonth, kind: .created)], asOf: monthEnd
        )
        XCTAssertEqual(monthlySummary.current?.outcome, .notEvaluated(.partialCoverage))

        let tracking = HabitPlanSnapshot(effectiveDay: midMonth, plan: .trackingOnly(recordingMode: .oncePerDay), trustStartDay: midMonth)
        let trackingSummary = HabitAnalyticsEngine.evaluate(
            createdAt: midMonth,
            logs: [HabitAnalyticsLog(id: UUID(), localDay: midMonth, isCompleted: true, occurredAt: Date())],
            plans: [tracking], lifecycle: [HabitLifecycleSnapshot(day: midMonth, kind: .created)], asOf: monthEnd
        )
        XCTAssertNil(trackingSummary.adherence)
        XCTAssertNil(trackingSummary.consistency)
        XCTAssertNil(trackingSummary.currentStreak)
        XCTAssertEqual(trackingSummary.activityByDay[midMonth], 1)
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
