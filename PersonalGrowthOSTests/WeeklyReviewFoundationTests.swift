import Foundation
import SwiftData
import UIKit
import XCTest
@testable import PersonalGrowthOS

@MainActor
final class WeeklyReviewFoundationTests: XCTestCase {
    func testWeekPeriodUsesOneStableNaturalWeekAcrossYearBoundary() throws {
        let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        let calendar = WeeklyReviewCalendarPolicy.calendar(timeZone: timeZone)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2027,
            month: 1,
            day: 1,
            hour: 12
        )))

        let period = try WeeklyReviewPeriod(containing: date, timeZone: timeZone)

        XCTAssertEqual(period.identifier, "2026-W53")
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: period.start),
            DateComponents(year: 2026, month: 12, day: 28)
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: period.end),
            DateComponents(year: 2027, month: 1, day: 3)
        )
        XCTAssertTrue(period.contains(date))
        XCTAssertFalse(period.contains(period.endExclusive))
    }

    func testWeekPeriodUsesCalendarDaysAcrossDaylightSavingTime() throws {
        let timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        let calendar = WeeklyReviewCalendarPolicy.calendar(timeZone: timeZone)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 8,
            hour: 12
        )))

        let period = try WeeklyReviewPeriod(containing: date, timeZone: timeZone)

        XCTAssertEqual(
            calendar.dateComponents([.day], from: period.start, to: period.endExclusive).day,
            7
        )
        XCTAssertTrue(period.contains(date))
    }

    func testCanonicalIdentifierReopensExactReviewAcrossTimeZones() throws {
        let shanghai = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let shanghaiPeriod = try WeeklyReviewPeriod(
            identifier: "2026-W35",
            timeZone: shanghai
        )
        let losAngelesPeriod = try WeeklyReviewPeriod(
            identifier: "2026-W35",
            timeZone: losAngeles
        )

        XCTAssertEqual(shanghaiPeriod.identifier, "2026-W35")
        XCTAssertEqual(losAngelesPeriod.identifier, "2026-W35")

        let container = try PersistenceContainerFactory.makeInMemory()
        let review = WeeklyReview(
            weekIdentifier: shanghaiPeriod.identifier,
            periodStart: shanghaiPeriod.start,
            periodEnd: shanghaiPeriod.end,
            createdAt: shanghaiPeriod.start
        )
        container.mainContext.insert(review)
        try container.mainContext.save()

        let reopened = try XCTUnwrap(
            WeeklyReviewService(
                context: container.mainContext,
                timeZone: losAngeles
            ).review(identifier: losAngelesPeriod.identifier)
        )
        XCTAssertEqual(reopened.id, review.id)
    }

    func testCanonicalIdentifierParsingRejectsNonCanonicalOrInvalidWeeks() {
        XCTAssertThrowsError(try WeeklyReviewPeriod(identifier: "2026-W5"))
        XCTAssertThrowsError(try WeeklyReviewPeriod(identifier: "2026-W00"))
        XCTAssertThrowsError(try WeeklyReviewPeriod(identifier: "2026-W54"))
        XCTAssertThrowsError(try WeeklyReviewPeriod(identifier: "2026-X35"))
    }

    func testWeeklyReviewDeduplicatesWeekAndPersistsDraftAcrossReopen() throws {
        let fixture = try WeeklyReviewFixture()
        defer { fixture.remove() }
        let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        let calendar = WeeklyReviewCalendarPolicy.calendar(timeZone: timeZone)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 3,
            hour: 10
        )))
        let reviewID: UUID
        do {
            let container = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
            var clock = date
            let service = WeeklyReviewService(
                context: container.mainContext,
                timeZone: timeZone,
                now: { clock }
            )
            let first = try XCTUnwrap(service.review(containing: date))
            let sameWeek = try XCTUnwrap(service.review(
                containing: date.addingTimeInterval(2 * 86_400)
            ))
            XCTAssertEqual(first.id, sameWeek.id)
            XCTAssertEqual(try service.history().count, 1)
            clock = date.addingTimeInterval(60)
            try service.update(first, draft: WeeklyReviewDraft(
                rememberedText: "  A meaningful conversation  ",
                improvementText: " ",
                nextStepText: "Ship the review loop",
                focusText: "  One focused hour  ",
                isCompleted: true
            ))
            reviewID = first.id
        }

        let reopened = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
        let review = try XCTUnwrap(
            reopened.mainContext.fetch(FetchDescriptor<WeeklyReview>()).first
        )
        XCTAssertEqual(review.id, reviewID)
        XCTAssertEqual(review.rememberedText, "A meaningful conversation")
        XCTAssertNil(review.improvementText)
        XCTAssertEqual(review.nextStepText, "Ship the review loop")
        XCTAssertEqual(review.focusText, "One focused hour")
        XCTAssertTrue(review.isCompleted)
        XCTAssertGreaterThan(review.updatedAt, review.createdAt)
    }

    func testHistoryIsNewestFirstAndPreviousReviewUsesExactAdjacentWeek() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        let calendar = WeeklyReviewCalendarPolicy.calendar(timeZone: timeZone)
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 12,
            hour: 12
        )))
        let previousDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: currentDate))
        let olderDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -14, to: currentDate))
        let service = WeeklyReviewService(context: container.mainContext, timeZone: timeZone)
        let older = try XCTUnwrap(service.review(containing: olderDate))
        older.focusText = "Not adjacent"
        let previous = try XCTUnwrap(service.review(containing: previousDate))
        previous.focusText = "Ship one calm improvement"
        let current = try XCTUnwrap(service.review(containing: currentDate))
        try container.mainContext.save()

        XCTAssertEqual(try service.history().map(\.id), [current.id, previous.id, older.id])
        XCTAssertEqual(
            try service.previousReview(containing: currentDate)?.id,
            previous.id
        )

        container.mainContext.delete(previous)
        try container.mainContext.save()
        XCTAssertNil(try service.previousReview(containing: currentDate))
    }

    func testEditStateTracksPersistedBaselineAndNewSave() {
        let baseline = WeeklyReviewDraft(
            rememberedText: "Original",
            improvementText: "",
            nextStepText: "",
            focusText: "Focus",
            isCompleted: false
        )
        var state = WeeklyReviewEditState(baseline: baseline)
        var edited = baseline

        XCTAssertFalse(state.isDirty(edited))
        edited.isCompleted = true
        XCTAssertTrue(state.isDirty(edited))
        state.markSaved(edited)
        XCTAssertFalse(state.isDirty(edited))
        edited.focusText = "New focus"
        XCTAssertTrue(state.isDirty(edited))
    }

    func testV6StoreMigratesToV7WithoutChangingExistingData() throws {
        let fixture = try WeeklyReviewFixture()
        defer { fixture.remove() }
        let entryID = UUID()
        let habitID = UUID()
        let weightID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        do {
            let schema = Schema(versionedSchema: PersonalGrowthSchemaV6.self)
            let configuration = ModelConfiguration(
                "PersonalGrowthOSV1",
                schema: schema,
                url: fixture.storeURL,
                cloudKitDatabase: .none
            )
            let legacy = try ModelContainer(for: schema, configurations: [configuration])
            legacy.mainContext.insert(Entry(
                id: entryID,
                body: "Existing entry",
                createdAt: timestamp
            ))
            legacy.mainContext.insert(Habit(
                id: habitID,
                name: "Existing habit",
                normalizedName: "existing habit",
                createdAt: timestamp
            ))
            legacy.mainContext.insert(WeightRecord(
                id: weightID,
                weightKilograms: 70,
                recordedAt: timestamp,
                createdAt: timestamp
            ))
            try legacy.mainContext.save()
        }

        let migrated = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<Entry>()).map(\.id), [entryID])
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<Habit>()).map(\.id), [habitID])
        XCTAssertEqual(
            try migrated.mainContext.fetch(FetchDescriptor<WeightRecord>()).map(\.id),
            [weightID]
        )
        XCTAssertEqual(try migrated.mainContext.fetchCount(FetchDescriptor<WeeklyReview>()), 0)
    }

    func testEmptyWeeklySummaryHidesUnavailableFacts() throws {
        let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        let period = try WeeklyReviewPeriod(containing: Date(), timeZone: timeZone)

        let summary = WeeklySummaryService.make(
            period: period,
            entries: [],
            habits: [],
            habitLogs: [],
            weightRecords: [],
            timeZone: timeZone
        )

        XCTAssertFalse(summary.hasActivity)
        XCTAssertNil(summary.entryCount)
        XCTAssertNil(summary.entryDayCount)
        XCTAssertNil(summary.imageEntryCount)
        XCTAssertNil(summary.habitCheckInCount)
        XCTAssertNil(summary.habitHighlight)
        XCTAssertNil(summary.weight)
        XCTAssertEqual(summary.topTags, [])
        XCTAssertEqual(summary.recentEntries, [])
    }

    func testEntrySummaryCountsDaysImagesTagsAndRecentEntries() throws {
        let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        let calendar = WeeklyReviewCalendarPolicy.calendar(timeZone: timeZone)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 3,
            hour: 10
        )))
        let period = try WeeklyReviewPeriod(containing: date, timeZone: timeZone)
        let first = Entry(body: "First", createdAt: date, occurredAt: date)
        let secondDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: date))
        let image = ImageMetadata(
            id: UUID(),
            relativePath: "Media/Originals/image.jpg",
            originalFilename: "image.jpg",
            contentType: "image/jpeg",
            byteCount: 1,
            pixelWidth: 1,
            pixelHeight: 1,
            checksum: String(repeating: "a", count: 64),
            createdAt: secondDate
        )
        let second = Entry(
            body: "Second",
            createdAt: secondDate,
            occurredAt: secondDate,
            images: [image]
        )
        image.entry = second
        let outside = Entry(
            body: "Outside",
            createdAt: period.endExclusive,
            occurredAt: period.endExclusive
        )
        let review = Entry(
            kind: .review,
            status: .organized,
            body: "Manual review",
            createdAt: secondDate,
            occurredAt: secondDate
        )
        let tag = Tag(
            displayName: "Learning",
            normalizedName: "learning",
            createdAt: date
        )
        let links = [first, second].map {
            ObjectLink(
                sourceType: .entry,
                sourceID: $0.id,
                targetType: .tag,
                targetID: tag.id,
                kind: .entryUsesTag,
                createdAt: date
            )
        }

        let summary = WeeklySummaryService.make(
            period: period,
            entries: [outside, review, first, second],
            habits: [],
            habitLogs: [],
            weightRecords: [],
            tags: [tag],
            links: links,
            timeZone: timeZone
        )

        XCTAssertEqual(summary.entryCount, 2)
        XCTAssertEqual(summary.entryDayCount, 2)
        XCTAssertEqual(summary.imageEntryCount, 1)
        XCTAssertEqual(summary.topTags, ["Learning"])
        XCTAssertEqual(summary.recentEntries.map(\.id), [second.id, first.id])
    }

    func testHabitAndWeightSummaryUsesOnlyCurrentWeekData() throws {
        let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        let calendar = WeeklyReviewCalendarPolicy.calendar(timeZone: timeZone)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 3,
            hour: 10
        )))
        let period = try WeeklyReviewPeriod(containing: date, timeZone: timeZone)
        let habit = Habit(
            name: "Water",
            normalizedName: "water",
            createdAt: date
        )
        let secondDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: date))
        let logs = [
            HabitLog(habitID: habit.id, occurredAt: date, isCompleted: true, createdAt: date),
            HabitLog(habitID: habit.id, occurredAt: date.addingTimeInterval(60), isCompleted: true, createdAt: date),
            HabitLog(habitID: habit.id, occurredAt: secondDay, isCompleted: true, createdAt: secondDay),
            HabitLog(
                habitID: habit.id,
                occurredAt: period.endExclusive,
                isCompleted: true,
                createdAt: period.endExclusive
            )
        ]
        let firstWeight = WeightRecord(
            weightKilograms: 70,
            recordedAt: date,
            createdAt: date
        )

        let oneWeight = WeeklySummaryService.make(
            period: period,
            entries: [],
            habits: [habit],
            habitLogs: logs,
            weightRecords: [firstWeight],
            timeZone: timeZone
        )
        XCTAssertEqual(oneWeight.habitCheckInCount, 3)
        XCTAssertEqual(oneWeight.habitHighlight?.checkInCount, 3)
        XCTAssertEqual(oneWeight.habitHighlight?.activeDayCount, 2)
        XCTAssertEqual(oneWeight.weight?.latestKilograms, 70)
        XCTAssertNil(oneWeight.weight?.changeKilograms)

        let secondWeight = WeightRecord(
            weightKilograms: 69.5,
            recordedAt: secondDay,
            createdAt: secondDay
        )
        let twoWeights = WeeklySummaryService.make(
            period: period,
            entries: [],
            habits: [habit],
            habitLogs: logs,
            weightRecords: [secondWeight, firstWeight],
            timeZone: timeZone
        )
        XCTAssertEqual(twoWeights.weight?.firstKilograms, 70)
        XCTAssertEqual(twoWeights.weight?.latestKilograms, 69.5)
        XCTAssertEqual(try XCTUnwrap(twoWeights.weight?.changeKilograms), -0.5, accuracy: 0.001)
    }

    func testCalendarPolicyIgnoresLocaleRegionAndNonGregorianCalendar() throws {
        let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        let policyCalendar = WeeklyReviewCalendarPolicy.calendar(timeZone: timeZone)
        let date = try XCTUnwrap(policyCalendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 9,
            hour: 12
        )))
        var chineseCalendar = Calendar(identifier: .gregorian)
        chineseCalendar.locale = Locale(identifier: "zh_CN")
        chineseCalendar.timeZone = timeZone
        var buddhistCalendar = Calendar(identifier: .buddhist)
        buddhistCalendar.locale = Locale(identifier: "th_TH")
        buddhistCalendar.timeZone = timeZone

        let policyPeriod = try WeeklyReviewPeriod(containing: date, timeZone: timeZone)
        let localizedPeriod = try WeeklyReviewPeriod(
            containing: date,
            timeZone: chineseCalendar.timeZone
        )
        let nonGregorianPeriod = try WeeklyReviewPeriod(
            containing: date,
            timeZone: buddhistCalendar.timeZone
        )

        XCTAssertEqual(policyPeriod.identifier, "2026-W32")
        XCTAssertEqual(localizedPeriod, policyPeriod)
        XCTAssertEqual(nonGregorianPeriod, policyPeriod)
    }
}

private struct WeeklyReviewFixture {
    let root: URL
    let storeURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PGOS-WeeklyReview-\(UUID().uuidString)", isDirectory: true)
        storeURL = root.appendingPathComponent("store.sqlite")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
extension WeeklyReviewFoundationTests {
    func testSystemSR03SavedCivilDayAndActualCutoffAcrossZonesAndHistoricalWeeks() async throws {
        for day in ["2026-10-18","2027-01-03","2026-03-08","2026-11-01"] {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let url=root.appendingPathComponent("weekly.sqlite")
        let la=TimeZone(identifier:"America/Los_Angeles")!,sh=TimeZone(identifier:"Asia/Shanghai")!
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=la
        func instant(_ day: String,_ minutes: Int) -> Date {ImportantCivilDay(identifier:day)!.instant(minutes:minutes,timeZone:la)!}
        let sunday=instant(day,1410),early=instant(day,480)
        let monday=instant(ImportantCivilDay(identifier:day)!.adding(days:1)!.identifier,600)
        let c=try PersistenceContainerFactory.makeOnDisk(at:url),context=c.mainContext
        let habit=try HabitService(context:context,now:{early.addingTimeInterval(-86400)}).create(name:"Civil day",recordingMode:.multiplePerDay,dailyTargetCount:2)
        var clock=early
        let check=HabitCheckInService(context:context,mediaStore:MediaStore(rootURL:root),now:{clock},calendar:calendar)
        _ = try check.incrementCount(habit,occurredAt:early)
        clock=sunday
        let late=try check.incrementCount(habit,occurredAt:sunday)
        let historical=try WeeklyReviewPeriod(containing:sunday,timeZone:la)
        let selected=try WeeklyReviewPeriod(identifier:historical.identifier,timeZone:sh)
        let read=ModelContext(try PersistenceContainerFactory.makeOnDisk(at:url))
        let logs=try read.fetch(FetchDescriptor<HabitLog>()),metadata=try read.fetch(FetchDescriptor<HabitLogDayMetadata>())
        let before=metadata.map(\.localDayIdentifier)
        func summary(_ period:WeeklyReviewPeriod,_ cutoff:Date,_ zone:TimeZone) -> WeeklySummary {
            WeeklySummaryService.make(period:period,entries:[],habits:[habit],habitLogs:logs,weightRecords:[],dayMetadata:metadata,asOf:cutoff,timeZone:zone)
        }
        XCTAssertEqual(summary(selected,monday,sh).habitCheckInCount,2)
        XCTAssertEqual(summary(selected,monday,sh).habitHighlight?.activeDayCount,1)
        XCTAssertEqual(summary(historical,early,la).habitCheckInCount,1)
        XCTAssertNil(summary(try WeeklyReviewPeriod(containing:monday,timeZone:sh),monday,sh).habitCheckInCount)
        XCTAssertEqual(try read.fetch(FetchDescriptor<HabitLogDayMetadata>()).map(\.localDayIdentifier),before)
        XCTAssertFalse(read.hasChanges)
        // A historical week is selected by identity; its Monday must never become the cutoff.
        XCTAssertEqual(summary(selected,monday,sh).habitCheckInCount,2)
        let analytics=HabitAnalyticsSnapshotBuilder.summary(habit:habit,logs:logs,dayMetadata:metadata,
            plans:try read.fetch(FetchDescriptor<HabitPlanRevision>()),lifecycleEvents:try read.fetch(FetchDescriptor<HabitLifecycleEvent>()),legacyConfigurations:try read.fetch(FetchDescriptor<HabitConfiguration>()),asOf:monday,timeZone:sh)
        XCTAssertEqual(analytics.activityByDay[HabitLocalDay(day)!],2)
        let projection=try await QuietWinsReader(modelContainer:c).read(window:.init(days:7,asOf:monday,timeZone:sh))
        let card=try XCTUnwrap(projection.evidenceCards.first {$0.kind == .habit})
        XCTAssertEqual(card.habitDays.count,1);XCTAssertEqual(card.sources.count,2)
        XCTAssertEqual(card.habitDays.first?.day,HabitLocalDay(day))
        try check.undoLatestCheckIn(habitID:habit.id,logID:late.id)
        let remaining=try ModelContext(c).fetch(FetchDescriptor<HabitLog>())
        XCTAssertEqual(WeeklySummaryService.make(period:selected,entries:[],habits:[habit],habitLogs:remaining,weightRecords:[],dayMetadata:try ModelContext(c).fetch(FetchDescriptor<HabitLogDayMetadata>()),asOf:monday,timeZone:sh).habitCheckInCount,1)
        // Legacy logs without day metadata use the existing Habit resolver fallback;
        // a read does not invent metadata or alter the actual timestamp.
        let legacy=HabitLog(habitID:habit.id,occurredAt:early,isCompleted:true,createdAt:early)
        XCTAssertEqual(WeeklySummaryService.make(period:historical,entries:[],habits:[habit],habitLogs:[legacy],weightRecords:[],asOf:monday,timeZone:la).habitCheckInCount,1)
        }
    }

    func testSystemSR03AllWeeklyDerivedFactsUseSameActualAsOf() throws {
        let zone=TimeZone(identifier:"Asia/Shanghai")!,c=try PersistenceContainerFactory.makeInMemory(),context=c.mainContext
        let now=ImportantCivilDay(identifier:"2026-10-19")!.instant(minutes:600,timeZone:zone)!,future=now.addingTimeInterval(240)
        let habit=try HabitService(context:context,now:{now.addingTimeInterval(-86400)}).create(name:"Future tolerance")
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=zone
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let media=MediaStore(rootURL:root),source=root.appendingPathComponent("future.png")
        let renderer=UIGraphicsImageRenderer(size:CGSize(width:2,height:2))
        try renderer.pngData {_ in UIColor.blue.setFill();UIRectFill(CGRect(x:0,y:0,width:2,height:2))}.write(to:source)
        let check=HabitCheckInService(context:context,mediaStore:media,now:{now},calendar:calendar)
        let log=try check.checkIn(habit,draft:HabitLogDraft(occurredAt:future))
        let entry=try EntryCreationService(persistence:ModelContextEntryPersistence(context:context),mediaStore:media,now:{now}).create(.init(body:"future",occurredAt:future,image:MediaSource(url:source,originalFilename:"future.png",contentType:"image/png")))
        let weight=try WeightRecordService(context:context,now:{now}).create(weightKilograms:72.345,recordedAt:future)
        let tag=Tag(displayName:"Future tag",normalizedName:"future tag",createdAt:now)
        context.insert(tag);context.insert(ObjectLink(sourceType:.entry,sourceID:entry.id,targetType:.tag,targetID:tag.id,kind:.entryUsesTag,createdAt:now))
        try context.save()
        let period=try WeeklyReviewPeriod(containing:now,timeZone:zone)
        func summary(_ cutoff:Date) throws -> WeeklySummary {
            WeeklySummaryService.make(period:period,entries:try context.fetch(FetchDescriptor<Entry>()),habits:[habit],habitLogs:try context.fetch(FetchDescriptor<HabitLog>()),weightRecords:try context.fetch(FetchDescriptor<WeightRecord>()),tags:[tag],links:try context.fetch(FetchDescriptor<ObjectLink>()),dayMetadata:try context.fetch(FetchDescriptor<HabitLogDayMetadata>()),asOf:cutoff,timeZone:zone)
        }
        let before=try summary(now)
        XCTAssertNil(before.entryCount);XCTAssertNil(before.entryDayCount);XCTAssertTrue(before.recentEntries.isEmpty);XCTAssertTrue(before.topTags.isEmpty)
        XCTAssertNil(before.habitCheckInCount);XCTAssertNil(before.weight);XCTAssertNil(before.imageEntryCount)
        let after=try summary(future)
        XCTAssertEqual(after.entryCount,1);XCTAssertEqual(after.entryDayCount,1);XCTAssertEqual(after.recentEntries.map(\.id),[entry.id]);XCTAssertEqual(after.topTags,[tag.displayName])
        XCTAssertEqual(after.habitCheckInCount,1);XCTAssertEqual(after.weight?.latestKilograms,72.345)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()),1);XCTAssertEqual(after.imageEntryCount,1)
        try EntryEditingService(persistence:ModelContextEntryPersistence(context:context),mediaStore:media,now:{now}).update(entry,with:.init(title:"Current after edit",body:"Edited fact",occurredAt:now,retainedImageIDs:entry.images.map(\.id),addedImages:[]))
        XCTAssertEqual(try summary(now).recentEntries.first?.title,"Current after edit")
        XCTAssertEqual(try summary(now).imageEntryCount,1);XCTAssertEqual(try summary(now).topTags,[tag.displayName])
        try WeightRecordService(context:context,now:{now}).update(weight,weightKilograms:73.125,recordedAt:now)
        XCTAssertEqual(try summary(now).weight?.latestKilograms,73.125)
        try check.undoLatestCheckIn(habitID:habit.id,logID:log.id)
        XCTAssertNil(try summary(future).habitCheckInCount)
        try EntryDeletionService(persistence:ModelContextEntryPersistence(context:context),mediaStore:media).permanentlyDelete(entry)
        try WeightRecordService(context:context).delete(weight)
        XCTAssertFalse(try summary(future).hasActivity);XCTAssertTrue(try summary(future).recentEntries.isEmpty);XCTAssertTrue(try summary(future).topTags.isEmpty)
    }
}

@MainActor extension WeeklyReviewFoundationTests {
    func testIntegrationIR05FixedMondaySeedAndReaderIgnoreElapsedWallTimeUntilClockAdvances() throws {
        let args=["-PGOSUITesting","-PGOSWeeklyCutoffTest"]
        let now=WeeklyReviewClock.current(arguments:args),zone=WeeklyReviewClock.zone(arguments:args)
        XCTAssertEqual(WeeklyReviewCalendarPolicy.calendar(timeZone:zone).component(.weekday,from:now),2)
        XCTAssertEqual(WeeklyReviewClock.current(arguments:args,live:now.addingTimeInterval(86400*365)),now)
        XCTAssertNotEqual(WeeklyReviewClock.current(arguments:[],live:now.addingTimeInterval(999)),now)
        let c=try PersistenceContainerFactory.makeInMemory(),context=c.mainContext
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        try WeeklyReviewClock.seed(context:context,mediaStore:MediaStore(rootURL:root))
        let period=try WeeklyReviewPeriod(containing:now,timeZone:zone)
        func read(_ selected:WeeklyReviewPeriod,_ asOf:Date) throws -> WeeklySummary {
            let fresh=ModelContext(c)
            return WeeklySummaryService.make(period:selected,entries:try fresh.fetch(FetchDescriptor<Entry>()),habits:try fresh.fetch(FetchDescriptor<Habit>()),habitLogs:try fresh.fetch(FetchDescriptor<HabitLog>()),weightRecords:try fresh.fetch(FetchDescriptor<WeightRecord>()),dayMetadata:try fresh.fetch(FetchDescriptor<HabitLogDayMetadata>()),asOf:asOf,timeZone:zone)
        }
        let first=try read(period,WeeklyReviewClock.current(arguments:args,live:now.addingTimeInterval(9999)))
        XCTAssertEqual(first.entryCount,1);XCTAssertEqual(first.habitCheckInCount,1);XCTAssertEqual(first.weight?.latestKilograms,70)
        XCTAssertEqual(first.recentEntries.map(\.title),["Current occurred entry"])
        let advanced=try read(period,WeeklyReviewClock.current(arguments:args+["-PGOSWeeklyAdvanceTest"]))
        XCTAssertEqual(advanced.entryCount,2);XCTAssertEqual(advanced.habitCheckInCount,2);XCTAssertEqual(advanced.weight?.latestKilograms,99)
        let historical=try read(period.previous(timeZone:zone),now)
        XCTAssertEqual(historical.entryCount,1);XCTAssertEqual(historical.weight?.latestKilograms,69)
        XCTAssertEqual(historical.recentEntries.map(\.title),["Historical Sunday entry"])
    }
}
