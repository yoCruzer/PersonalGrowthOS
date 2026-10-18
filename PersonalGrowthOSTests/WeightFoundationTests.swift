import Foundation
import SwiftData
import XCTest
@testable import PersonalGrowthOS

@MainActor
final class WeightFoundationTests: XCTestCase {
    func testReviewDailyMeansAreEqualWeightAndLatestIsAnActualMeasurement() throws {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        func instant(_ day: Int, _ hour: Int) -> Date { ImportantCivilDay(year: 2026, month: 10, day: day).instant(minutes: hour * 60, timeZone: zone)! }
        var builder = WeightReviewBuilder(now: instant(17, 18), timeZone: zone)
        let a = WeightMeasurement(kilograms: 70, recordedAt: instant(16, 8))
        let b = WeightMeasurement(kilograms: 72, recordedAt: instant(16, 18))
        let c = WeightMeasurement(kilograms: 75, recordedAt: instant(17, 8))
        [c, a, b, WeightMeasurement(kilograms: 1, recordedAt: instant(17, 19))].forEach { builder.append($0) }
        let snapshot = builder.snapshot(), summary = try XCTUnwrap(snapshot.summaries[.week])
        XCTAssertEqual(snapshot.daily.map(\.mean), [71, 75])
        XCTAssertEqual(try XCTUnwrap(summary.mean), 73, accuracy: 1e-10)
        XCTAssertEqual(summary.days, 2); XCTAssertEqual(summary.observations, 3)
        XCTAssertEqual(snapshot.latest.map(\.id), [c.id, b.id])
        XCTAssertEqual(snapshot.latest[0].kilograms - snapshot.latest[1].kilograms, 3)
    }

    func testReviewCalendarWindowsClampMonthsAndYearsAndUseExclusiveEnd() throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        func snapshot(_ y: Int, _ m: Int, _ d: Int) -> WeightReviewSnapshot {
            WeightReviewBuilder(now: ImportantCivilDay(year: y, month: m, day: d).instant(minutes: 720, timeZone: zone)!, timeZone: zone).snapshot()
        }
        let value = snapshot(2026, 10, 17)
        for (range, expected) in [(WeightReviewRange.week, "2026-10-11"), (.month, "2026-09-18"), (.quarter, "2026-07-18"), (.year, "2025-10-18")] {
            XCTAssertEqual(HabitLocalDay(date: value.summaries[range]!.start, timeZone: zone).description, expected)
        }
        XCTAssertEqual(HabitLocalDay(date: snapshot(2024, 5, 30).summaries[.quarter]!.start, timeZone: zone).description, "2024-02-29")
        XCTAssertEqual(HabitLocalDay(date: snapshot(2024, 2, 28).summaries[.year]!.start, timeZone: zone).description, "2023-02-28")
        var builder = WeightReviewBuilder(now: Date(), through: value.asOfDay, timeZone: zone)
        builder.append(.init(kilograms: 70, recordedAt: value.endExclusive.addingTimeInterval(-1)))
        builder.append(.init(kilograms: 80, recordedAt: value.endExclusive))
        XCTAssertEqual(builder.snapshot().summaries[.all]?.observations, 1)
    }

    func testReviewCoverageAndStreaksUseAllHistoryAndRespectYesterdayAndGaps() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let now = ImportantCivilDay(year: 2026, month: 1, day: 3).instant(minutes: 720, timeZone: zone)!
        var builder = WeightReviewBuilder(now: now, timeZone: zone)
        let days = ["2025-01-01", "2025-12-30", "2025-12-31", "2026-01-01", "2026-01-02"]
        for day in days {
            let instant = ImportantCivilDay(identifier: day)!.instant(minutes: 720, timeZone: zone)!
            builder.append(.init(kilograms: 70, recordedAt: instant)); builder.append(.init(kilograms: 72, recordedAt: instant))
        }
        let snapshot = builder.snapshot()
        XCTAssertEqual(snapshot.recordedDays, 5); XCTAssertEqual(snapshot.spanDays, 368)
        XCTAssertEqual(snapshot.longestStreak, 4); XCTAssertEqual(snapshot.endingStreak, 4)
        XCTAssertEqual(snapshot.streakEnd, snapshot.calendar.date(byAdding: .day, value: -1, to: snapshot.asOfDay))
        XCTAssertEqual(snapshot.summaries[.month]?.days, 4)
        XCTAssertEqual(Set(snapshot.daily.map(\.segment)).count, 2)
        let empty = WeightReviewBuilder(now: now, timeZone: zone).snapshot()
        XCTAssertNil(empty.earliest); XCTAssertNil(empty.streakEnd); XCTAssertEqual(empty.endingStreak, 0)
    }

    func testReviewAxisContainsEveryEnabledReferenceAndExtremeValueWithoutFabricatingDays() {
        let zone = TimeZone(secondsFromGMT: 0)!, now = Date()
        var builder = WeightReviewBuilder(now: now, timeZone: zone)
        builder.append(.init(kilograms: 70, recordedAt: now.addingTimeInterval(-86400)))
        builder.append(.init(kilograms: 1000, recordedAt: now.addingTimeInterval(-86400 * 60)))
        let snapshot = builder.snapshot()
        XCTAssertEqual(snapshot.points(.week).count, 1)
        let axis = snapshot.axis(range: .week, references: [.quarter])
        XCTAssertTrue(axis.domain.contains(70)); XCTAssertTrue(axis.domain.contains(snapshot.summaries[.quarter]!.mean!))
        XCTAssertGreaterThanOrEqual(axis.domain.upperBound - axis.domain.lowerBound, 2)
        XCTAssertEqual(snapshot.daily.count, 2)
        XCTAssertTrue(snapshot.axis(range: .all, references: []).domain.contains(1000))
    }

    func testReviewCurrentZoneIsFrozenAndSameInstantHasConsistentDifferentDayAfterRefresh() {
        let instant = ISO8601DateFormatter().date(from: "2026-10-17T01:00:00Z")!
        var west = WeightReviewBuilder(now: instant.addingTimeInterval(3600), timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        var east = WeightReviewBuilder(now: instant.addingTimeInterval(3600), timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        let measurement = WeightMeasurement(kilograms: 70, recordedAt: instant)
        west.append(measurement); east.append(measurement)
        let a = west.snapshot(), b = east.snapshot()
        XCTAssertEqual(HabitLocalDay(date: a.daily[0].day, timeZone: a.calendar.timeZone).description, "2026-10-16")
        XCTAssertEqual(HabitLocalDay(date: b.daily[0].day, timeZone: b.calendar.timeZone).description, "2026-10-17")
        XCTAssertEqual(a.latest[0].recordedAt, instant); XCTAssertEqual(b.latest[0].recordedAt, instant)
    }

    func testReviewProductionReaderStreamsFiveYearsAndPagesMeasurementsAfterSaveEditDelete() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("UsageWeight-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("weight.sqlite")
        let container = try PersistenceContainerFactory.makeOnDisk(at: url), context = container.mainContext
        context.autosaveEnabled = false
        let zone = TimeZone(secondsFromGMT: 0)!, now = Date()
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        var mostRecent: UUID?
        for index in 0..<10_000 {
            let at = calendar.date(byAdding: .day, value: -(index % 1826), to: now.addingTimeInterval(-60))!
            let record = WeightRecord(weightKilograms: 70 + Double(index % 30) / 10, recordedAt: at, createdAt: at)
            if index == 0 { mostRecent = record.id }
            context.insert(record)
        }
        try context.save()
        let clock = ContinuousClock(), began = clock.now
        let reader = WeightReviewReader(modelContainer: container)
        let snapshot = try await reader.snapshot(now: now, zone: zone)
        let elapsed = began.duration(to: clock.now)
        XCTAssertEqual(snapshot.daily.count, 1826); XCTAssertEqual(snapshot.summaries[.all]?.observations, 10_000)
        XCTAssertEqual(snapshot.latest.count, 2)
        let first = try await reader.records(now: now, limit: 50)
        let second = try await reader.records(now: now, offset: 50, limit: 50)
        XCTAssertEqual(first.count, 50); XCTAssertEqual(second.count, 50)
        XCTAssertTrue(Set(first.map(\.id)).isDisjoint(with: Set(second.map(\.id))))
        let recent = try await reader.records(now: now, limit: 5); XCTAssertEqual(recent.count, 5)
        let targetID = mostRecent!
        let target = try XCTUnwrap(context.fetch(FetchDescriptor<WeightRecord>(predicate: #Predicate { $0.id == targetID })).first)
        let earliest = calendar.date(byAdding: .day, value: -2000, to: now)!
        try WeightRecordService(context: context).update(target, weightKilograms: 80, recordedAt: earliest)
        let changed = try await WeightReviewReader(modelContainer: container).snapshot(now: Date(), zone: zone)
        XCTAssertEqual(changed.recordedDays, 1827); XCTAssertEqual(changed.earliest, calendar.startOfDay(for: earliest))
        try WeightRecordService(context: context).delete(target)
        let deleted = try await WeightReviewReader(modelContainer: container).snapshot(now: Date(), zone: zone)
        XCTAssertEqual(deleted.recordedDays, 1826); XCTAssertEqual(deleted.summaries[.all]?.observations, 9999)
        let attachment = XCTAttachment(string: "Synthetic on-disk 10,000 measurements / 1,826 days; streaming snapshot \(elapsed); recent limit=5; pages=50+50 disjoint. Xcode27.1 iPhone18Pro iOS27.0 simulator. No Instruments/RSS measurement.")
        attachment.name = "Usage-weight-five-year-reader-performance"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testReviewMidnightDSTGapUsesCivilBoundariesAndDoesNotBreakStreakOrSpan() throws {
        let zone = TimeZone(identifier: "America/Sao_Paulo")!
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        func instant(_ day: Int, _ minutes: Int) -> Date { ImportantCivilDay(year: 2018, month: 11, day: day).instant(minutes: minutes, timeZone: zone)! }
        // Brazil skipped midnight on Nov 4. The following day starts at 00:00, not 01:00.
        var historical = WeightReviewBuilder(now: instant(6, 720), through: instant(4, 720), timeZone: zone)
        historical.append(.init(kilograms: 70, recordedAt: instant(4, 720)))
        historical.append(.init(kilograms: 80, recordedAt: instant(5, 30)))
        let value = historical.snapshot()
        XCTAssertEqual(value.endExclusive, calendar.startOfDay(for: instant(5, 720)))
        XCTAssertEqual(value.summaries[.all]?.observations, 1)
        XCTAssertEqual(calendar.component(.hour, from: value.summaries[.week]!.start), 0)
        var builder = WeightReviewBuilder(now: instant(5, 720), timeZone: zone)
        for day in [3, 4, 5] { builder.append(.init(kilograms: 70, recordedAt: instant(day, 720))) }
        let snapshot = builder.snapshot()
        XCTAssertEqual(snapshot.recordedDays, 3); XCTAssertEqual(snapshot.spanDays, 3)
        XCTAssertEqual(snapshot.endingStreak, 3); XCTAssertEqual(snapshot.longestStreak, 3)
        XCTAssertEqual(Set(snapshot.daily.map(\.segment)).count, 1)
    }

    func testWeightValidationAcceptsPositiveKilogramsAndRejectsInvalidValues() throws {
        XCTAssertEqual(try WeightRules.validatedKilograms(72.4), 72.4)
        for invalid in [0, -1, .infinity, .nan, WeightRules.maximumKilograms + 0.1] {
            XCTAssertThrowsError(try WeightRules.validatedKilograms(invalid)) {
                XCTAssertEqual($0 as? WeightValidationError, .invalidWeight)
            }
        }
    }

    func testCreateEditDeleteAndLatestTrend() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        var clock = firstDate
        let service = WeightRecordService(context: context, now: { clock })
        let first = try service.create(weightKilograms: 72.5, recordedAt: firstDate)
        clock.addTimeInterval(10)
        let second = try service.create(
            weightKilograms: 71.8,
            recordedAt: firstDate.addingTimeInterval(86_400)
        )

        XCTAssertEqual(try service.fetchAll().map(\.id), [second.id, first.id])
        let initialTrend = try XCTUnwrap(WeightTrend.make(from: service.fetchAll()))
        XCTAssertEqual(initialTrend.latestKilograms, 71.8, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(initialTrend.changeKilograms), -0.7, accuracy: 0.001)

        clock.addTimeInterval(10)
        try service.update(second, weightKilograms: 71.6, recordedAt: second.recordedAt)
        XCTAssertEqual(second.weightKilograms, 71.6)
        XCTAssertEqual(second.updatedAt, clock)

        try service.delete(first)
        XCTAssertEqual(try service.fetchAll().map(\.id), [second.id])
        let remainingTrend = try XCTUnwrap(WeightTrend.make(from: service.fetchAll()))
        XCTAssertEqual(remainingTrend.latestKilograms, 71.6, accuracy: 0.001)
        XCTAssertNil(remainingTrend.changeKilograms)
    }

    func testServiceAndTrendUseStableUUIDOrderingWhenTimestampsMatch() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let firstID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let thirdID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let first = WeightRecord(
            id: firstID,
            weightKilograms: 70,
            recordedAt: timestamp,
            createdAt: timestamp
        )
        let second = WeightRecord(
            id: secondID,
            weightKilograms: 71,
            recordedAt: timestamp,
            createdAt: timestamp
        )
        let third = WeightRecord(
            id: thirdID,
            weightKilograms: 73,
            recordedAt: timestamp,
            createdAt: timestamp
        )
        [third, first, second].forEach(context.insert)
        try context.save()

        let serviceOrder = try WeightRecordService(context: context).fetchAll()
        XCTAssertEqual(serviceOrder.map(\.id), [firstID, secondID, thirdID])
        XCTAssertEqual(
            WeightRecordOrdering.oldestFirst([third, first, second]).map(\.id),
            [thirdID, secondID, firstID]
        )

        let trend = try XCTUnwrap(WeightTrend.make(from: [third, first, second]))
        XCTAssertEqual(trend.latestKilograms, 70, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(trend.changeKilograms), -1, accuracy: 0.001)
    }

    func testWeightRecordPersistsAcrossStoreReopen() throws {
        let fixture = try WeightFixture()
        defer { fixture.remove() }
        let recordID: UUID
        do {
            let container = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
            let record = try WeightRecordService(context: container.mainContext).create(
                weightKilograms: 68.25,
                recordedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
            recordID = record.id
        }

        let reopened = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
        let records = try WeightRecordService(context: reopened.mainContext).fetchAll()
        XCTAssertEqual(records.map(\.id), [recordID])
        XCTAssertEqual(records.first?.weightKilograms, 68.25)
    }

    func testV5StoreMigratesToV6WithoutChangingExistingLifeLogData() throws {
        let fixture = try WeightFixture()
        defer { fixture.remove() }
        let entryID = UUID()
        let habitID = UUID()
        let goalID = UUID()
        do {
            let schema = Schema(versionedSchema: PersonalGrowthSchemaV5.self)
            let configuration = ModelConfiguration(
                "PersonalGrowthOSV1",
                schema: schema,
                url: fixture.storeURL,
                cloudKitDatabase: .none
            )
            let legacy = try ModelContainer(for: schema, configurations: [configuration])
            legacy.mainContext.insert(Entry(
                id: entryID,
                body: "Existing Life Log",
                createdAt: Date()
            ))
            legacy.mainContext.insert(Habit(
                id: habitID,
                name: "Existing Habit",
                normalizedName: "existing habit",
                createdAt: Date()
            ))
            legacy.mainContext.insert(Goal(
                id: goalID,
                title: "Existing Goal",
                normalizedTitle: "existing goal",
                createdAt: Date()
            ))
            try legacy.mainContext.save()
        }

        let migrated = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
        let migratedEntry = try XCTUnwrap(
            migrated.mainContext.fetch(FetchDescriptor<Entry>()).first
        )
        let migratedHabit = try XCTUnwrap(
            migrated.mainContext.fetch(FetchDescriptor<Habit>()).first
        )
        let migratedGoal = try XCTUnwrap(
            migrated.mainContext.fetch(FetchDescriptor<Goal>()).first
        )
        XCTAssertEqual(migratedEntry.id, entryID)
        XCTAssertEqual(migratedEntry.body, "Existing Life Log")
        XCTAssertEqual(migratedHabit.id, habitID)
        XCTAssertEqual(migratedHabit.name, "Existing Habit")
        XCTAssertEqual(migratedGoal.id, goalID)
        XCTAssertEqual(migratedGoal.title, "Existing Goal")
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<WeightRecord>()).count, 0)
    }
}

private struct WeightFixture {
    let root: URL
    let storeURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PGOS-Weight-\(UUID().uuidString)", isDirectory: true)
        storeURL = root.appendingPathComponent("store.sqlite")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

extension WeightFoundationTests {
    func testBuild9TodayWeightExcludesFutureAndSelectsLatestSameDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_730_030_000)
        let start = calendar.startOfDay(for: now)
        let old = WeightRecord(weightKilograms: 72, recordedAt: start.addingTimeInterval(-1), createdAt: now)
        let today = WeightRecord(weightKilograms: 71.5, recordedAt: start, createdAt: now)
        let latest = WeightRecord(weightKilograms: 71.4, recordedAt: now, createdAt: now)
        let future = WeightRecord(weightKilograms: 70, recordedAt: now.addingTimeInterval(86400), createdAt: now)
        let snapshot = TodayWeightSnapshot(records: [future, today, old, latest], now: now, calendar: calendar)
        XCTAssertEqual(snapshot.today?.id, latest.id)
        XCTAssertEqual(snapshot.previous?.id, old.id)
        XCTAssertNil(TodayWeightSnapshot(records: [old, future], now: now, calendar: calendar).today)
        XCTAssertEqual(TodayWeightSnapshot(records: [latest], now: now.addingTimeInterval(86400), calendar: calendar).previous?.id, latest.id)
    }
}

extension WeightFoundationTests {
    func testBuild9WeightInputPreservesDecimalCommaAndRejectsInvalidValues() throws {
        XCTAssertEqual(try WeightRules.kilograms(from: "72.5"), 72.5)
        XCTAssertEqual(try WeightRules.kilograms(from: "72,5"), 72.5)
        for text in ["", "abc", "72,5.1", "0", "-1", "1001", "nan", "inf"] {
            XCTAssertThrowsError(try WeightRules.kilograms(from: text))
        }
    }
}

extension WeightFoundationTests {
    func testUsageBMIUnroundedBoundariesInvalidInputsAndExplicitRoundingHint() throws {
        for reference in BMIReference.allCases {
            for (index,limit) in reference.thresholds.enumerated() {
                XCTAssertEqual(BMICalculation.category(limit-0.0001,reference:reference)?.rawValue,index)
                XCTAssertEqual(BMICalculation.category(limit,reference:reference)?.rawValue,index+1)
                XCTAssertEqual(BMICalculation.category(limit+0.0001,reference:reference)?.rawValue,index+1)
                XCTAssertEqual(BMICalculation.boundaryHint(limit-0.0001,reference:reference),limit)
                XCTAssertNil(BMICalculation.boundaryHint(limit,reference:reference))
            }
        }
        XCTAssertEqual(try XCTUnwrap(BMICalculation.value(kilograms:70,centimeters:175)),70/(1.75*1.75),accuracy:0.00000001)
        for height in [0.0,-1,.nan,.infinity,49.9,300.1] {XCTAssertNil(BMICalculation.value(kilograms:70,centimeters:height))}
        for weight in [0.0,-1,.nan,.infinity] {XCTAssertNil(BMICalculation.value(kilograms:weight,centimeters:175))}
    }
}


extension WeightFoundationTests {
    func testUsageBodyPreferenceReadIsPureSaveDoesNotCommitOtherDraftAndClearRemovesHeight() throws {
        let container=try PersistenceContainerFactory.makeInMemory(),context=container.mainContext
        context.autosaveEnabled=false
        context.insert(Entry(body:"Synthetic unrelated unsaved draft",createdAt:Date()))
        XCTAssertEqual(try BodyReferenceService.read(container),.init(reference:.china))
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<BodyReferenceSettings>()),0)
        XCTAssertEqual(try BodyReferenceService.height(from:"175,5"),175.5)
        for text in ["0","-1","nan","inf","175,5.1","49","301"] {XCTAssertThrowsError(try BodyReferenceService.height(from:text))}
        try BodyReferenceService.save(.init(heightCentimeters:175.5,reference:.who),container:container)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Entry>()),0)
        XCTAssertTrue(context.hasChanges)
        XCTAssertEqual(try BodyReferenceService.read(container),.init(heightCentimeters:175.5,reference:.who))
        try BodyReferenceService.save(.init(reference:.who),container:container)
        let snapshot=try TransferSnapshot.make(context:ModelContext(container))
        XCTAssertNil(snapshot.bodyReferenceSettings.first?.heightCentimeters)
        XCTAssertEqual(snapshot.bodyReferenceSettings.first?.referenceRawValue,"who")
        try BodyReferenceService.save(.init(reference:.china),container:container)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<BodyReferenceSettings>()),0)
    }
}


extension WeightFoundationTests {
    func testReviewCZoneRefreshDropsForeignMidnightAndKeepsCompleteDayFacts() async throws {
        let shanghai=try XCTUnwrap(TimeZone(identifier:"Asia/Shanghai")),la=try XCTUnwrap(TimeZone(identifier:"America/Los_Angeles"))
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=la
        let old=try XCTUnwrap(ImportantCivilDay(year:2026,month:10,day:18).instant(minutes:0,timeZone:shanghai))
        let local=try XCTUnwrap(ImportantCivilDay(year:2026,month:10,day:17).instant(minutes:0,timeZone:la))
        let now=local.addingTimeInterval(23*3600)
        let container=try PersistenceContainerFactory.makeInMemory()
        for (hours,value) in [(0.5,70.0),(10.0,72.0)] {container.mainContext.insert(WeightRecord(weightKilograms:value,recordedAt:local.addingTimeInterval(hours*3600),createdAt:now))}
        try container.mainContext.save()
        let reader=WeightReviewReader(modelContainer:container)
        let broken=try await reader.records(start:old,end:calendar.date(byAdding:.day,value:1,to:local),now:now)
        XCTAssertEqual(broken.count,1,"Old Shanghai midnight is 09:00 LA, excluding the real morning fact")
        let retained=WeightReviewSelection.retainedDay(old,previousZoneID:shanghai.identifier,calendar:calendar)
        XCTAssertNil(retained)
        let recent=try await reader.records(start:retained,end:nil,now:now)
        XCTAssertEqual(Set(recent.map(\.kilograms)),[70,72])
        let same=WeightReviewSelection.retainedDay(local.addingTimeInterval(3600),previousZoneID:la.identifier,calendar:calendar)
        XCTAssertEqual(same,local)
        let complete=try await reader.records(start:same,end:calendar.date(byAdding:.day,value:1,to:local),now:now)
        XCTAssertEqual(complete.count,2)
        let snapshot=try await reader.snapshot(now:now,zone:la)
        XCTAssertEqual(snapshot.daily.first?.mean,71);XCTAssertEqual(snapshot.daily.first?.observations,2)
    }
}

private actor WeightReadBarrier {
    var waiting=false
    var continuation: CheckedContinuation<[WeightMeasurement],Error>?
    func pause() async throws -> [WeightMeasurement] {
        try await withCheckedThrowingContinuation {continuation=$0;waiting=true}
    }
    func release(_ rows: [WeightMeasurement]) {continuation?.resume(returning:rows);continuation=nil}
}
extension WeightFoundationTests {
    func testReviewFixF4LatePageRetryAndRefreshCannotOverwriteCurrentQuery() async throws {
        let a=WeightMeasurementQuery(start:Date(timeIntervalSince1970:0),end:Date(timeIntervalSince1970:100),now:Date(),refresh:0,limit:50)
        var b=a;b.start=Date(timeIntervalSince1970:100);b.end=Date(timeIntervalSince1970:200)
        let aRows=(0..<50).map {WeightMeasurement(kilograms:Double(60+$0),recordedAt:Date(timeIntervalSince1970:Double($0)))}
        let bRows=[WeightMeasurement(kilograms:72,recordedAt:Date(timeIntervalSince1970:150))]
        for retry in [false,true] {
            let loader=WeightMeasurementLoader(),barrier=WeightReadBarrier()
            await loader.load(a,read:{_,_ in aRows})
            if retry {
                await loader.load(a,reset:false,read:{_,_ in throw CocoaError(.fileReadUnknown)})
                XCTAssertTrue(loader.failed)
            }
            let old=Task {
                if retry {await loader.retry(read:{_,_ in try await barrier.pause()})}
                else {await loader.load(a,reset:false,read:{_,_ in try await barrier.pause()})}
            }
            while !(await barrier.waiting) {await Task.yield()}
            await loader.load(b,read:{_,_ in bRows})
            await barrier.release([aRows[0]]);await old.value
            XCTAssertEqual(loader.query,b);XCTAssertEqual(loader.records.map(\.id),bRows.map(\.id));XCTAssertFalse(loader.failed)
            await loader.load(a,read:{_,_ in aRows})
            XCTAssertEqual(loader.records.map(\.id),aRows.map(\.id))
            await loader.load(a,reset:false,read:{_,offset in XCTAssertEqual(offset,50);return [bRows[0]]})
            XCTAssertEqual(loader.records.count,51)
            loader.cancel() // The list header can leave and re-enter the viewport.
            await loader.initial(a,read:{_,_ in XCTFail("Same query must retain its loaded pages");return []})
            XCTAssertEqual(loader.records.count,51)
            var refreshed=a;refreshed.refresh=1
            let pending=WeightReadBarrier()
            let stale=Task {await loader.load(a,reset:false,read:{_,_ in try await pending.pause()})}
            while !(await pending.waiting) {await Task.yield()}
            loader.select(refreshed)
            await loader.load(refreshed,read:{_,_ in bRows})
            await pending.release(aRows);await stale.value
            XCTAssertEqual(loader.records.map(\.id),bRows.map(\.id));XCTAssertEqual(loader.query,refreshed)
        }
    }
    func testReviewFixUX2CutoffRecentAndIndependentAllHistoryUseDifferentBounds() async throws {
        let c=try PersistenceContainerFactory.makeInMemory(),zone=TimeZone.current
        let today=ImportantCivilDay(year:2026,month:10,day:18).instant(minutes:720,timeZone:zone)!
        let first=ImportantCivilDay(year:2026,month:10,day:1).instant(minutes:600,timeZone:zone)!
        let later=ImportantCivilDay(year:2026,month:10,day:17).instant(minutes:600,timeZone:zone)!
        for date in [first,later] {c.mainContext.insert(WeightRecord(weightKilograms:70,recordedAt:date,createdAt:date))}
        try c.mainContext.save()
        let reader=WeightReviewReader(modelContainer:c)
        let snapshot=try await reader.snapshot(now:today,through:ImportantCivilDay(year:2026,month:10,day:10).instant(minutes:0,timeZone:zone),zone:zone)
        let recent=try await reader.records(end:snapshot.endExclusive,now:snapshot.now)
        XCTAssertEqual(recent.map(\.recordedAt),[first]);XCTAssertEqual(snapshot.summaries[.all]?.observations,1)
        let all=try await reader.records(now:Date.distantFuture)
        XCTAssertEqual(all.map(\.recordedAt),[later,first])
    }
}
