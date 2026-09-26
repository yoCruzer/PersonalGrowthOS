import Foundation
import SwiftData
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import PersonalGrowthOS

@MainActor
final class PersistenceMediaFoundationTests: XCTestCase {
    func testRepositorySavesFetchesAndUpdatesCanonicalEntry() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let repository = EntryRepository(context: container.mainContext)
        let date = Date(timeIntervalSince1970: 1_000)
        let entry = Entry(body: "Original", createdAt: date)

        try repository.save(entry)
        entry.body = "Updated"
        entry.updatedAt = Date(timeIntervalSince1970: 2_000)
        try repository.saveChanges()

        let fetched = try XCTUnwrap(repository.fetch(id: entry.id))
        XCTAssertTrue(fetched === entry)
        XCTAssertEqual(fetched.body, "Updated")
        XCTAssertEqual(try repository.fetchAll().map(\.id), [entry.id])
    }

    func testOnDiskStoreReopensWithSameAppOwnedIdentity() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let entryID = UUID()

        try saveFixtureEntry(id: entryID, storeURL: fixture.storeURL)

        let reopened = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
        let repository = EntryRepository(context: reopened.mainContext)
        let entry = try XCTUnwrap(repository.fetch(id: entryID))
        XCTAssertEqual(entry.id, entryID)
        XCTAssertEqual(entry.body, "Persistent")
    }

    func testMediaStoreCopiesOriginalAndReturnsRelativeMetadata() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let bytes = fixturePNG(color: .red)
        try bytes.write(to: fixture.sourceURL)
        let store = MediaStore(rootURL: fixture.mediaRoot)

        let stored = try store.storeOriginal(MediaSource(
            url: fixture.sourceURL,
            originalFilename: "memory.png",
            contentType: "image/png"
        ))

        XCTAssertFalse(stored.relativePath.hasPrefix("/"))
        XCTAssertEqual(stored.byteCount, Int64(bytes.count))
        XCTAssertEqual(try Data(contentsOf: store.fileURL(for: stored.relativePath)), bytes)
        XCTAssertEqual(stored.checksum.count, 64)
        XCTAssertEqual(stored.pixelWidth, 4)
        XCTAssertEqual(stored.pixelHeight, 4)
    }

    func testCreationPersistsRelativeMetadataWithoutImageBinary() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let bytes = fixturePNG(color: .blue)
        try bytes.write(to: fixture.sourceURL)
        let container = try PersistenceContainerFactory.makeInMemory()
        let persistence = ModelContextEntryPersistence(context: container.mainContext)
        let service = EntryCreationService(
            persistence: persistence,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot),
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let entry = try service.create(EntryCreationDraft(
            image: MediaSource(
                url: fixture.sourceURL,
                originalFilename: "memory.png",
                contentType: "image/png"
            )
        ))

        let metadata = try XCTUnwrap(entry.images.first)
        XCTAssertEqual(entry.images.count, 1)
        XCTAssertFalse(metadata.relativePath.hasPrefix("/"))
        XCTAssertEqual(metadata.byteCount, Int64(bytes.count))
        XCTAssertEqual(metadata.entry?.id, entry.id)
    }

    func testSaveFailureRemovesOnlyNewlyCreatedOriginal() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let bytes = fixturePNG(color: .green)
        try bytes.write(to: fixture.sourceURL)
        let persistence = FailingEntryPersistence()
        let mediaStore = MediaStore(rootURL: fixture.mediaRoot)
        let service = EntryCreationService(persistence: persistence, mediaStore: mediaStore)

        XCTAssertThrowsError(try service.create(EntryCreationDraft(
            body: "Draft remains with caller",
            image: MediaSource(
                url: fixture.sourceURL,
                originalFilename: "memory.png",
                contentType: "image/png"
            )
        )))

        XCTAssertTrue(persistence.didRollback)
        XCTAssertEqual(try fixture.originalFiles(), [])
        XCTAssertEqual(try Data(contentsOf: fixture.sourceURL), bytes)
    }

    func testIdentityCollisionDoesNotDeleteExistingOriginal() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let firstBytes = fixturePNG(color: .red)
        let secondBytes = fixturePNG(color: .blue)
        try firstBytes.write(to: fixture.sourceURL)
        let store = MediaStore(rootURL: fixture.mediaRoot)
        let imageID = UUID()
        let source = MediaSource(
            url: fixture.sourceURL,
            originalFilename: "memory.png",
            contentType: "image/png"
        )
        let stored = try store.storeOriginal(source, id: imageID)
        try secondBytes.write(to: fixture.sourceURL)

        XCTAssertThrowsError(try store.storeOriginal(source, id: imageID)) {
            XCTAssertEqual($0 as? MediaStoreError, .destinationAlreadyExists)
        }
        XCTAssertEqual(try Data(contentsOf: store.fileURL(for: stored.relativePath)), firstBytes)
    }

    func testMissingSourcePublishesNoEntryOrFile() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let persistence = RecordingEntryPersistence()
        let service = EntryCreationService(
            persistence: persistence,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot)
        )

        XCTAssertThrowsError(try service.create(EntryCreationDraft(
            image: MediaSource(
                url: fixture.sourceURL,
                originalFilename: "missing.png",
                contentType: "image/png"
            )
        ))) {
            XCTAssertEqual($0 as? MediaStoreError, .sourceMissing)
        }
        XCTAssertNil(persistence.insertedEntry)
        XCTAssertEqual(try fixture.originalFiles(), [])
    }

    func testInsufficientCapacityPublishesNoEntryOrFile() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let bytes = fixturePNG(color: .orange)
        try bytes.write(to: fixture.sourceURL)
        let persistence = RecordingEntryPersistence()
        let service = EntryCreationService(
            persistence: persistence,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { 1 })
        )

        XCTAssertThrowsError(try service.create(EntryCreationDraft(
            body: "Keep this draft",
            image: MediaSource(
                url: fixture.sourceURL,
                originalFilename: "memory.png",
                contentType: "image/png"
            )
        ))) {
            XCTAssertEqual(
                $0 as? MediaStoreError,
                .insufficientCapacity(
                    requiredBytes: Int64(bytes.count * 2) + MediaStore.capacitySafetyReserve,
                    availableBytes: 1
                )
            )
        }
        XCTAssertNil(persistence.insertedEntry)
        XCTAssertEqual(try fixture.originalFiles(), [])
    }

    func testMultiImageCreationPreservesOrderingAndCleansPartialFailure() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let secondURL = fixture.root.appendingPathComponent("second.png")
        try fixturePNG(color: .red).write(to: fixture.sourceURL)
        try fixturePNG(color: .blue).write(to: secondURL)
        let first = MediaSource(
            url: fixture.sourceURL,
            originalFilename: "first.png",
            contentType: "image/png"
        )
        let second = MediaSource(
            url: secondURL,
            originalFilename: "second.png",
            contentType: "image/png"
        )
        let container = try PersistenceContainerFactory.makeInMemory()
        let service = EntryCreationService(
            persistence: ModelContextEntryPersistence(context: container.mainContext),
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        )

        let entry = try service.create(EntryCreationDraft(images: [first, second]))

        XCTAssertEqual(entry.images.sorted(by: { $0.sortOrder < $1.sortOrder }).map(\.originalFilename), ["first.png", "second.png"])
        XCTAssertEqual(try fixture.originalFiles().count, 2)

        let failingFixture = try TemporaryFixture()
        defer { failingFixture.remove() }
        try fixturePNG(color: .green).write(to: failingFixture.sourceURL)
        let invalidURL = failingFixture.root.appendingPathComponent("invalid.bin")
        try fixturePNG(color: .black).write(to: invalidURL)
        let recording = RecordingEntryPersistence()
        let failingService = EntryCreationService(
            persistence: recording,
            mediaStore: MediaStore(rootURL: failingFixture.mediaRoot, availableCapacity: { .max })
        )

        XCTAssertThrowsError(try failingService.create(EntryCreationDraft(images: [
            MediaSource(url: failingFixture.sourceURL, originalFilename: "valid.png", contentType: "image/png"),
            MediaSource(url: invalidURL, originalFilename: "invalid.bin", contentType: "application/octet-stream")
        ])))
        XCTAssertNil(recording.insertedEntry)
        XCTAssertEqual(try failingFixture.originalFiles(), [])
    }

    func testPermanentDeleteRestoresOriginalWhenDatabaseSaveFails() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let bytes = fixturePNG(color: .purple)
        try bytes.write(to: fixture.sourceURL)
        let mediaStore = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        let stored = try mediaStore.storeOriginal(MediaSource(
            url: fixture.sourceURL,
            originalFilename: "memory.png",
            contentType: "image/png"
        ))
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let metadata = ImageMetadata(
            id: stored.id,
            relativePath: stored.relativePath,
            originalFilename: "memory.png",
            contentType: "image/png",
            byteCount: stored.byteCount,
            pixelWidth: stored.pixelWidth,
            pixelHeight: stored.pixelHeight,
            checksum: stored.checksum,
            createdAt: timestamp
        )
        let entry = Entry(createdAt: timestamp, images: [metadata])
        metadata.entry = entry
        let persistence = FailingDeletionPersistence()
        let service = EntryDeletionService(persistence: persistence, mediaStore: mediaStore)

        XCTAssertThrowsError(try service.permanentlyDelete(entry))

        XCTAssertTrue(persistence.didRollback)
        XCTAssertEqual(try Data(contentsOf: mediaStore.fileURL(for: stored.relativePath)), bytes)
    }

    func testArchivePreservesMediaAndPermanentDeleteRemovesIt() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        try fixturePNG(color: .brown).write(to: fixture.sourceURL)
        let container = try PersistenceContainerFactory.makeInMemory()
        let persistence = ModelContextEntryPersistence(context: container.mainContext)
        let mediaStore = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        let creation = EntryCreationService(persistence: persistence, mediaStore: mediaStore)
        let entry = try creation.create(EntryCreationDraft(image: MediaSource(
            url: fixture.sourceURL,
            originalFilename: "memory.png",
            contentType: "image/png"
        )))
        let originalPath = try XCTUnwrap(entry.images.first?.relativePath)
        let deletion = EntryDeletionService(persistence: persistence, mediaStore: mediaStore)

        try deletion.archive(entry)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try mediaStore.fileURL(for: originalPath).path))

        try deletion.permanentlyDelete(entry)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try mediaStore.fileURL(for: originalPath).path))
    }

    func testPermanentDeleteRemovesOnlySelectedEntryAndItsOriginal() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let secondURL = fixture.root.appendingPathComponent("second.png")
        try fixturePNG(color: .brown).write(to: fixture.sourceURL)
        try fixturePNG(color: .cyan).write(to: secondURL)
        let container = try PersistenceContainerFactory.makeInMemory()
        let persistence = ModelContextEntryPersistence(context: container.mainContext)
        let mediaStore = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        let creation = EntryCreationService(persistence: persistence, mediaStore: mediaStore)
        let first = try creation.create(EntryCreationDraft(
            body: "Delete me",
            image: MediaSource(url: fixture.sourceURL, originalFilename: "first.png", contentType: "image/png")
        ))
        let second = try creation.create(EntryCreationDraft(
            body: "Keep me",
            image: MediaSource(url: secondURL, originalFilename: "second.png", contentType: "image/png")
        ))
        let firstPath = try XCTUnwrap(first.images.first?.relativePath)
        let secondPath = try XCTUnwrap(second.images.first?.relativePath)

        try EntryDeletionService(persistence: persistence, mediaStore: mediaStore).permanentlyDelete(first)

        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Entry>()).map(\.id), [second.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: try mediaStore.fileURL(for: firstPath).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try mediaStore.fileURL(for: secondPath).path))
    }

    func testEditingReplacesTextDateAndImagesAtomically() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let secondURL = fixture.root.appendingPathComponent("second.png")
        try fixturePNG(color: .red).write(to: fixture.sourceURL)
        try fixturePNG(color: .blue).write(to: secondURL)
        let container = try PersistenceContainerFactory.makeInMemory()
        let persistence = ModelContextEntryPersistence(context: container.mainContext)
        let mediaStore = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        let entry = try EntryCreationService(persistence: persistence, mediaStore: mediaStore).create(
            EntryCreationDraft(
                body: "Before",
                image: MediaSource(
                    url: fixture.sourceURL,
                    originalFilename: "first.png",
                    contentType: "image/png"
                )
            )
        )
        let oldPath = try XCTUnwrap(entry.images.first?.relativePath)
        let occurredAt = Date(timeIntervalSince1970: 500)

        try EntryEditingService(persistence: persistence, mediaStore: mediaStore).update(
            entry,
            with: EntryEditingDraft(
                title: "Changed",
                body: "After",
                occurredAt: occurredAt,
                retainedImageIDs: [],
                addedImages: [MediaSource(
                    url: secondURL,
                    originalFilename: "second.png",
                    contentType: "image/png"
                )]
            )
        )

        XCTAssertEqual(entry.title, "Changed")
        XCTAssertEqual(entry.body, "After")
        XCTAssertEqual(entry.occurredAt, occurredAt)
        XCTAssertEqual(entry.images.map(\.originalFilename), ["second.png"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: try mediaStore.fileURL(for: oldPath).path))
        XCTAssertEqual(try fixture.originalFiles().count, 1)
    }

    func testEditingFailureRestoresEntryAndOriginalMedia() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let secondURL = fixture.root.appendingPathComponent("second.png")
        let originalBytes = fixturePNG(color: .red)
        try originalBytes.write(to: fixture.sourceURL)
        try fixturePNG(color: .blue).write(to: secondURL)
        let mediaStore = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        let stored = try mediaStore.storeOriginal(MediaSource(
            url: fixture.sourceURL,
            originalFilename: "first.png",
            contentType: "image/png"
        ))
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let metadata = ImageMetadata(
            id: stored.id,
            relativePath: stored.relativePath,
            originalFilename: "first.png",
            contentType: "image/png",
            byteCount: stored.byteCount,
            pixelWidth: stored.pixelWidth,
            pixelHeight: stored.pixelHeight,
            checksum: stored.checksum,
            createdAt: timestamp
        )
        let entry = Entry(body: "Before", createdAt: timestamp, images: [metadata])
        metadata.entry = entry
        let persistence = FailingEditingPersistence()

        XCTAssertThrowsError(try EntryEditingService(
            persistence: persistence,
            mediaStore: mediaStore
        ).update(entry, with: EntryEditingDraft(
            title: nil,
            body: "After",
            occurredAt: timestamp,
            retainedImageIDs: [],
            addedImages: [MediaSource(
                url: secondURL,
                originalFilename: "second.png",
                contentType: "image/png"
            )]
        )))

        XCTAssertTrue(persistence.didRollback)
        XCTAssertEqual(entry.body, "Before")
        XCTAssertEqual(entry.images.map(\.id), [stored.id])
        XCTAssertEqual(try Data(contentsOf: mediaStore.fileURL(for: stored.relativePath)), originalBytes)
        XCTAssertEqual(try fixture.originalFiles().count, 1)
    }

    func testThumbnailCacheIsReproducibleAndDoesNotChangeOriginal() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let bytes = fixturePNG(color: .cyan)
        try bytes.write(to: fixture.sourceURL)
        let mediaStore = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        let stored = try mediaStore.storeOriginal(MediaSource(
            url: fixture.sourceURL,
            originalFilename: "memory.png",
            contentType: "image/png"
        ))
        let metadata = ImageMetadata(
            id: stored.id,
            relativePath: stored.relativePath,
            originalFilename: "memory.png",
            contentType: "image/png",
            byteCount: stored.byteCount,
            pixelWidth: stored.pixelWidth,
            pixelHeight: stored.pixelHeight,
            checksum: stored.checksum,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let thumbnailStore = ThumbnailStore(
            rootURL: fixture.root.appendingPathComponent("Thumbnails", isDirectory: true),
            mediaStore: mediaStore
        )

        XCTAssertNotNil(thumbnailStore.image(for: metadata))
        XCTAssertNotNil(thumbnailStore.image(for: metadata))
        XCTAssertEqual(try Data(contentsOf: mediaStore.fileURL(for: stored.relativePath)), bytes)

        thumbnailStore.removeThumbnail(for: metadata.id)
        XCTAssertNotNil(thumbnailStore.image(for: metadata))
    }

    func testInterruptedTrashRecoveryUsesDatabaseOwnership() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let bytes = fixturePNG(color: .magenta)
        try bytes.write(to: fixture.sourceURL)
        let mediaStore = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        let stored = try mediaStore.storeOriginal(MediaSource(
            url: fixture.sourceURL,
            originalFilename: "memory.png",
            contentType: "image/png"
        ))

        _ = try mediaStore.moveToTrash(stored.relativePath)
        try mediaStore.recoverInterruptedTrash(referencedOriginalPaths: [stored.relativePath])
        XCTAssertEqual(try Data(contentsOf: mediaStore.fileURL(for: stored.relativePath)), bytes)

        _ = try mediaStore.moveToTrash(stored.relativePath)
        try mediaStore.recoverInterruptedTrash(referencedOriginalPaths: [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: try mediaStore.fileURL(for: stored.relativePath).path))
    }

    func testOriginalByteLimitAcceptsBoundaryAndRejectsAboveBeforeCopying() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let atLimit = pngByPaddingToByteCount(
            fixturePNG(color: .orange),
            byteCount: Int(MediaStore.maximumOriginalByteCount)
        )
        try atLimit.write(to: fixture.sourceURL)
        let mediaStore = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        let stored = try mediaStore.storeOriginal(MediaSource(
            url: fixture.sourceURL,
            originalFilename: "at-limit.png",
            contentType: "image/png"
        ))
        XCTAssertEqual(stored.byteCount, MediaStore.maximumOriginalByteCount)
        XCTAssertEqual(try Data(contentsOf: mediaStore.fileURL(for: stored.relativePath)), atLimit)

        let handle = try FileHandle(forWritingTo: fixture.sourceURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0]))
        try handle.close()

        XCTAssertThrowsError(try mediaStore.storeOriginal(MediaSource(
            url: fixture.sourceURL,
            originalFilename: "oversized.png",
            contentType: "image/png"
        ))) {
            XCTAssertEqual(
                $0 as? MediaStoreError,
                .originalTooLarge(maximumBytes: MediaStore.maximumOriginalByteCount)
            )
        }
        XCTAssertEqual(try fixture.originalFiles().count, 1)
    }

    func testRichEntriesAndImageOrderingSurviveOnDiskReopen() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let secondURL = fixture.root.appendingPathComponent("second.png")
        let firstBytes = fixturePNG(color: .red)
        let secondBytes = fixturePNG(color: .blue)
        try firstBytes.write(to: fixture.sourceURL)
        try secondBytes.write(to: secondURL)
        let mediaStore = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        let textID: UUID
        let imageID: UUID
        let mixedID: UUID
        var expectedMixedChecksums: [String] = []

        do {
            let container = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
            let persistence = ModelContextEntryPersistence(context: container.mainContext)
            let creation = EntryCreationService(
                persistence: persistence,
                mediaStore: mediaStore,
                now: { Date(timeIntervalSince1970: 1_000) }
            )
            let text = try creation.create(EntryCreationDraft(body: "Text only"))
            let image = try creation.create(EntryCreationDraft(image: MediaSource(
                url: fixture.sourceURL,
                originalFilename: "image-only.png",
                contentType: "image/png"
            )))
            let mixed = try creation.create(EntryCreationDraft(
                body: "Mixed",
                images: [
                    MediaSource(url: fixture.sourceURL, originalFilename: "first.png", contentType: "image/png"),
                    MediaSource(url: secondURL, originalFilename: "second.png", contentType: "image/png")
                ]
            ))
            let reversedIDs = mixed.images
                .sorted(by: { $0.sortOrder > $1.sortOrder })
                .map(\.id)
            try EntryEditingService(persistence: persistence, mediaStore: mediaStore).update(
                mixed,
                with: EntryEditingDraft(
                    title: "Reordered",
                    body: "Mixed after edit",
                    occurredAt: Date(timeIntervalSince1970: 900),
                    retainedImageIDs: reversedIDs,
                    addedImages: []
                )
            )
            textID = text.id
            imageID = image.id
            mixedID = mixed.id
            expectedMixedChecksums = mixed.images
                .sorted(by: { $0.sortOrder < $1.sortOrder })
                .map(\.checksum)
        }

        let reopened = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
        let repository = EntryRepository(context: reopened.mainContext)
        XCTAssertEqual(try XCTUnwrap(repository.fetch(id: textID)).body, "Text only")
        let imageEntry = try XCTUnwrap(repository.fetch(id: imageID))
        XCTAssertEqual(imageEntry.images.map(\.originalFilename), ["image-only.png"])
        let mixedEntry = try XCTUnwrap(repository.fetch(id: mixedID))
        XCTAssertEqual(mixedEntry.title, "Reordered")
        XCTAssertEqual(mixedEntry.body, "Mixed after edit")
        let reopenedImages = mixedEntry.images.sorted(by: { $0.sortOrder < $1.sortOrder })
        XCTAssertEqual(reopenedImages.map(\.originalFilename), ["second.png", "first.png"])
        XCTAssertEqual(reopenedImages.map(\.checksum), expectedMixedChecksums)
        XCTAssertEqual(try Data(contentsOf: mediaStore.fileURL(for: reopenedImages[0].relativePath)), secondBytes)
        XCTAssertEqual(try Data(contentsOf: mediaStore.fileURL(for: reopenedImages[1].relativePath)), firstBytes)
    }

    func testRepositoryTieBreakerIsStableAcrossReopen() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let date = Date(timeIntervalSince1970: 1_000)
        do {
            let container = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
            let repository = EntryRepository(context: container.mainContext)
            try repository.save(Entry(body: "One", createdAt: date))
            try repository.save(Entry(body: "Two", createdAt: date))
        }
        let firstReopen = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
        let firstOrder = try EntryRepository(context: firstReopen.mainContext).fetchAll().map(\.id)
        let secondReopen = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
        let secondOrder = try EntryRepository(context: secondReopen.mainContext).fetchAll().map(\.id)
        XCTAssertEqual(firstOrder, secondOrder)
    }

    func testMultiImageFailureMatrixLeavesOnlyUnrelatedOriginal() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let secondURL = fixture.root.appendingPathComponent("second.png")
        let thirdURL = fixture.root.appendingPathComponent("third.png")
        try fixturePNG(color: .red).write(to: fixture.sourceURL)
        try fixturePNG(color: .blue).write(to: secondURL)
        try fixturePNG(color: .green).write(to: thirdURL)
        let sources = [
            MediaSource(url: fixture.sourceURL, originalFilename: "first.png", contentType: "image/png"),
            MediaSource(url: secondURL, originalFilename: "second.png", contentType: "image/png"),
            MediaSource(url: thirdURL, originalFilename: "third.png", contentType: "image/png")
        ]
        let unrelatedStore = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        let unrelated = try unrelatedStore.storeOriginal(sources[2])
        let failingStore = MediaStore(
            rootURL: fixture.mediaRoot,
            availableCapacity: { .max },
            beforeStoreCopy: { copyNumber in
                if copyNumber == 2 { throw InjectedMediaFailure.copy }
            }
        )
        let recording = RecordingEntryPersistence()

        XCTAssertThrowsError(try EntryCreationService(
            persistence: recording,
            mediaStore: failingStore
        ).create(EntryCreationDraft(images: sources)))
        XCTAssertNil(recording.insertedEntry)
        XCTAssertEqual(try fixture.originalFiles().map(\.lastPathComponent), [
            try unrelatedStore.fileURL(for: unrelated.relativePath).lastPathComponent
        ])
        XCTAssertEqual(try fixture.stagingFiles(), [])

        let aggregateBytes = try sources.reduce(Int64(0)) {
            $0 + Int64((try FileManager.default.attributesOfItem(atPath: $1.url.path)[.size] as? NSNumber)?.intValue ?? 0)
        }
        let lowCapacityStore = MediaStore(
            rootURL: fixture.mediaRoot,
            availableCapacity: { aggregateBytes * 2 + MediaStore.capacitySafetyReserve - 1 }
        )
        XCTAssertThrowsError(try EntryCreationService(
            persistence: RecordingEntryPersistence(),
            mediaStore: lowCapacityStore
        ).create(EntryCreationDraft(images: sources))) {
            guard case MediaStoreError.insufficientCapacity = $0 else {
                return XCTFail("Expected aggregate capacity rejection, got \($0)")
            }
        }
        XCTAssertEqual(try fixture.originalFiles().count, 1)

        XCTAssertThrowsError(try EntryCreationService(
            persistence: FailingEntryPersistence(),
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        ).create(EntryCreationDraft(images: sources)))
        XCTAssertEqual(try fixture.originalFiles().count, 1)
    }

    func testRollbackRestoreFailureIsReportedAndRecoveredOnNextLaunch() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let bytes = fixturePNG(color: .purple)
        try bytes.write(to: fixture.sourceURL)
        let initialStore = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        let stored = try initialStore.storeOriginal(MediaSource(
            url: fixture.sourceURL,
            originalFilename: "memory.png",
            contentType: "image/png"
        ))
        let metadata = ImageMetadata(
            id: stored.id,
            relativePath: stored.relativePath,
            originalFilename: "memory.png",
            contentType: "image/png",
            byteCount: stored.byteCount,
            checksum: stored.checksum,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let entry = Entry(createdAt: Date(timeIntervalSince1970: 1_000), images: [metadata])
        metadata.entry = entry
        let restoreFailingStore = MediaStore(
            rootURL: fixture.mediaRoot,
            availableCapacity: { .max },
            beforeTrashRestore: { throw InjectedMediaFailure.restore }
        )

        XCTAssertThrowsError(try EntryDeletionService(
            persistence: FailingDeletionPersistence(),
            mediaStore: restoreFailingStore
        ).permanentlyDelete(entry)) {
            XCTAssertEqual($0 as? EntryMediaOperationError, .rollbackIncomplete)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: try initialStore.fileURL(for: stored.relativePath).path))

        let launchStore = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        try launchStore.recoverInterruptedTrash(referencedOriginalPaths: [stored.relativePath])
        XCTAssertEqual(try Data(contentsOf: launchStore.fileURL(for: stored.relativePath)), bytes)
    }

    func testMediaReconciliationPreservesOrphansAndReportsMissingReferences() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let bytes = fixturePNG(color: .cyan)
        try bytes.write(to: fixture.sourceURL)
        let store = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        let orphan = try store.storeOriginal(MediaSource(
            url: fixture.sourceURL,
            originalFilename: "orphan.png",
            contentType: "image/png"
        ))
        let stagingURL = fixture.mediaRoot.appendingPathComponent("Staging/interrupted.png")
        try FileManager.default.createDirectory(at: stagingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: stagingURL)
        let missingPath = "Media/Originals/00/missing.png"

        let report = try store.reconcile(referencedOriginalPaths: [missingPath])

        XCTAssertEqual(report.removedStagingFileCount, 1)
        XCTAssertEqual(report.missingOriginalPaths, [missingPath])
        XCTAssertEqual(report.recoveryFilePaths.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try store.fileURL(for: orphan.relativePath).path))
        XCTAssertEqual(try Data(contentsOf: store.fileURL(for: report.recoveryFilePaths[0])), bytes)
    }

    func testPixelLimitAcceptsBoundaryAndRejectsAboveBoundary() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let atLimit = try solidGrayscalePNG(width: 10_000, height: 8_000)
        try atLimit.write(to: fixture.sourceURL)
        let store = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        let stored = try store.storeOriginal(MediaSource(
            url: fixture.sourceURL,
            originalFilename: "at-limit.png",
            contentType: "image/png"
        ))
        XCTAssertEqual(stored.pixelWidth * stored.pixelHeight, MediaStore.maximumPixelCount)
        XCTAssertEqual(try Data(contentsOf: store.fileURL(for: stored.relativePath)), atLimit)

        let aboveLimitURL = fixture.root.appendingPathComponent("above-limit.png")
        try solidGrayscalePNG(width: 10_000, height: 8_001).write(to: aboveLimitURL)
        XCTAssertThrowsError(try store.storeOriginal(MediaSource(
            url: aboveLimitURL,
            originalFilename: "above-limit.png",
            contentType: "image/png"
        ))) {
            XCTAssertEqual(
                $0 as? MediaStoreError,
                .imageTooLarge(maximumPixels: MediaStore.maximumPixelCount)
            )
        }
    }

    func testBoundaryMediaResourceMeasurements() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let byteBoundaryURL = fixture.root.appendingPathComponent("byte-boundary.png")
        let pixelBoundaryURL = fixture.root.appendingPathComponent("pixel-boundary.png")
        try pngByPaddingToByteCount(
            fixturePNG(color: .orange),
            byteCount: Int(MediaStore.maximumOriginalByteCount)
        ).write(to: byteBoundaryURL)
        try solidGrayscalePNG(width: 10_000, height: 8_000).write(to: pixelBoundaryURL)
        let measuredRoot = fixture.root.appendingPathComponent("MeasuredMedia", isDirectory: true)
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(
            metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTStorageMetric()],
            options: options
        ) {
            try? FileManager.default.removeItem(at: measuredRoot)
            autoreleasepool {
                do {
                    let store = MediaStore(rootURL: measuredRoot, availableCapacity: { .max })
                    let stored = try store.storeOriginal(MediaSource(
                        url: byteBoundaryURL,
                        originalFilename: "byte-boundary.png",
                        contentType: "image/png"
                    ))
                    let preview = try XCTUnwrap(ThumbnailStore.downsampledImage(
                        at: pixelBoundaryURL,
                        maximumPixelSize: 512
                    ))
                    XCTAssertEqual(stored.byteCount, MediaStore.maximumOriginalByteCount)
                    XCTAssertLessThanOrEqual(max(preview.cgImage?.width ?? .max, preview.cgImage?.height ?? .max), 512)
                } catch {
                    XCTFail("Boundary measurement failed: \(error)")
                }
            }
        }

        let measuredStore = MediaStore(rootURL: measuredRoot, availableCapacity: { .max })
        XCTAssertEqual(try measuredStore.originalsByteCount(), MediaStore.maximumOriginalByteCount)
        XCTAssertEqual(try regularFileByteCount(at: measuredRoot.appendingPathComponent("Staging")), 0)
    }

    func testStartupMediaReconciliationIsIntegratedAndIdempotent() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let bytes = fixturePNG(color: .magenta)
        let orphanURL = fixture.root.appendingPathComponent("orphan.png")
        try bytes.write(to: fixture.sourceURL)
        try fixturePNG(color: .cyan).write(to: orphanURL)
        let mediaStore = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        let referenced = try mediaStore.storeOriginal(MediaSource(
            url: fixture.sourceURL,
            originalFilename: "referenced.png",
            contentType: "image/png"
        ))
        let orphan = try mediaStore.storeOriginal(MediaSource(
            url: orphanURL,
            originalFilename: "orphan.png",
            contentType: "image/png"
        ))
        let missingID = UUID()
        let missingPath = "Media/Originals/00/missing.png"
        do {
            let container = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
            let timestamp = Date(timeIntervalSince1970: 1_000)
            let referencedMetadata = ImageMetadata(
                id: referenced.id,
                relativePath: referenced.relativePath,
                originalFilename: "referenced.png",
                contentType: "image/png",
                byteCount: referenced.byteCount,
                checksum: referenced.checksum,
                createdAt: timestamp
            )
            let missingMetadata = ImageMetadata(
                id: missingID,
                relativePath: missingPath,
                originalFilename: "missing.png",
                contentType: "image/png",
                byteCount: 1,
                checksum: "missing",
                sortOrder: 1,
                createdAt: timestamp
            )
            try EntryRepository(context: container.mainContext).save(Entry(
                body: "Recovery fixture",
                createdAt: timestamp,
                images: [referencedMetadata, missingMetadata]
            ))
        }
        _ = try mediaStore.moveToTrash(referenced.relativePath)
        let stagingURL = fixture.mediaRoot.appendingPathComponent("Staging/interrupted.png")
        try FileManager.default.createDirectory(at: stagingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: stagingURL)
        let thumbnailRoot = fixture.root.appendingPathComponent("Thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: thumbnailRoot, withIntermediateDirectories: true)
        try bytes.write(to: thumbnailRoot.appendingPathComponent("\(orphan.id.uuidString.lowercased()).jpg"))
        try bytes.write(to: thumbnailRoot.appendingPathComponent("\(missingID.uuidString.lowercased()).jpg"))

        let reopened = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
        let metadata = try reopened.mainContext.fetch(FetchDescriptor<ImageMetadata>())
        let thumbnailStore = ThumbnailStore(rootURL: thumbnailRoot, mediaStore: mediaStore)
        let firstReport = try StartupMediaReconciler.reconcile(
            mediaStore: mediaStore,
            thumbnailStore: thumbnailStore,
            imageMetadata: metadata
        )

        XCTAssertEqual(try Data(contentsOf: mediaStore.fileURL(for: referenced.relativePath)), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try mediaStore.fileURL(for: orphan.relativePath).path))
        XCTAssertEqual(firstReport.removedStagingFileCount, 1)
        XCTAssertEqual(firstReport.removedThumbnailCount, 1)
        XCTAssertEqual(firstReport.missingOriginalPaths, [missingPath])
        XCTAssertEqual(firstReport.recoveryFilePaths.count, 1)
        let missingMetadata = try XCTUnwrap(metadata.first { $0.id == missingID })
        XCTAssertNil(thumbnailStore.image(for: missingMetadata))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: thumbnailRoot.appendingPathComponent("\(missingID.uuidString.lowercased()).jpg").path
        ))

        let secondReport = try StartupMediaReconciler.reconcile(
            mediaStore: mediaStore,
            thumbnailStore: thumbnailStore,
            imageMetadata: metadata
        )
        XCTAssertEqual(secondReport.removedStagingFileCount, 0)
        XCTAssertEqual(secondReport.removedThumbnailCount, 0)
        XCTAssertEqual(secondReport.missingOriginalPaths, firstReport.missingOriginalPaths)
        XCTAssertEqual(secondReport.recoveryFilePaths, firstReport.recoveryFilePaths)
    }

    func testEditingMultiImageCopyFailurePreservesEntryAndUnrelatedOriginals() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let secondURL = fixture.root.appendingPathComponent("second.png")
        let thirdURL = fixture.root.appendingPathComponent("third.png")
        try fixturePNG(color: .red).write(to: fixture.sourceURL)
        try fixturePNG(color: .blue).write(to: secondURL)
        try fixturePNG(color: .green).write(to: thirdURL)
        let healthyStore = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        let original = try healthyStore.storeOriginal(MediaSource(
            url: fixture.sourceURL,
            originalFilename: "original.png",
            contentType: "image/png"
        ))
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let originalMetadata = ImageMetadata(
            id: original.id,
            relativePath: original.relativePath,
            originalFilename: "original.png",
            contentType: "image/png",
            byteCount: original.byteCount,
            checksum: original.checksum,
            createdAt: timestamp
        )
        let entry = Entry(body: "Before", createdAt: timestamp, images: [originalMetadata])
        let failingStore = MediaStore(
            rootURL: fixture.mediaRoot,
            availableCapacity: { .max },
            beforeStoreCopy: { if $0 == 2 { throw InjectedMediaFailure.copy } }
        )

        XCTAssertThrowsError(try EntryEditingService(
            persistence: FailingEditingPersistence(),
            mediaStore: failingStore
        ).update(entry, with: EntryEditingDraft(
            title: nil,
            body: "After",
            occurredAt: timestamp,
            orderedImages: [
                .added(MediaSource(url: secondURL, originalFilename: "second.png", contentType: "image/png")),
                .retained(original.id),
                .added(MediaSource(url: thirdURL, originalFilename: "third.png", contentType: "image/png"))
            ]
        )))

        XCTAssertEqual(entry.body, "Before")
        XCTAssertEqual(entry.images.first?.id, original.id)
        XCTAssertEqual(try fixture.originalFiles().count, 1)
        XCTAssertEqual(try fixture.stagingFiles(), [])
    }

    func testEditingCanOrderNewPhotoBeforeRetainedPhoto() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let secondURL = fixture.root.appendingPathComponent("second.png")
        try fixturePNG(color: .red).write(to: fixture.sourceURL)
        try fixturePNG(color: .blue).write(to: secondURL)
        let container = try PersistenceContainerFactory.makeInMemory()
        let persistence = ModelContextEntryPersistence(context: container.mainContext)
        let mediaStore = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        let entry = try EntryCreationService(persistence: persistence, mediaStore: mediaStore).create(
            EntryCreationDraft(image: MediaSource(
                url: fixture.sourceURL,
                originalFilename: "retained.png",
                contentType: "image/png"
            ))
        )
        let retainedID = try XCTUnwrap(entry.images.first?.id)

        try EntryEditingService(persistence: persistence, mediaStore: mediaStore).update(
            entry,
            with: EntryEditingDraft(
                title: nil,
                body: nil,
                occurredAt: entry.occurredAt,
                orderedImages: [
                    .added(MediaSource(url: secondURL, originalFilename: "new.png", contentType: "image/png")),
                    .retained(retainedID)
                ]
            )
        )

        XCTAssertEqual(
            entry.images.sorted(by: { $0.sortOrder < $1.sortOrder }).map(\.originalFilename),
            ["new.png", "retained.png"]
        )
    }

    func testEditingRestoreFailureReportsRecoveryAndNextLaunchRestoresOriginal() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let replacementURL = fixture.root.appendingPathComponent("replacement.png")
        let originalBytes = fixturePNG(color: .red)
        try originalBytes.write(to: fixture.sourceURL)
        try fixturePNG(color: .blue).write(to: replacementURL)
        let healthyStore = MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        let original = try healthyStore.storeOriginal(MediaSource(
            url: fixture.sourceURL,
            originalFilename: "original.png",
            contentType: "image/png"
        ))
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let metadata = ImageMetadata(
            id: original.id,
            relativePath: original.relativePath,
            originalFilename: "original.png",
            contentType: "image/png",
            byteCount: original.byteCount,
            checksum: original.checksum,
            createdAt: timestamp
        )
        let entry = Entry(body: "Before", createdAt: timestamp, images: [metadata])
        let restoreFailingStore = MediaStore(
            rootURL: fixture.mediaRoot,
            availableCapacity: { .max },
            beforeTrashRestore: { throw InjectedMediaFailure.restore }
        )

        XCTAssertThrowsError(try EntryEditingService(
            persistence: FailingEditingPersistence(),
            mediaStore: restoreFailingStore
        ).update(entry, with: EntryEditingDraft(
            title: nil,
            body: "After",
            occurredAt: timestamp,
            orderedImages: [
                .added(MediaSource(
                    url: replacementURL,
                    originalFilename: "replacement.png",
                    contentType: "image/png"
                ))
            ]
        ))) {
            XCTAssertEqual($0 as? EntryMediaOperationError, .rollbackIncomplete)
        }
        XCTAssertEqual(entry.body, "Before")
        XCTAssertFalse(FileManager.default.fileExists(atPath: try healthyStore.fileURL(for: original.relativePath).path))
        XCTAssertEqual(try fixture.originalFiles(), [])

        try healthyStore.recoverInterruptedTrash(referencedOriginalPaths: [original.relativePath])
        XCTAssertEqual(try Data(contentsOf: healthyStore.fileURL(for: original.relativePath)), originalBytes)
    }

    func testRestoreMovesArchivedEntryBackToOrganized() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let persistence = ModelContextEntryPersistence(context: container.mainContext)
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let service = EntryDeletionService(
            persistence: persistence,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { .max })
        )
        let entry = Entry(status: .archived, body: "Recoverable", createdAt: Date())
        persistence.insert(entry)
        try persistence.save()

        try service.restore(entry)

        XCTAssertEqual(entry.status, .organized)
    }

    private func saveFixtureEntry(id: UUID, storeURL: URL) throws {
        let container = try PersistenceContainerFactory.makeOnDisk(at: storeURL)
        let repository = EntryRepository(context: container.mainContext)
        try repository.save(Entry(
            id: id,
            body: "Persistent",
            createdAt: Date(timeIntervalSince1970: 1_000)
        ))
    }
}

private enum InjectedMediaFailure: Error {
    case copy
    case restore
}

@MainActor
private final class RecordingEntryPersistence: EntryPersisting {
    var insertedEntry: Entry?
    var didRollback = false

    func insert(_ entry: Entry) {
        insertedEntry = entry
    }

    func save() throws {}

    func rollback() {
        didRollback = true
        insertedEntry = nil
    }
}

@MainActor
private final class FailingEntryPersistence: EntryPersisting {
    enum Failure: Error {
        case injected
    }

    var didRollback = false

    func insert(_ entry: Entry) {}

    func save() throws {
        throw Failure.injected
    }

    func rollback() {
        didRollback = true
    }
}

@MainActor
private final class FailingDeletionPersistence: EntryDeletingPersistence {
    enum Failure: Error {
        case injected
    }

    var didRollback = false

    func delete(_ entry: Entry) {}

    func save() throws {
        throw Failure.injected
    }

    func rollback() {
        didRollback = true
    }
}

@MainActor
private final class FailingEditingPersistence: EntryEditingPersistence {
    enum Failure: Error {
        case injected
    }

    var didRollback = false

    func delete(_ image: ImageMetadata) {}

    func save() throws {
        throw Failure.injected
    }

    func rollback() {
        didRollback = true
    }
}

@MainActor
private func fixturePNG(color: UIColor) -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format).pngData { context in
        color.setFill()
        context.cgContext.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }
}

private func solidGrayscalePNG(width: UInt32, height: UInt32) throws -> Data {
    var result = Data([137, 80, 78, 71, 13, 10, 26, 10])
    var header = [UInt8](repeating: 0, count: 13)
    writeBigEndian(width, into: &header, at: 0)
    writeBigEndian(height, into: &header, at: 4)
    header[8] = 1
    header[9] = 0
    appendPNGChunk(type: "IHDR", payload: Data(header), to: &result)

    let bytesPerRow = Int((width + 7) / 8)
    let raw = Data(count: (bytesPerRow + 1) * Int(height))
    let compressed = try (raw as NSData).compressed(using: .zlib) as Data
    appendPNGChunk(type: "IDAT", payload: compressed, to: &result)
    appendPNGChunk(type: "IEND", payload: Data(), to: &result)
    return result
}

private func pngByPaddingToByteCount(_ png: Data, byteCount: Int) -> Data {
    precondition(png.count + 12 <= byteCount)
    var result = Data(png.dropLast(12))
    appendPNGChunk(
        type: "pgOS",
        payload: Data(count: byteCount - png.count - 12),
        to: &result
    )
    result.append(png.suffix(12))
    precondition(result.count == byteCount)
    return result
}

private func appendPNGChunk(type: String, payload: Data, to result: inout Data) {
    var lengthBytes = [UInt8](repeating: 0, count: 4)
    writeBigEndian(UInt32(payload.count), into: &lengthBytes, at: 0)
    let typeBytes = Array(type.utf8)
    result.append(contentsOf: lengthBytes)
    result.append(contentsOf: typeBytes)
    result.append(payload)
    var crcBytes = [UInt8](repeating: 0, count: 4)
    writeBigEndian(crc32(ArraySlice(typeBytes + [UInt8](payload))), into: &crcBytes, at: 0)
    result.append(contentsOf: crcBytes)
}

private func writeBigEndian(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
    bytes[offset] = UInt8((value >> 24) & 0xff)
    bytes[offset + 1] = UInt8((value >> 16) & 0xff)
    bytes[offset + 2] = UInt8((value >> 8) & 0xff)
    bytes[offset + 3] = UInt8(value & 0xff)
}

private func crc32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
    var crc: UInt32 = 0xffff_ffff
    for byte in bytes {
        crc = crc32Table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
    }
    return crc ^ 0xffff_ffff
}

private let crc32Table: [UInt32] = (0..<256).map { value in
    var crc = UInt32(value)
    for _ in 0..<8 {
        crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb8_8320 : 0)
    }
    return crc
}

private func regularFileByteCount(at directory: URL) throws -> Int64 {
    guard FileManager.default.fileExists(atPath: directory.path),
          let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
          ) else { return 0 }
    return try (enumerator.allObjects as? [URL] ?? []).reduce(Int64(0)) { total, url in
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        return values.isRegularFile == true ? total + Int64(values.fileSize ?? 0) : total
    }
}

private struct TemporaryFixture {
    let root: URL
    let storeURL: URL
    let mediaRoot: URL
    let sourceURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PGOS-S2-\(UUID().uuidString)", isDirectory: true)
        storeURL = root.appendingPathComponent("store.sqlite")
        mediaRoot = root.appendingPathComponent("MediaRoot", isDirectory: true)
        sourceURL = root.appendingPathComponent("source.image")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func originalFiles() throws -> [URL] {
        let originals = mediaRoot.appendingPathComponent("Media/Originals", isDirectory: true)
        guard FileManager.default.fileExists(atPath: originals.path) else { return [] }
        let enumerator = FileManager.default.enumerator(
            at: originals,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        return (enumerator?.allObjects as? [URL] ?? []).filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    func stagingFiles() throws -> [URL] {
        let staging = mediaRoot.appendingPathComponent("Staging", isDirectory: true)
        guard FileManager.default.fileExists(atPath: staging.path) else { return [] }
        let enumerator = FileManager.default.enumerator(
            at: staging,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        return (enumerator?.allObjects as? [URL] ?? []).filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

extension PersistenceMediaFoundationTests {
    func testBuild9ExactV8MigrationAndContinuationReopen() throws {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Build8V8Fixture", withExtension: nil))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("PersonalGrowthOS.store")
        let entryID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let followUpID = UUID()
        var originalTimes: [Date] = []
        var planIDs: Set<UUID> = []
        try autoreleasepool {
            let container = try PersistenceContainerFactory.makeOnDisk(at: url)
            let context = container.mainContext
            let entry = try XCTUnwrap(EntryRepository(context: context).fetch(id: entryID))
            originalTimes = [entry.createdAt, entry.occurredAt, entry.updatedAt]
            XCTAssertEqual(entry.body, "Exact 95076bf source fact")
            XCTAssertEqual(entry.images.count, 1)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Media/" + entry.images[0].relativePath).path))
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Habit>()), 4)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<HabitLog>()), 6)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<HabitLogDayMetadata>()), 6)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<HabitLifecycleEvent>()), 4)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ObjectLink>()), 3)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Goal>()), 1)
            XCTAssertEqual(try context.fetch(FetchDescriptor<WeightRecord>()).first?.weightKilograms, 72.5)
            XCTAssertEqual(try context.fetch(FetchDescriptor<WeeklyReview>()).first?.rememberedText, "Build 7 memory")
            planIDs = Set(try context.fetch(FetchDescriptor<HabitPlanRevision>()).map(\.id))
            XCTAssertEqual(planIDs.count, 4)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryPin>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryFollowUp>()), 0)
            let service = EntryContinuationService(context: context)
            try service.setPinned(true, entryID: entryID)
            let pinDate = try XCTUnwrap(context.fetch(FetchDescriptor<EntryPin>()).first?.pinnedAt)
            try service.setPinned(true, entryID: entryID)
            XCTAssertEqual(try context.fetch(FetchDescriptor<EntryPin>()).first?.pinnedAt, pinDate)
            try service.add(entryID: entryID, body: "新的认识\n第二行", id: followUpID)
            try service.add(entryID: entryID, body: "新的认识\n第二行", id: followUpID)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryFollowUp>()), 1)
        }
        try autoreleasepool {
            let container = try PersistenceContainerFactory.makeOnDisk(at: url)
            let context = container.mainContext
            let entry = try XCTUnwrap(EntryRepository(context: context).fetch(id: entryID))
            XCTAssertEqual([entry.createdAt, entry.occurredAt, entry.updatedAt], originalTimes)
            XCTAssertEqual(Set(try context.fetch(FetchDescriptor<HabitPlanRevision>()).map(\.id)), planIDs)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryPin>()), 1)
            let followUp = try XCTUnwrap(context.fetch(FetchDescriptor<EntryFollowUp>()).first)
            XCTAssertEqual(followUp.id, followUpID)
            XCTAssertEqual(followUp.body, "新的认识\n第二行")
            let created = followUp.createdAt
            let service = EntryContinuationService(context: context, now: { created.addingTimeInterval(60) })
            try service.edit(followUp, body: followUp.body)
            XCTAssertEqual(followUp.updatedAt, created)
            try service.edit(followUp, body: "更新认识")
            XCTAssertEqual(followUp.createdAt, created)
            XCTAssertEqual(followUp.updatedAt, created.addingTimeInterval(60))
            XCTAssertEqual([entry.createdAt, entry.occurredAt, entry.updatedAt], originalTimes)
            let deletion = EntryDeletionService(persistence: ModelContextEntryPersistence(context: context), mediaStore: MediaStore(rootURL: root.appendingPathComponent("Media")))
            try deletion.archive(entry)
            XCTAssertThrowsError(try service.add(entryID: entryID, body: "归档不可编辑"))
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryFollowUp>()), 1)
            try deletion.restore(entry)
            try deletion.permanentlyDelete(entry)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryFollowUp>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryPin>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()), 0)
        }
    }
}

extension PersistenceMediaFoundationTests {
    func testBuild9ContinuationFailureRollbackSearchAndParentStatistics() throws {
        enum Injected: Error { case save }
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let date = Date(timeIntervalSince1970: 1000)
        let entry = Entry(body: "原文", createdAt: date)
        context.insert(entry)
        try context.save()
        let service = EntryContinuationService(context: context, now: { date.addingTimeInterval(60) })
        let thought = try service.add(entryID: entry.id, body: String(repeating: "过去的想法。", count: 100) + "独特认识", id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        try service.add(entryID: entry.id, body: "独特认识，再次补充", id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let failed = EntryContinuationService(context: context, save: { throw Injected.save })
        XCTAssertThrowsError(try failed.add(entryID: entry.id, body: "失败不落盘"))
        XCTAssertThrowsError(try failed.edit(thought, body: "失败编辑"))
        XCTAssertThrowsError(try failed.setPinned(true, entryID: entry.id))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryPin>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryFollowUp>()), 2)
        let results = try LocalSearchService(context: context).search("独特认识")
        XCTAssertEqual(results.entries.map(\.id), [entry.id])
        XCTAssertEqual(results.followUpMatches[entry.id]?.id, thought.id)
        XCTAssertTrue(results.followUpMatches[entry.id]?.snippet.contains("独特认识") == true)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()), 1)
        XCTAssertEqual([entry.createdAt, entry.occurredAt, entry.updatedAt], [date, date, date])
        XCTAssertEqual(entry.body, "原文")
        XCTAssertThrowsError(try service.add(entryID: entry.id, body: " \n"))
        try service.delete(thought)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryFollowUp>()), 1)
    }
}

extension PersistenceMediaFoundationTests {
    func testBuild9PinOrderingArchiveRestoreAndRepin() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let date = Date(timeIntervalSince1970: 1000)
        let first = Entry(body: "First", createdAt: date)
        let second = Entry(body: "Second", createdAt: date)
        context.insert(first)
        context.insert(second)
        try context.save()
        var now = date
        let service = EntryContinuationService(context: context, now: { now })
        try service.setPinned(true, entryID: first.id)
        now = date.addingTimeInterval(10)
        try service.setPinned(true, entryID: second.id)
        func pins() throws -> [EntryPin] { try context.fetch(FetchDescriptor<EntryPin>()) }
        XCTAssertEqual(EntryPinOrdering.entries(pins: try pins(), entries: [first, second]).map(\.id), [second.id, first.id])
        first.status = .archived
        try context.save()
        XCTAssertEqual(EntryPinOrdering.entries(pins: try pins(), entries: [first, second]).map(\.id), [second.id])
        first.status = .organized
        try context.save()
        XCTAssertEqual(try pins().first { $0.entryID == first.id }?.pinnedAt, date)
        try service.setPinned(false, entryID: first.id)
        now = date.addingTimeInterval(20)
        try service.setPinned(true, entryID: first.id)
        XCTAssertEqual(EntryPinOrdering.entries(pins: try pins(), entries: [first, second]).map(\.id), [first.id, second.id])
        XCTAssertEqual(first.updatedAt, date)
        let tied = try pins()
        tied.forEach { $0.pinnedAt = date }
        let expected = tied.sorted { $0.id.uuidString < $1.id.uuidString }.map(\.entryID)
        XCTAssertEqual(EntryPinOrdering.entries(pins: tied.reversed(), entries: [first, second]).map(\.id), expected)
    }
}

extension PersistenceMediaFoundationTests {
    func testPR6SearchRecomputesMembershipSnippetAndTargetAfterFollowUpChanges() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let original = Entry(body: "Original", createdAt: Date(timeIntervalSince1970: 1000))
        let bodyMatch = Entry(body: "needle in original", createdAt: Date(timeIntervalSince1970: 900))
        context.insert(original)
        context.insert(bodyMatch)
        try context.save()
        var now = Date(timeIntervalSince1970: 1000)
        let service = EntryContinuationService(context: context, now: { now })
        let first = try service.add(entryID: original.id, body: "needle alpha")
        now = now.addingTimeInterval(10)
        let second = try service.add(entryID: original.id, body: "needle beta")
        let bodyThought = try service.add(entryID: bodyMatch.id, body: "needle extra")
        let search = LocalSearchService(context: context)
        XCTAssertEqual(try search.search("needle").followUpMatches[original.id]?.id, first.id)
        try service.edit(first, body: "no longer matches")
        let next = try search.search("needle")
        XCTAssertEqual(next.entries.map(\.id), [original.id, bodyMatch.id])
        XCTAssertEqual(next.followUpMatches[original.id]?.id, second.id)
        XCTAssertEqual(next.followUpMatches[original.id]?.snippet, "needle beta")
        try service.delete(second)
        try service.delete(bodyThought)
        let final = try search.search("needle")
        XCTAssertEqual(final.entries.map(\.id), [bodyMatch.id])
        XCTAssertTrue(final.followUpMatches.isEmpty)
    }
}

@MainActor
final class ExternalCaptureTests: XCTestCase {
    private func assertScan(_ importer: ExternalCaptureImporter, failures: Int,
                            file: StaticString = #filePath, line: UInt = #line) async throws {
        let actual = try await importer.scan()
        XCTAssertEqual(actual, failures, file: file, line: line)
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testStorageFailureNeverPublishesOrCommitsPartialShare() async throws {
        let root = try temporaryRoot()
        var inbox = ShareInbox(root: root.appendingPathComponent("Inbox"))
        inbox.beforePublication = { throw CocoaError(.fileWriteOutOfSpace) }
        let payload = ShareImportPayload(text: "Storage fixture")
        XCTAssertThrowsError(try inbox.publish(payload, files: [:])) { error in
            XCTAssertTrue(CaptureError.isStorageFailure(error))
        }
        XCTAssertTrue(try inbox.pending().isEmpty)
        XCTAssertEqual(try CaptureStagingSession.reclaimAbandoned(root: inbox.root), 0)
        inbox.beforePublication = nil
        let imageURL = root.appendingPathComponent("storage.png")
        let data = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        try data.write(to: imageURL)
        let imageID = UUID()
        let attachment = CaptureAttachment(id: imageID, filename: imageID.uuidString.lowercased(), contentType: "image/png",
            byteCount: Int64(data.count), checksum: try ShareInbox.checksum(imageURL))
        let imagePayload = ShareImportPayload(images: [attachment])
        try inbox.publish(imagePayload, files: [imageID: imageURL])
        let container = try PersistenceContainerFactory.makeInMemory()
        let media = MediaStore(rootURL: root, availableCapacity: { 0 })
        let importer = ExternalCaptureImporter(container: container, mediaStore: media, inbox: inbox)
        let report = try await importer.scanReport()
        XCTAssertEqual(report.failed, 1)
        XCTAssertEqual(report.pendingCount, 1)
        let items = try await importer.pendingItems()
        XCTAssertEqual(items.first?.reason, .storage)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Entry>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<CaptureImportReceipt>()), 0)
        XCTAssertEqual(try media.originalsByteCount(), 0)
        let retry = ExternalCaptureImporter(container: container,
            mediaStore: MediaStore(rootURL: root, availableCapacity: { .max }), inbox: inbox)
        try await retry.retry(imagePayload.id.uuidString.lowercased())
        XCTAssertTrue(try inbox.pending().isEmpty)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Entry>()), 1)
    }

    func testOwnedCopyCompensationRetriesIndividualFailuresAndPreservesUnknownRecovery() throws {
        let root = try temporaryRoot()
        let media = MediaStore(rootURL: root)
        let image = root.appendingPathComponent("source.png")
        try UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }.write(to: image)
        let source = MediaSource(url: image, originalFilename: "source.png", contentType: "image/png")
        let checksum = try ShareInbox.checksum(image)
        var journal = CaptureMediaJournal(operationID: UUID(), captureID: UUID())
        let firstID = try journal.prepareCopy(contentType: source.contentType, checksum: checksum, mediaStore: media)
        let first = try media.storeOriginal(source, id: firstID)
        let secondID = try journal.prepareCopy(contentType: source.contentType, checksum: checksum, mediaStore: media)
        let second = try media.storeOriginal(source, id: secondID)
        let unknown = try media.storeOriginal(source)
        // A previous startup can have moved interrupted copies into Recovery before compensation.
        _ = try media.reconcile(referencedOriginalPaths: [])
        let firstRecovery = try media.fileURL(for: "Recovery/Orphaned/" + first.relativePath)
        let secondRecovery = try media.fileURL(for: "Recovery/Orphaned/" + second.relativePath)
        let unknownRecovery = try media.fileURL(for: "Recovery/Orphaned/" + unknown.relativePath)
        CaptureMediaJournal.reconcile(mediaStore: media, referencedPaths: []) { url in
            if url == firstRecovery { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.removeItem(at: url)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstRecovery.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondRecovery.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknownRecovery.path))
        CaptureMediaJournal.reconcile(mediaStore: media, referencedPaths: [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstRecovery.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknownRecovery.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("CaptureCopyJournal").path).isEmpty)
    }

    func testOwnedCopyIntentBeforeCopyAndCommittedReferencesAreSafe() throws {
        let root = try temporaryRoot()
        let media = MediaStore(rootURL: root)
        let image = root.appendingPathComponent("source.png")
        try UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }.write(to: image)
        let checksum = try ShareInbox.checksum(image)
        var journal = CaptureMediaJournal(operationID: UUID(), captureID: UUID())
        _ = try journal.prepareCopy(contentType: "image/png", checksum: checksum, mediaStore: media)
        let committedID = try journal.prepareCopy(contentType: "image/png", checksum: checksum, mediaStore: media)
        let committed = try media.storeOriginal(MediaSource(url: image, originalFilename: "source.png", contentType: "image/png"), id: committedID)
        CaptureMediaJournal.reconcile(mediaStore: media, referencedPaths: [committed.relativePath])
        XCTAssertEqual(try ShareInbox.checksum(media.fileURL(for: committed.relativePath)), checksum)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("CaptureCopyJournal").path).isEmpty)
    }

    func testFailedInboxDeferralSurvivesReopenAndVersionChange() async throws {
        let root = try temporaryRoot()
        let inbox = ShareInbox(root: root.appendingPathComponent("Inbox"))
        let mediaStore = MediaStore(rootURL: root)
        let storeURL = root.appendingPathComponent("store.sqlite")
        let bad = ShareImportPayload(text: "Future shared content")
        let good = ShareImportPayload(text: "Valid shared content")
        try inbox.publish(bad, files: [:])
        let directory = try XCTUnwrap(inbox.pending().first)
        var future = bad
        future.schemaVersion = 99
        try JSONEncoder().encode(future).write(to: directory.appendingPathComponent("payload.json"))
        try inbox.publish(good, files: [:])
        do {
            let container = try PersistenceContainerFactory.makeOnDisk(at: storeURL)
            let importer = ExternalCaptureImporter(container: container, mediaStore: mediaStore, inbox: inbox)
            importer.processingVersion = "old"
            let first = try await importer.scanReport()
            XCTAssertEqual(first.newFailureIDs, [bad.id.uuidString.lowercased()])
            XCTAssertEqual(first.failed, 1)
            XCTAssertEqual(first.pendingCount, 1)
            XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Entry>()).map(\.id), [good.id])
            let repeated = try await importer.scanReport()
            XCTAssertTrue(repeated.newFailureIDs.isEmpty)
            let pending = try await importer.pendingItems()
            XCTAssertEqual(pending.first?.reason, .unsupportedVersion)
            XCTAssertFalse(try XCTUnwrap(pending.first).isCommitted)
            try await importer.keepForLater([bad.id.uuidString.lowercased()])
            let laterGood = ShareImportPayload(text: "New valid share after deferral")
            let laterBad = ShareImportPayload(text: "New invalid share after deferral")
            try inbox.publish(laterGood, files: [:])
            try inbox.publish(laterBad, files: [:])
            let laterDirectory = try XCTUnwrap(inbox.pending().first { $0.lastPathComponent == laterBad.id.uuidString.lowercased() })
            try Data("invalid JSON".utf8).write(to: laterDirectory.appendingPathComponent("payload.json"))
            let newFailure = try await importer.scanReport()
            XCTAssertEqual(newFailure.newFailureIDs, [laterBad.id.uuidString.lowercased()])
            XCTAssertEqual(newFailure.failed, 1)
            XCTAssertEqual(newFailure.pendingCount, 2)
            XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Entry>()), 2)
            try await importer.discardPending(laterBad.id.uuidString.lowercased())
        }
        do {
            let container = try PersistenceContainerFactory.makeOnDisk(at: storeURL)
            let importer = ExternalCaptureImporter(container: container, mediaStore: mediaStore, inbox: inbox)
            importer.processingVersion = "old"
            let pending = try await importer.pendingItems()
            XCTAssertTrue(try XCTUnwrap(pending.first).isDeferred)
            // A repaired fixture stays deferred until explicitly retried or the app version changes.
            try JSONEncoder().encode(bad).write(to: directory.appendingPathComponent("payload.json"))
            let deferred = try await importer.scanReport()
            XCTAssertEqual(deferred.failed, 0)
            XCTAssertEqual(deferred.pendingCount, 1)
            importer.processingVersion = "new"
            let updated = try await importer.scanReport()
            XCTAssertEqual(updated.pendingCount, 0)
            XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Entry>()), 3)
        }
    }

    func testPendingRetryAndDiscardAreSelectedAndReceiptAware() async throws {
        let root = try temporaryRoot()
        let inbox = ShareInbox(root: root.appendingPathComponent("Inbox"))
        let container = try PersistenceContainerFactory.makeInMemory()
        let importer = ExternalCaptureImporter(container: container, mediaStore: MediaStore(rootURL: root), inbox: inbox)
        let committed = ShareImportPayload(text: "Already committed")
        try inbox.publish(committed, files: [:])
        importer.checkpoint = { if $0 == "afterSave" { throw CaptureError.invalidPayload } }
        let failed = try await importer.scanReport()
        XCTAssertEqual(failed.failed, 1)
        var items = try await importer.pendingItems()
        XCTAssertTrue(try XCTUnwrap(items.first).isCommitted)
        XCTAssertEqual(items.first?.reason, .cleanup)
        let other = ShareImportPayload(text: "Leave this pending")
        try inbox.publish(other, files: [:])
        try await importer.discardPending(committed.id.uuidString.lowercased())
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Entry>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<CaptureImportReceipt>()), 1)
        XCTAssertEqual(try inbox.pending().map(\.lastPathComponent), [other.id.uuidString.lowercased()])
        try await importer.keepForLater([other.id.uuidString.lowercased()])
        items = try await importer.pendingItems()
        XCTAssertTrue(try XCTUnwrap(items.first).isDeferred)
        importer.checkpoint = nil
        try await importer.retry(other.id.uuidString.lowercased())
        XCTAssertTrue(try inbox.pending().isEmpty)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Entry>()), 2)
        // A retained duplicate of the committed entry only needs cleanup, even without its payload.
        try inbox.publish(committed, files: [:])
        let duplicate = try XCTUnwrap(inbox.pending().first)
        try FileManager.default.removeItem(at: duplicate.appendingPathComponent("payload.json"))
        try await importer.retry(committed.id.uuidString.lowercased())
        XCTAssertTrue(try inbox.pending().isEmpty)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Entry>()), 2)
    }

    func testConcurrentExplicitConsumptionCommitsOnceAndCleansIdempotently() async throws {
        let root = try temporaryRoot()
        let inbox = ShareInbox(root: root.appendingPathComponent("Inbox"))
        let payload = ShareImportPayload(text: "One shared record")
        try inbox.publish(payload, files: [:])
        let directory = try XCTUnwrap(inbox.pending().first)
        let container = try PersistenceContainerFactory.makeInMemory()
        let importer = ExternalCaptureImporter(container: container, mediaStore: MediaStore(rootURL: root), inbox: inbox)
        async let first: Void = importer.consume(directory)
        async let second: Void = importer.consume(directory)
        _ = try await (first, second)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Entry>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<CaptureImportReceipt>()), 1)
        XCTAssertTrue(try inbox.pending().isEmpty)
    }

    func testSharedStagingReclaimsOnlyAbandonedOwnedSessions() throws {
        let root = try temporaryRoot()
        let active = try CaptureStagingSession(root: root)
        var abandoned: CaptureStagingSession? = try CaptureStagingSession(root: root)
        let abandonedDirectory = try XCTUnwrap(abandoned?.directory)
        try Data("Unpublished copy".utf8).write(to: abandonedDirectory.appendingPathComponent("copy"))
        let legacy = root.appendingPathComponent("Staging/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let inbox = ShareInbox(root: root)
        try inbox.publish(ShareImportPayload(text: "User pending content"), files: [:])
        XCTAssertEqual(try CaptureStagingSession.reclaimAbandoned(root: root), 0)
        abandoned = nil // Models process termination releasing its kernel lease.
        XCTAssertEqual(try CaptureStagingSession.reclaimAbandoned(root: root), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandonedDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: active.directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertEqual(try inbox.pending().count, 1)
        try active.remove()
    }

    func testPublicProvidersPreserveMixedContentAndSkipUnknownAuxiliary() async throws {
        let root = try temporaryRoot()
        let reader = ShareProviderReader(workspace: root)
        let unknown = NSItemProvider(item: "Auxiliary" as NSString, typeIdentifier: "com.example.unknown")
        let text = NSItemProvider(item: "Quote" as NSString, typeIdentifier: UTType.text.identifier)
        let url = NSItemProvider(object: NSURL(string: "https://example.com/shared")!)
        let item = NSExtensionItem()
        item.attachments = [text, unknown]
        var result = try await reader.read([item])
        XCTAssertEqual(result.payload.text, "Quote")
        XCTAssertTrue(result.issues.isEmpty)
        item.attachments = [url, unknown]
        result = try await reader.read([item])
        XCTAssertEqual(result.payload.source?.url, "https://example.com/shared")
        XCTAssertTrue(result.issues.isEmpty)
        item.attachments = [unknown]
        result = try await reader.read([item])
        XCTAssertThrowsError(try result.payload.validate())

        let imageURL = root.appendingPathComponent("fixture.png")
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { _ in }
        try bytes.write(to: imageURL)
        let image = NSItemProvider(contentsOf: imageURL)!
        item.attachments = [image, url]
        item.attributedContentText = NSAttributedString(string: "Independent caption")
        result = try await reader.read([item])
        XCTAssertEqual(result.payload.text, "Independent caption")
        XCTAssertEqual(result.payload.images.count, 1)
        XCTAssertEqual(result.payload.source?.url, "https://example.com/shared")
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertNoThrow(try result.payload.validate())
        let owned = try XCTUnwrap(result.files.values.first)
        XCTAssertNotEqual(owned, imageURL)
        XCTAssertEqual(try Data(contentsOf: owned), bytes)
        XCTAssertNotNil(result.thumbnail)
        item.attachments = [image]
        result = try await reader.read([item])
        XCTAssertNil(result.payload.source, "An image file URL must never become a webpage source")
    }

    func testProviderAlternativesPartialFailureAndMultipleSourcesAreExplicit() async throws {
        let reader = ShareProviderReader(workspace: try temporaryRoot(), timeout: 0.1)
        let fallback = NSItemProvider()
        fallback.registerItem(forTypeIdentifier: UTType.propertyList.identifier) { completion, _, _ in
            completion?(nil, CaptureError.unsupportedProvider)
        }
        fallback.registerItem(forTypeIdentifier: UTType.text.identifier) { completion, _, _ in
            completion?("Fallback quote" as NSString, nil)
        }
        let item = NSExtensionItem()
        item.attachments = [fallback]
        item.attributedContentText = NSAttributedString(string: "Fallback quote")
        var result = try await reader.read([item])
        XCTAssertEqual(result.payload.text, "Fallback quote")
        XCTAssertTrue(result.issues.isEmpty)
        let brokenImage = NSItemProvider()
        brokenImage.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
            completion(nil, false, CaptureError.attachmentInvalid)
            return nil
        }
        item.attachments = [fallback, brokenImage]
        result = try await reader.read([item])
        XCTAssertEqual(result.payload.text, "Fallback quote")
        XCTAssertTrue(result.payload.images.isEmpty)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues.first?.item, 2)
        let first = NSItemProvider(item: NSURL(string: "https://one.example")!, typeIdentifier: UTType.url.identifier)
        let second = NSItemProvider(item: NSURL(string: "https://two.example")!, typeIdentifier: UTType.url.identifier)
        item.attachments = [first, second]
        result = try await reader.read([item])
        XCTAssertEqual(result.payload.source?.url, "https://one.example")
        XCTAssertTrue(result.payload.text.contains("https://two.example"))
        XCTAssertEqual(result.issues.first?.reason, .multipleSources)
    }

    func testImageRepresentationFallbackWebSourceAndCountLimit() async throws {
        let root = try temporaryRoot()
        let imageURL = root.appendingPathComponent("alternate.jpg")
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).jpegData(withCompressionQuality: 0.8) { _ in }
        try bytes.write(to: imageURL)
        let image = NSItemProvider()
        image.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
            completion(nil, false, CaptureError.attachmentInvalid); return nil
        }
        image.registerFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier, fileOptions: [], visibility: .all) { completion in
            completion(imageURL, false, nil); return nil
        }
        image.registerItem(forTypeIdentifier: UTType.url.identifier) { completion, _, _ in
            completion?(NSURL(string: "https://image.example/source")!, nil)
        }
        let item = NSExtensionItem()
        item.attachments = [image]
        let reader = ShareProviderReader(workspace: root)
        var result = try await reader.read([item])
        XCTAssertEqual(result.payload.images.count, 1)
        XCTAssertEqual(result.payload.source?.url, "https://image.example/source")
        XCTAssertTrue(result.issues.isEmpty)
        let owned = try XCTUnwrap(result.files.values.first)
        XCTAssertEqual(try Data(contentsOf: owned), bytes)
        item.attachments = Array(repeating: image, count: 10)
        result = try await reader.read([item])
        XCTAssertEqual(result.payload.images.count, 9)
        XCTAssertFalse(result.issues.isEmpty, "The tenth selected attachment cannot silently disappear")
        try FileManager.default.removeItem(at: imageURL)
        XCTAssertEqual(try Data(contentsOf: owned), bytes, "Owned callback copies outlive the provider file")

        let binaryText = NSItemProvider()
        binaryText.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
            completion(Data("UTF8 quote".utf8), nil); return nil
        }
        item.attachments = [binaryText]
        result = try await reader.read([item])
        XCTAssertEqual(result.payload.text, "UTF8 quote")
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testProviderTimeoutCancellationAndLateCompletionAreOnceOnly() async throws {
        let gate = CaptureLoadGate<String>()
        let progress = Progress(totalUnitCount: 1)
        do {
            _ = try await gate.wait(timeout: 0.01) { _ in progress }
            XCTFail("An uncooperative callback must time out")
        } catch { XCTAssertEqual(error as? CaptureError, .providerTimedOut) }
        XCTAssertTrue(progress.isCancelled)
        XCTAssertFalse(gate.finish(.success("Late value")))
        XCTAssertFalse(gate.finish(.failure(CaptureError.invalidPayload)))

        let cancelled = CaptureLoadGate<String>()
        let started = expectation(description: "Provider began")
        let task = Task { try await cancelled.wait(timeout: 30) { _ in started.fulfill(); return nil } }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled read must not deliver a value") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(cancelled.finish(.success("Old session")))
        let fresh = CaptureLoadGate<String>()
        let value = try await fresh.wait(timeout: 1) { gate in gate.finish(.success("New session")); return nil }
        XCTAssertEqual(value, "New session")

        let never = NSItemProvider()
        never.registerItem(forTypeIdentifier: UTType.text.identifier) { _, _, _ in }
        let item = NSExtensionItem()
        item.attachments = [never]
        item.attributedContentText = NSAttributedString(string: "Readable caption")
        let result = try await ShareProviderReader(workspace: try temporaryRoot(), timeout: 0.01).read([item])
        XCTAssertEqual(result.payload.text, "Readable caption")
        XCTAssertEqual(result.issues.first?.reason, .providerTimedOut)
    }

    func testSourceOnlySearchMatchesAfterEntryRenameWithoutDuplicates() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let entry = Entry(title: "Edited title", body: "A quote without a URL", createdAt: Date())
        context.insert(entry)
        context.insert(try EntryExternalSource(entryID: entry.id, source: CaptureSource(
            url: "https://source.example/unique-path", canonicalURL: "https://canonical.example/original",
            title: "Original source heading", siteName: "Distinct publisher", capturedAt: Date(), captureMode: .selectedContent)))
        try context.save()
        let search = LocalSearchService(context: context)
        for query in ["source.example", "unique-path", "Original source heading", "Distinct publisher", "canonical.example"] {
            XCTAssertEqual(try search.search(query).entries.map(\.id), [entry.id])
        }
        entry.title = "Original source heading"
        try context.save()
        XCTAssertEqual(try search.search("Original source heading").entries.map(\.id), [entry.id])
    }

    func testOptionalMetadataUsesUTF8BudgetWithoutChangingCoreContent() throws {
        let samples = [String(repeating: "a", count: 40_000),
                       String(repeating: "中", count: 12_000),
                       String(repeating: "👨‍👩‍👧‍👦", count: 2_000),
                       String(repeating: "e\u{301}", count: 20_000), "", "   "]
        for sample in samples {
            var source = CaptureSource(url: "https://example.com/original", canonicalURL: "javascript:bad",
                title: sample, siteName: sample, capturedAt: Date(), captureMode: .selectedContent)
            source.normalizeMetadata()
            XCTAssertLessThanOrEqual(source.title?.utf8.count ?? 0, 32_768)
            XCTAssertLessThanOrEqual(source.siteName?.utf8.count ?? 0, 4_096)
            if let title = source.title { XCTAssertTrue(sample.hasPrefix(title)) }
            if let site = source.siteName { XCTAssertTrue(sample.hasPrefix(site)) }
            XCTAssertNil(source.canonicalURL)
            XCTAssertEqual(source.url, "https://example.com/original")
            let payload = ShareImportPayload(text: "Unmodified user quote", source: source)
            XCTAssertNoThrow(try payload.validate())
            XCTAssertEqual(payload.text, "Unmodified user quote")
        }
        var source = CaptureSource(url: "https://example.com", canonicalURL: "https://example.com/" + String(repeating: "x", count: 17_000),
            title: String(repeating: "👨‍👩‍👧‍👦", count: 2_000), capturedAt: Date(), captureMode: .metadataOnly)
        XCTAssertThrowsError(try source.validate())
        source.normalizeMetadata()
        XCTAssertNil(source.canonicalURL)
        XCTAssertNoThrow(try source.validate())
        let savingSnapshot = source
        source.title = "Late metadata"
        XCTAssertNotEqual(source.title, savingSnapshot.title)
        var oversizedBody = ShareImportPayload(text: String(repeating: "中", count: 400_000), source: source)
        XCTAssertThrowsError(try oversizedBody.validate())
        oversizedBody.text = "Valid core"
        oversizedBody.source?.title = String(repeating: "👨‍👩‍👧‍👦", count: 2_000)
        XCTAssertThrowsError(try oversizedBody.validate())
    }

    func testPayloadValidationAndAtomicPublication() throws {
        let root = try temporaryRoot()
        let inbox = ShareInbox(root: root)
        var payload = ShareImportPayload()
        XCTAssertThrowsError(try inbox.publish(payload, files: [:]))
        payload.text = "Selected private text"
        payload.source = CaptureSource(url: "https://example.com/article", title: "Article", capturedAt: payload.createdAt, captureMode: .selectedContent)
        try inbox.publish(payload, files: [:])
        XCTAssertEqual(try inbox.read(XCTUnwrap(inbox.pending().first)), payload)
        payload.schemaVersion = 2
        XCTAssertThrowsError(try payload.validate())
        payload.schemaVersion = 1
        payload.source?.url = "javascript:alert(1)"
        XCTAssertThrowsError(try payload.validate())
        payload.source = nil
        payload.text = String(repeating: "\u{0001}", count: 400_000)
        XCTAssertThrowsError(try inbox.publish(payload, files: [:]))
        XCTAssertEqual(try inbox.pending().count, 1)
    }

    func testImportCommitInterruptionRetryDeletionAndReopen() async throws {
        let root = try temporaryRoot()
        let inbox = ShareInbox(root: root.appendingPathComponent("Inbox"))
        let url = root.appendingPathComponent("store.sqlite")
        let payload = ShareImportPayload(text: "A share awaiting app launch", source: CaptureSource(url: "https://example.com", capturedAt: Date(), captureMode: .metadataOnly))
        try inbox.publish(payload, files: [:])
        do {
            let container = try PersistenceContainerFactory.makeOnDisk(at: url)
            let importer = ExternalCaptureImporter(container: container, mediaStore: MediaStore(rootURL: root), inbox: inbox)
            importer.checkpoint = { if $0 == "beforeSave" { throw CaptureError.invalidPayload } }
            try await assertScan(importer, failures: 1)
            XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Entry>()), 0)
            XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<CaptureImportReceipt>()), 0)
            importer.checkpoint = { if $0 == "afterSave" { throw CaptureError.invalidPayload } }
            try await assertScan(importer, failures: 1)
            XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Entry>()), 1)
            XCTAssertEqual(try inbox.pending().count, 1)
            // Simulate process death after cleanup deleted the JSON but before removing its directory.
            let pending = try XCTUnwrap(inbox.pending().first)
            try FileManager.default.removeItem(at: pending.appendingPathComponent("payload.json"))
        }
        do {
            let container = try PersistenceContainerFactory.makeOnDisk(at: url)
            let context = container.mainContext
            let importer = ExternalCaptureImporter(container: container, mediaStore: MediaStore(rootURL: root), inbox: inbox)
            try await assertScan(importer, failures: 0)
            try await assertScan(importer, failures: 0)
            let entry = try XCTUnwrap(context.fetch(FetchDescriptor<Entry>()).first)
            XCTAssertEqual(entry.id, payload.id)
            XCTAssertEqual(entry.body, payload.text)
            XCTAssertEqual(try context.fetch(FetchDescriptor<EntryExternalSource>()).first?.source, payload.source)
            try EntryDeletionService(persistence: ModelContextEntryPersistence(context: context), mediaStore: MediaStore(rootURL: root)).permanentlyDelete(entry)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryExternalSource>()), 0)
            try inbox.publish(payload, files: [:])
            try await assertScan(importer, failures: 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()), 0)
        }
    }

    func testAttachmentRollbackRetryAndMetadataFallback() async throws {
        let root = try temporaryRoot()
        let image = root.appendingPathComponent("test.png")
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        try bytes.write(to: image)
        let id = UUID()
        let attachment = CaptureAttachment(id: id, filename: id.uuidString.lowercased(), contentType: "image/png", byteCount: Int64(bytes.count), checksum: try ShareInbox.checksum(image))
        let inbox = ShareInbox(root: root.appendingPathComponent("Inbox"))
        let secondID = UUID()
        let second = CaptureAttachment(id: secondID, filename: secondID.uuidString.lowercased(), contentType: "image/png", byteCount: Int64(bytes.count), checksum: attachment.checksum)
        let payload = ShareImportPayload(source: CaptureSource(url: "https://example.com/unavailable", capturedAt: Date(), captureMode: .metadataOnly), images: [attachment, second])
        try inbox.publish(payload, files: [id: image, secondID: image])
        let container = try PersistenceContainerFactory.makeInMemory()
        let store = MediaStore(rootURL: root, availableCapacity: { .max })
        let importer = ExternalCaptureImporter(container: container, mediaStore: store, inbox: inbox)
        var copied = 0
        importer.checkpoint = {
            if $0 == "attachment" { copied += 1 }
            if copied == 2 { throw CaptureError.invalidPayload }
        }
        try await assertScan(importer, failures: 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Entry>()), 0)
        XCTAssertEqual(try store.originalsByteCount(), 0)
        importer.checkpoint = nil
        try await assertScan(importer, failures: 0)
        let entry = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<Entry>()).first)
        XCTAssertEqual(entry.body, payload.source?.url)
        XCTAssertNil(entry.title)
        XCTAssertEqual(entry.images.count, 2)
        XCTAssertEqual(try Data(contentsOf: store.fileURL(for: entry.images[0].relativePath)), bytes)
        let imageOnly = ShareImportPayload(images: [attachment])
        try inbox.publish(imageOnly, files: [id: image])
        try await assertScan(importer, failures: 0)
        let imageEntry = try XCTUnwrap(EntryRepository(context: container.mainContext).fetch(id: imageOnly.id))
        XCTAssertNil(imageEntry.body)
        XCTAssertEqual(imageEntry.images.count, 1)
    }

    func testCorruptAndUnsupportedPackagesRemainRecoverable() async throws {
        let root = try temporaryRoot()
        let inbox = ShareInbox(root: root)
        let payload = ShareImportPayload(text: "Keep me")
        try inbox.publish(payload, files: [:])
        let directory = try XCTUnwrap(inbox.pending().first)
        try Data("{broken".utf8).write(to: directory.appendingPathComponent("payload.json"))
        let container = try PersistenceContainerFactory.makeInMemory()
        let importer = ExternalCaptureImporter(container: container, mediaStore: MediaStore(rootURL: root), inbox: inbox)
        try await assertScan(importer, failures: 1)
        XCTAssertEqual(try inbox.pending().count, 1)
        var future = payload; future.schemaVersion = 99
        try JSONEncoder().encode(future).write(to: directory.appendingPathComponent("payload.json"))
        try await assertScan(importer, failures: 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Entry>()), 0)
        try JSONEncoder().encode(payload).write(to: directory.appendingPathComponent("payload.json"))
        try await assertScan(importer, failures: 0)
    }

    func testV9StoreMigrationPreservesEntryAndContinuations() throws {
        let root = try temporaryRoot()
        let url = root.appendingPathComponent("old.store")
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try autoreleasepool {
            let schema = Schema(versionedSchema: PersonalGrowthSchemaV9.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let context = container.mainContext
            context.insert(Entry(id: id, body: "Build 9 fact", createdAt: date))
            context.insert(EntryPin(entryID: id, pinnedAt: date))
            context.insert(EntryFollowUp(entryID: id, body: "Later thought", createdAt: date))
            try context.save()
        }
        for _ in 0..<2 {
            try autoreleasepool {
                let container = try PersistenceContainerFactory.makeOnDisk(at: url)
                let context = container.mainContext
                let entry = try XCTUnwrap(EntryRepository(context: context).fetch(id: id))
                XCTAssertEqual(entry.body, "Build 9 fact")
                XCTAssertEqual(entry.createdAt, date)
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryPin>()), 1)
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryFollowUp>()), 1)
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryExternalSource>()), 0)
            }
        }
    }
}

extension ExternalCaptureTests {
    func testSourceBackupRoundTrip() async throws {
        let root = try temporaryRoot()
        let sourceContainer = try PersistenceContainerFactory.makeInMemory()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = Entry(body: "Quote", createdAt: date)
        let source = CaptureSource(url: "https://example.com/page", canonicalURL: "https://example.com/canonical", title: "Saved title", siteName: "Example", capturedAt: date, captureMode: .selectedContent)
        sourceContainer.mainContext.insert(entry)
        sourceContainer.mainContext.insert(try EntryExternalSource(entryID: entry.id, source: source))
        try sourceContainer.mainContext.save()
        let media = root.appendingPathComponent("Source")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        let exporter = ImportExportService(context: sourceContainer.mainContext, mediaStore: MediaStore(rootURL: media), availableCapacity: { .max })
        let lease = try await exporter.exportPackage()
        defer { lease.cleanup() }
        let targetURL = root.appendingPathComponent("target.sqlite")
        try await restoreSourcePackage(lease.url, storeURL: targetURL, media: root.appendingPathComponent("Target"))
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: targetURL)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<EntryExternalSource>()).first?.source, source)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<Entry>()).first?.id, entry.id)
    }

    private func restoreSourcePackage(_ url: URL, storeURL: URL, media: URL) async throws {
        let target = try PersistenceContainerFactory.makeOnDisk(at: storeURL)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        let importer = ImportExportService(context: target.mainContext, mediaStore: MediaStore(rootURL: media), availableCapacity: { .max })
        let result = try await importer.importPackage(from: url)
        XCTAssertEqual(result.objectCounts["entrySources"], 1)
    }
}
