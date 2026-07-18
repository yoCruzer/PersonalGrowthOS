import Foundation
import SwiftData
import UIKit
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
        crc ^= UInt32(byte)
        for _ in 0..<8 {
            crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb8_8320 : 0)
        }
    }
    return crc ^ 0xffff_ffff
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
