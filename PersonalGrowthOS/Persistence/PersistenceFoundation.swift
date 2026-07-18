import Foundation
import SwiftData

@Model
final class Entry {
    @Attribute(.unique) var id: UUID
    var kindRawValue: String
    var statusRawValue: String
    var title: String?
    var body: String?
    var createdAt: Date
    var occurredAt: Date
    var updatedAt: Date
    var periodStart: Date?
    var periodEnd: Date?

    @Relationship(deleteRule: .cascade, inverse: \ImageMetadata.entry)
    var images: [ImageMetadata]

    var kind: EntryKind {
        get { EntryKind(rawValue: kindRawValue) ?? .quickNote }
        set { kindRawValue = newValue.rawValue }
    }

    var status: EntryStatus {
        get { EntryStatus(rawValue: statusRawValue) ?? .inbox }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        kind: EntryKind = .quickNote,
        status: EntryStatus = .inbox,
        title: String? = nil,
        body: String? = nil,
        createdAt: Date,
        occurredAt: Date? = nil,
        updatedAt: Date? = nil,
        periodStart: Date? = nil,
        periodEnd: Date? = nil,
        images: [ImageMetadata] = []
    ) {
        self.id = id
        kindRawValue = kind.rawValue
        statusRawValue = status.rawValue
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.occurredAt = occurredAt ?? createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.images = images
    }
}

@Model
final class ImageMetadata {
    @Attribute(.unique) var id: UUID
    var relativePath: String
    var originalFilename: String
    var contentType: String
    var byteCount: Int64
    var pixelWidth: Int
    var pixelHeight: Int
    var checksum: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var entry: Entry?

    init(
        id: UUID,
        relativePath: String,
        originalFilename: String,
        contentType: String,
        byteCount: Int64,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        checksum: String,
        sortOrder: Int = 0,
        createdAt: Date,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.relativePath = relativePath
        self.originalFilename = originalFilename
        self.contentType = contentType
        self.byteCount = byteCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.checksum = checksum
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

enum PersonalGrowthSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Entry.self, ImageMetadata.self]
    }
}

enum PersonalGrowthMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PersonalGrowthSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

enum PersistenceContainerFactory {
    static func makeInMemory() throws -> ModelContainer {
        try make(configuration: ModelConfiguration(
            "PersonalGrowthOSV1",
            schema: Schema(versionedSchema: PersonalGrowthSchemaV1.self),
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        ))
    }

    static func makeOnDisk(at storeURL: URL) throws -> ModelContainer {
        try make(configuration: ModelConfiguration(
            "PersonalGrowthOSV1",
            schema: Schema(versionedSchema: PersonalGrowthSchemaV1.self),
            url: storeURL,
            cloudKitDatabase: .none
        ))
    }

    private static func make(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: PersonalGrowthSchemaV1.self),
            migrationPlan: PersonalGrowthMigrationPlan.self,
            configurations: [configuration]
        )
    }
}

@MainActor
final class EntryRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func save(_ entry: Entry) throws {
        context.insert(entry)
        try context.save()
    }

    func saveChanges() throws {
        try context.save()
    }

    func fetchAll() throws -> [Entry] {
        let descriptor = FetchDescriptor<Entry>(sortBy: [
            SortDescriptor(\Entry.occurredAt, order: .reverse),
            SortDescriptor(\Entry.createdAt, order: .reverse),
            SortDescriptor(\Entry.id, order: .forward)
        ])
        return try context.fetch(descriptor)
    }

    func fetch(id: UUID) throws -> Entry? {
        let requestedID = id
        var descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.id == requestedID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

@MainActor
protocol EntryPersisting: AnyObject {
    func insert(_ entry: Entry)
    func save() throws
    func rollback()
}

@MainActor
final class ModelContextEntryPersistence: EntryPersisting {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func insert(_ entry: Entry) {
        context.insert(entry)
    }

    func save() throws {
        try context.save()
    }

    func rollback() {
        context.rollback()
    }
}

struct EntryCreationDraft {
    var title: String?
    var body: String?
    var occurredAt: Date?
    var images: [MediaSource]

    init(
        title: String? = nil,
        body: String? = nil,
        occurredAt: Date? = nil,
        image: MediaSource? = nil,
        images: [MediaSource] = []
    ) {
        self.title = title
        self.body = body
        self.occurredAt = occurredAt
        self.images = image.map { [$0] } ?? images
    }
}

enum EntryMediaOperationError: Error, Equatable {
    case rollbackIncomplete
}

@MainActor
final class EntryCreationService {
    private let persistence: any EntryPersisting
    private let mediaStore: MediaStore
    private let now: () -> Date

    init(
        persistence: any EntryPersisting,
        mediaStore: MediaStore,
        now: @escaping () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.mediaStore = mediaStore
        self.now = now
    }

    func create(_ draft: EntryCreationDraft) throws -> Entry {
        try EntryRules.validateContent(body: draft.body, imageCount: draft.images.count)

        var storedFiles: [StoredMediaFile] = []
        do {
            try mediaStore.ensureCapacity(for: draft.images)
            for image in draft.images {
                storedFiles.append(try mediaStore.storeOriginal(image))
            }

            let timestamp = now()
            let metadata = zip(storedFiles, draft.images).enumerated().map { index, pair in
                let (storedFile, source) = pair
                return ImageMetadata(
                    id: storedFile.id,
                    relativePath: storedFile.relativePath,
                    originalFilename: source.originalFilename,
                    contentType: source.contentType,
                    byteCount: storedFile.byteCount,
                    pixelWidth: storedFile.pixelWidth,
                    pixelHeight: storedFile.pixelHeight,
                    checksum: storedFile.checksum,
                    sortOrder: index,
                    createdAt: timestamp
                )
            }
            let entry = Entry(
                title: draft.title,
                body: draft.body,
                createdAt: timestamp,
                occurredAt: draft.occurredAt,
                images: metadata
            )
            metadata.forEach { $0.entry = entry }

            persistence.insert(entry)
            try persistence.save()
            return entry
        } catch let operationError {
            persistence.rollback()
            var rollbackIncomplete = false
            for storedFile in storedFiles {
                do {
                    try mediaStore.removeOriginal(at: storedFile.relativePath)
                } catch {
                    rollbackIncomplete = true
                }
            }
            if rollbackIncomplete {
                throw EntryMediaOperationError.rollbackIncomplete
            }
            throw operationError
        }
    }
}

@MainActor
protocol EntryDeletingPersistence: AnyObject {
    func delete(_ entry: Entry)
    func save() throws
    func rollback()
}

extension ModelContextEntryPersistence: EntryDeletingPersistence {
    func delete(_ entry: Entry) {
        context.delete(entry)
    }
}

@MainActor
protocol EntryEditingPersistence: AnyObject {
    func delete(_ image: ImageMetadata)
    func save() throws
    func rollback()
}

extension ModelContextEntryPersistence: EntryEditingPersistence {
    func delete(_ image: ImageMetadata) {
        context.delete(image)
    }
}

struct EntryEditingDraft {
    let title: String?
    let body: String?
    let occurredAt: Date
    let retainedImageIDs: [UUID]
    let addedImages: [MediaSource]
}

@MainActor
final class EntryEditingService {
    private let persistence: any EntryEditingPersistence
    private let mediaStore: MediaStore
    private let now: () -> Date
    private let thumbnailCleanup: (UUID) -> Void

    init(
        persistence: any EntryEditingPersistence,
        mediaStore: MediaStore,
        now: @escaping () -> Date = Date.init,
        thumbnailCleanup: @escaping (UUID) -> Void = { _ in }
    ) {
        self.persistence = persistence
        self.mediaStore = mediaStore
        self.now = now
        self.thumbnailCleanup = thumbnailCleanup
    }

    func update(_ entry: Entry, with draft: EntryEditingDraft) throws {
        let imagesByID = Dictionary(
            entry.images.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let retained = draft.retainedImageIDs.compactMap { imagesByID[$0] }
        let retainedIDs = Set(draft.retainedImageIDs)
        let removed = imagesByID.values.filter { !retainedIDs.contains($0.id) }
        let finalImageCount = retained.count + draft.addedImages.count
        try EntryRules.validateContent(body: draft.body, imageCount: finalImageCount)

        let originalTitle = entry.title
        let originalBody = entry.body
        let originalOccurredAt = entry.occurredAt
        let originalUpdatedAt = entry.updatedAt
        let originalImages = entry.images
        let originalSortOrders = Dictionary(
            entry.images.map { ($0.id, $0.sortOrder) },
            uniquingKeysWith: { first, _ in first }
        )
        var addedFiles: [StoredMediaFile] = []
        var trashedFiles: [TrashedMediaFile] = []

        do {
            try mediaStore.ensureCapacity(for: draft.addedImages)
            for source in draft.addedImages {
                addedFiles.append(try mediaStore.storeOriginal(source))
            }
            for image in removed {
                trashedFiles.append(try mediaStore.moveToTrash(image.relativePath))
            }

            let timestamp = now()
            let addedMetadata = zip(addedFiles, draft.addedImages).enumerated().map { offset, pair in
                let (file, source) = pair
                return ImageMetadata(
                    id: file.id,
                    relativePath: file.relativePath,
                    originalFilename: source.originalFilename,
                    contentType: source.contentType,
                    byteCount: file.byteCount,
                    pixelWidth: file.pixelWidth,
                    pixelHeight: file.pixelHeight,
                    checksum: file.checksum,
                    sortOrder: retained.count + offset,
                    createdAt: timestamp
                )
            }
            retained.enumerated().forEach { index, image in image.sortOrder = index }
            addedMetadata.forEach { $0.entry = entry }
            removed.forEach { persistence.delete($0) }
            entry.title = draft.title
            entry.body = draft.body
            entry.occurredAt = draft.occurredAt
            entry.updatedAt = timestamp
            entry.images = retained + addedMetadata
            try persistence.save()
        } catch let operationError {
            persistence.rollback()
            var rollbackIncomplete = false
            for file in addedFiles {
                do {
                    try mediaStore.removeOriginal(at: file.relativePath)
                } catch {
                    rollbackIncomplete = true
                }
            }
            for file in trashedFiles.reversed() {
                do {
                    try mediaStore.restoreFromTrash(file)
                } catch {
                    rollbackIncomplete = true
                }
            }
            entry.title = originalTitle
            entry.body = originalBody
            entry.occurredAt = originalOccurredAt
            entry.updatedAt = originalUpdatedAt
            entry.images = originalImages
            originalImages.forEach {
                $0.entry = entry
                $0.sortOrder = originalSortOrders[$0.id] ?? $0.sortOrder
            }
            if rollbackIncomplete {
                throw EntryMediaOperationError.rollbackIncomplete
            }
            throw operationError
        }

        for file in trashedFiles {
            do {
                try mediaStore.purgeTrash(file)
            } catch {
                // Startup reconciliation safely retries committed trash cleanup.
            }
        }
        removed.forEach { thumbnailCleanup($0.id) }
    }
}

@MainActor
final class EntryDeletionService {
    private let persistence: any EntryDeletingPersistence
    private let mediaStore: MediaStore
    private let now: () -> Date
    private let thumbnailCleanup: (UUID) -> Void

    init(
        persistence: any EntryDeletingPersistence,
        mediaStore: MediaStore,
        now: @escaping () -> Date = Date.init,
        thumbnailCleanup: @escaping (UUID) -> Void = { _ in }
    ) {
        self.persistence = persistence
        self.mediaStore = mediaStore
        self.now = now
        self.thumbnailCleanup = thumbnailCleanup
    }

    func archive(_ entry: Entry) throws {
        let originalStatus = entry.status
        let originalUpdatedAt = entry.updatedAt
        entry.status = .archived
        entry.updatedAt = now()
        do {
            try persistence.save()
        } catch {
            persistence.rollback()
            entry.status = originalStatus
            entry.updatedAt = originalUpdatedAt
            throw error
        }
    }

    func restore(_ entry: Entry) throws {
        let originalStatus = entry.status
        let originalUpdatedAt = entry.updatedAt
        entry.status = .organized
        entry.updatedAt = now()
        do {
            try persistence.save()
        } catch {
            persistence.rollback()
            entry.status = originalStatus
            entry.updatedAt = originalUpdatedAt
            throw error
        }
    }

    func permanentlyDelete(_ entry: Entry) throws {
        let imageIDs = entry.images.map(\.id)
        var trashedFiles: [TrashedMediaFile] = []
        do {
            for image in entry.images {
                trashedFiles.append(try mediaStore.moveToTrash(image.relativePath))
            }
            persistence.delete(entry)
            try persistence.save()
        } catch let operationError {
            persistence.rollback()
            var rollbackIncomplete = false
            for trashedFile in trashedFiles.reversed() {
                do {
                    try mediaStore.restoreFromTrash(trashedFile)
                } catch {
                    rollbackIncomplete = true
                }
            }
            if rollbackIncomplete {
                throw EntryMediaOperationError.rollbackIncomplete
            }
            throw operationError
        }
        for trashedFile in trashedFiles {
            do {
                try mediaStore.purgeTrash(trashedFile)
            } catch {
                // Startup reconciliation safely retries committed trash cleanup.
            }
        }
        imageIDs.forEach(thumbnailCleanup)
    }
}
