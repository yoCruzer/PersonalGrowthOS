import Foundation
import SwiftData
import UIKit
import XCTest
@testable import PersonalGrowthOS

@MainActor
final class ImportantDayPersistenceTests: XCTestCase {
    private func fixture() throws -> (URL, MediaStore, MediaSource) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ImportantDay-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bytes = UIGraphicsImageRenderer(size: .init(width: 8, height: 8)).pngData { c in UIColor.blue.setFill(); c.fill(.init(x: 0, y: 0, width: 8, height: 8)) }
        let url = root.appendingPathComponent("source.png"); try bytes.write(to: url)
        return (root, MediaStore(rootURL: root), MediaSource(url: url, originalFilename: "source.png", contentType: "image/png"))
    }
    private func draft() -> ImportantDayDraft {
        var d = ImportantDayDraft(); d.title = "Synthetic anniversary"
        d.rule = .init(preset: .anniversary, calendar: .chinese, year: 2023, month: 2, day: 1,
            isLeapMonth: true, leapMonthRule: .regularFallback)
        d.preferences.today = .always; d.preferences.reminderOffsets = [0, 7]
        d.preferences.desktopVisible = true; d.preferences.cropX = 0.3
        return d
    }
    func testDayEntryManyToManyDoesNotRewriteOriginalEvidenceAndDeletesOnlyReferences() throws {
        let (root, media, _) = try fixture(); addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let date = Date(timeIntervalSince1970: 1000), service = ImportantDayService(context: context, mediaStore: media)
        let entry = Entry(body: "Original", createdAt: date); context.insert(entry)
        let a = try service.save(draft()), b = try service.save(draft())
        try service.linkEntry(dayID: a.id, entryID: entry.id); try service.linkEntry(dayID: a.id, entryID: entry.id)
        try service.linkEntry(dayID: b.id, entryID: entry.id, occurrence: .init(year: 2026, month: 6, day: 20))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ImportantDayEntryLink>()), 2)
        XCTAssertEqual(entry.createdAt, date); XCTAssertEqual(entry.updatedAt, date); XCTAssertEqual(entry.occurredAt, date); XCTAssertEqual(entry.body, "Original")
        try service.delete(id: a.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ImportantDayEntryLink>()), 1)
        try EntryDeletionService(persistence: ModelContextEntryPersistence(context: context), mediaStore: media).permanentlyDelete(entry)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ImportantDay>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ImportantDayEntryLink>()), 0)
    }
    func testRelatedEntryDefaultsToNowAndFailureRollsBackEntryRelationAndNewPhoto() throws {
        let (root, media, source) = try fixture(); addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let now = Date(), service = ImportantDayService(context: context, mediaStore: media, now: { now })
        let day = try service.save(draft())
        let entry = try service.createEntry(.init(body: "Today"), dayID: day.id)
        XCTAssertEqual(entry.occurredAt, now)
        var commits = 0
        let failing = ImportantDayService(context: context, mediaStore: media, commit: { commits += 1; throw CocoaError(.fileWriteOutOfSpace) })
        XCTAssertThrowsError(try failing.createEntry(.init(body: "failed", images: [source]), dayID: day.id))
        XCTAssertEqual(commits, 1); XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ImportantDayEntryLink>()), 1)
        let originals = root.appendingPathComponent("Media/Originals")
        let files = FileManager.default.enumerator(at: originals, includingPropertiesForKeys: [.isRegularFileKey])?.allObjects as? [URL] ?? []
        XCTAssertTrue(files.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.isEmpty)
    }
    func testCoverIsIndependentAndReplacementFailurePreservesPreviousThenDeletionCleansOwnFile() throws {
        let (root, media, source) = try fixture(); addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let entry = try EntryCreationService(persistence: ModelContextEntryPersistence(context: context), mediaStore: media).create(.init(images: [source]))
        let service = ImportantDayService(context: context, mediaStore: media)
        let day = try service.save(draft(), sourceEntryID: entry.id, coverSource: source)
        let cover = try XCTUnwrap(context.fetch(FetchDescriptor<ImportantDayCover>()).first)
        let originalPath = cover.relativePath
        XCTAssertNotEqual(originalPath, entry.images.first?.relativePath)
        let bytes = try Data(contentsOf: media.fileURL(for: originalPath))
        let failing = ImportantDayService(context: context, mediaStore: media, commit: { throw CocoaError(.fileWriteOutOfSpace) })
        XCTAssertThrowsError(try failing.save(draft(), id: day.id, coverSource: source))
        XCTAssertEqual(try context.fetch(FetchDescriptor<ImportantDayCover>()).map(\.relativePath), [originalPath])
        XCTAssertEqual(try Data(contentsOf: media.fileURL(for: originalPath)), bytes)
        try EntryDeletionService(persistence: ModelContextEntryPersistence(context: context), mediaStore: media).permanentlyDelete(entry)
        XCTAssertEqual(try Data(contentsOf: media.fileURL(for: originalPath)), bytes)
        try service.delete(id: day.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try media.fileURL(for: originalPath).path))
    }
    func testRelatedTodoIsTypedAtomicIdempotentAndDoesNotMoveWithDay() throws {
        let (root, media, _) = try fixture(); addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let service = ImportantDayService(context: context, mediaStore: media), day = try service.save(draft())
        let tasks = TodoTaskService(context: context), id = UUID()
        let task = try tasks.create(TodoDraft(title: "Cake", plannedDay: "2026-06-20"), id: id, importantDayID: day.id)
        _ = try tasks.create(TodoDraft(title: "Cake"), id: id, importantDayID: day.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ImportantDayTodoLink>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTaskSource>()), 0)
        var edit = try ImportantDayDraft(day); edit.rule.day = 2
        _ = try service.save(edit, id: day.id)
        XCTAssertEqual(task.plannedDay, "2026-06-20")
        XCTAssertNotEqual(try context.fetch(FetchDescriptor<ImportantDayTodoLink>()).first?.dayRevisionAtLink, day.revision)
        try tasks.transition(id: id, to: .completed); try service.delete(id: day.id)
        XCTAssertEqual(task.state, .completed); XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTask>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ImportantDayTodoLink>()), 0)
    }
    func testV8ExportRestoreReopenPreservesFactsLinksIndependentCoverAndLegacySourceLimitation() async throws {
        let (root, media, image) = try fixture(); addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceContainerFactory.makeOnDisk(at: root.appendingPathComponent("source.sqlite")), context = container.mainContext
        let service = ImportantDayService(context: context, mediaStore: media)
        let entry = Entry(body: "Synthetic direct entry", createdAt: Date(timeIntervalSince1970: 1000)); context.insert(entry); try context.save()
        let day = try service.save(draft(), sourceEntryID: entry.id, coverSource: image)
        _ = try TodoTaskService(context: context).create(TodoDraft(title: "Cake"), importantDayID: day.id)
        let before = try TransferSnapshot.make(context: context)
        let export = ImportExportService(context: context, mediaStore: media, availableCapacity: { .max })
        let lease = try await export.exportPackage(); defer { lease.cleanup() }
        let restoredRoot = root.appendingPathComponent("Restored"); try FileManager.default.createDirectory(at: restoredRoot, withIntermediateDirectories: true)
        let storeURL = restoredRoot.appendingPathComponent("store.sqlite")
        let target = try PersistenceContainerFactory.makeOnDisk(at: storeURL), restoredMedia = MediaStore(rootURL: restoredRoot)
        _ = try await ImportExportService(context: target.mainContext, mediaStore: restoredMedia, availableCapacity: { .max }).importPackage(from: lease.url)
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: storeURL)
        XCTAssertEqual(try TransferSnapshot.make(context: reopened.mainContext), before)
        let cover = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<ImportantDayCover>()).first)
        XCTAssertEqual(try Data(contentsOf: restoredMedia.fileURL(for: cover.relativePath)), try Data(contentsOf: image.url))
        XCTAssertEqual(ExportManifest.currentPackageSchemaVersion, 8)
        try ImportantDayIntegrity.validate(context: reopened.mainContext)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<CaptureImportReceipt>()), 0)
    }
}

@MainActor
extension ImportantDayPersistenceTests {
    func testFixedProductBaselineV11DiskOverlayAndLegacyV7ImportPreserveEverySupportedFact() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ImportantDayBaselineV11Fixture", withExtension: nil))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ImportantDayUpgrade-\(UUID())")
        try FileManager.default.copyItem(at: fixture, to: root)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        // Compare through a separate legacy import, then verify the on-disk overlay independently.
        let legacyRoot = root.appendingPathComponent("LegacyRestored")
        try FileManager.default.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        let legacyContainer = try PersistenceContainerFactory.makeOnDisk(at: legacyRoot.appendingPathComponent("store.sqlite"))
        let legacyMedia = MediaStore(rootURL: legacyRoot)
        _ = try await ImportExportService(context: legacyContainer.mainContext, mediaStore: legacyMedia, availableCapacity: { .max }).importPackage(from: root.appendingPathComponent("expected-v7.zip"))
        let expected = try TransferSnapshot.make(context: legacyContainer.mainContext)
        let migrated = try PersistenceContainerFactory.makeOnDisk(at: root.appendingPathComponent("PersonalGrowthOS.sqlite"))
        XCTAssertEqual(try TransferSnapshot.make(context: migrated.mainContext), expected)
        XCTAssertEqual(try migrated.mainContext.fetchCount(FetchDescriptor<CaptureImportReceipt>()), 1)
        XCTAssertEqual(try legacyContainer.mainContext.fetchCount(FetchDescriptor<CaptureImportReceipt>()), 0) // inherited accepted backup boundary
        XCTAssertEqual(try migrated.mainContext.fetchCount(FetchDescriptor<ImportantDay>()), 0)
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: root.appendingPathComponent("PersonalGrowthOS.sqlite"))
        XCTAssertEqual(try TransferSnapshot.make(context: reopened.mainContext), expected)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<CaptureImportReceipt>()), 1)
        for image in expected.images {
            let relative = root.appendingPathComponent(image.relativePath)
            let restored = legacyRoot.appendingPathComponent(image.relativePath)
            XCTAssertEqual(try Data(contentsOf: relative), try Data(contentsOf: restored))
        }
    }
}
