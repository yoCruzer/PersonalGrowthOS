import Foundation
import SwiftData
import UIKit
import XCTest
@testable import PersonalGrowthOS

@MainActor final class SleepPersistenceTests: XCTestCase {
    let zone = TimeZone(identifier: "Asia/Shanghai")!
    func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SleepSynthetic-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // SwiftData may retain SQLite handles beyond XCTest teardown. Retain this synthetic
        // root until the test host exits; external evidence cleanup can then remove it safely.
        return root
    }
    func testActualV11FixtureDirectUpgradeThroughStartupProtectionPreservesAllBackupFactsAndReceipt() async throws {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ImportantDayBaselineV11Fixture", withExtension: nil))
        let root = try root(); try FileManager.default.removeItem(at: root); try FileManager.default.copyItem(at: source, to: root)
        let store = root.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
        try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: root.appendingPathComponent("PersonalGrowthOS.sqlite"), to: store)
        let before = try Data(contentsOf: store)
        let legacyRoot = try self.root(), legacy = try PersistenceContainerFactory.makeOnDisk(at: legacyRoot.appendingPathComponent("store.sqlite"))
        _ = try await ImportExportService(context: legacy.mainContext, mediaStore: MediaStore(rootURL: legacyRoot), availableCapacity: { .max }).importPackage(from: root.appendingPathComponent("expected-v7.zip"))
        XCTAssertEqual(try legacy.mainContext.fetchCount(FetchDescriptor<CaptureImportReceipt>()), 0)
        // v7 omitted receipts. Independently read from the immutable baseline SQLite fixture
        // (ZID/ZIMPORTEDAT), rather than taking this expected identity from the upgraded store.
        legacy.mainContext.insert(CaptureImportReceipt(
            id: UUID(uuidString: "C71AD985-C3A0-45F3-879A-B23C5760D10C")!,
            importedAt: Date(timeIntervalSinceReferenceDate: 811692800)))
        try legacy.mainContext.save()
        let expected = try TransferSnapshot.make(context: legacy.mainContext)
        let app = try AppContainer.make(configuration: .init(launchMode: .uiTesting, resetDataOnLaunch: false), rootURLOverride: root)
        XCTAssertEqual(try TransferSnapshot.make(context: app.modelContainer.mainContext), expected)
        XCTAssertEqual(try app.modelContainer.mainContext.fetchCount(FetchDescriptor<CaptureImportReceipt>()), 1)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Recovery/BeforeMigration/Store/PersonalGrowthOS.sqlite")), before)
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: store)
        XCTAssertEqual(try TransferSnapshot.make(context: reopened.mainContext), expected)
        XCTAssertTrue(StartupStoreProtection.isCurrentStore(at: store))
        for image in expected.images { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(image.relativePath)), try Data(contentsOf: legacyRoot.appendingPathComponent(image.relativePath))) }
    }
    func testFrozenV12DiskUpgradeWithImportantDayCoverLinksAndExistingOtherSourceProtection() throws {
        let root = try root(), store = root.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
        try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        let media = MediaStore(rootURL: root)
        let imageURL = root.appendingPathComponent("synthetic.png")
        let bytes = UIGraphicsImageRenderer(size: .init(width: 4, height: 4)).pngData { c in UIColor.blue.setFill(); c.fill(.init(x: 0, y: 0, width: 4, height: 4)) }
        try bytes.write(to: imageURL)
        var entryID = UUID(), dayID = UUID(), coverPath = ""
        // A genuine V12 container: no V13 models or migration plan participate in its creation.
        try autoreleasepool {
            let schema = Schema(versionedSchema: PersonalGrowthSchemaV12.self)
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration("PersonalGrowthOSV1", schema: schema, url: store, cloudKitDatabase: .none)])
            old.mainContext.autosaveEnabled = false
            let entry = try EntryCreationService(persistence: ModelContextEntryPersistence(context: old.mainContext), mediaStore: media).create(.init(body: "V12 original", images: [MediaSource(url: imageURL, originalFilename: "fixture.png", contentType: "image/png")]))
            entryID = entry.id
            var draft = ImportantDayDraft(); draft.title = "Synthetic V12 day"; draft.rule = .init(preset: .anniversary, year: 2000, month: 2, day: 29, leapDayRule: .february28)
            let day = try ImportantDayService(context: old.mainContext, mediaStore: media).save(draft, sourceEntryID: entry.id, coverSource: MediaSource(url: imageURL, originalFilename: "cover.png", contentType: "image/png"))
            dayID = day.id
            _ = try TodoTaskService(context: old.mainContext).create(.init(title: "V12 linked task"), importantDayID: day.id)
            _ = try WeightRecordService(context: old.mainContext).create(weightKilograms: 70, recordedAt: Date())
            coverPath = try XCTUnwrap(old.mainContext.fetch(FetchDescriptor<ImportantDayCover>()).first?.relativePath)
            XCTAssertFalse(StartupStoreProtection.isCurrentStore(at: store))
        }
        let oldProtection = try StartupRetainedData.capture(rootURL: root, purpose: .beforeMigration)
        let oldBytes = try Data(contentsOf: oldProtection.snapshotURL.appendingPathComponent("Store/PersonalGrowthOS.sqlite"))
        // Simulates an intervening V12 save after a previous migration copy was retained.
        try autoreleasepool {
            let schema = Schema(versionedSchema: PersonalGrowthSchemaV12.self)
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration("PersonalGrowthOSV1", schema: schema, url: store, cloudKitDatabase: .none)])
            old.mainContext.insert(Entry(body: "V12 later fact", createdAt: Date())); try old.mainContext.save()
        }
        let second = try StartupRetainedData.capture(rootURL: root, purpose: .beforeMigration)
        XCTAssertNotEqual(second.snapshotURL, oldProtection.snapshotURL)
        XCTAssertEqual(try Data(contentsOf: oldProtection.snapshotURL.appendingPathComponent("Store/PersonalGrowthOS.sqlite")), oldBytes)
        XCTAssertEqual(try StartupRetainedData.capture(rootURL: root, purpose: .beforeMigration).snapshotURL, second.snapshotURL)
        let app = try AppContainer.make(configuration: .init(launchMode: .uiTesting, resetDataOnLaunch: false), rootURLOverride: root)
        let context = app.modelContainer.mainContext
        XCTAssertEqual(try context.fetch(FetchDescriptor<ImportantDay>()).map(\.id), [dayID])
        XCTAssertTrue(try context.fetch(FetchDescriptor<Entry>()).contains { $0.id == entryID && $0.body == "V12 original" })
        XCTAssertTrue(try context.fetch(FetchDescriptor<Entry>()).contains { $0.body == "V12 later fact" })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ImportantDayEntryLink>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ImportantDayTodoLink>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WeightRecord>()), 1)
        XCTAssertEqual(try Data(contentsOf: media.fileURL(for: coverPath)), bytes)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SleepRecord>()), 0)
        let before = try TransferSnapshot.make(context: context)
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: store)
        XCTAssertEqual(try TransferSnapshot.make(context: reopened.mainContext), before)
    }
    func testV9BothModulesExportEmptyRestoreReopenPreservesPrecisionAndFieldEvidence() async throws {
        let root = try root(), source = try PersistenceContainerFactory.makeOnDisk(at: root.appendingPathComponent("source.sqlite"))
        let clock = ImportantCivilDay(year: 2026, month: 10, day: 15).instant(minutes: 720, timeZone: zone)!
        let sleep = SleepService(context: source.mainContext, now: { clock })
        var draft = SleepDraft(day: "2026-10-15", zone: zone)
        draft.values.bedtime = .init(day: "2026-10-14", minute: 1410, precision: 60)
        draft.values.wake = .init(day: "2026-10-15", minute: 420, precision: 15); draft.values.feeling = 3
        _ = try sleep.save(draft); try sleep.setGoal(cutoffMinute: 1410, timeZone: zone)
        try sleep.setGoal(cutoffMinute: 30, timeZone: zone) // Preserve both active and pending rule evidence.
        var day = ImportantDayDraft(); day.title = "Combined synthetic day"
        _ = try ImportantDayService(context: source.mainContext, mediaStore: MediaStore(rootURL: root)).save(day)
        let expected = try TransferSnapshot.make(context: ModelContext(source))
        let lease = try await ImportExportService(context: source.mainContext, mediaStore: MediaStore(rootURL: root), availableCapacity: { .max }).exportPackage()
        defer { lease.cleanup() }
        let targetRoot = try self.root(), url = targetRoot.appendingPathComponent("target.sqlite")
        let target = try PersistenceContainerFactory.makeOnDisk(at: url)
        _ = try await ImportExportService(context: target.mainContext, mediaStore: MediaStore(rootURL: targetRoot), availableCapacity: { .max }).importPackage(from: lease.url)
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: url)
        XCTAssertEqual(try TransferSnapshot.make(context: reopened.mainContext), expected)
        try SleepIntegrity.validate(context: reopened.mainContext)
        XCTAssertEqual(ExportManifest.currentPackageSchemaVersion, 11)
    }
    func testIllegalSleepIdentityRangeEvidenceAndOldVersionPayloadAreRejected() throws {
        let c = try PersistenceContainerFactory.makeInMemory(), clock = Date()
        var draft = SleepDraft(day: ImportantCivilDay(clock, timeZone: zone).identifier, zone: zone); draft.values.feeling = 3
        _ = try SleepService(context: c.mainContext, now: { clock }).save(draft)
        let original = try SleepRecordTransfer(XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<SleepRecord>()).first))
        func data(_ records: [SleepRecordTransfer], _ goals: [SleepGoalTransfer] = []) -> TransferData {
            TransferData(entries: [], images: [], tags: [], links: [], habits: [], habitLogs: [], goals: [], goalEvents: [], sleepRecords: records, sleepGoals: goals)
        }
        XCTAssertThrowsError(try data([original, original]).validateSleep(packageVersion: 9))
        XCTAssertThrowsError(try data([original]).validateSleep(packageVersion: 8))
        var invalid = original; invalid.id = UUID(); XCTAssertThrowsError(try data([original, invalid]).validateSleep(packageVersion: 9))
        invalid = original; invalid.values.feeling = 6; XCTAssertThrowsError(try data([invalid]).validateSleep(packageVersion: 9))
        invalid = original; invalid.values.feelingFilledAt = clock.addingTimeInterval(1000); XCTAssertThrowsError(try data([invalid]).validateSleep(packageVersion: 9))
        invalid = original; invalid.values.bedtime = .init(day: draft.wakeDay, minute: 90, precision: 42); XCTAssertThrowsError(try data([invalid]).validateSleep(packageVersion: 9))
        invalid = original; invalid.timeZoneID = "Invalid/Zone"; XCTAssertThrowsError(try data([invalid]).validateSleep(packageVersion: 9))
        let g = SleepGoalTransfer(SleepGoalRule(effectiveDay: draft.wakeDay, cutoffMinute: 1410, createdAt: clock))
        XCTAssertThrowsError(try data([], [g, g]).validateSleep(packageVersion: 9))
    }
}
