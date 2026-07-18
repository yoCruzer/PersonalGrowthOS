import Foundation
import SwiftData
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
        let bytes = Data("original-image-bytes".utf8)
        try bytes.write(to: fixture.sourceURL)
        let store = MediaStore(rootURL: fixture.mediaRoot)

        let stored = try store.storeOriginal(MediaSource(
            url: fixture.sourceURL,
            originalFilename: "memory.jpg",
            contentType: "image/jpeg"
        ))

        XCTAssertFalse(stored.relativePath.hasPrefix("/"))
        XCTAssertEqual(stored.byteCount, Int64(bytes.count))
        XCTAssertEqual(try Data(contentsOf: store.fileURL(for: stored.relativePath)), bytes)
        XCTAssertEqual(stored.checksum.count, 64)
    }

    func testCreationPersistsRelativeMetadataWithoutImageBinary() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let bytes = Data("image".utf8)
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
        try Data("image".utf8).write(to: fixture.sourceURL)
        let persistence = FailingEntryPersistence()
        let mediaStore = MediaStore(rootURL: fixture.mediaRoot)
        let service = EntryCreationService(persistence: persistence, mediaStore: mediaStore)

        XCTAssertThrowsError(try service.create(EntryCreationDraft(
            body: "Draft remains with caller",
            image: MediaSource(
                url: fixture.sourceURL,
                originalFilename: "memory.jpg",
                contentType: "image/jpeg"
            )
        )))

        XCTAssertTrue(persistence.didRollback)
        XCTAssertEqual(try fixture.originalFiles(), [])
        XCTAssertEqual(try Data(contentsOf: fixture.sourceURL), Data("image".utf8))
    }

    func testIdentityCollisionDoesNotDeleteExistingOriginal() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }
        let firstBytes = Data("first-image".utf8)
        let secondBytes = Data("second-image".utf8)
        try firstBytes.write(to: fixture.sourceURL)
        let store = MediaStore(rootURL: fixture.mediaRoot)
        let imageID = UUID()
        let source = MediaSource(
            url: fixture.sourceURL,
            originalFilename: "memory.jpg",
            contentType: "image/jpeg"
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
                originalFilename: "missing.jpg",
                contentType: "image/jpeg"
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
        try Data("image".utf8).write(to: fixture.sourceURL)
        let persistence = RecordingEntryPersistence()
        let service = EntryCreationService(
            persistence: persistence,
            mediaStore: MediaStore(rootURL: fixture.mediaRoot, availableCapacity: { 1 })
        )

        XCTAssertThrowsError(try service.create(EntryCreationDraft(
            body: "Keep this draft",
            image: MediaSource(
                url: fixture.sourceURL,
                originalFilename: "memory.jpg",
                contentType: "image/jpeg"
            )
        ))) {
            XCTAssertEqual(
                $0 as? MediaStoreError,
                .insufficientCapacity(requiredBytes: 10, availableBytes: 1)
            )
        }
        XCTAssertNil(persistence.insertedEntry)
        XCTAssertEqual(try fixture.originalFiles(), [])
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

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
