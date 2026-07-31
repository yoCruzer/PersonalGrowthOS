import Foundation
import SwiftData
import XCTest
@testable import PersonalGrowthOS

@MainActor
final class WeightFoundationTests: XCTestCase {
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
