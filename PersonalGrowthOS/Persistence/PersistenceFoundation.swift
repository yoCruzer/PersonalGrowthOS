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
            SortDescriptor(\Entry.createdAt, order: .reverse)
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
    var image: MediaSource?
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
        try EntryRules.validateContent(body: draft.body, imageCount: draft.image == nil ? 0 : 1)

        var storedFile: StoredMediaFile?
        do {
            if let image = draft.image {
                storedFile = try mediaStore.storeOriginal(image)
            }

            let timestamp = now()
            let metadata = storedFile.map {
                ImageMetadata(
                    id: $0.id,
                    relativePath: $0.relativePath,
                    originalFilename: draft.image?.originalFilename ?? "image",
                    contentType: draft.image?.contentType ?? "application/octet-stream",
                    byteCount: $0.byteCount,
                    checksum: $0.checksum,
                    createdAt: timestamp
                )
            }
            let entry = Entry(
                title: draft.title,
                body: draft.body,
                createdAt: timestamp,
                occurredAt: draft.occurredAt,
                images: metadata.map { [$0] } ?? []
            )
            metadata?.entry = entry

            persistence.insert(entry)
            try persistence.save()
            return entry
        } catch {
            persistence.rollback()
            if let storedFile {
                try? mediaStore.removeOriginal(at: storedFile.relativePath)
            }
            throw error
        }
    }
}
