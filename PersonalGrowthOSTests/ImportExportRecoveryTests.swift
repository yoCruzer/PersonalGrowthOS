import CryptoKit
import Foundation
import SwiftData
import UIKit
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
                "todoTasks": 0, "todoEvents": 0, "todoLists": 0, "todoSeries": 0, "todoSources": 0
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
        try? FileManager.default.removeItem(at: root)
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
        if manifest.packageSchemaVersion < 7 && data.todoTasks.isEmpty && data.todoEvents.isEmpty && data.todoLists.isEmpty && data.todoSeries.isEmpty && data.todoSources.isEmpty {
            // Emit the actual legacy wire shape. Never strip non-empty new payloads.
            var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedData) as? [String: Any])
            for key in ["todoTasks", "todoEvents", "todoLists", "todoSeries", "todoSources"] { payload.removeValue(forKey: key) }
            encodedData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
        }
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
                // V4/V5 fixtures must preserve their historical wire format after the V7 exporter adds Todo arrays.
                for key in ["todoTasks", "todoEvents", "todoLists", "todoSeries", "todoSources"] { payload.removeValue(forKey: key) }
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
        let reminderClient = TodoNotificationStub(), reminders = TodoReminderCoordinator(client: reminderClient)
        await reminders.reconcile(context: reopened.mainContext)
        let restoredOpen = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<TodoTask>()).first { $0.state == .open })
        XCTAssertEqual(reminders.status(for: restoredOpen), .scheduled)
        XCTAssertEqual(Set(reminderClient.pending.keys), [TodoReminderCoordinator.identifier(restoredOpen.id)])
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

    func testV7RequiresTodoArraysAndLegacyClaimsRejectEvenEmptyNewKeys() async throws {
        let fixture = try TransferTestFixture(); defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage(); defer { lease.cleanup() }
        for scenario in 0..<3 {
            let corrupt = try mutatePackage(lease.url, under: fixture.root.appendingPathComponent("TodoWire\(scenario)"), mutation: { root, manifest, data in
                let version = scenario == 2 ? 6 : 7
                let url = root.appendingPathComponent("data.json")
                var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
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
