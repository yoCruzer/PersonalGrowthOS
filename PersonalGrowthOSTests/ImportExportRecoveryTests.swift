import CryptoKit
import Foundation
import SwiftData
import UIKit
import SwiftUI
import XCTest
@testable import PersonalGrowthOS

@MainActor
final class ImportExportRecoveryTests: XCTestCase {
    func testClockRollbackUpdatesExportRestoreAndReopenPreserveFacts() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makeEmptyStore(named: "ClockSource", onDisk: true)
        let context = source.container.mainContext
        let created = Date(timeIntervalSince1970: 5_000)
        let occurred = Date(timeIntervalSince1970: 1_000)
        var clock = created
        let input = fixture.root.appendingPathComponent("clock.png")
        try fixture.imageData.write(to: input)
        let persistence = ModelContextEntryPersistence(context: context)
        let entry = try EntryCreationService(persistence: persistence, mediaStore: source.mediaStore, now: { clock })
            .create(EntryCreationDraft(body: "Original content", images: [MediaSource(url: input, originalFilename: "clock.png", contentType: "image/png")]))
        let editor = EntryEditingService(persistence: persistence, mediaStore: source.mediaStore, now: { clock })
        let transitions = EntryDeletionService(persistence: persistence, mediaStore: source.mediaStore, now: { clock })
        let weights = WeightRecordService(context: context, now: { clock })
        let weight = try weights.create(weightKilograms: 70, recordedAt: occurred)
        let habits = HabitService(context: context, now: { clock })
        let habit = try habits.create(name: "Preserved habit")
        let goals = GoalService(context: context, now: { clock })
        let goal = try goals.create(title: "Preserved goal", kind: .standard)
        let reviews = WeeklyReviewService(context: context, now: { clock })
        let review = try XCTUnwrap(reviews.review(containing: occurred))
        let periodStart = review.periodStart
        let periodEnd = review.periodEnd
        let imageIDs = entry.images.map(\.id)
        clock = created.addingTimeInterval(60)
        for instant in [clock, created.addingTimeInterval(30), created.addingTimeInterval(-60)] {
            clock = instant
            try editor.update(entry, with: EntryEditingDraft(title: "Retained title", body: "Edited content",
                occurredAt: occurred, retainedImageIDs: imageIDs, addedImages: []))
            XCTAssertEqual(entry.updatedAt, created.addingTimeInterval(60))
            try transitions.archive(entry)
            XCTAssertEqual(entry.updatedAt, created.addingTimeInterval(60))
            try weights.update(weight, weightKilograms: 69, recordedAt: occurred)
            XCTAssertEqual(weight.updatedAt, created.addingTimeInterval(60))
            try habits.update(habit, name: habit.name, recordingMode: .multiplePerDay, dailyTargetCount: 2)
            try habits.updateName(habit, name: habit.name)
            try habits.transition(habit, to: habit.status == .active ? .paused : .active)
            XCTAssertEqual(habit.updatedAt, created.addingTimeInterval(60))
            try goals.update(goal, title: goal.title, kind: goal.kind)
            try goals.transition(goal, to: goal.status == .active ? .paused : .active)
            XCTAssertEqual(goal.updatedAt, created.addingTimeInterval(60))
            try reviews.update(review, draft: WeeklyReviewDraft(rememberedText: "Preserved review", improvementText: "", nextStepText: "", focusText: "", isCompleted: false))
            XCTAssertEqual(review.updatedAt, created.addingTimeInterval(60))
        }
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        let target = try fixture.makeEmptyStore(named: "ClockRestored", onDisk: true)
        _ = try await target.service.importPackage(from: lease.url)
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: target.storeURL)
        let restored = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Entry>()).first)
        XCTAssertEqual(restored.id, entry.id)
        XCTAssertEqual(restored.body, "Edited content")
        XCTAssertEqual(restored.title, "Retained title")
        XCTAssertEqual(restored.status, .archived)
        XCTAssertEqual(restored.createdAt, created)
        XCTAssertEqual(restored.updatedAt, created.addingTimeInterval(60))
        XCTAssertEqual(restored.occurredAt, occurred)
        XCTAssertEqual(restored.images.map(\.id), imageIDs)
        XCTAssertEqual(try Data(contentsOf: target.mediaStore.fileURL(for: XCTUnwrap(restored.images.first).relativePath)), fixture.imageData)
        let restoredWeight = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<WeightRecord>()).first)
        XCTAssertEqual(restoredWeight.id, weight.id)
        XCTAssertEqual(restoredWeight.createdAt, created)
        XCTAssertEqual(restoredWeight.updatedAt, created.addingTimeInterval(60))
        XCTAssertEqual(restoredWeight.recordedAt, occurred)
        XCTAssertEqual(restoredWeight.weightKilograms, 69)
        let restoredHabit = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Habit>()).first)
        XCTAssertEqual(restoredHabit.id, habit.id)
        XCTAssertEqual(restoredHabit.name, habit.name)
        XCTAssertEqual(restoredHabit.updatedAt, created.addingTimeInterval(60))
        let restoredGoal = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Goal>()).first)
        XCTAssertEqual(restoredGoal.id, goal.id)
        XCTAssertEqual(restoredGoal.title, goal.title)
        XCTAssertEqual(restoredGoal.updatedAt, created.addingTimeInterval(60))
        let restoredReview = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<WeeklyReview>()).first)
        XCTAssertEqual(restoredReview.id, review.id)
        XCTAssertEqual(restoredReview.rememberedText, "Preserved review")
        XCTAssertEqual(restoredReview.updatedAt, created.addingTimeInterval(60))
        XCTAssertEqual(restoredReview.periodStart, periodStart)
        XCTAssertEqual(restoredReview.periodEnd, periodEnd)
        let habitEvents = try reopened.mainContext.fetch(FetchDescriptor<HabitLifecycleEvent>())
        XCTAssertTrue(habitEvents.contains { $0.occurredAt == clock && $0.occurredLocalDay == HabitLocalDay(date: clock).description })
        let goalEvents = try reopened.mainContext.fetch(FetchDescriptor<GoalLifecycleEvent>())
        XCTAssertTrue(goalEvents.contains { $0.occurredAt == clock })
    }

    func testExplicitResaveRepairsInjectedLocalTimeWithoutChangingContentOrIdentity() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let entry = try XCTUnwrap(source.container.mainContext.fetch(FetchDescriptor<Entry>()).first)
        let created = entry.createdAt
        let occurred = entry.occurredAt
        let originalBody = entry.body
        let originalID = entry.id
        let imageIDs = entry.images.map(\.id)
        entry.updatedAt = created.addingTimeInterval(-60) // Synthetic preexisting local corruption.
        try source.container.mainContext.save()
        await assertThrows({ try await source.service.exportPackage() }) {
            XCTAssertEqual($0 as? TransferPackageError, .invalidObject("entry"))
        }
        try EntryEditingService(persistence: ModelContextEntryPersistence(context: source.container.mainContext),
            mediaStore: source.mediaStore, now: { created.addingTimeInterval(-120) })
            .update(entry, with: EntryEditingDraft(title: entry.title, body: entry.body, occurredAt: occurred,
                retainedImageIDs: imageIDs, addedImages: []))
        XCTAssertEqual(entry.createdAt, created)
        XCTAssertEqual(entry.updatedAt, created)
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        let target = try fixture.makeEmptyStore(named: "ExplicitTimeRepair")
        _ = try await target.service.importPackage(from: lease.url)
        let restored = try XCTUnwrap(target.container.mainContext.fetch(FetchDescriptor<Entry>()).first { $0.id == originalID })
        XCTAssertEqual(restored.body, originalBody)
        XCTAssertEqual(restored.occurredAt, occurred)
        XCTAssertEqual(Set(restored.images.map(\.id)), Set(imageIDs))
        for image in restored.images {
            XCTAssertEqual(try Data(contentsOf: target.mediaStore.fileURL(for: image.relativePath)), fixture.imageData)
        }
    }

    func testPublicationIdentitySurvivesMediaRootCreation() throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let root = fixture.root.appendingPathComponent("NewMediaRoot", isDirectory: true)
        let before = StorePublication.key(for: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertEqual(StorePublication.key(for: root), before)
        XCTAssertEqual(StorePublication.key(for: URL(fileURLWithPath: root.path, isDirectory: false)), before)
    }

    func testRestoreEmptyDirectoryCheckCannotDeleteAConcurrentUserImage() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        let checkedEmpty = expectation(description: "Restore checked Originals empty before installation")
        let resume = DispatchSemaphore(value: 0)
        defer { resume.signal() }
        let target = try fixture.makeEmptyStore(named: "ConcurrentImageBeforeInstall", publicationCheckpoint: {
            if $0 == .beforeInstall {
                checkedEmpty.fulfill()
                guard resume.wait(timeout: .now() + 30) == .success else { throw TransferPackageError.interrupted }
            }
        })
        let restore = Task { try await target.service.importPackage(from: lease.url) }
        await fulfillment(of: [checkedEmpty], timeout: 30)
        let imageURL = fixture.root.appendingPathComponent("concurrent-user.png")
        try fixture.imageData.write(to: imageURL)
        let stored = try target.mediaStore.storeOriginal(MediaSource(url: imageURL, originalFilename: "user.png", contentType: "image/png"))
        let image = ImageMetadata(id: stored.id, relativePath: stored.relativePath, originalFilename: "user.png",
            contentType: "image/png", byteCount: stored.byteCount, pixelWidth: stored.pixelWidth,
            pixelHeight: stored.pixelHeight, checksum: stored.checksum, createdAt: Date())
        let entry = Entry(body: "User image saved before restore install", createdAt: Date(), images: [image])
        image.entry = entry
        target.container.mainContext.insert(entry)
        try target.container.mainContext.save()
        resume.signal()
        await assertThrows({ try await restore.value }) { XCTAssertEqual($0 as? TransferPackageError, .targetNotEmpty) }
        let context = ModelContext(target.container)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Entry>()).map(\.id), [entry.id])
        XCTAssertEqual(try Data(contentsOf: target.mediaStore.fileURL(for: stored.relativePath)), fixture.imageData)
        XCTAssertEqual(try originalFiles(at: target.mediaStore.rootURL).count, 1)
    }

    func testExportCutoffQueuesShareAndCancelledConsumerWithoutLosingDraft() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let originalIDs = Set(try ModelContext(source.container).fetch(FetchDescriptor<Entry>()).map(\.id))
        source.container.mainContext.autosaveEnabled = false
        let draft = Entry(body: "Unsaved during export", createdAt: Date())
        source.container.mainContext.insert(draft)
        let snapshot = expectation(description: "Export snapshot owns publication lease")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let exporter = ImportExportService(context: source.container.mainContext, mediaStore: source.mediaStore,
            exportCheckpoint: {
                snapshot.fulfill()
                guard release.wait(timeout: .now() + 30) == .success else { throw TransferPackageError.interrupted }
            })
        let export = Task { try await exporter.exportPackage() }
        await fulfillment(of: [snapshot], timeout: 30)
        let inbox = ShareInbox(root: fixture.root.appendingPathComponent("ExportQueuedInbox"))
        let imageURL = fixture.root.appendingPathComponent("queued.png")
        try fixture.imageData.write(to: imageURL)
        let imageID = UUID()
        let attachment = CaptureAttachment(id: imageID, filename: imageID.uuidString.lowercased(),
            contentType: "image/png", byteCount: Int64(fixture.imageData.count), checksum: try ShareInbox.checksum(imageURL))
        let payload = ShareImportPayload(text: "Arrived after cutoff", images: [attachment])
        try inbox.publish(payload, files: [imageID: imageURL])
        let requested = expectation(description: "Both share consumers are scheduled")
        requested.expectedFulfillmentCount = 2
        let first = ExternalCaptureImporter(container: source.container, mediaStore: source.mediaStore, inbox: inbox)
        let second = ExternalCaptureImporter(container: source.container, mediaStore: source.mediaStore, inbox: inbox)
        first.checkpoint = { if $0 == "scheduled" { requested.fulfill() } }
        second.checkpoint = first.checkpoint
        let cancelled = Task { try await first.scan() }
        let queued = Task { try await second.scan() }
        await fulfillment(of: [requested], timeout: 30)
        cancelled.cancel()
        XCTAssertEqual(try ModelContext(source.container).fetchCount(FetchDescriptor<CaptureImportReceipt>()), 0)
        XCTAssertEqual(try inbox.pending().count, 1)
        release.signal()
        let lease = try await export.value
        defer { lease.cleanup() }
        await assertThrows({ try await cancelled.value }) { XCTAssertTrue($0 is CancellationError) }
        let failures = try await queued.value
        XCTAssertEqual(failures, 0)
        XCTAssertTrue(source.container.mainContext.hasChanges)
        XCTAssertEqual(draft.body, "Unsaved during export")
        let current = ModelContext(source.container)
        XCTAssertEqual(try current.fetchCount(FetchDescriptor<CaptureImportReceipt>()), 1)
        let imported = try XCTUnwrap(current.fetch(FetchDescriptor<Entry>()).first { $0.id == payload.id })
        let image = try XCTUnwrap(imported.images.first)
        XCTAssertEqual(try Data(contentsOf: source.mediaStore.fileURL(for: image.relativePath)), fixture.imageData)
        let restored = try fixture.makeEmptyStore(named: "ExportCutoffRestore")
        _ = try await restored.service.importPackage(from: lease.url)
        XCTAssertEqual(Set(try restored.container.mainContext.fetch(FetchDescriptor<Entry>()).map(\.id)), originalIDs)
        let restoredImages = try restored.container.mainContext.fetch(FetchDescriptor<ImageMetadata>())
        XCTAssertEqual(restoredImages.count, 1)
        XCTAssertEqual(try Data(contentsOf: restored.mediaStore.fileURL(for: XCTUnwrap(restoredImages.first).relativePath)), fixture.imageData)
    }

    func testExportDrainsValidSharesAndDisclosesOnlyUnimportedPending() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makeEmptyStore(named: "ExportPendingBoundary")
        let inbox = ShareInbox(root: fixture.root.appendingPathComponent("ShareInbox"))
        let valid = ShareImportPayload(text: "Included by export drain")
        let future = ShareImportPayload(text: "Future content remains pending")
        try inbox.publish(future, files: [:])
        let futureDirectory = try XCTUnwrap(inbox.pending().first)
        var unsupported = future
        unsupported.schemaVersion = 99
        try JSONEncoder().encode(unsupported).write(to: futureDirectory.appendingPathComponent("payload.json"))
        try inbox.publish(valid, files: [:])
        try FileManager.default.createDirectory(at: source.mediaStore.rootURL, withIntermediateDirectories: true)
        try Data("{damaged reminder state".utf8).write(to: source.mediaStore.rootURL.appendingPathComponent("CaptureInboxState.json"))
        let lease = try await source.service.exportPackage(inbox: inbox)
        defer { lease.cleanup() }
        XCTAssertEqual(lease.pendingShareCount, 1)
        XCTAssertEqual(try inbox.pending(), [futureDirectory])
        let target = try fixture.makeEmptyStore(named: "ExportPendingRestored")
        _ = try await target.service.importPackage(from: lease.url)
        let entries = try target.container.mainContext.fetch(FetchDescriptor<Entry>())
        XCTAssertEqual(entries.map(\.id), [valid.id])
        XCTAssertEqual(entries.first?.body, valid.text)
        XCTAssertEqual(try JSONDecoder().decode(ShareImportPayload.self, from: Data(contentsOf: futureDirectory.appendingPathComponent("payload.json"))), unsupported)
    }

    func testRestoreFailurePreservesInterleavedCommittedShareImage() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        let installed = expectation(description: "Restore installed originals before database save")
        let resume = DispatchSemaphore(value: 0)
        let target = try fixture.makeEmptyStore(named: "InterleavedShare", publicationCheckpoint: {
            if $0 == .beforeSave {
                installed.fulfill()
                guard resume.wait(timeout: .now() + 30) == .success else {
                    throw TransferPackageError.interrupted
                }
                throw TransferPackageError.interrupted
            }
        })
        let inbox = ShareInbox(root: fixture.root.appendingPathComponent("ShareInbox"))
        let imageURL = fixture.root.appendingPathComponent("shared.png")
        try fixture.imageData.write(to: imageURL)
        let imageID = UUID()
        let attachment = CaptureAttachment(id: imageID, filename: imageID.uuidString.lowercased(),
            contentType: "image/png", byteCount: Int64(fixture.imageData.count),
            checksum: try ShareInbox.checksum(imageURL))
        let payload = ShareImportPayload(images: [attachment])
        try inbox.publish(payload, files: [imageID: imageURL])
        let restore = Task { try await target.service.importPackage(from: lease.url) }
        await fulfillment(of: [installed], timeout: 30)
        let importer = ExternalCaptureImporter(container: target.container,
            mediaStore: target.mediaStore, inbox: inbox)
        defer { resume.signal() }
        let requested = expectation(description: "Share worker requested publication")
        importer.checkpoint = { if $0 == "scheduled" { requested.fulfill() } }
        let share = Task { try await importer.scan() }
        await fulfillment(of: [requested], timeout: 30)
        XCTAssertEqual(try ModelContext(target.container).fetchCount(FetchDescriptor<CaptureImportReceipt>()), 0)
        XCTAssertEqual(try inbox.pending().count, 1)
        resume.signal()
        await assertThrows({ try await restore.value }) {
            XCTAssertEqual($0 as? TransferPackageError, .interrupted)
        }
        let failures = try await share.value
        XCTAssertEqual(failures, 0)
        let context = ModelContext(target.container)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<Entry>()).first)
        XCTAssertEqual(entry.id, payload.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CaptureImportReceipt>()), 1)
        XCTAssertTrue(try inbox.pending().isEmpty)
        let image = try XCTUnwrap(entry.images.first)
        XCTAssertEqual(try Data(contentsOf: target.mediaStore.fileURL(for: image.relativePath)), fixture.imageData)
    }

    func testRestoreEmptyRecheckPreservesConcurrentUserImageAndQueuedShare() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        let installed = expectation(description: "Restore installed files before empty recheck")
        let resume = DispatchSemaphore(value: 0)
        defer { resume.signal() }
        let target = try fixture.makeEmptyStore(named: "EmptyRecheck", publicationCheckpoint: {
            if $0 == .afterInstall {
                installed.fulfill()
                guard resume.wait(timeout: .now() + 30) == .success else { throw TransferPackageError.interrupted }
            }
        })
        let restore = Task { try await target.service.importPackage(from: lease.url) }
        await fulfillment(of: [installed], timeout: 30)
        let imageURL = fixture.root.appendingPathComponent("user-during-restore.png")
        try fixture.imageData.write(to: imageURL)
        let stored = try target.mediaStore.storeOriginal(MediaSource(url: imageURL, originalFilename: "user.png", contentType: "image/png"))
        let image = ImageMetadata(id: stored.id, relativePath: stored.relativePath, originalFilename: "user.png",
            contentType: "image/png", byteCount: stored.byteCount, pixelWidth: stored.pixelWidth,
            pixelHeight: stored.pixelHeight, checksum: stored.checksum, createdAt: Date())
        let entry = Entry(body: "Saved by user during restore", createdAt: Date(), images: [image])
        image.entry = entry
        target.container.mainContext.insert(entry)
        try target.container.mainContext.save()
        let inbox = ShareInbox(root: fixture.root.appendingPathComponent("RecheckShare"))
        let payload = ShareImportPayload(text: "Queued until restore rejects nonempty target")
        try inbox.publish(payload, files: [:])
        let importer = ExternalCaptureImporter(container: target.container, mediaStore: target.mediaStore, inbox: inbox)
        let scheduled = expectation(description: "Share scheduled before empty recheck")
        importer.checkpoint = { if $0 == "scheduled" { scheduled.fulfill() } }
        let share = Task { try await importer.scan() }
        await fulfillment(of: [scheduled], timeout: 30)
        XCTAssertEqual(try inbox.pending().count, 1)
        resume.signal()
        await assertThrows({ try await restore.value }) { XCTAssertEqual($0 as? TransferPackageError, .targetNotEmpty) }
        let failures = try await share.value
        XCTAssertEqual(failures, 0)
        let context = ModelContext(target.container)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<Entry>()).map(\.id)), [entry.id, payload.id])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CaptureImportReceipt>()), 1)
        XCTAssertEqual(try originalFiles(at: target.mediaStore.rootURL).count, 1)
        XCTAssertEqual(try Data(contentsOf: target.mediaStore.fileURL(for: stored.relativePath)), fixture.imageData)
    }

    func testRestoreCancellationAfterInstallReleasesShareAndPreservesDraft() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        let installed = expectation(description: "Restore installed media")
        let resume = DispatchSemaphore(value: 0)
        let target = try fixture.makeEmptyStore(named: "CancelledWithDraft", publicationCheckpoint: {
            if $0 == .afterInstall {
                installed.fulfill()
                guard resume.wait(timeout: .now() + 30) == .success else {
                    throw TransferPackageError.interrupted
                }
            }
        })
        let inbox = ShareInbox(root: fixture.root.appendingPathComponent("PendingCancellation"))
        let payload = ShareImportPayload(text: "Queued share")
        try inbox.publish(payload, files: [:])
        let restore = Task { try await target.service.importPackage(from: lease.url) }
        defer { resume.signal() }
        await fulfillment(of: [installed], timeout: 30)
        let draft = Entry(body: "Unsaved draft", createdAt: Date())
        target.container.mainContext.autosaveEnabled = false
        target.container.mainContext.insert(draft)
        let importer = ExternalCaptureImporter(container: target.container, mediaStore: target.mediaStore, inbox: inbox)
        let scheduled = expectation(description: "Share scheduled during restore")
        importer.checkpoint = { if $0 == "scheduled" { scheduled.fulfill() } }
        let share = Task { try await importer.scan() }
        await fulfillment(of: [scheduled], timeout: 30)
        restore.cancel()
        resume.signal()
        await assertThrows({ try await restore.value }) { XCTAssertTrue($0 is CancellationError) }
        let failures = try await share.value
        XCTAssertEqual(failures, 0)
        XCTAssertTrue(target.container.mainContext.hasChanges)
        XCTAssertEqual(draft.body, "Unsaved draft")
        let saved = try ModelContext(target.container).fetch(FetchDescriptor<Entry>())
        XCTAssertEqual(saved.map(\.id), [payload.id])
        XCTAssertEqual(try originalFiles(at: target.mediaStore.rootURL), [])
    }

    func testSuccessfulRestoreDoesNotRollbackDraftCreatedDuringPublication() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        let publishing = expectation(description: "Restore before save")
        let resume = DispatchSemaphore(value: 0)
        let target = try fixture.makeEmptyStore(named: "SuccessWithDraft", publicationCheckpoint: {
            if $0 == .beforeSave {
                publishing.fulfill()
                guard resume.wait(timeout: .now() + 30) == .success else {
                    throw TransferPackageError.interrupted
                }
            }
        })
        let restore = Task { try await target.service.importPackage(from: lease.url) }
        defer { resume.signal() }
        await fulfillment(of: [publishing], timeout: 30)
        target.container.mainContext.autosaveEnabled = false
        let draft = Entry(body: "Keep editing", createdAt: Date())
        target.container.mainContext.insert(draft)
        let inbox = ShareInbox(root: fixture.root.appendingPathComponent("QueuedAfterSuccessfulRestore"))
        let payload = ShareImportPayload(text: "Queued during successful restore")
        try inbox.publish(payload, files: [:])
        let importer = ExternalCaptureImporter(container: target.container, mediaStore: target.mediaStore, inbox: inbox)
        let scheduled = expectation(description: "Share waits for successful restore")
        importer.checkpoint = { if $0 == "scheduled" { scheduled.fulfill() } }
        let share = Task { try await importer.scan() }
        await fulfillment(of: [scheduled], timeout: 30)
        XCTAssertEqual(try ModelContext(target.container).fetchCount(FetchDescriptor<CaptureImportReceipt>()), 0)
        resume.signal()
        _ = try await restore.value
        let failures = try await share.value
        XCTAssertEqual(failures, 0)
        XCTAssertEqual(try ModelContext(target.container).fetchCount(FetchDescriptor<CaptureImportReceipt>()), 1)
        XCTAssertTrue(try inbox.pending().isEmpty)
        XCTAssertTrue(target.container.mainContext.hasChanges)
        XCTAssertEqual(draft.body, "Keep editing")
        XCTAssertFalse(try ModelContext(target.container).fetch(FetchDescriptor<Entry>()).contains { $0.id == draft.id })
    }

    func testLegacyV1TransferDataDecodesWithoutWeightRecordsAndValidates() throws {
        let data = Data("""
        {
          "entries": [],
          "images": [],
          "tags": [],
          "links": [],
          "habits": [],
          "habitLogs": [],
          "goals": [],
          "goalEvents": []
        }
        """.utf8)
        let legacy = try JSONDecoder().decode(TransferData.self, from: data)
        XCTAssertEqual(legacy.weightRecords, [])
        XCTAssertEqual(legacy.weeklyReviews, [])
        let manifest = ExportManifest(
            formatIdentifier: ExportManifest.formatIdentifier,
            packageSchemaVersion: 1,
            appVersion: "1.0",
            appBuild: "1",
            exportID: UUID(),
            exportedAt: Date(),
            objectCounts: legacy.objectCounts(forPackageSchemaVersion: 1),
            dataFile: ExportFileRecord(path: "data.json", byteCount: 0, sha256: ""),
            mediaFiles: []
        )

        XCTAssertNoThrow(try TransferValidator.validate(
            manifest: manifest,
            data: legacy,
            limits: .production
        ))
    }

    func testLegacyV1PackageImportsWithExplicitEmptyWeightRecords() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        let legacyPackage = try mutatePackage(
            lease.url,
            under: fixture.root.appendingPathComponent("LegacyV1"),
            rewriteJSON: { manifest, data in
                let legacyData = TransferData(
                    entries: data.entries,
                    images: data.images,
                    tags: data.tags,
                    links: data.links,
                    habits: data.habits,
                    habitLogs: data.habitLogs.map {
                        HabitLogTransfer(
                            id: $0.id,
                            habitID: $0.habitID,
                            occurredAt: $0.occurredAt,
                            isCompleted: $0.isCompleted,
                            quantity: $0.quantity,
                            unit: $0.unit,
                            result: $0.result,
                            linkedEntryID: $0.linkedEntryID,
                            createdAt: $0.createdAt
                        )
                    },
                    goals: data.goals,
                    goalEvents: data.goalEvents
                )
                return (ExportManifest(
                    formatIdentifier: manifest.formatIdentifier,
                    packageSchemaVersion: 1,
                    appVersion: manifest.appVersion,
                    appBuild: manifest.appBuild,
                    exportID: manifest.exportID,
                    exportedAt: manifest.exportedAt,
                    objectCounts: legacyData.objectCounts(forPackageSchemaVersion: 1),
                    dataFile: manifest.dataFile,
                    mediaFiles: manifest.mediaFiles
                ), legacyData)
            }
        )
        let target = try fixture.makeEmptyStore(named: "LegacyV1Target")

        let result = try await target.service.importPackage(from: legacyPackage)

        var expectedCounts = source.expectedCounts
        expectedCounts["weightRecords"] = 0
        expectedCounts["weeklyReviews"] = 0
        expectedCounts["habitPlanRevisions"] = 0
        expectedCounts["habitLifecycleEvents"] = 0
        var expectedIDs = source.expectedIDs
        expectedIDs["weightRecords"] = []
        expectedIDs["weeklyReviews"] = []
        XCTAssertEqual(result.objectCounts, expectedCounts)
        var importedIDs = try ids(in: target.container.mainContext)
        importedIDs["habitPlanRevisions"] = []
        importedIDs["habitLifecycleEvents"] = []
        expectedIDs["habitPlanRevisions"] = []
        expectedIDs["habitLifecycleEvents"] = []
        XCTAssertEqual(importedIDs, expectedIDs)
        XCTAssertEqual(try target.container.mainContext.fetchCount(FetchDescriptor<HabitPlanRevision>()), 1)
        XCTAssertEqual(try target.container.mainContext.fetchCount(FetchDescriptor<HabitLifecycleEvent>()), 1)
        XCTAssertEqual(try target.container.mainContext.fetchCount(FetchDescriptor<WeightRecord>()), 0)
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: target.container.mainContext))
    }

    func testSchemaV1RejectsNonEmptyWeightRecords() throws {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let data = makeTransferData(weightRecords: [
            WeightRecordTransfer(
                id: UUID(),
                weightKilograms: 72.4,
                recordedAt: timestamp,
                createdAt: timestamp,
                updatedAt: timestamp
            )
        ])

        XCTAssertThrowsError(try TransferValidator.validate(
            manifest: makeManifest(schemaVersion: 1, data: data),
            data: data,
            limits: .production
        )) {
            XCTAssertEqual($0 as? TransferPackageError, .invalidObject("weightRecord"))
        }
    }

    func testSchemaV2ValidatesWeightPayloads() throws {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let valid = WeightRecordTransfer(
            id: UUID(),
            weightKilograms: 72.4,
            recordedAt: Date(timeIntervalSince1970: 900),
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let validData = makeTransferData(weightRecords: [valid])
        XCTAssertNoThrow(try TransferValidator.validate(
            manifest: makeManifest(schemaVersion: 2, data: validData),
            data: validData,
            limits: .production
        ))

        let duplicateData = makeTransferData(weightRecords: [valid, valid])
        XCTAssertThrowsError(try TransferValidator.validate(
            manifest: makeManifest(schemaVersion: 2, data: duplicateData),
            data: duplicateData,
            limits: .production
        )) {
            XCTAssertEqual($0 as? TransferPackageError, .duplicateID("weightRecord"))
        }

        let invalidWeightData = makeTransferData(weightRecords: [
            WeightRecordTransfer(
                id: UUID(),
                weightKilograms: 0,
                recordedAt: timestamp,
                createdAt: timestamp,
                updatedAt: timestamp
            )
        ])
        XCTAssertThrowsError(try TransferValidator.validate(
            manifest: makeManifest(schemaVersion: 2, data: invalidWeightData),
            data: invalidWeightData,
            limits: .production
        )) {
            XCTAssertEqual($0 as? TransferPackageError, .invalidObject("weightRecord"))
        }

        let invalidTimestampData = makeTransferData(weightRecords: [
            WeightRecordTransfer(
                id: UUID(),
                weightKilograms: 72.4,
                recordedAt: timestamp,
                createdAt: timestamp,
                updatedAt: timestamp.addingTimeInterval(-1)
            )
        ])
        XCTAssertThrowsError(try TransferValidator.validate(
            manifest: makeManifest(schemaVersion: 2, data: invalidTimestampData),
            data: invalidTimestampData,
            limits: .production
        )) {
            XCTAssertEqual($0 as? TransferPackageError, .invalidObject("weightRecord"))
        }
    }

    func testSchemaV3ValidatesWeeklyReviewPayloadsAndOlderSchemasRejectThem() throws {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let review = WeeklyReviewTransfer(
            id: UUID(),
            weekIdentifier: "2026-W31",
            periodStart: Date(timeIntervalSince1970: 900),
            periodEnd: Date(timeIntervalSince1970: 1_500),
            rememberedText: "A meaningful moment",
            improvementText: nil,
            nextStepText: "Continue",
            focusText: "One thing",
            isCompleted: true,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let validData = makeTransferData(weeklyReviews: [review])
        XCTAssertNoThrow(try TransferValidator.validate(
            manifest: makeManifest(schemaVersion: 3, data: validData),
            data: validData,
            limits: .production
        ))
        XCTAssertThrowsError(try TransferValidator.validate(
            manifest: makeManifest(schemaVersion: 2, data: validData),
            data: validData,
            limits: .production
        )) {
            XCTAssertEqual($0 as? TransferPackageError, .invalidObject("weeklyReview"))
        }

        let duplicateData = makeTransferData(weeklyReviews: [review, review])
        XCTAssertThrowsError(try TransferValidator.validate(
            manifest: makeManifest(schemaVersion: 3, data: duplicateData),
            data: duplicateData,
            limits: .production
        )) {
            XCTAssertEqual($0 as? TransferPackageError, .duplicateID("weeklyReview"))
        }
    }

    func testSchemaV4RejectsMissingOrInvalidPlanRecordingMode() throws {
        let habitID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let habit = HabitTransfer(
            id: habitID,
            name: "Run",
            normalizedName: "run",
            status: HabitStatus.active.rawValue,
            recordingMode: HabitRecordingMode.oncePerDay.rawValue,
            dailyTargetCount: nil,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        for rawMode in [nil, "not-a-mode"] {
            let plan = HabitPlanRevisionTransfer(
                id: UUID(),
                habitID: habitID,
                effectiveLocalDay: "2026-09-07",
                period: HabitPlanPeriod.week.rawValue,
                goal: HabitPlanGoal.count.rawValue,
                targetCount: 3,
                weekdays: "",
                recordingMode: rawMode,
                trustCoverageStartLocalDay: "2026-09-07",
                createdAt: timestamp
            )
            let data = makeTransferData(habits: [habit], habitPlanRevisions: [plan])
            XCTAssertThrowsError(try TransferValidator.validate(
                manifest: makeManifest(schemaVersion: 4, data: data),
                data: data,
                limits: .production
            )) {
                XCTAssertEqual($0 as? TransferPackageError, .invalidObject("habitPlanRevision"))
            }
        }
    }

    func testOlderSchemasRejectV4HabitPlanAndLifecyclePayloads() throws {
        let habitID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let habit = HabitTransfer(
            id: habitID,
            name: "Run",
            normalizedName: "run",
            status: HabitStatus.active.rawValue,
            recordingMode: HabitRecordingMode.oncePerDay.rawValue,
            dailyTargetCount: nil,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let planData = makeTransferData(
            habits: [habit],
            habitPlanRevisions: [HabitPlanRevisionTransfer(
                id: UUID(),
                habitID: habitID,
                effectiveLocalDay: "2026-09-07",
                period: HabitPlanPeriod.week.rawValue,
                goal: HabitPlanGoal.count.rawValue,
                targetCount: 3,
                weekdays: "",
                recordingMode: HabitRecordingMode.oncePerDay.rawValue,
                trustCoverageStartLocalDay: "2026-09-07",
                createdAt: timestamp
            )]
        )
        XCTAssertThrowsError(try TransferValidator.validate(
            manifest: makeManifest(schemaVersion: 3, data: planData),
            data: planData,
            limits: .production
        )) {
            XCTAssertEqual($0 as? TransferPackageError, .invalidObject("habitPlanRevision"))
        }

        let lifecycleData = makeTransferData(
            habits: [habit],
            habitLifecycleEvents: [HabitLifecycleEventTransfer(
                id: UUID(),
                habitID: habitID,
                kind: HabitLifecycleEventKind.created.rawValue,
                occurredLocalDay: "2026-09-07",
                occurredAt: timestamp,
                createdAt: timestamp
            )]
        )
        XCTAssertThrowsError(try TransferValidator.validate(
            manifest: makeManifest(schemaVersion: 3, data: lifecycleData),
            data: lifecycleData,
            limits: .production
        )) {
            XCTAssertEqual($0 as? TransferPackageError, .invalidObject("habitLifecycleEvent"))
        }
    }

    func testSchemaV4ValidatesMigrationBaselineKnownStatus() throws {
        let habitID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let habit = HabitTransfer(
            id: habitID,
            name: "Legacy Habit",
            normalizedName: "legacy habit",
            status: HabitStatus.paused.rawValue,
            recordingMode: HabitRecordingMode.oncePerDay.rawValue,
            dailyTargetCount: nil,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        func data(knownStatus: String?, kind: HabitLifecycleEventKind = .migrationBaseline) -> TransferData {
            makeTransferData(
                habits: [habit],
                habitLifecycleEvents: [HabitLifecycleEventTransfer(
                    id: UUID(),
                    habitID: habitID,
                    kind: kind.rawValue,
                    occurredLocalDay: "2026-09-07",
                    occurredAt: timestamp,
                    createdAt: timestamp,
                    knownStatus: knownStatus
                )]
            )
        }

        let valid = data(knownStatus: HabitStatus.paused.rawValue)
        XCTAssertNoThrow(try TransferValidator.validate(
            manifest: makeManifest(schemaVersion: 4, data: valid),
            data: valid,
            limits: .production
        ))
        for invalid in [
            data(knownStatus: nil),
            data(knownStatus: "unknown"),
            data(knownStatus: HabitStatus.active.rawValue, kind: .created)
        ] {
            XCTAssertThrowsError(try TransferValidator.validate(
                manifest: makeManifest(schemaVersion: 4, data: invalid),
                data: invalid,
                limits: .production
            )) {
                XCTAssertEqual($0 as? TransferPackageError, .invalidObject("habitLifecycleEvent"))
            }
        }
    }

    func testSchemaV4RejectsImpossibleOncePerDayPlanTargets() throws {
        let habitID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let habit = HabitTransfer(
            id: habitID,
            name: "Bounded",
            normalizedName: "bounded",
            status: HabitStatus.active.rawValue,
            recordingMode: HabitRecordingMode.oncePerDay.rawValue,
            dailyTargetCount: nil,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let invalidPlans: [(HabitPlanPeriod, HabitPlanGoal, Int, String)] = [
            (.day, .everyDay, 2, ""),
            (.day, .selectedWeekdays, 2, "2"),
            (.week, .count, 8, ""),
            (.month, .count, 29, "")
        ]

        for (period, goal, target, weekdays) in invalidPlans {
            let data = makeTransferData(
                habits: [habit],
                habitPlanRevisions: [HabitPlanRevisionTransfer(
                    id: UUID(),
                    habitID: habitID,
                    effectiveLocalDay: "2026-09-07",
                    period: period.rawValue,
                    goal: goal.rawValue,
                    targetCount: target,
                    weekdays: weekdays,
                    recordingMode: HabitRecordingMode.oncePerDay.rawValue,
                    trustCoverageStartLocalDay: "2026-09-07",
                    createdAt: timestamp
                )]
            )
            XCTAssertThrowsError(try TransferValidator.validate(
                manifest: makeManifest(schemaVersion: 4, data: data),
                data: data,
                limits: .production
            )) {
                XCTAssertEqual($0 as? TransferPackageError, .invalidObject("habitPlanRevision"))
            }
        }
    }

    func testSchemaV4RejectsDuplicatePlanEffectiveDayForHabit() throws {
        let habitID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let habit = HabitTransfer(
            id: habitID,
            name: "Unique Plan",
            normalizedName: "unique plan",
            status: HabitStatus.active.rawValue,
            recordingMode: HabitRecordingMode.oncePerDay.rawValue,
            dailyTargetCount: nil,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        func revision(id: UUID) -> HabitPlanRevisionTransfer {
            HabitPlanRevisionTransfer(
                id: id,
                habitID: habitID,
                effectiveLocalDay: "2026-09-07",
                period: HabitPlanPeriod.day.rawValue,
                goal: HabitPlanGoal.everyDay.rawValue,
                targetCount: 1,
                weekdays: "",
                recordingMode: HabitRecordingMode.oncePerDay.rawValue,
                trustCoverageStartLocalDay: "2026-09-07",
                createdAt: timestamp
            )
        }
        let data = makeTransferData(
            habits: [habit],
            habitPlanRevisions: [revision(id: UUID()), revision(id: UUID())]
        )

        XCTAssertThrowsError(try TransferValidator.validate(
            manifest: makeManifest(schemaVersion: 4, data: data),
            data: data,
            limits: .production
        )) {
            XCTAssertEqual($0 as? TransferPackageError, .duplicateID("habitPlanRevisionEffectiveDay"))
        }
    }

    func testSchemasBeforeV4RejectHabitLogLocalDayMetadata() throws {
        let habitID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let habit = HabitTransfer(
            id: habitID,
            name: "Legacy",
            normalizedName: "legacy",
            status: HabitStatus.active.rawValue,
            recordingMode: HabitRecordingMode.oncePerDay.rawValue,
            dailyTargetCount: nil,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let v4Log = HabitLogTransfer(
            id: UUID(), habitID: habitID, occurredAt: timestamp, isCompleted: true,
            quantity: nil, unit: nil, result: nil, linkedEntryID: nil, createdAt: timestamp,
            localDayIdentifier: "2026-09-07",
            localTimeZoneIdentifier: "UTC",
            localDayProvenance: HabitLogDayProvenance.legacyBootstrap.rawValue
        )

        for schemaVersion in 1...3 {
            let data = makeTransferData(habits: [habit], habitLogs: [v4Log])
            XCTAssertThrowsError(try TransferValidator.validate(
                manifest: makeManifest(schemaVersion: schemaVersion, data: data),
                data: data,
                limits: .production
            )) {
                XCTAssertEqual($0 as? TransferPackageError, .invalidObject("habitLog"))
            }
        }
    }

    func testFullRoundTripPreservesEveryObjectIdentityRelationshipAndOriginal() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let logs = LogRecorder()
        let source = try fixture.makePopulatedStore(log: { logs.values.append($0) })
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }

        let target = try fixture.makeEmptyStore(named: "Target", log: { logs.values.append($0) })
        let result = try await target.service.importPackage(from: lease.url)

        XCTAssertEqual(result.objectCounts, source.expectedCounts)
        XCTAssertEqual(result.restoredMediaCount, 1)
        XCTAssertEqual(try ids(in: target.container.mainContext), source.expectedIDs)
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: target.container.mainContext))
        let restoredImage = try XCTUnwrap(target.container.mainContext.fetch(FetchDescriptor<ImageMetadata>()).first)
        XCTAssertEqual(
            try Data(contentsOf: target.mediaStore.fileURL(for: restoredImage.relativePath)),
            fixture.imageData
        )
        let restoredWeight = try XCTUnwrap(
            target.container.mainContext.fetch(FetchDescriptor<WeightRecord>()).first
        )
        let sourceWeight = try XCTUnwrap(
            source.container.mainContext.fetch(FetchDescriptor<WeightRecord>()).first
        )
        XCTAssertEqual(restoredWeight.id, sourceWeight.id)
        XCTAssertEqual(restoredWeight.weightKilograms, sourceWeight.weightKilograms)
        XCTAssertEqual(restoredWeight.recordedAt, sourceWeight.recordedAt)
        XCTAssertEqual(restoredWeight.createdAt, sourceWeight.createdAt)
        XCTAssertEqual(restoredWeight.updatedAt, sourceWeight.updatedAt)
        let restoredWeeklyReview = try XCTUnwrap(
            target.container.mainContext.fetch(FetchDescriptor<WeeklyReview>()).first
        )
        let sourceWeeklyReview = try XCTUnwrap(
            source.container.mainContext.fetch(FetchDescriptor<WeeklyReview>()).first
        )
        XCTAssertEqual(restoredWeeklyReview.id, sourceWeeklyReview.id)
        XCTAssertEqual(restoredWeeklyReview.weekIdentifier, sourceWeeklyReview.weekIdentifier)
        XCTAssertEqual(restoredWeeklyReview.rememberedText, sourceWeeklyReview.rememberedText)
        XCTAssertEqual(restoredWeeklyReview.focusText, sourceWeeklyReview.focusText)
        XCTAssertEqual(restoredWeeklyReview.isCompleted, sourceWeeklyReview.isCompleted)
        let sourcePlan = try XCTUnwrap(source.container.mainContext.fetch(FetchDescriptor<HabitPlanRevision>()).first)
        let restoredPlan = try XCTUnwrap(target.container.mainContext.fetch(FetchDescriptor<HabitPlanRevision>()).first)
        XCTAssertEqual(restoredPlan.id, sourcePlan.id)
        XCTAssertEqual(restoredPlan.effectiveLocalDay, sourcePlan.effectiveLocalDay)
        XCTAssertEqual(restoredPlan.plan, sourcePlan.plan)
        XCTAssertEqual(restoredPlan.origin, sourcePlan.origin)
        let sourceDayMetadata = try XCTUnwrap(source.container.mainContext.fetch(FetchDescriptor<HabitLogDayMetadata>()).first)
        let restoredDayMetadata = try XCTUnwrap(target.container.mainContext.fetch(FetchDescriptor<HabitLogDayMetadata>()).first)
        XCTAssertEqual(restoredDayMetadata.habitLogID, sourceDayMetadata.habitLogID)
        XCTAssertEqual(restoredDayMetadata.localDayIdentifier, sourceDayMetadata.localDayIdentifier)
        XCTAssertEqual(restoredDayMetadata.localTimeZoneIdentifier, sourceDayMetadata.localTimeZoneIdentifier)
        XCTAssertEqual(restoredDayMetadata.provenance, sourceDayMetadata.provenance)
        XCTAssertEqual(
            try target.container.mainContext.fetch(FetchDescriptor<HabitLifecycleEvent>()).map(\.id),
            try source.container.mainContext.fetch(FetchDescriptor<HabitLifecycleEvent>()).map(\.id)
        )
        let sourceHabitEvent = try XCTUnwrap(source.container.mainContext.fetch(FetchDescriptor<HabitLifecycleEvent>()).first)
        let restoredHabitEvent = try XCTUnwrap(target.container.mainContext.fetch(FetchDescriptor<HabitLifecycleEvent>()).first)
        XCTAssertEqual(restoredHabitEvent.kind, sourceHabitEvent.kind)
        XCTAssertEqual(restoredHabitEvent.knownStatus, sourceHabitEvent.knownStatus)
        let joinedLogs = logs.values.joined(separator: "|")
        XCTAssertFalse(joinedLogs.contains(TransferTestFixture.secretBody))
        XCTAssertFalse(joinedLogs.contains(fixture.root.path))
        XCTAssertFalse(joinedLogs.contains(fixture.imageData.base64EncodedString()))
    }

    func testLegacyTargetlessMultipleHabitRoundTripsWithoutChangingIdentityOrHistory() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let sourceContext = source.container.mainContext
        let sourceHabit = try XCTUnwrap(sourceContext.fetch(FetchDescriptor<Habit>()).first)
        let sourceLogIDs = Set(try sourceContext.fetch(FetchDescriptor<HabitLog>()).map(\.id))
        sourceContext.insert(HabitConfiguration(
            habitID: sourceHabit.id,
            recordingMode: .multiplePerDay,
            dailyTargetCount: nil,
            updatedAt: sourceHabit.updatedAt
        ))
        try sourceContext.save()

        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        let target = try fixture.makeEmptyStore(named: "LegacyTargetless")

        _ = try await target.service.importPackage(from: lease.url)

        let restoredHabit = try XCTUnwrap(
            target.container.mainContext.fetch(FetchDescriptor<Habit>()).first
        )
        XCTAssertEqual(restoredHabit.id, sourceHabit.id)
        XCTAssertEqual(
            try HabitSettingsResolver.settings(
                for: restoredHabit.id,
                context: target.container.mainContext
            ),
            HabitSettings(recordingMode: .multiplePerDay, dailyTargetCount: nil)
        )
        XCTAssertEqual(
            Set(try target.container.mainContext.fetch(FetchDescriptor<HabitLog>()).map(\.id)),
            sourceLogIDs
        )
        XCTAssertEqual(try ids(in: target.container.mainContext), source.expectedIDs)
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: target.container.mainContext))
    }

    func testTransferValidatorRejectsNonPositiveProvidedHabitTarget() throws {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        for target in [0, -1] {
            let data = makeTransferData(habits: [HabitTransfer(
                id: UUID(),
                name: "Water",
                normalizedName: "water",
                status: HabitStatus.active.rawValue,
                recordingMode: HabitRecordingMode.multiplePerDay.rawValue,
                dailyTargetCount: target,
                createdAt: timestamp,
                updatedAt: timestamp
            )])
            XCTAssertThrowsError(try TransferValidator.validate(
                manifest: makeManifest(schemaVersion: 3, data: data),
                data: data,
                limits: .production
            )) {
                XCTAssertEqual($0 as? TransferPackageError, .invalidObject("habit"))
            }
        }
    }

    func testDeleteIsolatedDatasetThenRestoreSameOnDiskStore() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore(onDisk: true)
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        let originalIDs = source.expectedIDs
        let originalPaths = try source.container.mainContext
            .fetch(FetchDescriptor<ImageMetadata>())
            .map(\.relativePath)

        try deleteAllFixtureData(source.container.mainContext)
        try source.container.mainContext.save()
        for path in originalPaths { try source.mediaStore.removeOriginal(at: path) }
        XCTAssertEqual(try totalObjectCount(in: source.container.mainContext), 0)

        _ = try await source.service.importPackage(from: lease.url)

        XCTAssertEqual(try ids(in: source.container.mainContext), originalIDs)
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: source.container.mainContext))
        XCTAssertEqual(try originalFiles(at: source.mediaStore.rootURL).count, 1)
    }

    func testImportedOnDiskStoreReopensWithoutDanglingLinksAndCanReExportEquivalentData() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let firstLease = try await source.service.exportPackage()
        defer { firstLease.cleanup() }
        let target = try fixture.makeEmptyStore(named: "PersistentTarget", onDisk: true)

        _ = try await target.service.importPackage(from: firstLease.url)
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: target.storeURL)
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: reopened.mainContext))
        XCTAssertEqual(try ids(in: reopened.mainContext), source.expectedIDs)

        let reexportService = ImportExportService(
            context: reopened.mainContext,
            mediaStore: target.mediaStore,
            workspaceRoot: fixture.root.appendingPathComponent("Reexport"),
            availableCapacity: { .max },
            now: { Date(timeIntervalSince1970: 9_000) },
            appVersion: { ("1.0", "1") }
        )
        let secondLease = try await reexportService.exportPackage()
        defer { secondLease.cleanup() }
        XCTAssertEqual(
            try extractedDataJSON(from: firstLease.url, under: fixture.root.appendingPathComponent("ExtractOne")),
            try extractedDataJSON(from: secondLease.url, under: fixture.root.appendingPathComponent("ExtractTwo"))
        )
    }

    func testNonEmptyTargetRejectsImportWithoutMutation() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        let target = try fixture.makeEmptyStore(named: "NonEmpty")
        let existing = Entry(body: "Keep me", createdAt: Date(timeIntervalSince1970: 50))
        target.container.mainContext.insert(existing)
        try target.container.mainContext.save()

        await assertThrows({ try await target.service.importPackage(from: lease.url) }) {
            XCTAssertEqual($0 as? TransferPackageError, .targetNotEmpty)
        }
        XCTAssertEqual(try target.container.mainContext.fetch(FetchDescriptor<Entry>()).map(\.id), [existing.id])
        XCTAssertEqual(try regularFiles(at: target.mediaStore.rootURL), [])
    }

    func testInterruptedPublicationLeavesEmptyTargetAndNoOriginals() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        let target = try fixture.makeEmptyStore(
            named: "Interrupted",
            publicationCheckpoint: { checkpoint in
                if checkpoint == .afterMediaCopy(1) { throw TransferPackageError.interrupted }
            }
        )

        await assertThrows({ try await target.service.importPackage(from: lease.url) }) {
            XCTAssertEqual($0 as? TransferPackageError, .interrupted)
        }
        XCTAssertEqual(try totalObjectCount(in: target.container.mainContext), 0)
        XCTAssertEqual(try originalFiles(at: target.mediaStore.rootURL), [])
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: target.container.mainContext))

        let beforeSaveTarget = try fixture.makeEmptyStore(
            named: "InterruptedBeforeSave",
            publicationCheckpoint: { checkpoint in
                if checkpoint == .beforeSave { throw TransferPackageError.interrupted }
            }
        )
        await assertThrows({ try await beforeSaveTarget.service.importPackage(from: lease.url) }) {
            XCTAssertEqual($0 as? TransferPackageError, .interrupted)
        }
        XCTAssertEqual(try totalObjectCount(in: beforeSaveTarget.container.mainContext), 0)
        XCTAssertEqual(try originalFiles(at: beforeSaveTarget.mediaStore.rootURL), [])
    }

    func testMissingMediaAndCorruptDataAreRejectedBeforePublication() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }

        let missingMedia = try mutatePackage(
            lease.url,
            under: fixture.root.appendingPathComponent("MissingMedia"),
            mutation: { root, _, _ in
                let media = try XCTUnwrap(try regularFiles(at: root.appendingPathComponent("media")).first)
                try FileManager.default.removeItem(at: media)
            }
        )
        let corruptManifest = try mutatePackage(
            lease.url,
            under: fixture.root.appendingPathComponent("CorruptManifest"),
            mutation: { root, _, _ in
                try Data("{".utf8).write(to: root.appendingPathComponent("manifest.json"))
            }
        )
        let corruptData = try mutatePackage(
            lease.url,
            under: fixture.root.appendingPathComponent("CorruptData"),
            mutation: { root, _, _ in
                try Data("tampered".utf8).write(to: root.appendingPathComponent("data.json"))
            }
        )

        for package in [missingMedia, corruptManifest, corruptData] {
            let target = try fixture.makeEmptyStore(named: UUID().uuidString)
            await assertThrows({ try await target.service.importPackage(from: package) })
            XCTAssertEqual(try totalObjectCount(in: target.container.mainContext), 0)
            XCTAssertEqual(try originalFiles(at: target.mediaStore.rootURL), [])
        }
    }

    func testDuplicateObjectIDAndUnsupportedSchemaAreRejected() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }

        let duplicate = try mutatePackage(
            lease.url,
            under: fixture.root.appendingPathComponent("Duplicate"),
            rewriteJSON: { manifest, data in
                let duplicateData = TransferData(
                    entries: data.entries + [try XCTUnwrap(data.entries.first)],
                    images: data.images,
                    tags: data.tags,
                    links: data.links,
                    habits: data.habits,
                    habitLogs: data.habitLogs,
                    goals: data.goals,
                    goalEvents: data.goalEvents,
                    weightRecords: data.weightRecords,
                    weeklyReviews: data.weeklyReviews
                )
                return (manifest, duplicateData)
            }
        )
        let unsupported = try mutatePackage(
            lease.url,
            under: fixture.root.appendingPathComponent("Unsupported"),
            rewriteJSON: { manifest, data in
                (ExportManifest(
                    formatIdentifier: manifest.formatIdentifier,
                    packageSchemaVersion: ExportManifest.currentPackageSchemaVersion + 1,
                    appVersion: manifest.appVersion,
                    appBuild: manifest.appBuild,
                    exportID: manifest.exportID,
                    exportedAt: manifest.exportedAt,
                    objectCounts: manifest.objectCounts,
                    dataFile: manifest.dataFile,
                    mediaFiles: manifest.mediaFiles
                ), data)
            },
            refreshManifest: false
        )

        let duplicateTarget = try fixture.makeEmptyStore(named: "DuplicateTarget")
        await assertThrows({ try await duplicateTarget.service.importPackage(from: duplicate) }) {
            XCTAssertEqual($0 as? TransferPackageError, .duplicateID("entry"))
        }
        let schemaTarget = try fixture.makeEmptyStore(named: "SchemaTarget")
        await assertThrows({ try await schemaTarget.service.importPackage(from: unsupported) }) {
            XCTAssertEqual($0 as? TransferPackageError, .unsupportedSchema(ExportManifest.currentPackageSchemaVersion + 1))
        }
    }

    func testArchiveAndExpandedFileAndObjectLimitsAreEnforced() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        let archiveSize = try fileSize(lease.url)

        let cases = [
            ZIPImportLimits(maximumArchiveBytes: archiveSize - 1, maximumExpandedBytes: .max,
                            capacitySafetyReserve: 0, maximumFileCount: 100, maximumObjectCount: 100,
                            maximumCompressionRatio: 100),
            ZIPImportLimits(maximumArchiveBytes: .max, maximumExpandedBytes: 1,
                            capacitySafetyReserve: 0, maximumFileCount: 100, maximumObjectCount: 100,
                            maximumCompressionRatio: 100),
            ZIPImportLimits(maximumArchiveBytes: .max, maximumExpandedBytes: .max,
                            capacitySafetyReserve: 0, maximumFileCount: 2, maximumObjectCount: 100,
                            maximumCompressionRatio: 100),
            ZIPImportLimits(maximumArchiveBytes: .max, maximumExpandedBytes: .max,
                            capacitySafetyReserve: 0, maximumFileCount: 100, maximumObjectCount: 1,
                            maximumCompressionRatio: 100),
            ZIPImportLimits(maximumArchiveBytes: .max, maximumExpandedBytes: .max,
                            capacitySafetyReserve: 0, maximumFileCount: 100, maximumObjectCount: 100,
                            maximumCompressionRatio: 100, maximumManifestBytes: 1),
            ZIPImportLimits(maximumArchiveBytes: .max, maximumExpandedBytes: .max,
                            capacitySafetyReserve: 0, maximumFileCount: 100, maximumObjectCount: 100,
                            maximumCompressionRatio: 100, maximumDataBytes: 1)
        ]
        for (index, limits) in cases.enumerated() {
            let target = try fixture.makeEmptyStore(named: "Limit-\(index)", limits: limits)
            await assertThrows({ try await target.service.importPackage(from: lease.url) })
            XCTAssertEqual(try totalObjectCount(in: target.container.mainContext), 0)
            XCTAssertEqual(try regularFiles(at: fixture.root.appendingPathComponent("Workspace-Limit-\(index)")), [])
        }

        XCTAssertThrowsError(try ZIPArchiveReader(
            archiveURL: lease.url,
            limits: .production,
            availableCapacity: 0
        )) {
            XCTAssertEqual($0 as? ZIPArchiveError, .insufficientCapacity)
        }
    }

    func testExportEnforcesItsOwnImportCompatibilityLimits() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lowObjectLimits = ZIPImportLimits(
            maximumArchiveBytes: .max,
            maximumExpandedBytes: .max,
            capacitySafetyReserve: 0,
            maximumFileCount: 100,
            maximumObjectCount: 1,
            maximumCompressionRatio: 100
        )
        let lowDataLimits = ZIPImportLimits(
            maximumArchiveBytes: .max,
            maximumExpandedBytes: .max,
            capacitySafetyReserve: 0,
            maximumFileCount: 100,
            maximumObjectCount: 100,
            maximumCompressionRatio: 100,
            maximumDataBytes: 1
        )

        for (name, limits) in [("Object", lowObjectLimits), ("Data", lowDataLimits)] {
            let workspace = fixture.root.appendingPathComponent("ExportLimit-\(name)")
            let service = ImportExportService(
                context: source.container.mainContext,
                mediaStore: source.mediaStore,
                workspaceRoot: workspace,
                limits: limits,
                availableCapacity: { .max }
            )
            await assertThrows({ try await service.exportPackage() })
            XCTAssertEqual(try regularFiles(at: workspace), [])
        }
    }

    func testOversizedMediaMemberIsRejectedBeforeJSONDecodeAndExtraction() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let files = fixture.root.appendingPathComponent("OversizedMemberFiles", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let manifest = files.appendingPathComponent("manifest.json")
        let data = files.appendingPathComponent("data.json")
        let media = files.appendingPathComponent("oversized.png")
        try Data("{}".utf8).write(to: manifest)
        try Data("{}".utf8).write(to: data)
        try Data(repeating: 0, count: Int(MediaStore.maximumOriginalByteCount + 1)).write(to: media)
        let archive = fixture.root.appendingPathComponent("oversized-member.zip")
        try ZIPArchiveWriter.write(sources: [
            ZIPSource(path: "manifest.json", fileURL: manifest),
            ZIPSource(path: "data.json", fileURL: data),
            ZIPSource(path: "media/oversized.png", fileURL: media)
        ], to: archive)
        let target = try fixture.makeEmptyStore(named: "OversizedMember")

        await assertThrows({ try await target.service.importPackage(from: archive) }) {
            XCTAssertEqual($0 as? ZIPArchiveError, .expandedSizeExceeded)
        }
        XCTAssertEqual(try totalObjectCount(in: target.container.mainContext), 0)
        XCTAssertEqual(try originalFiles(at: target.mediaStore.rootURL), [])
    }

    func testCompressionRatioUnsafePathSymlinkAndCaseCollisionFixturesAreRejected() throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let files = fixture.root.appendingPathComponent("ZIPFiles", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let first = files.appendingPathComponent("first")
        let second = files.appendingPathComponent("second")
        try Data(repeating: 7, count: 256).write(to: first)
        try Data(repeating: 8, count: 16).write(to: second)

        let ratio = fixture.root.appendingPathComponent("ratio.zip")
        try ZIPArchiveWriter.write(sources: [ZIPSource(path: "ratio.bin", fileURL: first)], to: ratio)
        try patchCentralDirectory(at: ratio) { data, offset in
            writeUInt32(1, to: &data, at: offset + 20)
        }
        XCTAssertThrowsError(try ZIPArchiveReader(archiveURL: ratio, limits: .production, availableCapacity: .max)) {
            XCTAssertEqual($0 as? ZIPArchiveError, .compressionRatioExceeded)
        }

        let unsafe = fixture.root.appendingPathComponent("unsafe.zip")
        try ZIPArchiveWriter.write(sources: [ZIPSource(path: "safe.txt", fileURL: second)], to: unsafe)
        try replaceASCII("safe.txt", with: "../x.txt", in: unsafe)
        XCTAssertThrowsError(try ZIPArchiveReader(archiveURL: unsafe, limits: .production, availableCapacity: .max)) {
            XCTAssertEqual($0 as? ZIPArchiveError, .unsafePath)
        }

        let symlink = fixture.root.appendingPathComponent("symlink.zip")
        try ZIPArchiveWriter.write(sources: [ZIPSource(path: "link.txt", fileURL: second)], to: symlink)
        try patchCentralDirectory(at: symlink) { data, offset in
            writeUInt32(UInt32(0o120777) << 16, to: &data, at: offset + 38)
        }
        XCTAssertThrowsError(try ZIPArchiveReader(archiveURL: symlink, limits: .production, availableCapacity: .max)) {
            XCTAssertEqual($0 as? ZIPArchiveError, .unsupportedFileType)
        }

        let collision = fixture.root.appendingPathComponent("collision.zip")
        try ZIPArchiveWriter.write(sources: [
            ZIPSource(path: "A/a.txt", fileURL: second),
            ZIPSource(path: "B/b.txt", fileURL: second)
        ], to: collision)
        try replaceASCII("B/b.txt", with: "a/A.txt", in: collision)
        XCTAssertThrowsError(try ZIPArchiveReader(archiveURL: collision, limits: .production, availableCapacity: .max)) {
            XCTAssertEqual($0 as? ZIPArchiveError, .duplicatePath)
        }
    }

    func testZIP64ExactAndAboveEntryCountSentinelsRoundTrip() throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let empty = fixture.root.appendingPathComponent("empty")
        try Data().write(to: empty)
        let sources = (0...Int(UInt16.max)).map {
            ZIPSource(path: "f/\($0)", fileURL: empty)
        }
        let limits = ZIPImportLimits(
            maximumArchiveBytes: 32 * 1_024 * 1_024,
            maximumExpandedBytes: 1,
            capacitySafetyReserve: 0,
            maximumFileCount: 70_000,
            maximumObjectCount: 1,
            maximumCompressionRatio: 100
        )

        for count in [Int(UInt16.max), Int(UInt16.max) + 1] {
            let archive = fixture.root.appendingPathComponent("zip64-count-\(count).zip")
            try ZIPArchiveWriter.write(sources: Array(sources.prefix(count)), to: archive)
            let reader = try ZIPArchiveReader(
                archiveURL: archive,
                limits: limits,
                availableCapacity: .max
            )
            XCTAssertEqual(reader.members.count, count)
            XCTAssertEqual(reader.members.first?.path, "f/0")
            XCTAssertEqual(reader.members.last?.path, "f/\(count - 1)")
        }
    }

    func testExportLeaseAndLaunchRecoveryCleanupTemporaryArtifacts() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage()
        let archiveURL = lease.url
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        lease.cleanup()
        lease.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))

        let interrupted = source.mediaStore.rootURL.appendingPathComponent("Transfer/Import/interrupted.tmp")
        try FileManager.default.createDirectory(
            at: interrupted.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("private".utf8).write(to: interrupted)
        try ImportExportService.cleanupInterruptedTransfers(mediaRootURL: source.mediaStore.rootURL)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: source.mediaStore.rootURL.appendingPathComponent("Transfer").path
        ))
    }

    func testCancelledExportAndImportLeaveNoTemporaryOrPublishedData() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()

        let cancelledExport = Task { try await source.service.exportPackage() }
        cancelledExport.cancel()
        await assertThrows({ try await cancelledExport.value }) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertEqual(try regularFiles(at: fixture.root.appendingPathComponent("Workspace-Source")), [])

        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        let target = try fixture.makeEmptyStore(named: "CancelledImport")
        let cancelledImport = Task { try await target.service.importPackage(from: lease.url) }
        cancelledImport.cancel()
        await assertThrows({ try await cancelledImport.value }) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertEqual(try totalObjectCount(in: target.container.mainContext), 0)
        XCTAssertEqual(try originalFiles(at: target.mediaStore.rootURL), [])
        XCTAssertEqual(try regularFiles(at: fixture.root.appendingPathComponent("Workspace-CancelledImport")), [])
    }

    func testStartupReconciliationQuarantinesCrashWindowImportOriginals() throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let target = try fixture.makeEmptyStore(named: "CrashWindow")
        let id = UUID()
        let idString = id.uuidString.lowercased()
        let relativePath = "Media/Originals/\(idString.prefix(2))/\(idString).png"
        let installedURL = try target.mediaStore.fileURL(for: relativePath)
        try FileManager.default.createDirectory(
            at: installedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fixture.imageData.write(to: installedURL)

        let report = try target.mediaStore.reconcile(referencedOriginalPaths: [])

        XCTAssertEqual(try originalFiles(at: target.mediaStore.rootURL), [])
        XCTAssertEqual(report.recoveryFilePaths.count, 1)
        XCTAssertEqual(try regularFiles(at: target.mediaStore.rootURL.appendingPathComponent("Recovery")).count, 1)
        XCTAssertEqual(try totalObjectCount(in: target.container.mainContext), 0)
    }

    func testExportFailureCleansAssemblyAndLogsAreRedacted() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let logs = LogRecorder()
        let store = try fixture.makePopulatedStore(log: { logs.values.append($0) })
        let image = try XCTUnwrap(store.container.mainContext.fetch(FetchDescriptor<ImageMetadata>()).first)
        try store.mediaStore.removeOriginal(at: image.relativePath)

        await assertThrows({ try await store.service.exportPackage() })
        let workspace = fixture.root.appendingPathComponent("Workspace-Source")
        XCTAssertEqual(try regularFiles(at: workspace), [])
        let joined = logs.values.joined(separator: "|")
        XCTAssertFalse(joined.contains(TransferTestFixture.secretBody))
        XCTAssertFalse(joined.contains(fixture.root.path))
        XCTAssertFalse(joined.contains(fixture.imageData.base64EncodedString()))
    }
}

@MainActor
private final class LogRecorder {
    var values: [String] = []
}

@MainActor
private func assertThrows<T>(
    _ operation: () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    verify: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await operation()
        XCTFail("Expected operation to throw", file: file, line: line)
    } catch {
        verify(error)
    }
}

@MainActor
private struct TransferStore {
    let container: ModelContainer
    let mediaStore: MediaStore
    let service: ImportExportService
    let storeURL: URL
    let expectedCounts: [String: Int]
    let expectedIDs: [String: Set<UUID>]
}

private func makeTransferData(
    habits: [HabitTransfer] = [],
    habitLogs: [HabitLogTransfer] = [],
    weightRecords: [WeightRecordTransfer] = [],
    weeklyReviews: [WeeklyReviewTransfer] = [],
    habitPlanRevisions: [HabitPlanRevisionTransfer] = [],
    habitLifecycleEvents: [HabitLifecycleEventTransfer] = []
) -> TransferData {
    TransferData(
        entries: [],
        images: [],
        tags: [],
        links: [],
        habits: habits,
        habitLogs: habitLogs,
        goals: [],
        goalEvents: [],
        weightRecords: weightRecords,
        weeklyReviews: weeklyReviews,
        habitPlanRevisions: habitPlanRevisions,
        habitLifecycleEvents: habitLifecycleEvents
    )
}

private func makeManifest(
    schemaVersion: Int,
    data: TransferData
) -> ExportManifest {
    ExportManifest(
        formatIdentifier: ExportManifest.formatIdentifier,
        packageSchemaVersion: schemaVersion,
        appVersion: "1.0",
        appBuild: "1",
        exportID: UUID(),
        exportedAt: Date(timeIntervalSince1970: 2_000),
        objectCounts: data.objectCounts(forPackageSchemaVersion: schemaVersion),
        dataFile: ExportFileRecord(path: "data.json", byteCount: 0, sha256: ""),
        mediaFiles: []
    )
}

@MainActor
private final class TransferTestFixture {
    static let secretBody = "SECRET-BODY-749ac"

    let root: URL
    let imageData: Data

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PGOS-S9-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        imageData = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format).pngData {
            UIColor.purple.setFill()
            $0.cgContext.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    func makePopulatedStore(
        onDisk: Bool = false,
        log: @escaping (String) -> Void = { _ in }
    ) throws -> TransferStore {
        let store = try makeEmptyStore(named: "Source", onDisk: onDisk, log: log)
        let context = store.container.mainContext
        let mediaSourceURL = root.appendingPathComponent("secret-source.png")
        try imageData.write(to: mediaSourceURL)
        let media = try store.mediaStore.storeOriginal(MediaSource(
            url: mediaSourceURL,
            originalFilename: "private-memory.png",
            contentType: "image/png"
        ))
        let base = Date(timeIntervalSince1970: 1_000)
        let image = ImageMetadata(
            id: media.id,
            relativePath: media.relativePath,
            originalFilename: "private-memory.png",
            contentType: "image/png",
            byteCount: media.byteCount,
            pixelWidth: media.pixelWidth,
            pixelHeight: media.pixelHeight,
            checksum: media.checksum,
            createdAt: base
        )
        let entry = Entry(
            status: .organized,
            title: "Private title",
            body: Self.secretBody,
            createdAt: base,
            images: [image]
        )
        image.entry = entry
        let review = Entry(
            kind: .review,
            status: .organized,
            body: "Weekly reflection",
            createdAt: Date(timeIntervalSince1970: 2_000),
            periodStart: Date(timeIntervalSince1970: 500),
            periodEnd: Date(timeIntervalSince1970: 1_500)
        )
        let tag = Tag(displayName: "Health", normalizedName: "health", createdAt: base)
        let habit = Habit(name: "Walk", normalizedName: "walk", createdAt: base)
        let goal = Goal(kind: .flag, title: "Feel stronger", normalizedTitle: "feel stronger", createdAt: base)
        let log = HabitLog(
            habitID: habit.id,
            occurredAt: Date(timeIntervalSince1970: 1_100),
            isCompleted: true,
            quantity: 2,
            unit: "km",
            result: "steady",
            linkedEntryID: entry.id,
            createdAt: Date(timeIntervalSince1970: 1_100)
        )
        let logDayMetadata = HabitLogDayMetadata(
            habitLogID: log.id,
            localDayIdentifier: HabitLocalDay(date: Date(timeIntervalSince1970: 1_100)).description,
            localTimeZoneIdentifier: TimeZone.current.identifier,
            provenance: .capturedAtWrite
        )
        let plan = HabitPlanRevision(
            habitID: habit.id,
            effectiveLocalDay: HabitLocalDay(date: base).description,
            plan: HabitPlan(recordingMode: .oncePerDay, period: .week, goal: .count, targetCount: 3, weekdays: []),
            trustCoverageStartLocalDay: HabitLocalDay(date: base).description,
            createdAt: base
        )
        let habitEvent = HabitLifecycleEvent(
            habitID: habit.id,
            kind: .migrationBaseline,
            occurredLocalDay: HabitLocalDay(date: base).description,
            occurredAt: base,
            knownStatus: .active
        )
        let event = GoalLifecycleEvent(
            goalID: goal.id,
            kind: .created,
            occurredAt: base,
            createdAt: base
        )
        let weightRecord = WeightRecord(
            weightKilograms: 72.4,
            recordedAt: Date(timeIntervalSince1970: 1_200),
            createdAt: base
        )
        let weeklyReview = WeeklyReview(
            weekIdentifier: "1970-W01",
            periodStart: Date(timeIntervalSince1970: 0),
            periodEnd: Date(timeIntervalSince1970: 6 * 86_400),
            rememberedText: "A meaningful moment",
            nextStepText: "Continue",
            focusText: "One thing",
            isCompleted: true,
            createdAt: base
        )
        let links = [
            ObjectLink(sourceType: .entry, sourceID: entry.id, targetType: .tag, targetID: tag.id,
                       kind: .entryUsesTag, createdAt: base),
            ObjectLink(sourceType: .entry, sourceID: entry.id, targetType: .habit, targetID: habit.id,
                       kind: .entryRelatesHabit, createdAt: base),
            ObjectLink(sourceType: .habit, sourceID: habit.id, targetType: .goal, targetID: goal.id,
                       kind: .habitSupportsGoal, createdAt: base),
            ObjectLink(sourceType: .entry, sourceID: review.id, targetType: .entry, targetID: entry.id,
                       kind: .reviewsEntry, createdAt: base),
            ObjectLink(sourceType: .entry, sourceID: review.id, targetType: .goal, targetID: goal.id,
                       kind: .reviewsGoal, createdAt: base)
        ]
        [entry, review].forEach(context.insert)
        context.insert(tag)
        context.insert(habit)
        context.insert(goal)
        context.insert(log)
        context.insert(logDayMetadata)
        context.insert(plan)
        context.insert(habitEvent)
        context.insert(event)
        context.insert(weightRecord)
        context.insert(weeklyReview)
        links.forEach(context.insert)
        try context.save()
        try LinkIntegrityService.validate(context: context)
        return TransferStore(
            container: store.container,
            mediaStore: store.mediaStore,
            service: store.service,
            storeURL: store.storeURL,
            expectedCounts: [
                "entries": 2, "images": 1, "tags": 1, "links": 5,
                "habits": 1, "habitLogs": 1, "goals": 1, "goalEvents": 1,
                "weightRecords": 1, "weeklyReviews": 1,
                "habitPlanRevisions": 1, "habitLifecycleEvents": 1,
                "entryPins": 0, "entryFollowUps": 0, "entrySources": 0,
                "todoTasks": 0, "todoEvents": 0, "todoLists": 0, "todoSeries": 0, "todoSources": 0,
                "importantDays": 0, "importantDayEntryLinks": 0, "importantDayTodoLinks": 0, "importantDayCovers": 0, "sleepRecords": 0, "sleepGoals": 0, "captureReceipts": 0, "investmentParticipants": 0, "investmentActivities": 0, "investmentSessions": 0, "investmentOperations": 0,
                "todoSeriesPreferences": 0, "todoReminderIntents": 0, "bodyReferenceSettings": 0
            ],
            expectedIDs: try ids(in: context)
        )
    }

    func makeEmptyStore(
        named name: String,
        onDisk: Bool = false,
        limits: ZIPImportLimits = .production,
        log: @escaping (String) -> Void = { _ in },
        publicationCheckpoint: ((ImportPublicationCheckpoint) throws -> Void)? = nil
    ) throws -> TransferStore {
        let storeURL = root.appendingPathComponent("\(name).sqlite")
        let container = try onDisk
            ? PersistenceContainerFactory.makeOnDisk(at: storeURL)
            : PersistenceContainerFactory.makeInMemory()
        let mediaRoot = root.appendingPathComponent("Media-\(name)", isDirectory: true)
        let mediaStore = MediaStore(rootURL: mediaRoot, availableCapacity: { .max })
        let service = ImportExportService(
            context: container.mainContext,
            mediaStore: mediaStore,
            workspaceRoot: root.appendingPathComponent("Workspace-\(name)"),
            limits: limits,
            availableCapacity: { .max },
            now: { Date(timeIntervalSince1970: 8_000) },
            appVersion: { ("1.0", "1") },
            log: log,
            publicationCheckpoint: publicationCheckpoint
        )
        return TransferStore(
            container: container,
            mediaStore: mediaStore,
            service: service,
            storeURL: storeURL,
            expectedCounts: [:],
            expectedIDs: [:]
        )
    }

    func remove() {
        // The fixture owns live SwiftData contexts. Keep its unique synthetic disk root
        // for cleanup after the test host exits, rather than unlinking open SQLite files.
    }
}

@MainActor
private func ids(in context: ModelContext) throws -> [String: Set<UUID>] {
    [
        "entries": Set(try context.fetch(FetchDescriptor<Entry>()).map(\.id)),
        "images": Set(try context.fetch(FetchDescriptor<ImageMetadata>()).map(\.id)),
        "tags": Set(try context.fetch(FetchDescriptor<Tag>()).map(\.id)),
        "links": Set(try context.fetch(FetchDescriptor<ObjectLink>()).map(\.id)),
        "habits": Set(try context.fetch(FetchDescriptor<Habit>()).map(\.id)),
        "habitLogs": Set(try context.fetch(FetchDescriptor<HabitLog>()).map(\.id)),
        "goals": Set(try context.fetch(FetchDescriptor<Goal>()).map(\.id)),
        "goalEvents": Set(try context.fetch(FetchDescriptor<GoalLifecycleEvent>()).map(\.id)),
        "weightRecords": Set(try context.fetch(FetchDescriptor<WeightRecord>()).map(\.id)),
        "weeklyReviews": Set(try context.fetch(FetchDescriptor<WeeklyReview>()).map(\.id)),
        "habitPlanRevisions": Set(try context.fetch(FetchDescriptor<HabitPlanRevision>()).map(\.id)),
        "habitLifecycleEvents": Set(try context.fetch(FetchDescriptor<HabitLifecycleEvent>()).map(\.id)),
        "entryPins": Set(try context.fetch(FetchDescriptor<EntryPin>()).map(\.id)),
        "entryFollowUps": Set(try context.fetch(FetchDescriptor<EntryFollowUp>()).map(\.id)),
        "todoTasks": Set(try context.fetch(FetchDescriptor<TodoTask>()).map(\.id)),
        "todoEvents": Set(try context.fetch(FetchDescriptor<TodoTaskEvent>()).map(\.id)),
        "todoLists": Set(try context.fetch(FetchDescriptor<TodoList>()).map(\.id)),
        "todoSeries": Set(try context.fetch(FetchDescriptor<TodoSeries>()).map(\.id)),
        "todoSources": Set(try context.fetch(FetchDescriptor<TodoTaskSource>()).map(\.id))
    ]
}

@MainActor
private func totalObjectCount(in context: ModelContext) throws -> Int {
    try ids(in: context).values.reduce(0) { $0 + $1.count }
}

@MainActor
private func deleteAllFixtureData(_ context: ModelContext) throws {
    try context.fetch(FetchDescriptor<TodoTaskSource>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<TodoTaskEvent>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<TodoTask>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<TodoSeries>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<TodoList>()).forEach(context.delete)

    try context.fetch(FetchDescriptor<EntryPin>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<EntryFollowUp>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<ObjectLink>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<HabitLogDayMetadata>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<HabitLog>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<HabitPlanRevision>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<HabitLifecycleEvent>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<GoalLifecycleEvent>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<ImageMetadata>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<Entry>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<Tag>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<Habit>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<Goal>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<WeightRecord>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<WeeklyReview>()).forEach(context.delete)
}

private func originalFiles(at mediaRoot: URL) throws -> [URL] {
    try regularFiles(at: mediaRoot.appendingPathComponent("Media/Originals"))
}

private func regularFiles(at root: URL) throws -> [URL] {
    guard FileManager.default.fileExists(atPath: root.path),
          let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey]
          ) else { return [] }
    return try (enumerator.allObjects as? [URL] ?? []).filter {
        try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
    }.sorted { $0.path < $1.path }
}

private func extractedDataJSON(from archive: URL, under root: URL) throws -> Data {
    let reader = try ZIPArchiveReader(archiveURL: archive, availableCapacity: .max)
    try reader.extractAll(to: root)
    return try Data(contentsOf: root.appendingPathComponent("data.json"))
}

private func mutatePackage(
    _ archive: URL,
    under root: URL,
    mutation: ((URL, ExportManifest, TransferData) throws -> Void)? = nil,
    rewriteJSON: ((ExportManifest, TransferData) throws -> (ExportManifest, TransferData))? = nil,
    afterRewrite: ((URL, ExportManifest, TransferData) throws -> Void)? = nil,
    refreshManifest: Bool = true
) throws -> URL {
    let extracted = root.appendingPathComponent("Extracted", isDirectory: true)
    let reader = try ZIPArchiveReader(archiveURL: archive, availableCapacity: .max)
    try reader.extractAll(to: extracted)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let manifestURL = extracted.appendingPathComponent("manifest.json")
    let dataURL = extracted.appendingPathComponent("data.json")
    var manifest = try decoder.decode(ExportManifest.self, from: Data(contentsOf: manifestURL))
    var data = try decoder.decode(TransferData.self, from: Data(contentsOf: dataURL))
    try mutation?(extracted, manifest, data)
    if let rewriteJSON {
        (manifest, data) = try rewriteJSON(manifest, data)
        var encodedData = try encoder.encode(data)
        // Preserve each actual legacy wire format. Never strip a nonempty newer payload.
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedData) as? [String: Any])
        if manifest.packageSchemaVersion < 11 && data.todoSeriesPreferences.isEmpty && data.todoReminderIntents.isEmpty && data.bodyReferenceSettings.isEmpty {
            for key in ["todoSeriesPreferences","todoReminderIntents","bodyReferenceSettings"] {payload.removeValue(forKey:key)}
        }
        if manifest.packageSchemaVersion < 7 && data.todoTasks.isEmpty && data.todoEvents.isEmpty && data.todoLists.isEmpty && data.todoSeries.isEmpty && data.todoSources.isEmpty {
            for key in ["todoTasks", "todoEvents", "todoLists", "todoSeries", "todoSources"] { payload.removeValue(forKey: key) }
        }
        if manifest.packageSchemaVersion < 8 && data.importantDays.isEmpty && data.importantDayEntryLinks.isEmpty && data.importantDayTodoLinks.isEmpty && data.importantDayCovers.isEmpty {
            for key in ["importantDays", "importantDayEntryLinks", "importantDayTodoLinks", "importantDayCovers"] { payload.removeValue(forKey: key) }
        }
        if manifest.packageSchemaVersion < 10 && data.investmentParticipants.isEmpty && data.investmentActivities.isEmpty && data.investmentSessions.isEmpty && data.investmentOperations.isEmpty && data.captureReceipts.isEmpty {
            for key in ["captureReceipts", "investmentParticipants", "investmentActivities", "investmentSessions", "investmentOperations"] { payload.removeValue(forKey: key) }
        }
        if manifest.packageSchemaVersion < 9 && data.sleepRecords.isEmpty && data.sleepGoals.isEmpty {
            for key in ["captureReceipts", "investmentParticipants", "investmentActivities", "investmentSessions", "investmentOperations", "sleepRecords", "sleepGoals"] { payload.removeValue(forKey: key) }
        }
        encodedData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
        try encodedData.write(to: dataURL)
        if refreshManifest {
            manifest = ExportManifest(
                formatIdentifier: manifest.formatIdentifier,
                packageSchemaVersion: manifest.packageSchemaVersion,
                appVersion: manifest.appVersion,
                appBuild: manifest.appBuild,
                exportID: manifest.exportID,
                exportedAt: manifest.exportedAt,
                objectCounts: data.objectCounts(
                    forPackageSchemaVersion: manifest.packageSchemaVersion
                ),
                dataFile: ExportFileRecord(
                    path: "data.json",
                    byteCount: Int64(encodedData.count),
                    sha256: SHA256.hash(data: encodedData).map { String(format: "%02x", $0) }.joined()
                ),
                mediaFiles: manifest.mediaFiles
            )
        }
        try encoder.encode(manifest).write(to: manifestURL)
    }
    try afterRewrite?(extracted, manifest, data)
    let output = root.appendingPathComponent("mutated.zip")
    let sources = try regularFiles(at: extracted).map { file -> ZIPSource in
        let prefix = extracted.standardizedFileURL.path + "/"
        return ZIPSource(path: String(file.standardizedFileURL.path.dropFirst(prefix.count)), fileURL: file)
    }
    try ZIPArchiveWriter.write(sources: sources, to: output)
    return output
}

private func fileSize(_ url: URL) throws -> Int64 {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.size] as? NSNumber)?.int64Value ?? 0
}

private func patchCentralDirectory(
    at url: URL,
    patch: (inout Data, Int) -> Void
) throws {
    var data = try Data(contentsOf: url)
    let signature = Data([0x50, 0x4b, 0x01, 0x02])
    guard let range = data.range(of: signature) else { throw ZIPArchiveError.malformedArchive }
    patch(&data, range.lowerBound)
    try data.write(to: url)
}

private func replaceASCII(_ source: String, with replacement: String, in url: URL) throws {
    precondition(source.utf8.count == replacement.utf8.count)
    var data = try Data(contentsOf: url)
    let sourceData = Data(source.utf8)
    let replacementData = Data(replacement.utf8)
    var searchStart = data.startIndex
    while searchStart < data.endIndex,
          let range = data.range(of: sourceData, in: searchStart..<data.endIndex) {
        data.replaceSubrange(range, with: replacementData)
        searchStart = range.lowerBound + replacementData.count
    }
    try data.write(to: url)
}

private func writeUInt32(_ value: UInt32, to data: inout Data, at offset: Int) {
    data[offset] = UInt8(value & 0xff)
    data[offset + 1] = UInt8((value >> 8) & 0xff)
    data[offset + 2] = UInt8((value >> 16) & 0xff)
    data[offset + 3] = UInt8((value >> 24) & 0xff)
}

extension ImportExportRecoveryTests {
    func testBuild9V5ContinuationRoundTripAndLegacyRejection() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let context = source.container.mainContext
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<Entry>()).first)
        let service = EntryContinuationService(context: context, now: { Date(timeIntervalSince1970: 1_730_000_000) })
        try service.setPinned(true, entryID: entry.id)
        let thought = try service.add(entryID: entry.id, body: "后续认识\n第二行")
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        let target = try fixture.makeEmptyStore(named: "V5Target", onDisk: true)
        let preview = try await target.service.previewPackage(from: lease.url)
        XCTAssertEqual(preview.objectCounts["entryFollowUps"], 1)
        XCTAssertEqual(try totalObjectCount(in: target.container.mainContext), 0)
        let result = try await target.service.importPackage(from: lease.url)
        XCTAssertEqual(result.objectCounts["entryPins"], 1)
        XCTAssertEqual(result.objectCounts["entryFollowUps"], 1)
        let imported = try XCTUnwrap(target.container.mainContext.fetch(FetchDescriptor<EntryFollowUp>()).first)
        XCTAssertEqual(imported.id, thought.id)
        XCTAssertEqual(imported.entryID, thought.entryID)
        XCTAssertEqual(imported.body, thought.body)
        XCTAssertEqual(imported.createdAt, thought.createdAt)
        XCTAssertEqual(imported.updatedAt, thought.updatedAt)
        XCTAssertEqual(try ids(in: target.container.mainContext), try ids(in: context))
        let failing = try fixture.makeEmptyStore(named: "V5Rollback", publicationCheckpoint: { checkpoint in
            if checkpoint == .beforeSave { throw TransferPackageError.interrupted }
        })
        do { _ = try await failing.service.importPackage(from: lease.url); XCTFail("Injected save must fail") }
        catch { XCTAssertEqual(try totalObjectCount(in: failing.container.mainContext), 0) }
        let orphan = try fixture.makeEmptyStore(named: "V5Orphan")
        orphan.container.mainContext.insert(EntryPin(entryID: UUID(), pinnedAt: Date()))
        try orphan.container.mainContext.save()
        do { _ = try await orphan.service.importPackage(from: lease.url); XCTFail("Auxiliary records make the store nonempty") }
        catch { XCTAssertEqual(error as? TransferPackageError, .targetNotEmpty) }
        for version in 1...4 {
            let package = try mutatePackage(lease.url, under: fixture.root.appendingPathComponent("OldClaim\(version)"), rewriteJSON: { manifest, data in
                (ExportManifest(formatIdentifier: manifest.formatIdentifier, packageSchemaVersion: version,
                                appVersion: manifest.appVersion, appBuild: manifest.appBuild,
                                exportID: manifest.exportID, exportedAt: manifest.exportedAt,
                                objectCounts: data.objectCounts(forPackageSchemaVersion: version),
                                dataFile: manifest.dataFile, mediaFiles: manifest.mediaFiles), data)
            })
            let empty = try fixture.makeEmptyStore(named: "Rejected\(version)")
            do {
                _ = try await empty.service.importPackage(from: package)
                XCTFail("Old format must reject new payload")
            } catch { XCTAssertEqual(try totalObjectCount(in: empty.container.mainContext), 0) }
        }
    }

    func testBuild9InvalidContinuationPayloadsRejectedBeforeWriting() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        for variant in 0..<6 {
            let package = try mutatePackage(lease.url, under: fixture.root.appendingPathComponent("Invalid\(variant)"), rewriteJSON: { manifest, data in
                let id = data.entries[0].id
                let date = Date(timeIntervalSince1970: 1000)
                let pin = EntryPinTransfer(id: UUID(), entryID: variant == 0 ? UUID() : id, pinnedAt: date)
                let thought = EntryFollowUpTransfer(id: UUID(), entryID: variant == 1 ? UUID() : id,
                                                   body: variant == 2 ? " \n" : "想法", createdAt: date,
                                                   updatedAt: variant == 3 ? date.addingTimeInterval(-1) : date)
                let changed = TransferData(entries: data.entries, images: data.images, tags: data.tags,
                    links: data.links, habits: data.habits, habitLogs: data.habitLogs, goals: data.goals,
                    goalEvents: data.goalEvents, weightRecords: data.weightRecords, weeklyReviews: data.weeklyReviews,
                    habitPlanRevisions: data.habitPlanRevisions, habitLifecycleEvents: data.habitLifecycleEvents,
                    entryPins: variant == 5 ? [pin, EntryPinTransfer(id: UUID(), entryID: pin.entryID, pinnedAt: pin.pinnedAt)] : [pin], entryFollowUps: variant == 4 ? [thought, thought] : [thought])
                return (ExportManifest(formatIdentifier: manifest.formatIdentifier, packageSchemaVersion: 5,
                    appVersion: manifest.appVersion, appBuild: manifest.appBuild, exportID: manifest.exportID,
                    exportedAt: manifest.exportedAt, objectCounts: changed.objectCounts(forPackageSchemaVersion: 5),
                    dataFile: manifest.dataFile, mediaFiles: manifest.mediaFiles), changed)
            })
            let target = try fixture.makeEmptyStore(named: "InvalidTarget\(variant)")
            do { _ = try await target.service.importPackage(from: package); XCTFail("Invalid package accepted") }
            catch { XCTAssertEqual(try totalObjectCount(in: target.container.mainContext), 0) }
        }
    }
}

extension ImportExportRecoveryTests {
    func testBuild9V5RequiresNewArraysWhileV4AllowsThemMissing() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        for version in [4, 5] {
            let package = try mutatePackage(lease.url, under: fixture.root.appendingPathComponent("MissingArrays\(version)"), mutation: { root, manifest, data in
                let dataURL = root.appendingPathComponent("data.json")
                var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: dataURL)) as? [String: Any])
                payload.removeValue(forKey: "entryPins")
                payload.removeValue(forKey: "entryFollowUps")
                // V4/V5 fixtures must preserve their historical wire format after newer exporters add arrays.
                for key in ["todoSeriesPreferences", "todoReminderIntents", "bodyReferenceSettings", "captureReceipts", "investmentParticipants", "investmentActivities", "investmentSessions", "investmentOperations", "sleepRecords", "sleepGoals", "todoTasks", "todoEvents", "todoLists", "todoSeries", "todoSources", "importantDays", "importantDayEntryLinks", "importantDayTodoLinks", "importantDayCovers"] { payload.removeValue(forKey: key) }
                let bytes = try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys)
                try bytes.write(to: dataURL)
                let changedManifest = ExportManifest(formatIdentifier: manifest.formatIdentifier, packageSchemaVersion: version,
                    appVersion: manifest.appVersion, appBuild: manifest.appBuild, exportID: manifest.exportID,
                    exportedAt: manifest.exportedAt, objectCounts: data.objectCounts(forPackageSchemaVersion: version),
                    dataFile: ExportFileRecord(path: "data.json", byteCount: Int64(bytes.count),
                        sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()), mediaFiles: manifest.mediaFiles)
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .secondsSince1970
                try encoder.encode(changedManifest).write(to: root.appendingPathComponent("manifest.json"))
            })
            let target = try fixture.makeEmptyStore(named: "MissingArraysTarget\(version)")
            if version == 4 {
                _ = try await target.service.importPackage(from: package)
                XCTAssertEqual(try target.container.mainContext.fetchCount(FetchDescriptor<EntryFollowUp>()), 0)
                XCTAssertEqual(try target.container.mainContext.fetchCount(FetchDescriptor<Entry>()), 2)
            } else {
                do { _ = try await target.service.importPackage(from: package); XCTFail("V5 missing payload accepted") }
                catch { XCTAssertEqual(error as? TransferPackageError, .corruptData) }
                XCTAssertEqual(try totalObjectCount(in: target.container.mainContext), 0)
            }
        }
    }
}

extension ImportExportRecoveryTests {
    func testPR6SecurityScopeBoundaryPairsSuccessFailureAndCancellation() async throws {
        enum Expected: Error { case read }
        let url = URL(fileURLWithPath: "/synthetic-selected-backup.zip")
        for outcome in ["success", "error", "cancel"] {
            var events: [String] = []
            let task = Task { @MainActor in
                try await SecurityScopedFileAccess.perform(to: url, start: { selected in
                    XCTAssertEqual(selected, url)
                    events.append("start")
                    return true
                }, stop: { _ in events.append("stop") }) {
                    events.append("read")
                    await Task.yield()
                    XCTAssertEqual(events, ["start", "read"])
                    if outcome == "error" { throw Expected.read }
                    try Task.checkCancellation()
                    events.append("finished")
                }
            }
            if outcome == "cancel" { task.cancel() }
            do {
                try await task.value
                XCTAssertEqual(outcome, "success")
            } catch {
                if outcome == "cancel" { XCTAssertTrue(error is CancellationError) }
                else { XCTAssertTrue(error is Expected) }
            }
            XCTAssertEqual(events, outcome == "success" ? ["start", "read", "finished", "stop"] : ["start", "read", "stop"])
        }
        var events: [String] = []
        await SecurityScopedFileAccess.perform(to: url, start: { _ in events.append("start"); return false },
                                               stop: { _ in events.append("stop") }) {
            events.append("sandbox read")
        }
        XCTAssertEqual(events, ["start", "sandbox read"])
    }

    func testPR6RollbackClockEditSurvivesV5RestoreAndReopen() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makeEmptyStore(named: "ClockSource", onDisk: true)
        let context = source.container.mainContext
        let created = Date(timeIntervalSince1970: 1_730_000_000)
        let entry = Entry(body: "Original remains untouched", createdAt: created)
        context.insert(entry)
        try context.save()
        var now = created
        let service = EntryContinuationService(context: context, now: { now })
        let thought = try service.add(entryID: entry.id, body: "Initial")
        for (offset, text, expectedOffset) in [(0.0, "Equal clock", 1.0), (-100, "Backwards", 1), (60, "Forward", 60), (30, "Back before previous edit", 60)] {
            now = created.addingTimeInterval(offset)
            try service.edit(thought, body: text)
            XCTAssertEqual(thought.updatedAt, created.addingTimeInterval(expectedOffset))
            XCTAssertEqual(thought.createdAt, created)
            XCTAssertGreaterThan(thought.updatedAt, thought.createdAt)
        }
        now = created.addingTimeInterval(90)
        try service.edit(thought, body: thought.body)
        XCTAssertEqual(thought.updatedAt, created.addingTimeInterval(60))
        // A first edit under a backwards clock must retain an Edited marker through encoding.
        let equalTime = try service.add(entryID: entry.id, body: "Another")
        now = created
        try service.edit(equalTime, body: "Another edited")
        XCTAssertEqual(equalTime.updatedAt, equalTime.createdAt.addingTimeInterval(1))
        let parentTimes = [entry.createdAt, entry.occurredAt, entry.updatedAt]
        XCTAssertEqual(parentTimes, [created, created, created])
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        let targetURL = fixture.root.appendingPathComponent("ClockTarget.sqlite")
        do {
            let target = try fixture.makeEmptyStore(named: "ClockTarget", onDisk: true)
            _ = try await target.service.importPackage(from: lease.url)
        }
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: targetURL)
        let restoredParent = try XCTUnwrap(EntryRepository(context: reopened.mainContext).fetch(id: entry.id))
        XCTAssertEqual(restoredParent.body, entry.body)
        XCTAssertEqual([restoredParent.createdAt, restoredParent.occurredAt, restoredParent.updatedAt], parentTimes)
        let restored = try reopened.mainContext.fetch(FetchDescriptor<EntryFollowUp>())
        XCTAssertEqual(restored.count, 2)
        for original in [thought, equalTime] {
            let item = try XCTUnwrap(restored.first { $0.id == original.id })
            XCTAssertEqual(item.body, original.body)
            XCTAssertEqual(item.createdAt, original.createdAt)
            XCTAssertEqual(item.updatedAt, original.updatedAt)
            XCTAssertGreaterThan(item.updatedAt, item.createdAt)
        }
    }
}

@MainActor
extension ImportExportRecoveryTests {
    func testTodoV7RoundTripPreservesOccurrencesEventsListsSourcesAndOriginalMedia() async throws {
        let fixture = try TransferTestFixture(); defer { fixture.remove() }
        let source = try fixture.makePopulatedStore(onDisk: true), context = source.container.mainContext
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<Entry>()).first)
        let service = TodoTaskService(context: context)
        let list = try service.createList(name: "生活")
        let day = TodoDay(date: Date()).description
        let task = try service.create(TodoDraft(title: "买电池 🔋\n原文", notes: "备注", isImportant: true, plannedDay: day,
            deadlineDay: day, remindAt: TodoRecurrence.reminder(day: try TodoRecurrence.reminderDay(occurrence: TodoDay(day)!, offset: -1), minutes: 1200, timeZone: .current), listID: list.id), sourceEntryID: entry.id)
        let originalID = task.id, originalCreated = task.createdAt
        var conversion = TodoDraft(task); conversion.frequency = .monthly
        try service.edit(id: task.id, draft: conversion)
        XCTAssertEqual(task.id, originalID); XCTAssertEqual(task.createdAt, originalCreated)
        try service.transition(id: task.id, to: .completed)
        try service.transition(id: task.id, to: .open)
        try service.transition(id: task.id, to: .completed)
        try TodoIntegrity.validate(context: context)
        let lease: ExportPackageLease
        do { lease = try await source.service.exportPackage() }
        catch { XCTFail("Todo export failed: \(String(reflecting: error))"); throw error }
        defer { lease.cleanup() }
        let target = try fixture.makeEmptyStore(named: "TodoRestored", onDisk: true)
        let importPublished = expectation(forNotification: .todoTasksChanged, object: nil)
        let preview: ImportResult
        do { preview = try await target.service.previewPackage(from: lease.url) }
        catch { XCTFail("Todo preview failed: \(String(reflecting: error))"); throw error }
        XCTAssertEqual(preview.objectCounts["todoTasks"], 2)
        XCTAssertEqual(try totalObjectCount(in: target.container.mainContext), 0)
        do { _ = try await target.service.importPackage(from: lease.url) }
        catch { XCTFail("Todo import failed: \(String(reflecting: error))"); throw error }
        XCTAssertEqual(try ids(in: context), try ids(in: target.container.mainContext))
        await fulfillment(of: [importPublished], timeout: 2)
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: target.storeURL)
        try TodoIntegrity.validate(context: reopened.mainContext)
        let restored = try TodoTaskService(context: reopened.mainContext).task(id: task.id)
        XCTAssertEqual(restored.title, task.title); XCTAssertEqual(restored.completedAt, task.completedAt)
        XCTAssertEqual(restored.reminderTimeZoneID, task.reminderTimeZoneID)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<TodoSeries>()).first?.reminderDayOffset, -1)
        let reminderClient = TodoNotificationStub(), reminders = TodoReminderCoordinator(client: reminderClient, sleepPreferences:{.init()})
        await reminders.reconcile(context: reopened.mainContext)
        let restoredOpen = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<TodoTask>()).first { $0.state == .open })
        XCTAssertEqual(reminders.status(for: restoredOpen), .scheduled)
        let accepted=try XCTUnwrap(reminderClient.pending.values.first)
        XCTAssertEqual(reminderClient.pending.count,1)
        XCTAssertEqual(accepted.taskID,restoredOpen.id);XCTAssertEqual(accepted.title,restoredOpen.title)
        XCTAssertEqual(accepted.fireAt,restoredOpen.remindAt)
        let device=try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first)
        XCTAssertEqual(accepted.id,TodoIntentScheduling.identifier(device.id))
        XCTAssertEqual(device.taskID,restoredOpen.id);XCTAssertEqual(device.phaseRawValue,"accepted")
        let again = try await target.service.exportPackage(); defer { again.cleanup() }
        let expected = try extractedDataJSON(from: lease.url, under: fixture.root.appendingPathComponent("TodoExpected"))
        let actual = try extractedDataJSON(from: again.url, under: fixture.root.appendingPathComponent("TodoActual"))
        XCTAssertEqual(expected, actual)
        let image = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<ImageMetadata>()).first)
        XCTAssertEqual(try Data(contentsOf: target.mediaStore.fileURL(for: image.relativePath)), fixture.imageData)
    }

    func testTodoOnlyAndListOnlyTargetsRejectImportWithoutErasingData() async throws {
        let fixture = try TransferTestFixture(); defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage(); defer { lease.cleanup() }
        for index in 0..<2 {
            let target = try fixture.makeEmptyStore(named: "TodoOccupied\(index)")
            let service = TodoTaskService(context: target.container.mainContext)
            if index == 0 { _ = try service.create(TodoDraft(title: "保留私人待办")) }
            else { _ = try service.createList(name: "保留清单") }
            let idsBefore = try ids(in: target.container.mainContext)
            do { _ = try await target.service.importPackage(from: lease.url); XCTFail("Must reject a nonempty Todo target") }
            catch { XCTAssertEqual(error as? TransferPackageError, .targetNotEmpty) }
            XCTAssertEqual(try ids(in: target.container.mainContext), idsBefore)
        }
    }

    func testTodoImportSaveInterruptionRollsBackEveryNewEntityAndOriginalMedia() async throws {
        let fixture = try TransferTestFixture(); defer { fixture.remove() }
        let source = try fixture.makePopulatedStore(), context = source.container.mainContext
        let service = TodoTaskService(context: context)
        let list = try service.createList(name: "合成清单")
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<Entry>()).first)
        _ = try service.create(TodoDraft(title: "合成重复", plannedDay: "2026-10-09", listID: list.id, frequency: .weekly), sourceEntryID: entry.id)
        let lease = try await source.service.exportPackage(); defer { lease.cleanup() }
        for cancellation in [false, true] {
            let target = try fixture.makeEmptyStore(named: "TodoInterrupted\(cancellation)", onDisk: true, publicationCheckpoint: { stage in
                if stage == .beforeSave {
                    if cancellation { throw CancellationError() }
                    throw TransferPackageError.interrupted
                }
            })
            do { _ = try await target.service.importPackage(from: lease.url); XCTFail("Injected save must fail") }
            catch {
                if cancellation { XCTAssertTrue(error is CancellationError) }
                else { XCTAssertEqual(error as? TransferPackageError, .interrupted) }
            }
            XCTAssertEqual(try totalObjectCount(in: target.container.mainContext), 0)
            XCTAssertEqual(try originalFiles(at: target.mediaStore.rootURL), [])
            let reopened = try PersistenceContainerFactory.makeOnDisk(at: target.storeURL)
            XCTAssertEqual(try totalObjectCount(in: reopened.mainContext), 0)
        }
    }

    func testTodoCorruptStateDateEventReferenceDuplicateAndSeriesPackagesAreRejected() async throws {
        let fixture = try TransferTestFixture(); defer { fixture.remove() }
        let source = try fixture.makePopulatedStore(), context = source.container.mainContext
        let task = try TodoTaskService(context: context).create(TodoDraft(title: "有效期次", plannedDay: "2026-10-09", frequency: .daily))
        let lease = try await source.service.exportPackage(); defer { lease.cleanup() }
        for scenario in 0..<15 {
            let corrupt = try mutatePackage(lease.url, under: fixture.root.appendingPathComponent("TodoCorrupt\(scenario)"), rewriteJSON: { manifest, data in
                var tasks = data.todoTasks, events = data.todoEvents, series = data.todoSeries
                var sources = data.todoSources
                switch scenario {
                case 0: tasks[0].stateRawValue = "unknown"
                case 1: tasks[0].plannedDay = "2026-02-30"
                case 2: events[0].taskID = UUID()
                case 3: tasks.append(tasks[0])
                case 4: series[0].anchorDay = "bad-anchor"
                case 5: tasks[0].stateRawValue = "completed"; tasks[0].completedAt = Date()
                case 6: tasks[0].listID = UUID()
                case 7: tasks[0].seriesID = UUID()
                case 8: tasks[0].occurrenceKey = "wrong-occurrence"
                case 9: events[0].kindRawValue = TodoEventKind.reopened.rawValue
                case 10: sources = [TodoTaskSourceTransfer(TodoTaskSource(taskID: task.id, entryID: UUID()))]
                case 11: sources = [TodoTaskSourceTransfer(TodoTaskSource(taskID: UUID(), entryID: data.entries[0].id))]
                case 12: tasks[0].revision = Int.max
                case 13: series[0].reminderMinutes = 600; series[0].reminderDayOffset = 367
                default: series[0].reminderDayOffset = -1
                }
                return (manifest, data.replacingTodos(tasks: tasks, events: events, series: series, sources: sources))
            })
            let target = try fixture.makeEmptyStore(named: "TodoReject\(scenario)")
            do { _ = try await target.service.importPackage(from: corrupt); XCTFail("Corrupt Todo package must be rejected") }
            catch {
                XCTAssertEqual(error as? TransferPackageError, .invalidObject("todo integrity"))
                XCTAssertEqual(try totalObjectCount(in: target.container.mainContext), 0)
            }
        }
        XCTAssertEqual(try TodoTaskService(context: context).task(id: task.id).state, .open)
    }

    func testLegacyV1ThroughV6PackagesImportAndFrozenBuild12V6RestoresOriginalFacts() async throws {
        let fixture = try TransferTestFixture(); defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage(); defer { lease.cleanup() }
        for version in 1...6 {
            let legacy = try mutatePackage(lease.url, under: fixture.root.appendingPathComponent("LegalLegacy\(version)"), rewriteJSON: { manifest, data in
                let legacyData = TransferData(entries: data.entries, images: data.images, tags: data.tags, links: data.links,
                    habits: data.habits, habitLogs: data.habitLogs.map { log in
                        HabitLogTransfer(id: log.id, habitID: log.habitID, occurredAt: log.occurredAt,
                            isCompleted: log.isCompleted, quantity: log.quantity, unit: log.unit, result: log.result,
                            linkedEntryID: log.linkedEntryID, createdAt: log.createdAt,
                            localDayIdentifier: version >= 4 ? log.localDayIdentifier : nil,
                            localTimeZoneIdentifier: version >= 4 ? log.localTimeZoneIdentifier : nil,
                            localDayProvenance: version >= 4 ? log.localDayProvenance : nil)
                    }, goals: data.goals, goalEvents: data.goalEvents,
                    weightRecords: version >= 2 ? data.weightRecords : [], weeklyReviews: version >= 3 ? data.weeklyReviews : [],
                    habitPlanRevisions: version >= 4 ? data.habitPlanRevisions : [],
                    habitLifecycleEvents: version >= 4 ? data.habitLifecycleEvents : [],
                    entrySources: version >= 6 ? data.entrySources : [], entryPins: version >= 5 ? data.entryPins : [],
                    entryFollowUps: version >= 5 ? data.entryFollowUps : [])
                return (ExportManifest(formatIdentifier: manifest.formatIdentifier, packageSchemaVersion: version,
                    appVersion: manifest.appVersion, appBuild: manifest.appBuild, exportID: manifest.exportID,
                    exportedAt: manifest.exportedAt, objectCounts: legacyData.objectCounts(forPackageSchemaVersion: version),
                    dataFile: manifest.dataFile, mediaFiles: manifest.mediaFiles), legacyData)
            }, afterRewrite: { root, manifest, _ in
                // Remove features absent in the actual older wire format, while retaining V5/V6 required empty arrays.
                let url = root.appendingPathComponent("data.json")
                var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
                if version < 2 { payload.removeValue(forKey: "weightRecords") }
                if version < 3 { payload.removeValue(forKey: "weeklyReviews") }
                if version < 4 { payload.removeValue(forKey: "habitPlanRevisions"); payload.removeValue(forKey: "habitLifecycleEvents") }
                if version < 5 { payload.removeValue(forKey: "entryPins"); payload.removeValue(forKey: "entryFollowUps") }
                if version < 6 { payload.removeValue(forKey: "entrySources") }
                let bytes = try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys); try bytes.write(to: url)
                let changed = ExportManifest(formatIdentifier: manifest.formatIdentifier, packageSchemaVersion: version,
                    appVersion: manifest.appVersion, appBuild: manifest.appBuild, exportID: manifest.exportID,
                    exportedAt: manifest.exportedAt, objectCounts: manifest.objectCounts,
                    dataFile: ExportFileRecord(path: "data.json", byteCount: Int64(bytes.count),
                        sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()), mediaFiles: manifest.mediaFiles)
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
                try encoder.encode(changed).write(to: root.appendingPathComponent("manifest.json"))
            })
            let target = try fixture.makeEmptyStore(named: "LegalTarget\(version)", onDisk: true)
            _ = try await target.service.importPackage(from: legacy)
            let context = target.container.mainContext
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()), 2)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTask>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<WeightRecord>()), version >= 2 ? 1 : 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<WeeklyReview>()), version >= 3 ? 1 : 0)
            XCTAssertEqual(try Data(contentsOf: target.mediaStore.fileURL(for: try XCTUnwrap(context.fetch(FetchDescriptor<ImageMetadata>()).first).relativePath)), fixture.imageData)
        }
        let frozen = try XCTUnwrap(Bundle(for: TodoFoundationTests.self).url(forResource: "Build12V10Fixture", withExtension: nil))
        let target = try fixture.makeEmptyStore(named: "FrozenV6Restored", onDisk: true)
        _ = try await target.service.importPackage(from: frozen.appendingPathComponent("expected-v6.zip"))
        let again = try await target.service.exportPackage(); defer { again.cleanup() }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let expected = try decoder.decode(TransferData.self, from: extractedDataJSON(from: frozen.appendingPathComponent("expected-v6.zip"), under: fixture.root.appendingPathComponent("FrozenExpected")))
        let actual = try decoder.decode(TransferData.self, from: extractedDataJSON(from: again.url, under: fixture.root.appendingPathComponent("FrozenActual")))
        XCTAssertEqual(actual, expected)
    }

    func testV8RequiresAllDayArraysAndV7RejectsEvenEmptyNewKeysWithLegalLegacyPositiveControl() async throws {
        let fixture = try TransferTestFixture(); defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage(); defer { lease.cleanup() }
        let keys = ["importantDays", "importantDayEntryLinks", "importantDayTodoLinks", "importantDayCovers"]
        for scenario in 0..<10 {
            let package = try mutatePackage(lease.url, under: fixture.root.appendingPathComponent("DayWire\(scenario)"), mutation: { root, manifest, data in
                let version = scenario < 8 ? 8 : 7
                let url = root.appendingPathComponent("data.json")
                var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
                for key in ["todoSeriesPreferences", "todoReminderIntents", "bodyReferenceSettings", "captureReceipts", "investmentParticipants", "investmentActivities", "investmentSessions", "investmentOperations", "sleepRecords", "sleepGoals"] { payload.removeValue(forKey: key) }
                if scenario < 4 { payload.removeValue(forKey: keys[scenario]) }
                else if scenario < 8 { payload[keys[scenario - 4]] = NSNull() }
                else if scenario == 9 { for key in keys { payload.removeValue(forKey: key) } }
                let bytes = try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys); try bytes.write(to: url)
                let changed = ExportManifest(formatIdentifier: manifest.formatIdentifier, packageSchemaVersion: version,
                    appVersion: manifest.appVersion, appBuild: manifest.appBuild, exportID: manifest.exportID,
                    exportedAt: manifest.exportedAt, objectCounts: data.objectCounts(forPackageSchemaVersion: version),
                    dataFile: ExportFileRecord(path: "data.json", byteCount: Int64(bytes.count),
                        sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()), mediaFiles: manifest.mediaFiles)
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
                try encoder.encode(changed).write(to: root.appendingPathComponent("manifest.json"))
            })
            let target = try fixture.makeEmptyStore(named: "DayWireTarget\(scenario)")
            if scenario == 9 {
                _ = try await target.service.importPackage(from: package)
                XCTAssertEqual(try target.container.mainContext.fetchCount(FetchDescriptor<Entry>()), 2)
            } else {
                do { _ = try await target.service.importPackage(from: package); XCTFail("Malformed day wire accepted") }
                catch { XCTAssertEqual(error as? TransferPackageError, .corruptData) }
                XCTAssertEqual(try totalObjectCount(in: target.container.mainContext), 0)
            }
        }
    }

    func testV7RequiresTodoArraysAndLegacyClaimsRejectEvenEmptyNewKeys() async throws {
        let fixture = try TransferTestFixture(); defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage(); defer { lease.cleanup() }
        for scenario in 0..<3 {
            let corrupt = try mutatePackage(lease.url, under: fixture.root.appendingPathComponent("TodoWire\(scenario)"), mutation: { root, manifest, data in
                let version = scenario == 2 ? 6 : 7
                let url = root.appendingPathComponent("data.json")
                var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
                for key in ["todoSeriesPreferences", "todoReminderIntents", "bodyReferenceSettings", "captureReceipts", "investmentParticipants", "investmentActivities", "investmentSessions", "investmentOperations", "sleepRecords", "sleepGoals"] { payload.removeValue(forKey: key) }
                for key in ["importantDays", "importantDayEntryLinks", "importantDayTodoLinks", "importantDayCovers"] { payload.removeValue(forKey: key) }
                if scenario == 0 { payload.removeValue(forKey: "todoEvents") }
                if scenario == 1 { payload["todoTasks"] = NSNull() }
                let bytes = try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys); try bytes.write(to: url)
                let changed = ExportManifest(formatIdentifier: manifest.formatIdentifier, packageSchemaVersion: version,
                    appVersion: manifest.appVersion, appBuild: manifest.appBuild, exportID: manifest.exportID,
                    exportedAt: manifest.exportedAt, objectCounts: data.objectCounts(forPackageSchemaVersion: version),
                    dataFile: ExportFileRecord(path: "data.json", byteCount: Int64(bytes.count),
                        sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()), mediaFiles: manifest.mediaFiles)
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
                try encoder.encode(changed).write(to: root.appendingPathComponent("manifest.json"))
            })
            let target = try fixture.makeEmptyStore(named: "TodoWireTarget\(scenario)")
            do { _ = try await target.service.importPackage(from: corrupt); XCTFail("Invalid wire format accepted") }
            catch { XCTAssertEqual(error as? TransferPackageError, .corruptData) }
            XCTAssertEqual(try totalObjectCount(in: target.container.mainContext), 0)
        }
    }

    func testTodoCommittedAfterExportCutoffIsExcludedWithoutLosingCurrentFacts() async throws {
        let fixture = try TransferTestFixture(); defer { fixture.remove() }
        let source = try fixture.makePopulatedStore(onDisk: true), context = source.container.mainContext
        let service = TodoTaskService(context: context)
        let task = try service.create(TodoDraft(title: "截止点之前", plannedDay: "2026-10-09", frequency: .daily))
        let captured = expectation(description: "Frozen Todo export captured")
        let release = DispatchSemaphore(value: 0); defer { release.signal() }
        let exporter = ImportExportService(context: context, mediaStore: source.mediaStore, exportCheckpoint: {
            captured.fulfill()
            guard release.wait(timeout: .now() + 30) == .success else { throw TransferPackageError.interrupted }
        })
        let export = Task { try await exporter.exportPackage() }
        await fulfillment(of: [captured], timeout: 30)
        try service.transition(id: task.id, to: .completed)
        let later = try service.create(TodoDraft(title: "截止点之后"))
        release.signal()
        let lease = try await export.value; defer { lease.cleanup() }
        let target = try fixture.makeEmptyStore(named: "TodoCutoffRestore", onDisk: true)
        _ = try await target.service.importPackage(from: lease.url)
        let restored = TodoTaskService(context: target.container.mainContext)
        XCTAssertEqual(try restored.task(id: task.id).state, .open)
        XCTAssertThrowsError(try restored.task(id: later.id))
        XCTAssertEqual(try target.container.mainContext.fetchCount(FetchDescriptor<TodoTaskEvent>()), 1)
        XCTAssertEqual(try ModelContext(source.container).fetchCount(FetchDescriptor<TodoTask>()), 3)
        XCTAssertEqual(try service.task(id: task.id).state, .completed)
        try TodoIntegrity.validate(context: context)
    }

    func testTodoCommittedDuringImportPreflightPreventsPublicationAndSurvivesReopen() async throws {
        let fixture = try TransferTestFixture(); defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage(); defer { lease.cleanup() }
        let target = try fixture.makeEmptyStore(named: "TodoConcurrentTarget", onDisk: true)
        let service = TodoTaskService(context: target.container.mainContext)
        let taskID = UUID()
        let importer = ImportExportService(context: target.container.mainContext, mediaStore: target.mediaStore,
            availableCapacity: { .max },
            publicationCheckpoint: { stage in
                if stage == .afterPreflight {
                    try MainActor.assumeIsolated { _ = try service.create(TodoDraft(title: "并发保留"), id: taskID) }
                }
            })
        do { _ = try await importer.importPackage(from: lease.url); XCTFail("Concurrent committed Todo makes target nonempty") }
        catch { XCTAssertEqual(error as? TransferPackageError, .targetNotEmpty) }
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: target.storeURL)
        XCTAssertEqual(try TodoTaskService(context: reopened.mainContext).task(id: taskID).title, "并发保留")
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<Entry>()), 0)
        XCTAssertEqual(try originalFiles(at: target.mediaStore.rootURL), [])
        try TodoIntegrity.validate(context: reopened.mainContext)
    }
}

private extension TransferData {
    func replacingTodos(tasks: [TodoTaskTransfer]? = nil, events: [TodoTaskEventTransfer]? = nil, series: [TodoSeriesTransfer]? = nil, sources: [TodoTaskSourceTransfer]? = nil) -> TransferData {
        TransferData(entries: entries, images: images, tags: tags, links: links, habits: habits, habitLogs: habitLogs, goals: goals,
            goalEvents: goalEvents, weightRecords: weightRecords, weeklyReviews: weeklyReviews, habitPlanRevisions: habitPlanRevisions,
            habitLifecycleEvents: habitLifecycleEvents, entrySources: entrySources, entryPins: entryPins, entryFollowUps: entryFollowUps,
            todoTasks: tasks ?? todoTasks, todoEvents: events ?? todoEvents, todoLists: todoLists, todoSeries: series ?? todoSeries, todoSources: sources ?? todoSources)
    }
}

@MainActor extension ImportExportRecoveryTests {
    func testSleepV9MalformedPackagesFailAtomicallyAndV8DayPackageStillRestores() async throws {
        let fixture = try TransferTestFixture(); defer { fixture.remove() }
        let source = try fixture.makePopulatedStore(), clock = Date()
        var draft = SleepDraft(day: ImportantCivilDay(clock).identifier); draft.values.feeling = 4
        _ = try SleepService(context: source.container.mainContext, now: { clock }).save(draft)
        try SleepService(context: source.container.mainContext, now: { clock }).setGoal(cutoffMinute: 1410)
        var day = ImportantDayDraft(); day.title = "Synthetic combined restore"
        _ = try ImportantDayService(context: source.container.mainContext, mediaStore: source.mediaStore).save(day)
        let lease = try await source.service.exportPackage(); defer { lease.cleanup() }
        for scenario in 0..<10 {
            let package = try mutatePackage(lease.url, under: fixture.root.appendingPathComponent("SleepWire\(scenario)"), mutation: { root, manifest, data in
                let url = root.appendingPathComponent("data.json")
                var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
                for key in ["todoSeriesPreferences", "todoReminderIntents", "bodyReferenceSettings", "captureReceipts", "investmentParticipants", "investmentActivities", "investmentSessions", "investmentOperations"] { payload.removeValue(forKey:key) }
                var records = try XCTUnwrap(payload["sleepRecords"] as? [[String: Any]])
                var first = try XCTUnwrap(records.first)
                var values = try XCTUnwrap(first["values"] as? [String: Any])
                var version = 9
                switch scenario {
                case 0: values["feeling"] = 6; first["values"] = values; records[0] = first; payload["sleepRecords"] = records
                case 1: payload["sleepRecords"] = records + records
                case 2: first["id"] = UUID().uuidString; payload["sleepRecords"] = records + [first]
                case 3: values["bedtime"] = ["day": draft.wakeDay, "minute": 10, "precision": 42]; first["values"] = values; payload["sleepRecords"] = [first]
                case 4: first["timeZoneID"] = "Invalid/Zone"; payload["sleepRecords"] = [first]
                case 5: values["feelingFilledAt"] = clock.addingTimeInterval(9999).timeIntervalSinceReferenceDate; first["values"] = values; payload["sleepRecords"] = [first]
                case 6: payload.removeValue(forKey: "sleepRecords")
                case 7: payload["sleepGoals"] = NSNull()
                case 8: version = 8 // Old versions must reject even empty v9-only keys.
                default: version = 8; payload.removeValue(forKey: "sleepRecords"); payload.removeValue(forKey: "sleepGoals")
                }
                let bytes = try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys); try bytes.write(to: url)
                var counts = data.objectCounts(forPackageSchemaVersion: version)
                if scenario == 9 { counts.removeValue(forKey: "sleepRecords"); counts.removeValue(forKey: "sleepGoals") }
                let changed = ExportManifest(formatIdentifier: manifest.formatIdentifier, packageSchemaVersion: version,
                    appVersion: manifest.appVersion, appBuild: manifest.appBuild, exportID: manifest.exportID, exportedAt: manifest.exportedAt,
                    objectCounts: counts, dataFile: ExportFileRecord(path: "data.json", byteCount: Int64(bytes.count),
                        sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()), mediaFiles: manifest.mediaFiles)
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
                try encoder.encode(changed).write(to: root.appendingPathComponent("manifest.json"))
            })
            let target = try fixture.makeEmptyStore(named: "SleepWireTarget\(scenario)")
            if scenario == 9 {
                _ = try await target.service.importPackage(from: package)
                XCTAssertEqual(try target.container.mainContext.fetchCount(FetchDescriptor<ImportantDay>()), 1)
                XCTAssertEqual(try target.container.mainContext.fetchCount(FetchDescriptor<SleepRecord>()), 0)
                XCTAssertEqual(try target.container.mainContext.fetchCount(FetchDescriptor<Entry>()), 2)
            } else {
                do { _ = try await target.service.importPackage(from: package); XCTFail("Invalid sleep package accepted: \(scenario)") }
                catch { XCTAssertFalse(error is CancellationError) }
                XCTAssertEqual(try target.container.mainContext.fetchCount(FetchDescriptor<SleepRecord>()), 0)
                XCTAssertEqual(try target.container.mainContext.fetchCount(FetchDescriptor<ImportantDay>()), 0)
                XCTAssertEqual(try totalObjectCount(in: target.container.mainContext), 0)
            }
        }
    }
}

@MainActor extension ImportExportRecoveryTests {
    func testInvestmentV10MalformedPackagesRejectWithoutChangingTarget() async throws {
        let fixture = try TransferTestFixture(); defer { fixture.remove() }
        let source = try fixture.makePopulatedStore(onDisk:true)
        var clock = InvestmentClock(wall:Date(),uptime:1000,processID:"wire-synthetic")
        let s = InvestmentService(context:source.container.mainContext,clock:{clock}), activity = try s.createActivity(name:"Synthetic wire activity")
        let participant = try XCTUnwrap(ModelContext(source.container).fetch(FetchDescriptor<InvestmentParticipant>()).first).id
        try s.saveManual(id:UUID(),participantID:participant,activityID:activity,
            values:.init(day:ImportantCivilDay(clock.wall).identifier,timeZoneID:TimeZone.current.identifier,seconds:45,evidence:.dateDuration,source:.manual))
        let unfinishedID = UUID(); try s.start(activityID:activity,participantID:participant,operationID:unfinishedID)
        clock.wall.addTimeInterval(12); clock.uptime += 12
        let unfinished = try XCTUnwrap(s.operations().first { $0.id == unfinishedID })
        try s.command(.pause,id:unfinishedID,revision:unfinished.revision)
        let lease = try await source.service.exportPackage(); defer {lease.cleanup()}
        for scenario in 0..<20 {
            let archive = try mutatePackage(lease.url,under:fixture.root.appendingPathComponent("InvestmentWire\(scenario)"),mutation:{ root, manifest, _ in
                let dataURL = root.appendingPathComponent("data.json")
                var payload = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:dataURL)) as? [String:Any])
                for key in ["todoSeriesPreferences","todoReminderIntents","bodyReferenceSettings"] {payload.removeValue(forKey:key)}
                var sessions = try XCTUnwrap(payload["investmentSessions"] as? [[String:Any]])
                var ops = try XCTUnwrap(payload["investmentOperations"] as? [[String:Any]])
                var first = try XCTUnwrap(sessions.first), values = try XCTUnwrap(first["values"] as? [String:Any])
                var version = 10
                switch scenario {
                case 0: payload.removeValue(forKey:"investmentParticipants")
                case 1: payload["investmentActivities"] = NSNull()
                case 2: payload["investmentSessions"] = sessions + sessions
                case 3: first["activityID"] = UUID().uuidString; sessions[0] = first; payload["investmentSessions"] = sessions
                case 4: values["seconds"] = -45; first["values"] = values; payload["investmentSessions"] = [first]
                case 5: values["evidence"] = "unknown"; first["values"] = values; payload["investmentSessions"] = [first]
                case 6: values["feeling"] = 0; first["values"] = values; payload["investmentSessions"] = [first]
                case 7: values["source"] = "automaticMonitoring"; first["values"] = values; payload["investmentSessions"] = [first]
                case 8:
                    let index = try XCTUnwrap(ops.firstIndex { ($0["id"] as? String)?.lowercased() == unfinishedID.uuidString.lowercased() })
                    var duplicate = ops[index]; duplicate["id"] = UUID().uuidString; ops.append(duplicate); payload["investmentOperations"] = ops
                case 9:
                    var timer = try XCTUnwrap(ops[0]["timer"] as? [String:Any]); timer["state"] = "unknown"; ops[0]["timer"] = timer; payload["investmentOperations"] = ops
                case 10: first["revision"] = -1; payload["investmentSessions"] = [first]
                case 11: values["spans"] = [["start":1.0,"end":46.0]]; first["values"] = values; payload["investmentSessions"] = [first]
                case 12: payload.removeValue(forKey:"investmentOperations")
                case 13: payload.removeValue(forKey:"captureReceipts")
                case 14:
                    values["day"] = "2099-12-31"; first["values"] = values; payload["investmentSessions"] = [first]
                    let matching = try XCTUnwrap(ops.firstIndex { ($0["id"] as? String) == (first["id"] as? String) })
                    var timer = try XCTUnwrap(ops[matching]["timer"] as? [String:Any]);timer["values"] = values;ops[matching]["timer"] = timer;payload["investmentOperations"] = ops
                case 16,17:
                    first["revision"] = scenario == 16 ? Int.max : Int.min
                    payload["investmentSessions"] = [first]
                case 18,19:
                    let index = try XCTUnwrap(ops.firstIndex { ($0["id"] as? String)?.lowercased() == unfinishedID.uuidString.lowercased() })
                    ops[index]["revision"] = scenario == 18 ? Int.max : Int.min
                    payload["investmentOperations"] = ops
                default: version = 9 // Reject even empty new-version keys in a legacy package.
                }
                let bytes = try JSONSerialization.data(withJSONObject:payload,options:.sortedKeys); try bytes.write(to:dataURL)
                var counts = manifest.objectCounts
                for (key,value) in payload { if counts[key] != nil, let array = value as? [Any] { counts[key] = array.count } }
                let changed = ExportManifest(formatIdentifier:manifest.formatIdentifier,packageSchemaVersion:version,appVersion:manifest.appVersion,
                    appBuild:manifest.appBuild,exportID:manifest.exportID,exportedAt:manifest.exportedAt,objectCounts:counts,
                    dataFile:.init(path:"data.json",byteCount:Int64(bytes.count),sha256:SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined()),mediaFiles:manifest.mediaFiles)
                let encoder=JSONEncoder();encoder.dateEncodingStrategy = .secondsSince1970
                try encoder.encode(changed).write(to:root.appendingPathComponent("manifest.json"))
            })
            let target = try fixture.makeEmptyStore(named:"InvestmentWireTarget\(scenario)",onDisk:true)
            do { _ = try await target.service.importPackage(from:archive); XCTFail("Malformed V10 accepted \(scenario)") }
            catch { XCTAssertFalse(error is CancellationError) }
            XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(target.container)).totalObjectCount,0)
            let reopened = try PersistenceContainerFactory.makeOnDisk(at:try XCTUnwrap(target.storeURL))
            XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(reopened)).totalObjectCount,0)
        }
    }
}

extension ImportExportRecoveryTests {
    func testReviewFixF2TrueV110SingleOpenNilAndV7RestorePreserveOriginalRuleAndRollback() async throws {
        for (offset,elapsed,minute,skip) in [(0,3,600,false),(-1,3,601,true),(0,800,600,true),(-1,800,601,false)] {
            let fixture=try TransferTestFixture()
            let zone=TimeZone(identifier:"Asia/Shanghai")!,origin=TodoDay("2020-01-01")!.date(timeZone:TimeZone(identifier:"Asia/Shanghai")!)!
            let url=fixture.root.appendingPathComponent("legacy.sqlite"),taskID=UUID(),seriesID=UUID()
            let day=try TodoRecurrence.reminderDay(occurrence:TodoDay("2020-01-01")!,offset:offset)
            let fire=TodoRecurrence.reminder(day:day,minutes:600,timeZone:zone)!
            let draft=TodoDraft(title:"True V11 single",plannedDay:"2020-01-01",deadlineDay:"2020-01-02",remindAt:fire,frequency:.daily)
            var originalEvent: Data!
            try autoreleasepool {
                let schema=Schema(versionedSchema:PersonalGrowthSchemaV11Original.self)
                let old=try ModelContainer(for:schema,configurations:[ModelConfiguration("PersonalGrowthOSV1",schema:schema,url:url,cloudKitDatabase:.none)])
                let task=TodoTask(id:taskID,title:draft.title,plannedDay:draft.plannedDay,deadlineDay:draft.deadlineDay,remindAt:fire,seriesID:seriesID,occurrenceIndex:0,createdAt:origin)
                task.reminderLocalDay=day.description;task.reminderMinutes=600;task.reminderTimeZoneID=zone.identifier
                old.mainContext.insert(task)
                old.mainContext.insert(PersonalGrowthSchemaV11Original.TodoSeries(id:seriesID,frequency:.daily,anchorDay:"2020-01-01",draft:draft,reminderMinutes:600,createdAt:origin))
                originalEvent=try JSONEncoder().encode(TodoEventValue(task))
                old.mainContext.insert(TodoTaskEvent(taskID:taskID,sequence:0,kind:.created,occurredAt:origin,createdAt:origin,beforeValue:nil,afterValue:originalEvent))
                try old.mainContext.save()
            }
            let migrated=try PersistenceContainerFactory.makeOnDisk(at:url)
            XCTAssertNil(try migrated.mainContext.fetch(FetchDescriptor<TodoSeries>()).first?.reminderDayOffset)
            try TodoIntegrity.validate(context:migrated.mainContext)
            let export=ImportExportService(context:migrated.mainContext,mediaStore:MediaStore(rootURL:fixture.root),availableCapacity:{.max})
            let lease=try await export.exportPackage();defer {lease.cleanup()}
            let v7=try mutatePackage(lease.url,under:fixture.root.appendingPathComponent("wire-v7"),rewriteJSON:{manifest,data in
                (ExportManifest(formatIdentifier:manifest.formatIdentifier,packageSchemaVersion:7,appVersion:manifest.appVersion,appBuild:manifest.appBuild,exportID:manifest.exportID,exportedAt:manifest.exportedAt,objectCounts:data.objectCounts(forPackageSchemaVersion:7),dataFile:manifest.dataFile,mediaFiles:manifest.mediaFiles),data)
            })
            let restored=try fixture.makeEmptyStore(named:"V7-restored",onDisk:true)
            _ = try await restored.service.importPackage(from:v7)
            for (index,c) in [migrated,restored.container].enumerated() {
                let now=origin.addingTimeInterval(Double(elapsed)*86400),future=TodoRecurrence.reminder(day:TodoDay(date:now.addingTimeInterval(86400),timeZone:zone),minutes:minute,timeZone:zone)!
                let service=TodoTaskService(context:c.mainContext,now:{now},timeZone:{zone})
                XCTAssertEqual(try c.mainContext.fetchCount(FetchDescriptor<TodoTask>()),1)
                XCTAssertNil(try ModelContext(c).fetch(FetchDescriptor<TodoSeries>()).first?.reminderDayOffset)
                let before=try TransferSnapshot.make(context:ModelContext(c))
                XCTAssertThrowsError(try service.rescheduleReminder(id:taskID,to:future,channel:.alarm,commit:{_ in throw CocoaError(.fileWriteOutOfSpace)}))
                XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(c)),before)
                XCTAssertEqual(try ModelContext(c).fetchCount(FetchDescriptor<TodoReminderDeviceRecord>()),0)
                try service.rescheduleReminder(id:taskID,to:future,channel:.alarm)
                let reopened=try PersistenceContainerFactory.makeOnDisk(at:c.configurations.first!.url)
                XCTAssertEqual(try ModelContext(reopened).fetch(FetchDescriptor<TodoSeries>()).first?.reminderDayOffset,offset)
                let writer=TodoTaskService(context:reopened.mainContext,now:{now},timeZone:{zone})
                XCTAssertEqual(try writer.task(id:taskID).remindAt,future)
                try writer.transition(id:taskID,to:skip ? .canceled:.completed,skip:skip)
                let next=try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<TodoTask>()).first {$0.state == .open})
                XCTAssertEqual(next.reminderLocalDay,try TodoRecurrence.reminderDay(occurrence:TodoDay(next.plannedDay!)!,offset:offset).description)
                XCTAssertEqual(next.reminderMinutes,600)
                XCTAssertEqual(try writer.task(id:taskID).plannedDay,"2020-01-01")
                XCTAssertEqual(try writer.task(id:taskID).deadlineDay,"2020-01-02")
                XCTAssertEqual(try ModelContext(reopened).fetch(FetchDescriptor<TodoTaskEvent>()).first {$0.taskID == taskID && $0.sequence == 0}?.afterValue,originalEvent)
                let output=ImportExportService(context:reopened.mainContext,mediaStore:MediaStore(rootURL:fixture.root),availableCapacity:{.max})
                let archive=try await output.exportPackage();defer {archive.cleanup()}
                let final=try fixture.makeEmptyStore(named:"Final-\(index)",onDisk:true)
                _ = try await final.service.importPackage(from:archive.url)
                XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(final.container)),try TransferSnapshot.make(context:ModelContext(reopened)))
                try TodoIntegrity.validate(context:ModelContext(final.container))
            }
        }
    }
}

extension ImportExportRecoveryTests {
    /// Happy-path rescheduleOwnedReminder from f1b52b58: same fresh context, event chain and
    /// override intent; deliberately has no later preserveLegacyReminderOffset prevention.
    private func fix2OldF1Override(_ container: ModelContainer,id: UUID,fire: Date,now: Date,zone: TimeZone,channel: TodoReminderChannel = .notification, instanceOverride: Bool = true) throws {
        let c=ModelContext(container);c.autosaveEnabled=false
        let task=try XCTUnwrap(c.fetch(FetchDescriptor<TodoTask>(predicate:#Predicate {$0.id == id})).first)
        XCTAssertEqual(task.state,.open);XCTAssertGreaterThan(fire,now)
        let before=try JSONEncoder().encode(TodoEventValue(task))
        task.remindAt=fire;task.reminderLocalDay=TodoDay(date:fire,timeZone:zone).description
        let parts=WeeklyReviewCalendarPolicy.calendar(timeZone:zone).dateComponents([.hour,.minute],from:fire)
        task.reminderMinutes=parts.hour!*60+parts.minute!;task.reminderTimeZoneID=zone.identifier
        if let intent=try c.fetch(FetchDescriptor<TodoReminderIntent>(predicate:#Predicate {$0.id == id})).first {
            intent.generation=UUID();intent.revision += 1;intent.channelRawValue=channel.rawValue;intent.isInstanceOverride=instanceOverride
        } else {c.insert(TodoReminderIntent(taskID:id,channel:channel,isInstanceOverride:instanceOverride))}
        task.revision += 1;task.updatedAt=TechnicalTimestamp.updated(now:now,createdAt:task.createdAt,previous:task.updatedAt)
        c.insert(TodoTaskEvent(taskID:id,sequence:task.revision,kind:.edited,occurredAt:now,createdAt:task.updatedAt,beforeValue:before,afterValue:try JSONEncoder().encode(TodoEventValue(task))))
        try c.save();try TodoIntegrity.validate(context:ModelContext(container));try UsagePreferencesIntegrity.validate(context:ModelContext(container))
        XCTAssertEqual(try c.fetch(FetchDescriptor<TodoReminderIntent>(predicate:#Predicate {$0.id == id})).first?.isInstanceOverride,instanceOverride)
    }
    func testFix2CR03AlreadyOverriddenLegacyNilV15AndV11RestoreRecoverWithoutChangingHistory() async throws {
        for (offset,elapsed,minute,skip) in [(0,3,600,false),(-1,3,601,true),(0,800,600,true),(-1,800,601,false)] {
            let f=try TransferTestFixture();defer {f.remove()}
            let zone=TimeZone(identifier:"Asia/Shanghai")!,origin=TodoDay("2020-01-01")!.date(timeZone:TimeZone(identifier:"Asia/Shanghai")!)!
            let url=f.root.appendingPathComponent("legacy.sqlite"),id=UUID(),sid=UUID()
            let day=try TodoRecurrence.reminderDay(occurrence:TodoDay("2020-01-01")!,offset:offset)
            let fire=TodoRecurrence.reminder(day:day,minutes:600,timeZone:zone)!
            let listID=UUID()
            let draft=TodoDraft(title:"Legacy already overridden",plannedDay:"2020-01-01",deadlineDay:"2020-01-02",remindAt:fire,listID:listID,frequency:.daily)
            try autoreleasepool {
                let schema=Schema(versionedSchema:PersonalGrowthSchemaV11Original.self)
                let old=try ModelContainer(for:schema,configurations:[ModelConfiguration("PersonalGrowthOSV1",schema:schema,url:url,cloudKitDatabase:.none)])
                let task=TodoTask(id:id,title:draft.title,plannedDay:draft.plannedDay,deadlineDay:draft.deadlineDay,remindAt:fire,listID:listID,seriesID:sid,occurrenceIndex:0,createdAt:origin)
                task.reminderLocalDay=day.description;task.reminderMinutes=600;task.reminderTimeZoneID=zone.identifier
                old.mainContext.insert(TodoList(id:listID,name:"Legacy list",createdAt:origin));old.mainContext.insert(task);old.mainContext.insert(PersonalGrowthSchemaV11Original.TodoSeries(id:sid,frequency:.daily,anchorDay:"2020-01-01",draft:draft,reminderMinutes:600,createdAt:origin))
                old.mainContext.insert(TodoTaskEvent(taskID:id,sequence:0,kind:.created,occurredAt:origin,createdAt:origin,beforeValue:nil,afterValue:try JSONEncoder().encode(TodoEventValue(task))))
                try old.mainContext.save()
            }
            let migrated=try PersistenceContainerFactory.makeOnDisk(at:url),now=origin.addingTimeInterval(Double(elapsed)*86400)
            // An unrelated title edit precedes the old one-off override; it is not a rule edit.
            let oldService=TodoTaskService(context:migrated.mainContext,now:{origin.addingTimeInterval(1)},timeZone:{zone})
            var title=try oldService.draft(id:id);title.title="Legacy title edit"
            if elapsed == 800 && offset == -1 {title.listID=nil} // Only the rule still belongs to the deleted list.
            try oldService.edit(id:id,draft:title)
            let override=TodoRecurrence.reminder(day:TodoDay(date:now.addingTimeInterval(86400),timeZone:zone),minutes:minute,timeZone:zone)!
            try fix2OldF1Override(migrated,id:id,fire:override,now:now,zone:zone)
            XCTAssertNil(try ModelContext(migrated).fetch(FetchDescriptor<TodoSeries>()).first?.reminderDayOffset)
            let exporter=ImportExportService(context:migrated.mainContext,mediaStore:MediaStore(rootURL:f.root),availableCapacity:{.max})
            let archive=try await exporter.exportPackage();defer {archive.cleanup()}
            let restored=try f.makeEmptyStore(named:"overridden-v11",onDisk:true);_ = try await restored.service.importPackage(from:archive.url)
            for (index,c) in [try PersistenceContainerFactory.makeOnDisk(at:url),restored.container].enumerated() {
                let history=try ModelContext(c).fetch(FetchDescriptor<TodoTaskEvent>()).map {TodoTaskEventTransfer($0)}
                let before=try TransferSnapshot.make(context:ModelContext(c))
                let failing=TodoTaskService(context:ModelContext(c),now:{now},timeZone:{zone},save:{throw CocoaError(.fileWriteOutOfSpace)})
                XCTAssertThrowsError(try failing.transition(id:id,to:skip ? .canceled:.completed,skip:skip))
                XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(c)),before)
                let service=TodoTaskService(context:ModelContext(c),now:{now},timeZone:{zone})
                if index == 1 {
                    // A valid old override must remain recoverable after current-version
                    // metadata, timezone and list operations. Freeze before new evidence.
                    func continuation(_ writer: TodoTaskService) throws {
                        if elapsed == 3 && offset == 0 {
                            var metadata=try writer.draft(id:id);metadata.notes="Current metadata";metadata.title="Current title"
                            try writer.edit(id:id,draft:metadata)
                        } else if elapsed == 3 {
                            try writer.refreshRepeatingReminderTimes()
                        } else {try writer.deleteList(id:listID)}
                    }
                    let travelZone = elapsed == 3 && offset == -1 ? TimeZone(identifier:"America/Los_Angeles")!:zone
                    let failingContinuation=TodoTaskService(context:ModelContext(c),now:{now},timeZone:{travelZone},save:{throw CocoaError(.fileWriteOutOfSpace)})
                    XCTAssertThrowsError(try continuation(failingContinuation))
                    XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(c)),before)
                    try continuation(TodoTaskService(context:ModelContext(c),now:{now},timeZone:{travelZone}))
                    XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<TodoSeries>()).first?.reminderDayOffset,offset)
                    let afterContinuation=try TransferSnapshot.make(context:ModelContext(c))
                    XCTAssertThrowsError(try service.rescheduleReminder(id:id,to:override.addingTimeInterval(120),commit:{_ in throw CocoaError(.fileWriteOutOfSpace)}))
                    XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(c)),afterContinuation)
                    try service.rescheduleReminder(id:id,to:override.addingTimeInterval(120))
                    XCTAssertEqual(try service.task(id:id).remindAt,override.addingTimeInterval(120))
                } else {XCTAssertEqual(try service.task(id:id).remindAt,override)}
                try service.transition(id:id,to:skip ? .canceled:.completed,skip:skip)
                let next=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<TodoTask>()).first {$0.state == .open})
                XCTAssertEqual(next.reminderLocalDay,try TodoRecurrence.reminderDay(occurrence:TodoDay(next.plannedDay!)!,offset:offset).description)
                XCTAssertEqual(next.reminderMinutes,600)
                XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<TodoSeries>()).first?.reminderDayOffset,offset)
                let after=try ModelContext(c).fetch(FetchDescriptor<TodoTaskEvent>()).map {TodoTaskEventTransfer($0)}
                XCTAssertTrue(history.allSatisfy {after.contains($0)},"Preserve every historical event and snapshot byte")
                try TodoIntegrity.validate(context:ModelContext(c))
                let finalExport=ImportExportService(context:c.mainContext,mediaStore:MediaStore(rootURL:f.root),availableCapacity:{.max})
                let output=try await finalExport.exportPackage();defer {output.cleanup()}
                let final=try f.makeEmptyStore(named:"final-\(index)",onDisk:true);_ = try await final.service.importPackage(from:output.url)
                XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(final.container)),try TransferSnapshot.make(context:ModelContext(c)))
            }
        }
    }
}

@MainActor
extension ImportExportRecoveryTests {
    /// Same original V11 model used by the immutable-fixture and CR03 tests.
    private func systemLegacyNilStore(_ f: TransferTestFixture, override: Bool = false) throws -> (ModelContainer,UUID,UUID,Date,TimeZone) {
        let url=f.root.appendingPathComponent("system-legacy.sqlite"),id=UUID(),sid=UUID(),list=UUID()
        let zone=TimeZone(identifier:TimeZone.current.identifier == "America/Los_Angeles" ? "Asia/Shanghai":"America/Los_Angeles")!
        let now=TodoDay("2026-10-19")!.date(timeZone:zone)!,fire=TodoRecurrence.reminder(day:TodoDay("2026-10-20")!,minutes:600,timeZone:zone)!
        try autoreleasepool {
            let schema=Schema(versionedSchema:PersonalGrowthSchemaV11Original.self)
            let old=try ModelContainer(for:schema,configurations:[ModelConfiguration("PersonalGrowthOSV1",schema:schema,url:url,cloudKitDatabase:.none)])
            let draft=TodoDraft(title:"Original nil",plannedDay:"2026-10-20",remindAt:fire,listID:list,frequency:.daily)
            let task=TodoTask(id:id,title:draft.title,plannedDay:draft.plannedDay,remindAt:fire,listID:list,seriesID:sid,occurrenceIndex:0,createdAt:now)
            task.reminderLocalDay="2026-10-20";task.reminderMinutes=600;task.reminderTimeZoneID=zone.identifier
            let source=Entry(body:"Legacy source retains original",createdAt:now)
            old.mainContext.insert(source);old.mainContext.insert(TodoTaskSource(taskID:id,entryID:source.id))
            old.mainContext.insert(TodoList(id:list,name:"Legacy",createdAt:now));old.mainContext.insert(task)
            old.mainContext.insert(PersonalGrowthSchemaV11Original.TodoSeries(id:sid,frequency:.daily,anchorDay:"2026-10-20",draft:draft,reminderMinutes:600,createdAt:now))
            old.mainContext.insert(TodoTaskEvent(taskID:id,sequence:0,kind:.created,occurredAt:now,createdAt:now,beforeValue:nil,afterValue:try JSONEncoder().encode(TodoEventValue(task))))
            try old.mainContext.save()
        }
        let c=try PersistenceContainerFactory.makeOnDisk(at:url)
        if override {try fix2OldF1Override(c,id:id,fire:fire.addingTimeInterval(400*86400),now:now.addingTimeInterval(60),zone:zone)}
        return (c,id,list,now,zone)
    }

    func testSystemSR01StoppedNilDefaultEditsListCleanupAndReopen() async throws {
        for mode in 0..<4 {
            let f=try TransferTestFixture();defer {f.remove()}
            let (c,id,list,now,zone)=try systemLegacyNilStore(f,override:mode == 1)
            let service=TodoTaskService(context:ModelContext(c),now:{now.addingTimeInterval(120)},timeZone:{zone})
            if mode == 2 {try service.delete(id:id)} else {try service.stopSeries(taskID:id)}
            let before=try TransferSnapshot.make(context:ModelContext(c))
            if mode < 2 {
                var draft=try service.draft(id:id)
                if mode == 0 {draft.remindAt=nil} else {draft.title="Stopped metadata";draft.notes="Preserve override"}
                try service.edit(id:id,draft:draft)
                XCTAssertEqual(try service.task(id:id).remindAt,draft.remindAt)
            }
            let events=try ModelContext(c).fetch(FetchDescriptor<TodoTaskEvent>()).map {TodoTaskEventTransfer($0)}
            let afterEdit=try TransferSnapshot.make(context:ModelContext(c))
            let failing=TodoTaskService(context:ModelContext(c),now:{now},save:{throw CocoaError(.fileWriteOutOfSpace)})
            XCTAssertThrowsError(try failing.deleteList(id:list))
            XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(c)),afterEdit)
            try service.deleteList(id:list)
            let travel=TodoTaskService(context:ModelContext(c),now:{now},timeZone:{TimeZone(identifier:"Asia/Shanghai")!})
            try travel.refreshRepeatingReminderTimes()
            let read=ModelContext(try PersistenceContainerFactory.makeOnDisk(at:f.root.appendingPathComponent("system-legacy.sqlite")))
            XCTAssertTrue(try read.fetch(FetchDescriptor<TodoList>()).isEmpty)
            XCTAssertEqual(try read.fetch(FetchDescriptor<Entry>()).map(\.body),["Legacy source retains original"])
            XCTAssertTrue(try read.fetch(FetchDescriptor<TodoTask>()).allSatisfy {$0.listID == nil})
            XCTAssertTrue(try read.fetch(FetchDescriptor<TodoSeries>()).allSatisfy {$0.isStopped && $0.listID == nil})
            XCTAssertTrue(events.allSatisfy {event in (try? read.fetch(FetchDescriptor<TodoTaskEvent>()).map {TodoTaskEventTransfer($0)}.contains(event)) == true})
            try TodoIntegrity.validate(context:read)
            XCTAssertFalse(before.todoSeries.isEmpty)
            let exporter=ImportExportService(context:c.mainContext,mediaStore:MediaStore(rootURL:f.root),availableCapacity:{.max})
            let archive=try await exporter.exportPackage();defer {archive.cleanup()}
            let restored=try f.makeEmptyStore(named:"system-restored",onDisk:true)
            _ = try await restored.service.importPackage(from:archive.url)
            try TodoIntegrity.validate(context:ModelContext(restored.container))
        }
    }

    func testSystemSR01StoppedNilTravelDoesNotBlockHealthySharedReminders() async throws {
        let f=try TransferTestFixture();defer {f.remove()}
        let (c,id,_,now,zone)=try systemLegacyNilStore(f)
        let service=TodoTaskService(context:ModelContext(c),now:{now},timeZone:{zone})
        try service.stopSeries(taskID:id)
        let healthy=try service.create(.init(title:"Healthy Todo",remindAt:now.addingTimeInterval(3600)))
        var preferences=ImportantDayPreferences();preferences.reminderOffsets=[0]
        let future=ImportantCivilDay(now,timeZone:.current).adding(days:1)!
        let day=try ImportantDay(title:"Healthy Important Day",rule:.init(year:future.year,month:future.month,day:future.day),preferences:preferences)
        c.mainContext.insert(day);try c.mainContext.save()
        let client=TodoNotificationStub(),coordinator=TodoReminderCoordinator(client:client,now:{now},sleepPreferences:{.init(enabled:true,minute:540)},sleepHistory:SleepReminderHistory(defaults:nil))
        await coordinator.reconcile(context:ModelContext(c))
        XCTAssertEqual(coordinator.status(for:day).status,.scheduled)
        XCTAssertEqual(coordinator.sleepStatus().status,.scheduled)
        XCTAssertEqual(coordinator.status(for:try service.task(id:healthy.id)),.scheduled)
        XCTAssertEqual(coordinator.status(for:try service.task(id:id)),.none)
        XCTAssertFalse(client.addCalls.contains {$0.taskID == id})
    }
}

@MainActor
extension ImportExportRecoveryTests {
    func testSystemBV02BoundedNonfiniteQuantityDiskAndActualExportProbe() async throws {
        for (index,input) in ["inf","NaN","1e999","2.5"].enumerated() {
            let f=try TransferTestFixture();defer {f.remove()}
            let store=try f.makeEmptyStore(named:"quantity",onDisk:true)
            let now=Date(),value=try XCTUnwrap(Double(input))
            let habit=try HabitService(context:store.container.mainContext,now:{now}).create(name:"Quantity probe")
            let service=HabitCheckInService(context:store.container.mainContext,mediaStore:store.mediaStore,now:{now})
            do {
                let log=try service.checkIn(habit,draft:HabitLogDraft(occurredAt:now,quantity:value))
                let url=store.container.configurations.first!.url
                let reopened=try PersistenceContainerFactory.makeOnDisk(at:url)
                let persisted=try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<HabitLog>()).first {$0.id == log.id})
                let exporter=ImportExportService(context:reopened.mainContext,mediaStore:store.mediaStore,availableCapacity:{.max})
                do {
                    let archive=try await exporter.exportPackage();defer {archive.cleanup()}
                    print("PGOS_BV02 probe=\(index) input=\(input) saved=true persisted=\(String(describing:persisted.quantity)) export=PASS")
                } catch {
                    print("PGOS_BV02 probe=\(index) input=\(input) saved=true persisted=\(String(describing:persisted.quantity)) export=FAIL error=\(error)")
                }
            } catch {print("PGOS_BV02 probe=\(index) input=\(input) saved=false error=\(error)")}
        }
    }
}

@MainActor
extension ImportExportRecoveryTests {
    func testSystemBV02RejectsNonfiniteBeforeSaveAndPreservesOldInvalidFactInRawRecovery() async throws {
        let f=try TransferTestFixture();defer {f.remove()}
        let root=f.root.appendingPathComponent("LegacyQuantity"),store=root.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
        try FileManager.default.createDirectory(at:store.deletingLastPathComponent(),withIntermediateDirectories:true)
        let c=try PersistenceContainerFactory.makeOnDisk(at:store),context=c.mainContext,now=Date()
        let media=MediaStore(rootURL:root),habit=try HabitService(context:context,now:{now}).create(name:"Legacy quantity")
        let service=HabitCheckInService(context:context,mediaStore:media,now:{now})
        for text in ["inf","-inf","NaN","1e999"] {
            XCTAssertThrowsError(try HabitQuantityRules.parse(text))
            let value=try XCTUnwrap(Double(text))
            XCTAssertThrowsError(try service.checkIn(habit,draft:.init(occurredAt:now,quantity:value))) {XCTAssertEqual($0 as? HabitCheckInError,.invalidQuantity)}
            XCTAssertThrowsError(try service.checkInWithInsight(habit,logDraft:.init(occurredAt:now,quantity:value),entryDraft:.init(body:"Must not publish")))
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<HabitLog>()),0);XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()),0)
        let finite=try service.checkIn(habit,draft:.init(occurredAt:now,quantity:HabitQuantityRules.parse("2.5"),unit:"km",result:"Original result"))
        let exporter=ImportExportService(context:context,mediaStore:media,availableCapacity:{.max})
        let good=try await exporter.exportPackage();defer {good.cleanup()}
        let restored=try f.makeEmptyStore(named:"finite-restored",onDisk:true);_ = try await restored.service.importPackage(from:good.url)
        XCTAssertEqual(try restored.container.mainContext.fetch(FetchDescriptor<HabitLog>()).first?.quantity,2.5)
        // Reconstruct the exact old service's accepted persisted infinity, proved by
        // bv02 probe (no synthetic schema or invalid event chain is involved).
        finite.quantity = .infinity;try context.save()
        do {let archive=try await exporter.exportPackage();archive.cleanup();XCTFail("Do not claim a complete normal backup")}
        catch let error as NonfiniteHabitQuantityError {XCTAssertEqual(error.logIDs,[finite.id])}
        let raw=try await exporter.exportRetainedQuantityData(),extracted=f.root.appendingPathComponent("raw-quantity")
        try ZIPArchiveReader(archiveURL:raw,availableCapacity:.max).extractAll(to:extracted)
        XCTAssertFalse(FileManager.default.fileExists(atPath:extracted.appendingPathComponent("data.json").path))
        XCTAssertTrue(try String(contentsOf:extracted.appendingPathComponent("RECOVERY.txt"),encoding:.utf8).contains("NOT"))
        let recovered=try PersistenceContainerFactory.makeOnDisk(at:extracted.appendingPathComponent("Store/PersonalGrowthOS.sqlite"))
        let original=try XCTUnwrap(recovered.mainContext.fetch(FetchDescriptor<HabitLog>()).first)
        XCTAssertEqual(original.id,finite.id);XCTAssertEqual(original.quantity?.bitPattern,Double.infinity.bitPattern)
        XCTAssertEqual(original.result,"Original result");XCTAssertEqual(original.unit,"km")
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<HabitLog>()).first?.quantity?.bitPattern,Double.infinity.bitPattern)
    }
}

@MainActor
extension ImportExportRecoveryTests {
    func testSystemSR01UnrecoverableActivePolicyIsLocalAndExplicitRuleCanCorrectIt() async throws {
        let f=try TransferTestFixture();defer {f.remove()}
        let (c,id,list,now,zone)=try systemLegacyNilStore(f,override:true)
        let overridden=try TodoTaskService(context:ModelContext(c)).task(id:id).remindAt!
        try fix2OldF1Override(c,id:id,fire:overridden.addingTimeInterval(86460),now:now.addingTimeInterval(90),zone:zone)
        let before=try ModelContext(c).fetch(FetchDescriptor<TodoTaskEvent>()).map(TodoTaskEventTransfer.init)
        let service=TodoTaskService(context:ModelContext(c),now:{now},timeZone:{zone})
        let healthy=try service.create(.init(title:"Healthy beside unknown legacy",remindAt:now.addingTimeInterval(3600)))
        var preferences=ImportantDayPreferences();preferences.reminderOffsets=[0]
        let future=ImportantCivilDay(now,timeZone:.current).adding(days:1)!
        let day=try ImportantDay(title:"Healthy neighbour",rule:.init(year:future.year,month:future.month,day:future.day),preferences:preferences)
        c.mainContext.insert(day);try c.mainContext.save()
        let client=TodoNotificationStub(),coordinator=TodoReminderCoordinator(client:client,now:{now},sleepPreferences:{.init(enabled:true,minute:540)},sleepHistory:SleepReminderHistory(defaults:nil))
        // A current native request can predate the newer policy-recovery guard.
        // Use the actual intent scheduler to retain its valid durable ownership.
        let scheduling=TodoIntentScheduling(notifications:client,alarms:TodoAlarmStub(),now:{now})
        _ = try await scheduling.reconcile(container:c,requestNotifications:false,requestAlarms:false,selectedNotificationTaskIDs:[id],isCurrent:{true})
        let alreadySubmitted=client.addCalls.count
        client.failedRemovalIdentifiers=Set(client.pending.values.filter {$0.taskID == id}.map(\.id))
        XCTAssertFalse(client.failedRemovalIdentifiers.isEmpty)
        await coordinator.reconcile(context:ModelContext(c))
        XCTAssertTrue(coordinator.hasPendingCancellation)
        XCTAssertEqual(coordinator.status(for:try service.task(id:id)),.cancellationPending)
        client.failedRemovalIdentifiers=[]
        for _ in 0..<2 {await coordinator.reconcile(context:ModelContext(c))}
        XCTAssertFalse(coordinator.hasPendingCancellation)
        XCTAssertEqual(coordinator.status(for:try service.task(id:id)),.legacyRuleNeedsCorrection)
        XCTAssertEqual(coordinator.status(for:healthy),.scheduled)
        XCTAssertEqual(coordinator.status(for:day).status,.scheduled);XCTAssertEqual(coordinator.sleepStatus().status,.scheduled)
        XCTAssertFalse(client.addCalls.dropFirst(alreadySubmitted).contains {$0.taskID == id})
        let elapsed=TodoReminderCoordinator(client:client,now:{overridden.addingTimeInterval(3*86400)},sleepPreferences:{.init()})
        await elapsed.reconcile(context:ModelContext(c))
        XCTAssertEqual(elapsed.status(for:try service.task(id:id)),.legacyRuleNeedsCorrection,"An elapsed one-off must still explain the unknown future policy")
        try service.deleteList(id:list) // Category cleanup never needs a guessed future policy.
        var correction=try service.draft(id:id)
        correction.remindAt=TodoRecurrence.reminder(day:TodoDay(correction.plannedDay!)!,minutes:600,timeZone:zone)
        try service.edit(id:id,draft:correction,futureSeries:true)
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<TodoSeries>()).first?.reminderDayOffset,0)
        XCTAssertTrue(before.allSatisfy {event in (try? ModelContext(c).fetch(FetchDescriptor<TodoTaskEvent>()).map(TodoTaskEventTransfer.init).contains(event)) == true})
        try TodoIntegrity.validate(context:ModelContext(c))
    }

    func testSystemSR01OriginalMultiOccurrenceDeleteSiblingThenUnlinkAndCloseReminder() throws {
        let source=try XCTUnwrap(Bundle(for:Self.self).resourceURL?.appendingPathComponent("OriginalV11Fixture"))
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at:source,to:root);defer {try? FileManager.default.removeItem(at:root)}
        let c=try PersistenceContainerFactory.makeOnDisk(at:root.appendingPathComponent("store.sqlite"))
        let service=TodoTaskService(context:c.mainContext)
        let rootID=try XCTUnwrap(UUID(uuidString:String(contentsOf:root.appendingPathComponent("task-id.txt"),encoding:.utf8)))
        let sibling=try XCTUnwrap(c.mainContext.fetch(FetchDescriptor<TodoTask>()).first {$0.state == .open})
        let list=try service.createList(name:"Sibling list")
        var edit=try service.draft(id:sibling.id);edit.listID=list.id;try service.edit(id:sibling.id,draft:edit)
        XCTAssertNil(try c.mainContext.fetch(FetchDescriptor<TodoSeries>()).first?.reminderDayOffset)
        try service.delete(id:rootID)
        try TodoTaskService(context:ModelContext(c),timeZone:{.gmt}).refreshRepeatingReminderTimes()
        try service.deleteList(id:list.id)
        var close=try service.draft(id:sibling.id);close.remindAt=nil;try service.edit(id:sibling.id,draft:close)
        XCTAssertNil(try service.task(id:sibling.id).remindAt);XCTAssertNil(try service.task(id:sibling.id).listID)
        XCTAssertTrue(try c.mainContext.fetch(FetchDescriptor<TodoSeries>()).allSatisfy(\.isStopped))
        try TodoIntegrity.validate(context:ModelContext(c))
    }
}

@MainActor extension ImportExportRecoveryTests {
    func testSystemSR01InjectedIntegrityReadFailureIsNotSwallowedAsLocalLegacyPolicy() async throws {
        let f=try TransferTestFixture();defer {f.remove()}
        let (c,id,_,now,zone)=try systemLegacyNilStore(f)
        let healthy=try TodoTaskService(context:ModelContext(c),now:{now},timeZone:{zone}).create(.init(title:"Healthy beside an injected integrity failure",remindAt:now.addingTimeInterval(3600)))
        // Negative guard only: this is deliberately broken evidence, not a claim
        // that an ordinary production lifecycle creates this state.
        let read=ModelContext(c),event=try XCTUnwrap(read.fetch(FetchDescriptor<TodoTaskEvent>()).first {$0.taskID == id})
        event.afterValue=Data([0xff]);try read.save()
        XCTAssertThrowsError(try TodoIntegrity.validate(context:ModelContext(c)))
        let client=TodoNotificationStub(),coordinator=TodoReminderCoordinator(client:client,now:{now})
        await coordinator.reconcile(context:ModelContext(c))
        XCTAssertTrue(client.addCalls.isEmpty)
        XCTAssertEqual(coordinator.status(for:healthy),.confirmationRequired)
        XCTAssertNotEqual(coordinator.status(for:try TodoTaskService(context:ModelContext(c)).task(id:id)),.legacyRuleNeedsCorrection)
    }
}

@MainActor extension ImportExportRecoveryTests {
    func testIntegrationIR01StoppedRefreshDoesNotSaveOrPublish() throws {
        for legacy in [false,true] {
            let f=try TransferTestFixture();defer {f.remove()}
            let (c,id,_,now,zone)=try systemLegacyNilStore(f)
            let service=TodoTaskService(context:ModelContext(c),now:{now},timeZone:{zone})
            if !legacy {
                var draft=try service.draft(id:id)
                try service.edit(id:id,draft:draft,futureSeries:true)
                draft=try service.draft(id:id)
            }
            try service.stopSeries(taskID:id)
            let before=try TransferSnapshot.make(context:ModelContext(c))
            var saves=0,events=0
            let token=NotificationCenter.default.addObserver(forName:.todoTasksChanged,object:c,queue:nil) {_ in MainActor.assumeIsolated {events += 1}}
            defer {NotificationCenter.default.removeObserver(token)}
            let read=ModelContext(c);read.autosaveEnabled=false
            let travel=TodoTaskService(context:read,now:{now},timeZone:{.gmt},save:{saves += 1;try read.save()})
            XCTAssertTrue(try travel.refreshRepeatingReminderTimes().isEmpty)
            XCTAssertEqual(saves,0);XCTAssertEqual(events,0)
            XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(c)),before)
        }
    }
}

@MainActor extension ImportExportRecoveryTests {
    func testIntegrationIR02BothOwnedFutureChannelsCancelConfirmColdReopenAndCorrect() async throws {
        for channel:TodoReminderChannel in [.notification,.alarm] {
            for failure in 0..<3 {
                let f=try TransferTestFixture();defer {f.remove()}
                let (c,id,_,now,zone)=try systemLegacyNilStore(f,override:true)
                let fire=try TodoTaskService(context:ModelContext(c)).task(id:id).remindAt!
                try fix2OldF1Override(c,id:id,fire:fire.addingTimeInterval(86460),now:now.addingTimeInterval(90),zone:zone,channel:channel)
                let notifications=TodoNotificationStub(),alarms=TodoAlarmStub()
                let scheduler=TodoIntentScheduling(notifications:notifications,alarms:alarms,now:{now})
                _ = try await scheduler.reconcile(container:c,requestNotifications:false,requestAlarms:false,selectedNotificationTaskIDs:[id],isCurrent:{true})
                let original=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first)
                XCTAssertEqual(original.phaseRawValue,TodoReminderDevicePhase.accepted.rawValue)
                let nativeID=original.id,generation=original.intentGeneration
                func exists() -> Bool {channel == .alarm ? alarms.pending[nativeID] != nil:notifications.pending[TodoIntentScheduling.identifier(nativeID)] != nil}
                XCTAssertTrue(exists())
                if failure != 2 {alarms.failCancel=true;notifications.failedRemovalIdentifiers=[TodoIntentScheduling.identifier(nativeID)]}
                var failWrites=true
                let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms,journalCommit:{write in
                    let record=try write.fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first {$0.id == nativeID}
                    if failWrites, (failure == 0 && record?.phaseRawValue == TodoReminderDevicePhase.cancellationPending.rawValue || failure == 2 && record?.phaseRawValue == TodoReminderDevicePhase.retired.rawValue) {throw CocoaError(.fileWriteOutOfSpace)}
                    try write.save()
                })
                await coordinator.reconcile(context:ModelContext(c))
                XCTAssertEqual(coordinator.status(for:try TodoTaskService(context:ModelContext(c)).task(id:id)),.cancellationPending)
                XCTAssertEqual(exists(),failure != 2)
                let durable=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first {$0.id == nativeID})
                XCTAssertEqual(durable.intentGeneration,generation)
                XCTAssertEqual(durable.phaseRawValue,failure == 0 ? TodoReminderDevicePhase.accepted.rawValue:TodoReminderDevicePhase.cancellationPending.rawValue)
                failWrites=false;alarms.failCancel=false;notifications.failedRemovalIdentifiers=[]
                let cold=try PersistenceContainerFactory.makeOnDisk(at:c.configurations.first!.url)
                let reopened=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
                await reopened.reconcile(context:ModelContext(cold))
                let service=TodoTaskService(context:ModelContext(cold),now:{now},timeZone:{.current})
                XCTAssertFalse(exists());XCTAssertEqual(reopened.status(for:try service.task(id:id)),.legacyRuleNeedsCorrection)
                XCTAssertEqual(try ModelContext(cold).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first {$0.id == nativeID}?.phaseRawValue,TodoReminderDevicePhase.retired.rawValue)
                var correction=try service.draft(id:id)
                correction.remindAt=TodoRecurrence.reminder(day:TodoDay(correction.plannedDay!)!,minutes:600,timeZone:.current)
                correction.reminderChannel=channel
                try service.edit(id:id,draft:correction,futureSeries:true)
                await reopened.reconcile(context:ModelContext(cold))
                XCTAssertEqual(reopened.status(for:try service.task(id:id)),.scheduled)
                let accepted=try XCTUnwrap(ModelContext(cold).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first {$0.phaseRawValue == TodoReminderDevicePhase.accepted.rawValue})
                XCTAssertNotEqual(accepted.intentGeneration,generation);XCTAssertNotEqual(accepted.id,nativeID)
                XCTAssertTrue(channel == .alarm ? alarms.pending[accepted.id] != nil:notifications.pending[TodoIntentScheduling.identifier(accepted.id)] != nil)
                print("PGOS_IR02 channel=\(channel.rawValue) failure=\(failure) old=\(nativeID) new=\(accepted.id) coldConfirmed=true")
            }
        }
    }
}

@MainActor extension ImportExportRecoveryTests {
    func testIntegrationIR01MountedProductionEventBridgeSettlesAndReleasesSettingsGate() async throws {
        for mode in 0..<3 {
            let f=try TransferTestFixture();defer {f.remove()}
            let (c,id,_,now,zone)=try systemLegacyNilStore(f,override:mode == 2)
            let service=TodoTaskService(context:ModelContext(c),now:{now},timeZone:{zone})
            if mode == 0 {let draft=try service.draft(id:id);try service.edit(id:id,draft:draft,futureSeries:true)}
            if mode < 2 {try service.stopSeries(taskID:id)}
            else {
                let fire=try service.task(id:id).remindAt!
                try fix2OldF1Override(c,id:id,fire:fire.addingTimeInterval(86460),now:now.addingTimeInterval(90),zone:zone)
            }
            // A healthy repeating neighbour really changes zone and must emit one fact event.
            let healthy=try service.create(.init(title:"Bridge healthy",plannedDay:"2026-10-20",remindAt:TodoRecurrence.reminder(day:TodoDay("2026-10-20")!,minutes:600,timeZone:zone),frequency:.daily))
            var preferences=ImportantDayPreferences();preferences.reminderOffsets=[0]
            let tomorrow=ImportantCivilDay(now,timeZone:.current).adding(days:1)!
            let day=try ImportantDay(title:"Bridge ImportantDay",rule:.init(year:tomorrow.year,month:tomorrow.month,day:tomorrow.day),preferences:preferences)
            c.mainContext.insert(day);try c.mainContext.save()
            let client=TodoNotificationStub(),coordinator=TodoReminderCoordinator(client:client,now:{now},sleepPreferences:{.init(enabled:true,minute:540)},sleepHistory:SleepReminderHistory(defaults:nil))
            let mounted=expectation(description:"Real event subscriptions mounted"),entered=expectation(description:"Permission await after refresh")
            var release:CheckedContinuation<Void,Never>?
            client.whileCheckingPermission={await withCheckedContinuation {release=$0;entered.fulfill()}}
            let window=UIWindow(frame:UIScreen.main.bounds)
            let host=UIHostingController(rootView:Color.clear.modifier(TodoReminderEvents(container:c,coordinator:coordinator)).onAppear {mounted.fulfill()})
            window.rootViewController=host;window.makeKeyAndVisible()
            let failSafe=Task { @MainActor in
                try? await Task.sleep(for:.seconds(5));guard !Task.isCancelled else {return}
                window.rootViewController=nil;release?.resume();release=nil
            }
            defer {failSafe.cancel();window.isHidden=true;window.rootViewController=nil;release?.resume()}
            await fulfillment(of:[mounted],timeout:3)
            var events=0
            let token=NotificationCenter.default.addObserver(forName:.todoTasksChanged,object:c,queue:nil) {_ in MainActor.assumeIsolated {events += 1}}
            defer {NotificationCenter.default.removeObserver(token)}
            let reconcile=Task {await coordinator.reconcile(context:ModelContext(c))}
            await fulfillment(of:[entered],timeout:3)
            let settingsClient=SystemSettingsLateClient();settingsClient.suspendFirst=false
            let waiter=Task {try await LocalReminderScheduler(client:settingsClient).updateDaily(enabled:true,minutesAfterMidnight:480,requestPermission:false)}
            if mode == 2 {
                var edit=try service.draft(id:healthy.id);edit.title="Latest external title"
                try service.edit(id:healthy.id,draft:edit)
            }
            // The notification callback has already submitted a real generation-invalidating Task.
            await Task.yield()
            release?.resume();release=nil
            await reconcile.value
            let waiterResult=try await waiter.value
            XCTAssertEqual(waiterResult,.scheduled)
            XCTAssertEqual(events,mode == 2 ? 2:1)
            if mode == 2 {XCTAssertTrue(client.pending.values.contains {$0.taskID == healthy.id && $0.title == "Latest external title"})}
            XCTAssertEqual(coordinator.status(for:try service.task(id:healthy.id)),.scheduled)
            XCTAssertEqual(coordinator.status(for:day).status,.scheduled);XCTAssertEqual(coordinator.sleepStatus().status,.scheduled)
            XCTAssertEqual(coordinator.status(for:try service.task(id:id)),mode == 2 ? .legacyRuleNeedsCorrection:.none)
            await coordinator.reconcile(context:ModelContext(c))
            XCTAssertEqual(events,mode == 2 ? 2:1,"A completed no-change pass must remain silent")
            print("PGOS_IR01 mode=\(mode) events=\(events) healthyThree=true gateWaiter=scheduled")
        }
    }
}

@MainActor extension ImportExportRecoveryTests {
    func testIntegrationIR01RealTravelSaveFailureRollsBackAndRetryPublishesExactlyOnce() throws {
        let f=try TransferTestFixture();defer {f.remove()}
        let (c,id,_,now,zone)=try systemLegacyNilStore(f)
        let before=try TransferSnapshot.make(context:ModelContext(c))
        var events=0
        let token=NotificationCenter.default.addObserver(forName:.todoTasksChanged,object:c,queue:nil) {_ in MainActor.assumeIsolated {events += 1}}
        defer {NotificationCenter.default.removeObserver(token)}
        let context=ModelContext(c);context.autosaveEnabled=false
        let failing=TodoTaskService(context:context,now:{now},timeZone:{.gmt},save:{throw CocoaError(.fileWriteOutOfSpace)})
        XCTAssertThrowsError(try failing.refreshRepeatingReminderTimes())
        XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(c)),before);XCTAssertEqual(events,0)
        XCTAssertTrue(try TodoTaskService(context:ModelContext(c),now:{now},timeZone:{.gmt}).refreshRepeatingReminderTimes().isEmpty)
        XCTAssertEqual(events,1)
        let task=try TodoTaskService(context:ModelContext(c)).task(id:id)
        XCTAssertNotEqual(task.reminderTimeZoneID,zone.identifier)
        XCTAssertTrue(try TodoTaskService(context:ModelContext(c),now:{now},timeZone:{.gmt}).refreshRepeatingReminderTimes().isEmpty)
        XCTAssertEqual(events,1)
    }

    func testIntegrationIR02UnresolvedFutureSystemStopNeverRevivesAndElapsedAlarmStillRings() async throws {
        for ringing in [false,true] {
            let f=try TransferTestFixture();defer {f.remove()}
            let (c,id,_,start,zone)=try systemLegacyNilStore(f,override:true)
            let fire=try TodoTaskService(context:ModelContext(c)).task(id:id).remindAt!.addingTimeInterval(86460)
            try fix2OldF1Override(c,id:id,fire:fire,now:start.addingTimeInterval(90),zone:zone,channel:.alarm)
            var now=start
            let notifications=TodoNotificationStub(),alarms=TodoAlarmStub()
            let scheduler=TodoIntentScheduling(notifications:notifications,alarms:alarms,now:{now})
            _ = try await scheduler.reconcile(container:c,requestNotifications:false,requestAlarms:false,isCurrent:{true})
            let native=try XCTUnwrap(alarms.pending.keys.first)
            if ringing {now=fire.addingTimeInterval(1)} else {alarms.pending.removeValue(forKey:native)}
            let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
            await coordinator.reconcile(context:ModelContext(c));await coordinator.reconcile(context:ModelContext(c))
            XCTAssertEqual(alarms.scheduleCalls.count,1)
            XCTAssertEqual(alarms.pending[native] != nil,ringing)
            if ringing {XCTAssertTrue(alarms.cancelCalls.isEmpty)}
            else {
                XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first?.phaseRawValue,TodoReminderDevicePhase.retired.rawValue)
                let service=TodoTaskService(context:ModelContext(c),now:{now})
                var metadata=try service.draft(id:id);metadata.title="Ordinary metadata"
                // A conservative rule refusal also cannot create a new native identity.
                do {try service.edit(id:id,draft:metadata)} catch {XCTAssertEqual(error as? TodoFailure,.invalidReminderOffset)}
                await coordinator.reconcile(context:ModelContext(c))
                XCTAssertTrue(alarms.pending.isEmpty);XCTAssertEqual(alarms.scheduleCalls.count,1)
            }
        }
    }
}

@MainActor extension ImportExportRecoveryTests {
    func testIntegrationIR02RetiredAlarmQueryFailureStaysLocalBesideHealthyThree() async throws {
        let f=try TransferTestFixture();defer {f.remove()}
        let (c,id,_,now,zone)=try systemLegacyNilStore(f,override:true)
        let fire=try TodoTaskService(context:ModelContext(c)).task(id:id).remindAt!.addingTimeInterval(86460)
        try fix2OldF1Override(c,id:id,fire:fire,now:now.addingTimeInterval(90),zone:zone,channel:.alarm)
        let client=TodoNotificationStub(),alarms=TodoAlarmStub()
        _ = try await TodoIntentScheduling(notifications:client,alarms:alarms,now:{now}).reconcile(container:c,requestNotifications:false,requestAlarms:false,isCurrent:{true})
        let coordinator=TodoReminderCoordinator(client:client,now:{now},sleepPreferences:{.init(enabled:true,minute:540)},sleepHistory:SleepReminderHistory(defaults:nil),alarmClient:alarms)
        await coordinator.reconcile(context:ModelContext(c))
        XCTAssertTrue(alarms.pending.isEmpty)
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first?.phaseRawValue,TodoReminderDevicePhase.retired.rawValue)
        let cold=try PersistenceContainerFactory.makeOnDisk(at:c.configurations.first!.url)
        let healthy=try TodoTaskService(context:ModelContext(cold),now:{now}).create(.init(title:"Healthy despite Alarm query",remindAt:now.addingTimeInterval(3600)))
        var preferences=ImportantDayPreferences();preferences.reminderOffsets=[0]
        let tomorrow=ImportantCivilDay(now,timeZone:.current).adding(days:1)!
        let day=try ImportantDay(title:"Healthy day beside query failure",rule:.init(year:tomorrow.year,month:tomorrow.month,day:tomorrow.day),preferences:preferences)
        cold.mainContext.insert(day);try cold.mainContext.save()
        alarms.failReads=true
        let reopened=TodoReminderCoordinator(client:client,now:{now},sleepPreferences:{.init(enabled:true,minute:540)},sleepHistory:SleepReminderHistory(defaults:nil),alarmClient:alarms)
        await reopened.reconcile(context:ModelContext(cold))
        XCTAssertEqual(reopened.status(for:try TodoTaskService(context:ModelContext(cold)).task(id:id)),.cancellationPending)
        XCTAssertEqual(reopened.status(for:healthy),.scheduled)
        XCTAssertEqual(reopened.status(for:day).status,.scheduled);XCTAssertEqual(reopened.sleepStatus().status,.scheduled)
        alarms.failReads=false
        await reopened.reconcile(context:ModelContext(cold))
        XCTAssertEqual(reopened.status(for:try TodoTaskService(context:ModelContext(cold)).task(id:id)),.legacyRuleNeedsCorrection)
        XCTAssertTrue(alarms.pending.isEmpty);XCTAssertEqual(alarms.scheduleCalls.count,1)
    }
}

private final class IntegrationRawRaceTrace: @unchecked Sendable {
    private let lock=NSLock()
    private var values:[String]=[]
    private var frozen=false
    private var released=false
    let rawRelease=DispatchSemaphore(value:0)
    let attempted=DispatchSemaphore(value:0)
    let probed=DispatchSemaphore(value:0)
    func add(_ value:String) {lock.lock();values.append(value);lock.unlock()}
    func freeze() {lock.lock();frozen=true;values.append("writer-frozen");lock.unlock()}
    func writerReleased() {lock.lock();frozen=false;values.append("writer-released");lock.unlock()}
    func nativeAttempt() {lock.lock();values.append(frozen ? "native-save-held":"native-save-free");lock.unlock()}
    func reset() {lock.lock();values=[];lock.unlock()}
    func snapshot() -> [String] {lock.lock();defer {lock.unlock()};return values}
    func release() {lock.lock();let first = !released;released=true;values.append("release-requested");lock.unlock();if first {rawRelease.signal()}}
}
@MainActor extension ImportExportRecoveryTests {
    func testIntegrationV01RawWriterActualAlarmJournalSaveAndIndependentMainProbe() async throws {
        let f=try TransferTestFixture();defer {f.remove()}
        let root=f.root.appendingPathComponent("RawRace"),url=root.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        let c=try PersistenceContainerFactory.makeOnDisk(at:url),context=c.mainContext,media=MediaStore(rootURL:root)
        context.autosaveEnabled=false
        let now=ImportantCivilDay(identifier:"2026-10-19")!.instant(minutes:600,timeZone:.gmt)!
        let source=root.appendingPathComponent("raw-race-source.png")
        try f.imageData.write(to:source)
        let entry=try EntryCreationService(persistence:ModelContextEntryPersistence(context:context),mediaStore:media,now:{now}).create(.init(body:"Raw race original image",image:MediaSource(url:source,originalFilename:"raw-race-source.png",contentType:"image/png")))
        let asset=try XCTUnwrap(entry.images.first)
        let habit=try HabitService(context:context,now:{now}).create(name:"Raw race retained original")
        let log=try HabitCheckInService(context:context,mediaStore:media,now:{now}).checkIn(habit,draft:.init(occurredAt:now,quantity:2.5,unit:"km",result:"Original raw race result"))
        log.quantity = .infinity;try context.save()
        let task=try TodoTaskService(context:ModelContext(c),now:{now}).create(.init(title:"Actual Alarm disappearance",remindAt:now.addingTimeInterval(3600),reminderChannel:.alarm))
        let trace=IntegrationRawRaceTrace(),notifications=TodoNotificationStub(),alarms=TodoAlarmStub()
        let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms,journalCommit:{write in
            trace.nativeAttempt()
            do {try write.save();trace.add("native-save-success")}
            catch {trace.add("native-save-error");throw error}
        })
        await coordinator.reconcile(context:ModelContext(c))
        XCTAssertEqual(coordinator.status(for:task),.scheduled);XCTAssertEqual(alarms.pending.count,1)
        trace.reset();coordinator.observeSystemChanges(container:c)
        let frozen=expectation(description:"Actual raw BEGIN IMMEDIATE holds writer"),probe=expectation(description:"Independent MainActor probe delivered")
        let exporter=ImportExportService(context:context,mediaStore:media,availableCapacity:{.max},rawCaptureCheckpoint:{phase in
            if phase == "frozen" {
                trace.freeze();frozen.fulfill()
                if trace.rawRelease.wait(timeout:.now()+10) != .success {trace.add("raw-failsafe-timeout")}
            } else if phase == "released" {trace.writerReleased()}
        })
        TodoJournalWriteProbe.willCommit={container in
            if container === c {trace.add("production-journal-entry");trace.attempted.signal()}
        }
        defer {TodoJournalWriteProbe.willCommit=nil;trace.release()}
        let exporting=Task {try await exporter.exportRetainedQuantityData()}
        await fulfillment(of:[frozen],timeout:5)
        let independent=Task.detached {
            if trace.attempted.wait(timeout:.now()+6) == .success {
                trace.add("independent-probe-submitted")
                Task { @MainActor in
                    trace.add("main-probe")
                    XCTAssertEqual(coordinator.status(for:task),.confirmationRequired,"A busy journal must not claim durable success")
                    let service=TodoTaskService(context:ModelContext(c),now:{now})
                    do {
                        var draft=try service.draft(id:task.id);draft.title="Retry after raw capture"
                        XCTAssertThrowsError(try service.edit(id:task.id,draft:draft)) {XCTAssertEqual($0 as? StorePublicationFailure,.busy)}
                        XCTAssertEqual(try service.task(id:task.id).title,"Actual Alarm disappearance")
                        trace.add("todo-command-busy-input-retryable")
                    } catch {XCTFail("Unexpected read failure: \(error)")}
                    probe.fulfill();trace.probed.signal()
                }
                if trace.probed.wait(timeout:.now()+2) != .success {trace.add("probe-failsafe-timeout")}
            } else {trace.add("no-production-save-entry")}
            trace.release()
        }
        // This is the production Alarm observation callback, independent of the raw-export sheet.
        alarms.pending.removeAll();alarms.changed?()
        await fulfillment(of:[probe],timeout:10)
        let raw=try await exporting.value;await independent.value
        let events=trace.snapshot()
        print("PGOS_V01 events=\(events.joined(separator:","))")
        XCTAssertTrue(events.contains("production-journal-entry"))
        XCTAssertFalse(events.contains("native-save-held"),"Publication exclusion must prevent native save while raw writer holds")
        XCTAssertFalse(events.contains("probe-failsafe-timeout"))
        XCTAssertTrue(events.contains("todo-command-busy-input-retryable"))
        let probeIndex=try XCTUnwrap(events.firstIndex(of:"main-probe")),releaseIndex=try XCTUnwrap(events.firstIndex(of:"writer-released"))
        XCTAssertLessThan(probeIndex,releaseIndex,"MainActor must respond before raw writer release")
        let extracted=f.root.appendingPathComponent("raw-race-reopened")
        try ZIPArchiveReader(archiveURL:raw,availableCapacity:.max).extractAll(to:extracted)
        let recovered=try PersistenceContainerFactory.makeOnDisk(at:extracted.appendingPathComponent("Store/PersonalGrowthOS.sqlite"))
        let original=try XCTUnwrap(ModelContext(recovered).fetch(FetchDescriptor<HabitLog>()).first {$0.id == log.id})
        XCTAssertEqual(original.quantity?.bitPattern,Double.infinity.bitPattern);XCTAssertEqual(original.unit,"km");XCTAssertEqual(original.result,"Original raw race result")
        let rawEntry=try XCTUnwrap(ModelContext(recovered).fetch(FetchDescriptor<Entry>()).first {$0.id == entry.id})
        XCTAssertEqual(rawEntry.body,entry.body);XCTAssertEqual(rawEntry.images.first?.id,asset.id)
        XCTAssertEqual(try Data(contentsOf:extracted.appendingPathComponent(asset.relativePath)),f.imageData)
        XCTAssertEqual(try Data(contentsOf:media.fileURL(for:asset.relativePath)),f.imageData)
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<HabitLog>()).first?.quantity?.bitPattern,Double.infinity.bitPattern)
        TodoJournalWriteProbe.willCommit=nil
        let retry=TodoTaskService(context:ModelContext(c),now:{now})
        var draft=try retry.draft(id:task.id);draft.title="Retry after raw capture"
        try retry.edit(id:task.id,draft:draft)
        XCTAssertEqual(try retry.task(id:task.id).title,"Retry after raw capture")
        await coordinator.reconcile(context:ModelContext(c))
        XCTAssertTrue(alarms.pending.isEmpty)
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first?.phaseRawValue,TodoReminderDevicePhase.retired.rawValue)
    }
}

@MainActor extension ImportExportRecoveryTests {
    // V11 fixture followed by the old f1 ordinary-edit transaction: it renewed the
    // changed reminder but left isInstanceOverride=false and did not freeze nil policy.
    func testTerminalRR01OldOrdinaryEditSameValueCorrectionCreatesRealRequest() async throws {
        for channel:TodoReminderChannel in [.notification,.alarm] {
            let f=try TransferTestFixture();defer {f.remove()}
            let (c,id,_,now,zone)=try systemLegacyNilStore(f)
            let original=try TodoTaskService(context:ModelContext(c)).task(id:id).remindAt!
            try fix2OldF1Override(c,id:id,fire:original.addingTimeInterval(60),now:now.addingTimeInterval(60),zone:zone,channel:channel,instanceOverride:false)
            let notifications=TodoNotificationStub(),alarms=TodoAlarmStub()
            let scheduler=TodoIntentScheduling(notifications:notifications,alarms:alarms,now:{now})
            _ = try await scheduler.reconcile(container:c,requestNotifications:false,requestAlarms:false,selectedNotificationTaskIDs:[id],isCurrent:{true})
            let old=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first)
            XCTAssertEqual(old.phaseRawValue,TodoReminderDevicePhase.accepted.rawValue)
            let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
            await coordinator.reconcile(context:ModelContext(c))
            XCTAssertEqual(coordinator.status(for:try TodoTaskService(context:ModelContext(c)).task(id:id)),.legacyRuleNeedsCorrection)
            XCTAssertTrue(notifications.pending.isEmpty);XCTAssertTrue(alarms.pending.isEmpty)
            let service=TodoTaskService(context:ModelContext(c),now:{now},timeZone:{.current})
            let history=try ModelContext(c).fetch(FetchDescriptor<TodoTaskEvent>()).sorted {$0.sequence < $1.sequence}.map(\.afterValue)
            let draft=try service.draft(id:id),planned=draft.plannedDay,deadline=draft.deadlineDay
            let saved=expectation(description:"Actual TodoEditorView same-value future save")
            let window=UIWindow(frame:UIScreen.main.bounds)
            TodoEditorInteractionProbe.loaded={loaded,save in
                TodoEditorInteractionProbe.loaded=nil
                XCTAssertEqual(loaded.remindAt,draft.remindAt);XCTAssertEqual(loaded.reminderChannel,channel)
                save(true)
            }
            window.rootViewController=UIHostingController(rootView:TodoEditorView(task:try service.task(id:id)) {_ in saved.fulfill()}.modelContainer(c).environment(coordinator))
            window.makeKeyAndVisible()
            defer {TodoEditorInteractionProbe.loaded=nil;window.isHidden=true;window.rootViewController=nil}
            await fulfillment(of:[saved],timeout:4)
            XCTAssertEqual(try service.task(id:id).remindAt,draft.remindAt)
            let correctedGeneration=try service.reminderIntent(for:id)?.generation
            // Actual editor submits reconciliation asynchronously after its save callback.
            // Observe that complete command instead of racing a second reconcile caller.
            for _ in 0..<150 {
                if coordinator.status(for:try service.task(id:id)) == .scheduled,
                   (channel == .alarm ? alarms.pending.count:notifications.pending.count) == 1 {break}
                try await Task.sleep(for:.milliseconds(20))
            }
            XCTAssertEqual(coordinator.status(for:try service.task(id:id)),.scheduled)
            try service.edit(id:id,draft:draft,futureSeries:true)
            XCTAssertEqual(try service.reminderIntent(for:id)?.generation,correctedGeneration)
            await coordinator.reconcile(context:ModelContext(c))
            XCTAssertEqual(coordinator.status(for:try service.task(id:id)),.scheduled)
            let intent=try XCTUnwrap(service.reminderIntent(for:id))
            XCTAssertNotEqual(intent.generation,old.intentGeneration)
            XCTAssertEqual(try service.task(id:id).remindAt,draft.remindAt)
            XCTAssertEqual(try service.task(id:id).plannedDay,planned);XCTAssertEqual(try service.task(id:id).deadlineDay,deadline)
            let records=try ModelContext(c).fetch(FetchDescriptor<TodoReminderDeviceRecord>())
            XCTAssertEqual(records.filter {$0.phaseRawValue == TodoReminderDevicePhase.accepted.rawValue}.count,1)
            XCTAssertEqual(channel == .alarm ? alarms.pending.count:notifications.pending.count,1)
            let generation=intent.generation
            try service.edit(id:id,draft:draft,futureSeries:true)
            XCTAssertEqual(try service.reminderIntent(for:id)?.generation,generation,"Committed correction retry must not renew again")
            let cold=try PersistenceContainerFactory.makeOnDisk(at:c.configurations.first!.url)
            let reopened=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
            await reopened.reconcile(context:ModelContext(cold))
            XCTAssertEqual(reopened.status(for:try TodoTaskService(context:ModelContext(cold)).task(id:id)),.scheduled)
            XCTAssertEqual(try ModelContext(cold).fetch(FetchDescriptor<TodoTaskEvent>()).sorted {$0.sequence < $1.sequence}.prefix(history.count).map(\.afterValue),history)
            print("PGOS_RR01 channel=\(channel.rawValue) sameTime=true ordinaryFalse=true nativeCount=\(channel == .alarm ? alarms.pending.count:notifications.pending.count)")
        }
    }
    func testTerminalRR02ActualSleepObserveRawWriterAndRecovery() async throws {
        let f=try TransferTestFixture();defer {f.remove()}
        let root=f.root.appendingPathComponent("SleepRawRace"),url=root.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        let c=try PersistenceContainerFactory.makeOnDisk(at:url),media=MediaStore(rootURL:root)
        var clock=ImportantCivilDay(identifier:"2026-10-19")!.instant(minutes:600,timeZone:.current)!
        let service=SleepService(context:c.mainContext,now:{clock})
        try service.setGoal(cutoffMinute:1410);try service.setGoal(cutoffMinute:60)
        clock=ImportantCivilDay(identifier:"2026-10-20")!.instant(minutes:600,timeZone:.current)!
        let workspace=SleepWorkspace(now:{clock}),trace=IntegrationRawRaceTrace()
        let frozen=expectation(description:"Sleep real raw writer held"),probe=expectation(description:"Sleep independent main probe")
        let exporter=ImportExportService(context:c.mainContext,mediaStore:media,availableCapacity:{.max},rawCaptureCheckpoint:{phase in
            if phase == "frozen" {trace.freeze();frozen.fulfill();if trace.rawRelease.wait(timeout:.now()+10) != .success {trace.add("raw-failsafe-timeout")}}
            else if phase == "released" {trace.writerReleased()}
        })
        SleepGoalObservationProbe.willObserve={container in if container === c {trace.add("production-observe-entry");trace.attempted.signal()}}
        SleepGoalObservationProbe.willSave={container in if container === c {trace.nativeAttempt()}}
        defer {SleepGoalObservationProbe.willObserve=nil;SleepGoalObservationProbe.willSave=nil;trace.release()}
        let secondHeld=expectation(description:"Second legitimate publisher acquired before MainActor retry")
        let secondRelease=DispatchSemaphore(value:0),secondAttempt=DispatchSemaphore(value:0)
        var second=false
        var holder:Task<Void,Error>?
        SleepGoalObservationProbe.beforeRetry={container in
            guard container === c,!second else {return};second=true
            holder=Task.detached {
                try StorePublication.perform(at:root) {
                    secondHeld.fulfill()
                    if secondAttempt.wait(timeout:.now()+6) != .success {trace.add("second-attempt-timeout")}
                    secondRelease.signal()
                }
            }
            await self.fulfillment(of:[secondHeld],timeout:4)
            trace.add("second-publisher-held")
        }
        SleepGoalObservationProbe.didDefer={container in
            if container === c,second {trace.add("second-busy-observe");secondAttempt.signal()}
        }
        defer {SleepGoalObservationProbe.beforeRetry=nil;SleepGoalObservationProbe.didDefer=nil;secondAttempt.signal();secondRelease.signal()}
        let exporting=Task {try await exporter.exportRetainedQuantityData()}
        await fulfillment(of:[frozen],timeout:5)
        let independent=Task.detached {
            if trace.attempted.wait(timeout:.now()+6) == .success {
                trace.add("independent-probe-submitted")
                Task { @MainActor in trace.add("main-probe");probe.fulfill();trace.probed.signal() }
                if trace.probed.wait(timeout:.now()+2) != .success {trace.add("probe-failsafe-timeout")}
            } else {trace.add("no-observe-entry")}
            trace.release()
        }
        workspace.refresh(ModelContext(c))
        let held=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<SleepGoalRule>()).first {$0.effectiveDay == "2026-10-20"})
        trace.add(held.hasTakenEffect ? "marker-durable-after-refresh":"marker-pending-after-refresh")
        XCTAssertFalse(held.hasTakenEffect,"Busy must not claim a persisted activation")
        XCTAssertEqual(workspace.loadError,StorePublicationFailure.busy.localizedDescription)
        clock=ImportantCivilDay(identifier:"2026-10-19")!.instant(minutes:600,timeZone:.current)!
        XCTAssertThrowsError(try service.setGoal(cutoffMinute:90)) {XCTAssertEqual($0 as? StorePublicationFailure,.busy)}
        await fulfillment(of:[probe],timeout:10)
        _ = try await exporting.value;await independent.value
        // The production deferred refresh must recover after exclusion is released.
        for _ in 0..<100 {if try ModelContext(c).fetch(FetchDescriptor<SleepGoalRule>()).first(where:{$0.effectiveDay == "2026-10-20"})?.hasTakenEffect == true {break};try await Task.sleep(for:.milliseconds(20))}
        let events=trace.snapshot();print("PGOS_RR02 events=\(events.joined(separator:","))")
        XCTAssertTrue(events.contains("production-observe-entry"));XCTAssertFalse(events.contains("native-save-held"));XCTAssertFalse(events.contains("probe-failsafe-timeout"))
        XCTAssertLessThan(try XCTUnwrap(events.firstIndex(of:"main-probe")),try XCTUnwrap(events.firstIndex(of:"writer-released")))
        XCTAssertTrue(try ModelContext(c).fetch(FetchDescriptor<SleepGoalRule>()).first {$0.effectiveDay == "2026-10-20"}!.hasTakenEffect)
        XCTAssertNil(workspace.loadError)
        try await holder?.value
        XCTAssertTrue(events.contains("second-publisher-held"));XCTAssertTrue(events.contains("second-busy-observe"));XCTAssertFalse(events.contains("second-attempt-timeout"))
        clock=ImportantCivilDay(identifier:"2026-10-19")!.instant(minutes:600,timeZone:.current)!
        XCTAssertThrowsError(try service.setGoal(cutoffMinute:90))
    }
}

@MainActor extension ImportExportRecoveryTests {
    func testTerminalRR01CorrectionRollbackCancellationOwnershipAndMetadataDoNotRevive() async throws {
        for channel:TodoReminderChannel in [.notification,.alarm] {
            for source in 0..<2 { // old ordinary edit and old deleteList timestamp update
                let f=try TransferTestFixture();defer {f.remove()}
                let (c,id,list,now,zone)=try systemLegacyNilStore(f)
                let fire=try TodoTaskService(context:ModelContext(c)).task(id:id).remindAt!
                if source == 0 {
                    try fix2OldF1Override(c,id:id,fire:fire.addingTimeInterval(60),now:now.addingTimeInterval(60),zone:zone,channel:channel,instanceOverride:false)
                } else {
                    // Exact old f1 deleteList effects: unlink tasks/events, unlink rule,
                    // update technical timestamp, without later offset preservation.
                    let write=ModelContext(c);write.autosaveEnabled=false
                    let task=try TodoTaskService(context:write).task(id:id),before=try JSONEncoder().encode(TodoEventValue(task))
                    task.listID=nil;task.revision += 1;task.updatedAt=now.addingTimeInterval(60)
                    write.insert(TodoTaskEvent(taskID:id,sequence:task.revision,kind:.edited,occurredAt:now,createdAt:task.updatedAt,beforeValue:before,afterValue:try JSONEncoder().encode(TodoEventValue(task))))
                    let rule=try XCTUnwrap(write.fetch(FetchDescriptor<TodoSeries>()).first);rule.listID=nil;rule.updatedAt=now.addingTimeInterval(60)
                    write.insert(TodoReminderIntent(taskID:id,channel:channel))
                    write.delete(try XCTUnwrap(write.fetch(FetchDescriptor<TodoList>()).first {$0.id == list}));try write.save()
                    try TodoIntegrity.validate(context:ModelContext(c));try UsagePreferencesIntegrity.validate(context:ModelContext(c))
                }
                let notifications=TodoNotificationStub(),alarms=TodoAlarmStub()
                let scheduling=TodoIntentScheduling(notifications:notifications,alarms:alarms,now:{now})
                _ = try await scheduling.reconcile(container:c,requestNotifications:false,requestAlarms:false,selectedNotificationTaskIDs:[id],isCurrent:{true})
                let original=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first)
                XCTAssertEqual(original.phaseRawValue,TodoReminderDevicePhase.accepted.rawValue)
                notifications.failedRemovalIdentifiers=[TodoIntentScheduling.identifier(original.id)];alarms.failCancel=true
                let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
                await coordinator.reconcile(context:ModelContext(c))
                let service=TodoTaskService(context:ModelContext(c),now:{now},timeZone:{.current}),draft=try service.draft(id:id)
                let before=try TransferSnapshot.make(context:ModelContext(c))
                let failing=TodoTaskService(context:ModelContext(c),now:{now},timeZone:{.current},save:{throw CocoaError(.fileWriteOutOfSpace)})
                XCTAssertThrowsError(try failing.edit(id:id,draft:draft,futureSeries:true))
                XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(c)),before)
                try service.edit(id:id,draft:draft,futureSeries:true)
                let generation=try service.reminderIntent(for:id)?.generation
                XCTAssertNotEqual(generation,original.intentGeneration)
                await coordinator.reconcile(context:ModelContext(c))
                XCTAssertEqual(coordinator.status(for:try service.task(id:id)),.cancellationPending)
                XCTAssertEqual(channel == .alarm ? alarms.pending.count:notifications.pending.count,1,"Unconfirmed old ownership prevents parallel replacement")
                notifications.failedRemovalIdentifiers=[];alarms.failCancel=false
                let cold=try PersistenceContainerFactory.makeOnDisk(at:c.configurations.first!.url)
                let reopened=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
                await reopened.reconcile(context:ModelContext(cold))
                XCTAssertEqual(reopened.status(for:try TodoTaskService(context:ModelContext(cold)).task(id:id)),.scheduled)
                XCTAssertEqual(channel == .alarm ? alarms.pending.count:notifications.pending.count,1)
                // A subsequent external System Stop is terminal under title-only editing.
                notifications.pending.removeAll();alarms.pending.removeAll()
                await reopened.reconcile(context:ModelContext(cold))
                let fresh=TodoTaskService(context:ModelContext(cold),now:{now})
                var metadata=try fresh.draft(id:id);metadata.title="Metadata after System Stop"
                try fresh.edit(id:id,draft:metadata,futureSeries:true)
                await reopened.reconcile(context:ModelContext(cold))
                XCTAssertEqual(try fresh.reminderIntent(for:id)?.generation,generation)
                XCTAssertTrue(notifications.pending.isEmpty);XCTAssertTrue(alarms.pending.isEmpty)
                XCTAssertEqual(reopened.status(for:try fresh.task(id:id)),.stopped)
            }
        }
    }
}

// Frozen f1b52b58 TodoTaskService, renamed only. Executes the real old transition,
// successor generation and deleteList transactions; never used by production.
@MainActor
private final class TerminalRecheckOldF1Service {
    private let context: ModelContext
    private let now: () -> Date
    private let timeZone: () -> TimeZone
    private let save: () throws -> Void
    init(context: ModelContext, now: @escaping () -> Date = Date.init,
         timeZone: @escaping () -> TimeZone = { .current }, save: (() throws -> Void)? = nil) {
        self.context = context; self.now = now; self.timeZone = timeZone
        self.save = save ?? { try context.save() }
    }
    private func transaction<T>(_ operation: () throws -> T) throws -> T {
        do { let result = try operation(); try save(); NotificationCenter.default.post(name: .todoTasksChanged, object: context.container); return result }
        catch { context.rollback(); throw error }
    }
    func task(id: UUID) throws -> TodoTask {
        guard let task = try context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == id })).first else { throw TodoFailure.missingTask }
        return task
    }
    private func requireList(_ id: UUID?) throws {
        if let id, try context.fetchCount(FetchDescriptor<TodoList>(predicate: #Predicate { $0.id == id })) != 1 { throw TodoFailure.missingList }
    }
    private func setReminderWallTime(_ task: TodoTask, from instant: Date?) {
        guard task.seriesID != nil, let instant else {
            task.reminderTimeZoneID = nil; task.reminderLocalDay = nil; task.reminderMinutes = nil
            return
        }
        let zone = timeZone()
        let parts = WeeklyReviewCalendarPolicy.calendar(timeZone: zone).dateComponents([.hour, .minute], from: instant)
        task.reminderTimeZoneID = zone.identifier
        task.reminderLocalDay = TodoDay(date: instant, timeZone: zone).description
        task.reminderMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
    private func series(_ id: UUID) throws -> TodoSeries {
        guard let value = try context.fetch(FetchDescriptor<TodoSeries>(predicate: #Predicate { $0.id == id })).first else { throw TodoFailure.invalidSeries }
        return value
    }
    private func record(_ task: TodoTask, kind: TodoEventKind, before: TodoEventValue?, at date: Date) throws {
        if before != nil { task.revision += 1 }
        task.updatedAt = TechnicalTimestamp.updated(now: date, createdAt: task.createdAt, previous: task.updatedAt)
        context.insert(TodoTaskEvent(taskID: task.id, sequence: task.revision, kind: kind,
            occurredAt: date, createdAt: task.updatedAt,
            beforeValue: try before.map { try JSONEncoder().encode($0) },
            afterValue: try JSONEncoder().encode(TodoEventValue(task))))
    }
    private func makeSeries(_ draft: TodoDraft, at date: Date) throws -> TodoSeries {
        guard let frequency = draft.frequency, let anchor = draft.plannedDay ?? draft.deadlineDay else { throw TodoFailure.invalidSeries }
        let zone = timeZone()
        let minutes = draft.remindAt.map { instant in
            let parts = WeeklyReviewCalendarPolicy.calendar(timeZone: zone).dateComponents([.hour, .minute], from: instant)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        let offset = try draft.remindAt.map { try TodoRecurrence.reminderOffset(localDay: TodoDay(date: $0, timeZone: zone).description, anchor: anchor) }
        let series=TodoSeries(frequency: frequency, anchorDay: anchor, draft: draft, reminderMinutes: minutes, reminderDayOffset: offset, createdAt: date)
        if frequency == .customWeekdays || (draft.reminderChannel ?? .notification) != .notification {
            context.insert(TodoSeriesPreferences(seriesID:series.id,weekdaysMask:frequency == .customWeekdays ? try TodoWeekdayRule.mask(draft.weekdays) : nil,channel:draft.reminderChannel ?? .notification))
        }
        return series
    }
    @discardableResult
    func create(_ draft: TodoDraft, sourceEntryID: UUID? = nil, id: UUID = UUID(), importantDayID: UUID? = nil, importantDayOccurrence: ImportantCivilDay? = nil) throws -> TodoTask {
        try draft.validate(); try requireList(draft.listID)
        if let sourceEntryID, try context.fetchCount(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == sourceEntryID })) != 1 { throw TodoFailure.missingSource }
        var relatedDay: ImportantDay?
        if let importantDayID {
            guard draft.frequency == nil, importantDayOccurrence.map({ $0.date != nil }) ?? true,
                  let day = try context.fetch(FetchDescriptor<ImportantDay>(predicate: #Predicate { $0.id == importantDayID })).first,
                  !day.isArchived else { throw TodoFailure.missingSource }
            relatedDay = day
        }
        // A caller retry uses the same identity; never overwrite its already committed content.
        if let existing = try context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == id })).first { return existing }
        let date = now()
        return try transaction {
            var seriesID: UUID?
            if draft.frequency != nil {
                let series = try makeSeries(draft, at: date)
                context.insert(series); seriesID = series.id
            }
            let task = TodoTask(id: id, title: draft.title, notes: draft.notes, isImportant: draft.isImportant,
                plannedDay: draft.plannedDay, deadlineDay: draft.deadlineDay, remindAt: draft.remindAt,
                listID: draft.listID, seriesID: seriesID, occurrenceIndex: seriesID == nil ? nil : 0, createdAt: date)
            setReminderWallTime(task, from: draft.remindAt)
            context.insert(task)
            try setIntent(task,channel:draft.reminderChannel ?? .notification,override:false,renew:false)
            try record(task, kind: .created, before: nil, at: date)
            if let sourceEntryID { context.insert(TodoTaskSource(taskID: task.id, entryID: sourceEntryID)) }
            if let relatedDay { context.insert(ImportantDayTodoLink(dayID: relatedDay.id, taskID: task.id,
                occurrence: importantDayOccurrence, dayRevisionAtLink: relatedDay.revision, createdAt: date)) }
            return task
        }
    }
    func preferences(for seriesID: UUID) throws -> TodoSeriesPreferences? {
        try context.fetch(FetchDescriptor<TodoSeriesPreferences>(predicate:#Predicate {$0.id == seriesID})).first
    }
    func occurrence(_ rule: TodoSeries,index: Int) throws -> TodoDay {
        guard let frequency=TodoFrequency(rawValue:rule.frequencyRawValue) else {throw TodoFailure.invalidSeries}
        return try TodoRecurrence.day(anchor:rule.anchorDay,frequency:frequency,index:index,weekdaysMask:preferences(for:rule.id)?.weekdaysMask)
    }
    func reminderIntent(for id: UUID) throws -> TodoReminderIntent? {
        try context.fetch(FetchDescriptor<TodoReminderIntent>(predicate:#Predicate {$0.id == id})).first
    }
    func draft(id: UUID) throws -> TodoDraft {
        let task=try task(id:id)
        var draft=TodoDraft(task)
        if let intent=try reminderIntent(for:id) {
            guard let channel=TodoReminderChannel(rawValue:intent.channelRawValue) else {throw TodoFailure.corruptData}
            draft.reminderChannel=channel
        }
        if let seriesID=task.seriesID,let mask=try preferences(for:seriesID)?.weekdaysMask {draft.weekdays=try TodoWeekdayRule.weekdays(mask)}
        return draft
    }
    private func setIntent(_ task: TodoTask,channel: TodoReminderChannel,override: Bool,renew: Bool) throws {
        if let intent=try reminderIntent(for:task.id) {
            if renew || intent.channelRawValue != channel.rawValue || intent.isInstanceOverride != override {
                guard intent.revision >= 0,intent.revision < Int.max-1 else {throw TodoFailure.corruptData}
                intent.generation=UUID();intent.revision += 1;intent.channelRawValue=channel.rawValue;intent.isInstanceOverride=override
            }
        } else if task.remindAt != nil || channel != .notification || override {
            context.insert(TodoReminderIntent(taskID:task.id,channel:channel,isInstanceOverride:override))
        }
    }
    /// A deliberate current-occurrence reminder; never changes the plan, deadline or series anchor.
    func rescheduleReminder(id: UUID,to fireAt: Date,channel: TodoReminderChannel? = nil,
                            expectedRevision: Int? = nil,commit: ((ModelContext) throws -> Void)? = nil) throws {
        let write=ModelContext(context.container);write.autosaveEnabled=false
        let writer=TerminalRecheckOldF1Service(context:write,now:now,timeZone:timeZone,save:{try (commit ?? {try $0.save()})(write)})
        try writer.rescheduleOwnedReminder(id:id,to:fireAt,channel:channel,expectedRevision:expectedRevision)
    }
    private func rescheduleOwnedReminder(id: UUID,to fireAt: Date,channel: TodoReminderChannel?,expectedRevision: Int?) throws {
        let task=try task(id:id)
        if let expectedRevision,expectedRevision != task.revision {throw TodoFailure.staleTask}
        guard task.state == .open,fireAt.timeIntervalSinceReferenceDate.isFinite,fireAt > now() else {throw TodoFailure.invalidReminder}
        if let seriesID=task.seriesID,try series(seriesID).isStopped {throw TodoFailure.invalidSeries}
        let existing=try reminderIntent(for:id)
        let selected=try channel ?? existing.map {value in
            guard let channel=TodoReminderChannel(rawValue:value.channelRawValue) else {throw TodoFailure.corruptData};return channel
        } ?? .notification
        try transaction {
            guard task.state == .open,fireAt > now() else {throw TodoFailure.invalidReminder}
            let before=try TodoEventValue(task)
            task.remindAt=fireAt;setReminderWallTime(task,from:fireAt)
            try setIntent(task,channel:selected,override:task.seriesID != nil,renew:true)
            try record(task,kind:.edited,before:before,at:now())
        }
    }
    private func reminderOffset(for rule: TodoSeries) throws -> Int {
        if let offset = rule.reminderDayOffset { return offset }
        // Old V11 candidates have no offset. Recover the first matching saved wall-day
        // without changing task/event bytes; an absent reminder needs no policy.
        guard let minutes = rule.reminderMinutes, TodoFrequency(rawValue: rule.frequencyRawValue) != nil else { return 0 }
        let id = rule.id
        let candidates = try context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.seriesID == id }))
            .filter { $0.reminderMinutes == minutes && $0.reminderLocalDay != nil }
            .sorted { ($0.occurrenceIndex ?? 0) < ($1.occurrenceIndex ?? 0) }
        guard let first = candidates.first, let index = first.occurrenceIndex, let local = first.reminderLocalDay else { return 0 }
        return try TodoRecurrence.reminderOffset(localDay: local, anchor: occurrence(rule,index:index).description)
    }
    private func applyTemplate(_ rule: TodoSeries, to task: TodoTask, at date: Date) throws {
        let before = try TodoEventValue(task),oldReminder=task.remindAt
        task.title = rule.title; task.notes = rule.notes; task.isImportant = rule.isImportant; task.listID = rule.listID
        try applyReminder(rule, to: task)
        let channel=try preferences(for:rule.id).flatMap {TodoReminderChannel(rawValue:$0.reminderChannelRawValue)} ?? .notification
        try setIntent(task,channel:channel,override:false,renew:oldReminder != task.remindAt)
        try record(task, kind: .edited, before: before, at: date)
    }
    private func applyReminder(_ rule: TodoSeries, to task: TodoTask) throws {
        guard let minutes = rule.reminderMinutes else {
            task.remindAt = nil; setReminderWallTime(task, from: nil); return
        }
        guard TodoFrequency(rawValue: rule.frequencyRawValue) != nil, let index = task.occurrenceIndex else { throw TodoFailure.invalidSeries }
        let occurrence = try occurrence(rule,index:index)
        let day = try TodoRecurrence.reminderDay(occurrence: occurrence, offset: reminderOffset(for: rule))
        guard let reminder = TodoRecurrence.reminder(day: day, minutes: minutes, timeZone: timeZone()) else { throw TodoFailure.invalidReminder }
        task.remindAt = reminder; task.reminderLocalDay = day.description
        task.reminderMinutes = minutes; task.reminderTimeZoneID = timeZone().identifier
    }
    func edit(id: UUID, draft: TodoDraft, futureSeries: Bool = false) throws {
        try draft.validate(); try requireList(draft.listID)
        let task = try task(id: id)
        if let frequency = draft.frequency {
            guard task.state == .open else { throw TodoFailure.conversionRequiresOpen }
            if let seriesID = task.seriesID {
                let rule = try series(seriesID)
                var existing = try self.draft(id:task.id); existing.frequency = frequency
                var requested=draft
                let current=existing.reminderChannel ?? .notification
                existing.reminderChannel=current;requested.reminderChannel=draft.reminderChannel ?? current
                let history = try context.fetch(FetchDescriptor<TodoTaskEvent>(predicate: #Predicate { $0.taskID == id }))
                // A committed conversion retry is idempotent, not an arbitrary rule edit.
                guard rule.frequencyRawValue == frequency.rawValue, existing == requested,
                      history.contains(where: { $0.kindRawValue == TodoEventKind.convertedToSeries.rawValue }) else { throw TodoFailure.invalidSeries }
                return
            }
        }
        let previousIntent=try reminderIntent(for:id)
        let currentChannel=previousIntent.flatMap {TodoReminderChannel(rawValue:$0.channelRawValue)} ?? .notification
        let selectedChannel=draft.reminderChannel ?? currentChannel
        let reminderChanged=task.remindAt != draft.remindAt
        let retainOverride=previousIntent?.isInstanceOverride == true && !reminderChanged && !futureSeries && draft.remindAt != nil
        try transaction {
            let before = try TodoEventValue(task)
            if draft.frequency != nil {
                let rule = try makeSeries(draft, at: now())
                context.insert(rule)
                task.seriesID = rule.id; task.occurrenceIndex = 0; task.occurrenceKey = "\(rule.id.uuidString)/0"
                setReminderWallTime(task, from: draft.remindAt)
            }
            task.title = draft.title; task.notes = draft.notes; task.isImportant = draft.isImportant
            task.plannedDay = draft.plannedDay; task.deadlineDay = draft.deadlineDay
            if task.remindAt != draft.remindAt { setReminderWallTime(task, from: draft.remindAt) }
            task.remindAt = draft.remindAt; task.listID = draft.listID
            if !retainOverride,let seriesID = task.seriesID, let local = task.reminderLocalDay, let index = task.occurrenceIndex {
                let rule = try series(seriesID)
                guard TodoFrequency(rawValue: rule.frequencyRawValue) != nil else { throw TodoFailure.invalidSeries }
                _ = try TodoRecurrence.reminderOffset(localDay: local, anchor: occurrence(rule,index:index).description)
            }
            if futureSeries, let seriesID = task.seriesID {
                let series = try series(seriesID)
                series.title = draft.title; series.notes = draft.notes; series.isImportant = draft.isImportant
                series.listID = draft.listID
                if let preference=try preferences(for:seriesID) {preference.reminderChannelRawValue=selectedChannel.rawValue}
                else if selectedChannel != .notification {context.insert(TodoSeriesPreferences(seriesID:seriesID,channel:selectedChannel))}
                series.reminderMinutes = task.reminderMinutes
                if let local = task.reminderLocalDay, let index = task.occurrenceIndex, TodoFrequency(rawValue: series.frequencyRawValue) != nil {
                    series.reminderDayOffset = try TodoRecurrence.reminderOffset(localDay: local, anchor: occurrence(series,index:index).description)
                } else { series.reminderDayOffset = nil }
                for successor in try context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.seriesID == seriesID }))
                    where successor.id != task.id && successor.state == .open && (successor.occurrenceIndex ?? -1) > (task.occurrenceIndex ?? -1) {
                    try applyTemplate(series, to: successor, at: now())
                }
                series.updatedAt = TechnicalTimestamp.updated(now: now(), createdAt: series.createdAt, previous: series.updatedAt)
            }
            try setIntent(task,channel:selectedChannel,override:retainOverride,renew:reminderChanged)
            try record(task, kind: draft.frequency == nil ? .edited : .convertedToSeries, before: before, at: now())
        }
    }
    func transition(id: UUID, to state: TodoTaskState, skip: Bool = false) throws {
        let task = try task(id: id)
        guard task.state != state else { return }
        if skip && (state != .canceled || task.seriesID == nil || task.state != .open) { throw TodoFailure.invalidSeries }
        try transaction {
            let date = now(), before = try TodoEventValue(task)
            if state == .open, let seriesID = task.seriesID {
                let others = try context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.seriesID == seriesID }))
                for other in others where other.id != id && other.state == .open {
                    let value = try TodoEventValue(other)
                    other.stateRawValue = TodoTaskState.canceled.rawValue; other.canceledAt = date; other.completedAt = nil
                    try record(other, kind: .successorWithdrawn, before: value, at: date)
                }
            }
            task.stateRawValue = state.rawValue
            if state == .open,let fire=task.remindAt,fire > now(),
               try task.seriesID.map({try !series($0).isStopped}) ?? true {
                let intent=try reminderIntent(for:id)
                let channel=intent.flatMap {TodoReminderChannel(rawValue:$0.channelRawValue)} ?? .notification
                try setIntent(task,channel:channel,override:intent?.isInstanceOverride ?? false,renew:true)
            }
            task.completedAt = state == .completed ? date : nil
            task.canceledAt = state == .canceled ? date : nil
            try record(task, kind: state == .completed ? .completed : state == .open ? .reopened : skip ? .skipped : .canceled, before: before, at: date)
            if state != .open { try generateNext(after: task, at: date) }
        }
    }
    private func generateNext(after task: TodoTask, at date: Date) throws {
        guard let seriesID = task.seriesID else { return }
        let series = try series(seriesID)
        guard !series.isStopped, let frequency = TodoFrequency(rawValue: series.frequencyRawValue), let index = task.occurrenceIndex else { return }
        let siblings = try context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.seriesID == seriesID }))
        guard !siblings.contains(where: { $0.state == .open }) else { return }
        var next = try TodoRecurrence.nextIndex(anchor: series.anchorDay, frequency: frequency, after: index, today: TodoDay(date: date, timeZone: timeZone()),weekdaysMask:preferences(for:series.id)?.weekdaysMask)
        // Completed or deliberately skipped facts are never reopened as a side effect.
        while let existing = siblings.first(where: { $0.occurrenceIndex == next }) {
            let existingID = existing.id
            let last = try context.fetch(FetchDescriptor<TodoTaskEvent>(predicate: #Predicate { $0.taskID == existingID }))
                .max { $0.sequence < $1.sequence }
            if existing.state == .canceled && last?.kindRawValue == TodoEventKind.successorWithdrawn.rawValue { break }
            next += 1
        }
        if let existing = siblings.first(where: { $0.occurrenceIndex == next }) {
            let before = try TodoEventValue(existing)
            existing.stateRawValue = TodoTaskState.open.rawValue; existing.canceledAt = nil; existing.completedAt = nil
            try record(existing, kind: .reopened, before: before, at: date)
            try applyTemplate(series, to: existing, at: date)
            return
        }
        let occurrence = try occurrence(series,index:next)
        func shifted(_ anchor: String?) throws -> String? {
            try anchor.map { value in
                if [.weekdays,.weekends,.customWeekdays].contains(frequency) {
                    guard let origin=TodoDay(series.anchorDay)?.date(timeZone:TodoRecurrence.utc),let endpoint=TodoDay(value)?.date(timeZone:TodoRecurrence.utc),let base=occurrence.date(timeZone:TodoRecurrence.utc) else {throw TodoFailure.invalidSeries}
                    var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TodoRecurrence.utc
                    let offset=calendar.dateComponents([.day],from:origin,to:endpoint).day!
                    guard let result=calendar.date(byAdding:.day,value:offset,to:base) else {throw TodoFailure.invalidSeries}
                    let day=TodoDay(date:result,timeZone:TodoRecurrence.utc)
                    guard TodoDay(day.description) != nil else {throw TodoFailure.invalidSeries}
                    return day.description
                }
                return try TodoRecurrence.day(anchor:value,frequency:frequency,index:next).description
            }
        }
        let planned = try shifted(series.plannedAnchorDay), deadline = try shifted(series.deadlineAnchorDay)
        let reminderDay = try TodoRecurrence.reminderDay(occurrence: occurrence, offset: reminderOffset(for: series))
        let reminder = series.reminderMinutes.flatMap { TodoRecurrence.reminder(day: reminderDay, minutes: $0, timeZone: timeZone()) }
        let nextTask = TodoTask(title: series.title, notes: series.notes, isImportant: series.isImportant,
            plannedDay: planned, deadlineDay: deadline, remindAt: reminder, listID: series.listID,
            seriesID: seriesID, occurrenceIndex: next, createdAt: date)
        if reminder != nil {
            nextTask.reminderTimeZoneID = timeZone().identifier
            nextTask.reminderLocalDay = reminderDay.description
            nextTask.reminderMinutes = series.reminderMinutes
        }
        context.insert(nextTask)
        let channel=try preferences(for:series.id).flatMap {TodoReminderChannel(rawValue:$0.reminderChannelRawValue)} ?? .notification
        try setIntent(nextTask,channel:channel,override:false,renew:false)
        try record(nextTask, kind: .created, before: nil, at: date)
        let sourceTaskID = task.id
        if let source = try context.fetch(FetchDescriptor<TodoTaskSource>(predicate: #Predicate { $0.taskID == sourceTaskID })).first {
            context.insert(TodoTaskSource(taskID: nextTask.id, entryID: source.entryID))
        }
    }
    func refreshRepeatingReminderTimes() throws {
        let zone = timeZone()
        let tasks = try context.fetch(FetchDescriptor<TodoTask>()).filter {
            $0.state == .open && $0.seriesID != nil && $0.remindAt != nil && $0.reminderTimeZoneID != zone.identifier
        }
        guard !tasks.isEmpty else { return }
        try transaction {
            for task in tasks {
                guard let dayString = task.reminderLocalDay, let day = TodoDay(dayString),
                      let minutes = task.reminderMinutes else { throw TodoFailure.corruptData }
                let before = try TodoEventValue(task)
                guard let adjusted = TodoRecurrence.reminder(day: day, minutes: minutes, timeZone: zone) else { throw TodoFailure.invalidReminder }
                task.remindAt = adjusted; task.reminderTimeZoneID = zone.identifier
                try record(task, kind: .edited, before: before, at: now())
            }
        }
    }
    func stopSeries(taskID: UUID) throws {
        let task = try task(id: taskID)
        guard let seriesID = task.seriesID else { return }
        let series = try series(seriesID)
        guard !series.isStopped else { return }
        try transaction {
            series.isStopped = true
            series.updatedAt = TechnicalTimestamp.updated(now: now(), createdAt: series.createdAt, previous: series.updatedAt)
            try record(task, kind: .seriesStopped, before: TodoEventValue(task), at: now())
        }
    }
    func delete(id: UUID) throws {
        let task = try task(id: id)
        try transaction {
            // Deleting an occurrence stops generation so a restart cannot resurrect it.
            if let seriesID = task.seriesID {
                let series = try series(seriesID); series.isStopped = true
                series.updatedAt = TechnicalTimestamp.updated(now: now(), createdAt: series.createdAt, previous: series.updatedAt)
            }
            try context.fetch(FetchDescriptor<TodoTaskEvent>(predicate: #Predicate { $0.taskID == id })).forEach(context.delete)
            try context.fetch(FetchDescriptor<TodoTaskSource>(predicate: #Predicate { $0.taskID == id })).forEach(context.delete)
            try context.fetch(FetchDescriptor<ImportantDayTodoLink>(predicate: #Predicate { $0.taskID == id })).forEach(context.delete)
            if let intent=try reminderIntent(for:id) {context.delete(intent)}
            context.delete(task)
        }
    }
    func createList(name: String) throws -> TodoList {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 200 else { throw TodoFailure.invalidTitle }
        return try transaction { let list = TodoList(name: name, createdAt: now()); context.insert(list); return list }
    }
    func renameList(id: UUID, name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 200 else { throw TodoFailure.invalidTitle }
        guard let list = try context.fetch(FetchDescriptor<TodoList>(predicate: #Predicate { $0.id == id })).first else { throw TodoFailure.missingList }
        try transaction { list.name = name; list.updatedAt = TechnicalTimestamp.updated(now: now(), createdAt: list.createdAt, previous: list.updatedAt) }
    }
    func deleteList(id: UUID) throws {
        guard let list = try context.fetch(FetchDescriptor<TodoList>(predicate: #Predicate { $0.id == id })).first else { throw TodoFailure.missingList }
        try transaction {
            for task in try context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.listID == id })) {
                let before = try TodoEventValue(task); task.listID = nil
                try record(task, kind: .edited, before: before, at: now())
            }
            for series in try context.fetch(FetchDescriptor<TodoSeries>(predicate: #Predicate { $0.listID == id })) {
                series.listID = nil
                series.updatedAt = TechnicalTimestamp.updated(now: now(), createdAt: series.createdAt, previous: series.updatedAt)
            }
            context.delete(list)
        }
    }
}


@MainActor extension ImportExportRecoveryTests {
    private func recheckPeerZone(for home: TimeZone, at instant: Date) throws -> TimeZone {
        let preferred = ["Asia/Hong_Kong", "Asia/Shanghai", "Africa/Abidjan"]
        let candidates = (preferred + TimeZone.knownTimeZoneIdentifiers).compactMap(TimeZone.init(identifier:))
            + [TimeZone(secondsFromGMT: home.secondsFromGMT(for: instant))!]
        return try XCTUnwrap(candidates.first {
            $0.identifier != home.identifier && $0.secondsFromGMT(for: instant) == home.secondsFromGMT(for: instant)
        })
    }

    private func recheckTerminatedAncestor(_ f:TransferTestFixture, channel:TodoReminderChannel, skipped:Bool, zone:TimeZone = .current) throws -> (ModelContainer,UUID,UUID,Date,TimeZone) {
        let url=f.root.appendingPathComponent("ancestor.sqlite"),id=UUID(),sid=UUID(),list=UUID()
        let now=TodoDay("2026-10-19")!.date(timeZone:zone)!
        let fire=TodoRecurrence.reminder(day:TodoDay("2026-10-20")!,minutes:480,timeZone:zone)!
        try autoreleasepool {
            let schema=Schema(versionedSchema:PersonalGrowthSchemaV11Original.self)
            let old=try ModelContainer(for:schema,configurations:[ModelConfiguration("PersonalGrowthOSV1",schema:schema,url:url,cloudKitDatabase:.none)])
            let draft=TodoDraft(title:"Terminated ancestor",plannedDay:"2026-10-20",deadlineDay:"2026-10-21",remindAt:fire,listID:list,frequency:.daily)
            let task=TodoTask(id:id,title:draft.title,plannedDay:draft.plannedDay,deadlineDay:draft.deadlineDay,remindAt:fire,listID:list,seriesID:sid,occurrenceIndex:0,createdAt:now)
            task.reminderLocalDay="2026-10-20";task.reminderMinutes=480;task.reminderTimeZoneID=zone.identifier
            let entry=Entry(body:"Immutable ancestor source",createdAt:now)
            old.mainContext.insert(entry);old.mainContext.insert(TodoTaskSource(taskID:id,entryID:entry.id))
            old.mainContext.insert(TodoList(id:list,name:"Old f1 deleted list",createdAt:now));old.mainContext.insert(task)
            old.mainContext.insert(PersonalGrowthSchemaV11Original.TodoSeries(id:sid,frequency:.daily,anchorDay:"2026-10-20",draft:draft,reminderMinutes:480,createdAt:now))
            old.mainContext.insert(TodoTaskEvent(taskID:id,sequence:0,kind:.created,occurredAt:now,createdAt:now,beforeValue:nil,afterValue:try JSONEncoder().encode(TodoEventValue(task))))
            try old.mainContext.save()
        }
        let c=try PersistenceContainerFactory.makeOnDisk(at:url)
        let old=TerminalRecheckOldF1Service(context:ModelContext(c),now:{now.addingTimeInterval(60)},timeZone:{zone})
        var draft=try old.draft(id:id);draft.reminderChannel=channel
        try old.edit(id:id,draft:draft)
        try old.transition(id:id,to:skipped ? .canceled:.completed,skip:skipped)
        let successor=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<TodoTask>()).first {$0.state == .open})
        draft=try old.draft(id:successor.id);draft.reminderChannel=channel
        try old.edit(id:successor.id,draft:draft)
        try old.deleteList(id:list)
        let rule=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<TodoSeries>()).first)
        XCTAssertNil(rule.reminderDayOffset);XCTAssertGreaterThan(rule.updatedAt,rule.createdAt)
        XCTAssertEqual(try old.task(id:id).state,skipped ? .canceled:.completed)
        XCTAssertEqual(successor.reminderMinutes,480)
        try TodoIntegrity.validate(context:ModelContext(c));try UsagePreferencesIntegrity.validate(context:ModelContext(c))
        return (c,id,successor.id,now,zone)
    }

    func testRecheckTC01TerminatedAncestorSameValueActualEditorRestoresOnlySuccessor() async throws {
        let home = TimeZone.current
        let reference = TodoDay("2026-10-19")!.date(timeZone: home)!
        let changedZone = try recheckPeerZone(for: home, at: reference)
        for channel:TodoReminderChannel in [.notification,.alarm] {
            for skipped in [false,true] {
                let f=try TransferTestFixture();defer {f.remove()}
                let (c,a,b,now,zone)=try recheckTerminatedAncestor(f,channel:channel,skipped:skipped)
                XCTAssertEqual(zone.identifier, TimeZone.current.identifier, "Return-to-home precondition must hold on every host")
                XCTAssertNotEqual(zone.identifier,changedZone.identifier);XCTAssertEqual(zone.secondsFromGMT(for:now),changedZone.secondsFromGMT(for:now))
                let originalFire = try XCTUnwrap(TodoTaskService(context: ModelContext(c)).task(id: b).remindAt)
                XCTAssertEqual(zone.secondsFromGMT(for: originalFire), changedZone.secondsFromGMT(for: originalFire))
                let notifications=TodoNotificationStub(),alarms=TodoAlarmStub()
                let scheduling=TodoIntentScheduling(notifications:notifications,alarms:alarms,now:{now})
                _ = try await scheduling.reconcile(container:c,requestNotifications:false,requestAlarms:false,selectedNotificationTaskIDs:[b],isCurrent:{true})
                let old=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first {$0.taskID == b})
                XCTAssertEqual(old.phaseRawValue,TodoReminderDevicePhase.accepted.rawValue)
                let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
                let unresolved=try TodoTaskService(context:ModelContext(c),now:{now},timeZone:{changedZone}).refreshRepeatingReminderTimes()
                XCTAssertEqual(unresolved,[b])
                _ = try await scheduling.quarantineFutureRequests(container:c,taskIDs:unresolved,isCurrent:{true})
                await coordinator.reconcile(context:ModelContext(c))
                XCTAssertTrue(notifications.pending.isEmpty);XCTAssertTrue(alarms.pending.isEmpty)
                XCTAssertEqual(coordinator.status(for:try TodoTaskService(context:ModelContext(c)).task(id:b)),.stopped,"Returning to the original device zone must not revive the quarantined generation")
                let service=TodoTaskService(context:ModelContext(c)),draft=try service.draft(id:a)
                let before=try TransferSnapshot.make(context:ModelContext(c)),originalB=try TodoEventValue(service.task(id:b))
                let sourceGeneration=try service.reminderIntent(for:a)?.generation
                let saved=expectation(description:"Terminated ancestor actual editor applied future")
                let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap {$0 as? UIWindowScene}.first)
                let window=UIWindow(windowScene:scene);window.frame=UIScreen.main.bounds;window.windowLevel = .normal + 1
                TodoEditorInteractionProbe.loaded={loaded,save in
                    TodoEditorInteractionProbe.loaded=nil
                    XCTAssertEqual(loaded.remindAt,draft.remindAt);XCTAssertEqual(loaded.reminderChannel,channel)
                    save(true)
                }
                window.rootViewController=UIHostingController(rootView:TodoEditorView(task:try service.task(id:a)) {_ in saved.fulfill()}.modelContainer(c).environment(coordinator))
                window.makeKeyAndVisible()
                defer {TodoEditorInteractionProbe.loaded=nil;window.isHidden=true;window.rootViewController=nil}
                await fulfillment(of:[saved],timeout:4)
                for _ in 0..<150 {
                    if coordinator.status(for:try service.task(id:b)) == .scheduled {break}
                    try await Task.sleep(for:.milliseconds(20))
                }
                XCTAssertEqual(coordinator.status(for:try service.task(id:b)),.scheduled,"Same UTC instant must not accidentally supply renewal")
                let intent=try XCTUnwrap(service.reminderIntent(for:b)),generation=intent.generation
                XCTAssertNotEqual(generation,old.intentGeneration)
                XCTAssertEqual(channel == .alarm ? alarms.pending.count:notifications.pending.count,1)
                if channel == .alarm {XCTAssertNil(alarms.pending[old.id])}
                else {XCTAssertNil(notifications.pending[TodoIntentScheduling.identifier(old.id)])}
                XCTAssertEqual(try service.task(id:a).state,skipped ? .canceled:.completed)
                XCTAssertEqual(try service.reminderIntent(for:a)?.generation,sourceGeneration,"Terminated source does not receive a renewed correction intent")
                XCTAssertEqual(try service.task(id:b).remindAt,originalB.remindAt)
                XCTAssertEqual(try service.task(id:b).plannedDay,originalB.plannedDay);XCTAssertEqual(try service.task(id:b).deadlineDay,originalB.deadlineDay)
                try service.edit(id:a,draft:draft,futureSeries:true)
                XCTAssertEqual(try service.reminderIntent(for:b)?.generation,generation)
                let cold=try PersistenceContainerFactory.makeOnDisk(at:c.configurations.first!.url)
                let reopened=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
                await reopened.reconcile(context:ModelContext(cold))
                XCTAssertEqual(reopened.status(for:try TodoTaskService(context:ModelContext(cold)).task(id:b)),.scheduled)
                XCTAssertEqual(try TodoTaskService(context:ModelContext(cold)).task(id:a).state,skipped ? .canceled:.completed)
                let after=try TransferSnapshot.make(context:ModelContext(cold))
                XCTAssertEqual(before.entries,after.entries);XCTAssertEqual(before.todoSources,after.todoSources)
                XCTAssertTrue(before.todoEvents.allSatisfy {after.todoEvents.contains($0)},"Existing history is immutable")
                XCTAssertEqual(after.todoSeries.first?.reminderDayOffset,0)
                // Healthy explicit future metadata and a stopped series do not
                // turn an external System Stop into a new scheduling intent.
                notifications.pending.removeAll();alarms.pending.removeAll()
                await reopened.reconcile(context:ModelContext(cold))
                let fresh=TodoTaskService(context:ModelContext(cold))
                var metadata=try fresh.draft(id:a);metadata.title="Ancestor metadata after System Stop"
                try fresh.edit(id:a,draft:metadata,futureSeries:true)
                await reopened.reconcile(context:ModelContext(cold))
                XCTAssertEqual(try fresh.reminderIntent(for:b)?.generation,generation)
                XCTAssertTrue(notifications.pending.isEmpty);XCTAssertTrue(alarms.pending.isEmpty)
                XCTAssertEqual(reopened.status(for:try fresh.task(id:b)),.stopped)
                try fresh.stopSeries(taskID:a)
                metadata.title="Metadata of stopped series"
                try fresh.edit(id:a,draft:metadata,futureSeries:true)
                await reopened.reconcile(context:ModelContext(cold))
                XCTAssertEqual(try fresh.reminderIntent(for:b)?.generation,generation)
                XCTAssertTrue(notifications.pending.isEmpty);XCTAssertTrue(alarms.pending.isEmpty)
                print("PGOS_TC01 actualEditor=true source=\(skipped ? "canceled":"completed") channel=\(channel.rawValue) old=\(old.id) new=\(generation) native=\(channel == .alarm ? alarms.pending.count:notifications.pending.count) sameOffset=true")
            }
        }
    }

    func testCIFixtureDifferentDeviceZoneKeepsTerminatedAncestorSuccessorQuarantined() async throws {
        let home = TimeZone.current
        let reference = TodoDay("2026-10-19")!.date(timeZone: home)!
        let originalZone = try recheckPeerZone(for: home, at: reference)
        for channel: TodoReminderChannel in [.notification, .alarm] {
            for skipped in [false, true] {
                let fixture = try TransferTestFixture(); defer { fixture.remove() }
                let (container, ancestor, successor, now, zone) = try recheckTerminatedAncestor(fixture, channel: channel, skipped: skipped, zone: originalZone)
                XCTAssertNotEqual(zone.identifier, TimeZone.current.identifier)
                XCTAssertEqual(home.identifier, TimeZone.current.identifier)
                XCTAssertEqual(zone.secondsFromGMT(for: now), home.secondsFromGMT(for: now))
                let originalTask = try TodoEventValue(TodoTaskService(context: ModelContext(container)).task(id: successor))
                let fire = try XCTUnwrap(originalTask.remindAt)
                XCTAssertEqual(zone.secondsFromGMT(for: fire), home.secondsFromGMT(for: fire))
                let notifications = TodoNotificationStub(), alarms = TodoAlarmStub()
                let scheduling = TodoIntentScheduling(notifications: notifications, alarms: alarms, now: { now })
                _ = try await scheduling.reconcile(container: container, requestNotifications: false, requestAlarms: false, selectedNotificationTaskIDs: [successor], isCurrent: { true })
                let record = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first { $0.taskID == successor })
                XCTAssertEqual(record.phaseRawValue, TodoReminderDevicePhase.accepted.rawValue)
                XCTAssertEqual(channel == .alarm ? alarms.pending.count : notifications.pending.count, 1)
                let snapshot = try TransferSnapshot.make(context: ModelContext(container))
                let before = try XCTUnwrap(TodoTaskService(context: ModelContext(container)).reminderIntent(for: successor)?.generation)
                let unresolved = try TodoTaskService(context: ModelContext(container), now: { now }, timeZone: { home }).refreshRepeatingReminderTimes()
                XCTAssertEqual(unresolved, [successor])
                _ = try await scheduling.quarantineFutureRequests(container: container, taskIDs: unresolved, isCurrent: { true })
                let coordinator = TodoReminderCoordinator(client: notifications, now: { now }, sleepPreferences: { .init() }, alarmClient: alarms)
                await coordinator.reconcile(context: ModelContext(container))
                let service = TodoTaskService(context: ModelContext(container))
                XCTAssertEqual(coordinator.status(for: try service.task(id: successor)), .legacyRuleNeedsCorrection)
                XCTAssertTrue(notifications.pending.isEmpty); XCTAssertTrue(alarms.pending.isEmpty)
                XCTAssertEqual(try service.reminderIntent(for: successor)?.generation, before)
                XCTAssertEqual(try service.task(id: ancestor).state, skipped ? .canceled : .completed)
                XCTAssertEqual(try service.task(id: successor).remindAt, originalTask.remindAt)
                XCTAssertEqual(try service.task(id: successor).plannedDay, originalTask.plannedDay)
                XCTAssertEqual(try service.task(id: successor).deadlineDay, originalTask.deadlineDay)
                let after = try TransferSnapshot.make(context: ModelContext(container))
                XCTAssertEqual(snapshot.entries, after.entries); XCTAssertEqual(snapshot.todoSources, after.todoSources)
                XCTAssertEqual(snapshot.todoEvents, after.todoEvents)
            }
        }
    }

    func testRecheckTC01TerminatedAncestorRollbackAndUnconfirmedCancellation() async throws {
        let home = TimeZone.current
        let changedZone = try recheckPeerZone(for: home, at: TodoDay("2026-10-19")!.date(timeZone: home)!)
        for channel:TodoReminderChannel in [.notification,.alarm] {
            for skipped in [false,true] {
                let f=try TransferTestFixture();defer {f.remove()}
                let (c,a,b,now,_)=try recheckTerminatedAncestor(f,channel:channel,skipped:skipped)
                let notifications=TodoNotificationStub(),alarms=TodoAlarmStub()
                let scheduling=TodoIntentScheduling(notifications:notifications,alarms:alarms,now:{now})
                _ = try await scheduling.reconcile(container:c,requestNotifications:false,requestAlarms:false,selectedNotificationTaskIDs:[b],isCurrent:{true})
                let old=try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first {$0.taskID == b})
                notifications.failedRemovalIdentifiers=[TodoIntentScheduling.identifier(old.id)];alarms.failCancel=true
                let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
                let unresolved=try TodoTaskService(context:ModelContext(c),now:{now},timeZone:{changedZone}).refreshRepeatingReminderTimes()
                XCTAssertEqual(unresolved,[b])
                _ = try await scheduling.quarantineFutureRequests(container:c,taskIDs:unresolved,isCurrent:{true})
                await coordinator.reconcile(context:ModelContext(c))
                let service=TodoTaskService(context:ModelContext(c),now:{now}),draft=try service.draft(id:a)
                let before=try TransferSnapshot.make(context:ModelContext(c))
                let failing=TodoTaskService(context:ModelContext(c),now:{now},save:{throw CocoaError(.fileWriteOutOfSpace)})
                XCTAssertThrowsError(try failing.edit(id:a,draft:draft,futureSeries:true))
                XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(c)),before)
                try service.edit(id:a,draft:draft,futureSeries:true)
                XCTAssertNotEqual(try service.reminderIntent(for:b)?.generation,old.intentGeneration)
                await coordinator.reconcile(context:ModelContext(c))
                XCTAssertEqual(coordinator.status(for:try service.task(id:b)),.cancellationPending)
                XCTAssertEqual(channel == .alarm ? alarms.pending.count:notifications.pending.count,1)
                notifications.failedRemovalIdentifiers=[];alarms.failCancel=false
                let cold=try PersistenceContainerFactory.makeOnDisk(at:c.configurations.first!.url)
                let reopened=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
                await reopened.reconcile(context:ModelContext(cold))
                XCTAssertEqual(reopened.status(for:try TodoTaskService(context:ModelContext(cold)).task(id:b)),.scheduled)
                XCTAssertEqual(channel == .alarm ? alarms.pending.count:notifications.pending.count,1)
                XCTAssertEqual(try TodoTaskService(context:ModelContext(cold)).task(id:a).state,skipped ? .canceled:.completed)
            }
        }
    }
}
