import Foundation
import SwiftData
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
