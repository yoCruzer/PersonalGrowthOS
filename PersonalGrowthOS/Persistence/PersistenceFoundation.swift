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

enum PersonalGrowthSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Entry.self, ImageMetadata.self, Tag.self, ObjectLink.self]
    }
}

enum PersonalGrowthSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Entry.self, ImageMetadata.self, Tag.self, ObjectLink.self, Habit.self, HabitLog.self]
    }
}

enum PersonalGrowthSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            Entry.self, ImageMetadata.self, Tag.self, ObjectLink.self,
            Habit.self, HabitLog.self, Goal.self, GoalLifecycleEvent.self
        ]
    }
}

enum PersonalGrowthSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            Entry.self, ImageMetadata.self, Tag.self, ObjectLink.self,
            Habit.self, HabitLog.self, HabitConfiguration.self,
            Goal.self, GoalLifecycleEvent.self
        ]
    }
}

enum PersonalGrowthSchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            Entry.self, ImageMetadata.self, Tag.self, ObjectLink.self,
            Habit.self, HabitLog.self, HabitConfiguration.self,
            Goal.self, GoalLifecycleEvent.self, WeightRecord.self
        ]
    }
}

enum PersonalGrowthSchemaV7: VersionedSchema {
    static let versionIdentifier = Schema.Version(7, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            Entry.self, ImageMetadata.self, Tag.self, ObjectLink.self,
            Habit.self, HabitLog.self, HabitConfiguration.self,
            Goal.self, GoalLifecycleEvent.self, WeightRecord.self, WeeklyReview.self
        ]
    }
}

enum PersonalGrowthSchemaV8: VersionedSchema {
    static let versionIdentifier = Schema.Version(8, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            Entry.self, ImageMetadata.self, Tag.self, ObjectLink.self,
            Habit.self, HabitLog.self, HabitConfiguration.self,
            HabitLogDayMetadata.self, HabitPlanRevision.self, HabitLifecycleEvent.self,
            Goal.self, GoalLifecycleEvent.self, WeightRecord.self, WeeklyReview.self
        ]
    }
}

// Additive entities preserve the checksums of every historical shared Entry schema.
@Model
final class EntryPin {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var entryID: UUID
    var pinnedAt: Date

    init(id: UUID = UUID(), entryID: UUID, pinnedAt: Date) {
        self.id = id
        self.entryID = entryID
        self.pinnedAt = pinnedAt
    }
}

@Model
final class EntryFollowUp {
    @Attribute(.unique) var id: UUID
    var entryID: UUID
    var body: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), entryID: UUID, body: String, createdAt: Date, updatedAt: Date? = nil) {
        self.id = id
        self.entryID = entryID
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

enum PersonalGrowthSchemaV9: VersionedSchema {
    static let versionIdentifier = Schema.Version(9, 0, 0)
    static var models: [any PersistentModel.Type] {
        PersonalGrowthSchemaV8.models + [EntryPin.self, EntryFollowUp.self]
    }
}

enum PersonalGrowthMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            PersonalGrowthSchemaV1.self,
            PersonalGrowthSchemaV2.self,
            PersonalGrowthSchemaV3.self,
            PersonalGrowthSchemaV4.self,
            PersonalGrowthSchemaV5.self,
            PersonalGrowthSchemaV6.self,
            PersonalGrowthSchemaV7.self,
            PersonalGrowthSchemaV8.self,
            PersonalGrowthSchemaV9.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            MigrationStage.lightweight(
                fromVersion: PersonalGrowthSchemaV1.self,
                toVersion: PersonalGrowthSchemaV2.self
            ),
            MigrationStage.lightweight(
                fromVersion: PersonalGrowthSchemaV2.self,
                toVersion: PersonalGrowthSchemaV3.self
            ),
            MigrationStage.lightweight(
                fromVersion: PersonalGrowthSchemaV3.self,
                toVersion: PersonalGrowthSchemaV4.self
            ),
            MigrationStage.lightweight(
                fromVersion: PersonalGrowthSchemaV4.self,
                toVersion: PersonalGrowthSchemaV5.self
            ),
            MigrationStage.lightweight(
                fromVersion: PersonalGrowthSchemaV5.self,
                toVersion: PersonalGrowthSchemaV6.self
            ),
            MigrationStage.lightweight(
                fromVersion: PersonalGrowthSchemaV6.self,
                toVersion: PersonalGrowthSchemaV7.self
            ),
            MigrationStage.lightweight(
                fromVersion: PersonalGrowthSchemaV7.self,
                toVersion: PersonalGrowthSchemaV8.self
            ),
            MigrationStage.lightweight(
                fromVersion: PersonalGrowthSchemaV8.self,
                toVersion: PersonalGrowthSchemaV9.self
            )
        ]
    }
}

enum PersistenceContainerFactory {
    static func makeInMemory() throws -> ModelContainer {
        try make(configuration: ModelConfiguration(
            "PersonalGrowthOSV1",
            schema: Schema(versionedSchema: PersonalGrowthSchemaV9.self),
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        ))
    }

    static func makeOnDisk(at storeURL: URL) throws -> ModelContainer {
        try make(configuration: ModelConfiguration(
            "PersonalGrowthOSV1",
            schema: Schema(versionedSchema: PersonalGrowthSchemaV9.self),
            url: storeURL,
            cloudKitDatabase: .none
        ))
    }

    private static func make(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: PersonalGrowthSchemaV9.self),
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

struct ReviewCreationDraft {
    var entryDraft: EntryCreationDraft
    var period: ReviewPeriod?
    var reviewedEntryIDs: Set<UUID>
    var reviewedHabitIDs: Set<UUID>
    var reviewedGoalIDs: Set<UUID>

    init(
        entryDraft: EntryCreationDraft,
        period: ReviewPeriod? = nil,
        reviewedEntryIDs: Set<UUID> = [],
        reviewedHabitIDs: Set<UUID> = [],
        reviewedGoalIDs: Set<UUID> = []
    ) {
        self.entryDraft = entryDraft
        self.period = period
        self.reviewedEntryIDs = reviewedEntryIDs
        self.reviewedHabitIDs = reviewedHabitIDs
        self.reviewedGoalIDs = reviewedGoalIDs
    }
}

@MainActor
final class ReviewCreationService {
    private let context: ModelContext
    private let mediaStore: MediaStore
    private let now: () -> Date
    private let save: () throws -> Void

    init(
        context: ModelContext,
        mediaStore: MediaStore,
        now: @escaping () -> Date = Date.init,
        save: (() throws -> Void)? = nil
    ) {
        self.context = context
        self.mediaStore = mediaStore
        self.now = now
        self.save = save ?? { try context.save() }
    }

    func create(_ draft: ReviewCreationDraft) throws -> Entry {
        try EntryRules.validateContent(
            body: draft.entryDraft.body,
            imageCount: draft.entryDraft.images.count
        )
        try EntryRules.validatePeriod(draft.period, for: .review)
        try validateEndpoints(draft)

        var storedFiles: [StoredMediaFile] = []
        do {
            try mediaStore.ensureCapacity(for: draft.entryDraft.images)
            for image in draft.entryDraft.images {
                storedFiles.append(try mediaStore.storeOriginal(image))
            }

            let timestamp = now()
            let metadata = zip(storedFiles, draft.entryDraft.images).enumerated().map { index, pair in
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
                kind: .review,
                title: draft.entryDraft.title,
                body: draft.entryDraft.body,
                createdAt: timestamp,
                occurredAt: draft.entryDraft.occurredAt,
                periodStart: draft.period?.start,
                periodEnd: draft.period?.end,
                images: metadata
            )
            metadata.forEach { $0.entry = entry }
            context.insert(entry)
            reviewLinks(for: entry.id, draft: draft, createdAt: timestamp).forEach(context.insert)
            try save()
            return entry
        } catch let operationError {
            context.rollback()
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

    private func validateEndpoints(_ draft: ReviewCreationDraft) throws {
        let entryIDs = Set(try context.fetch(FetchDescriptor<Entry>()).map(\.id))
        let habitIDs = Set(try context.fetch(FetchDescriptor<Habit>()).map(\.id))
        let goalIDs = Set(try context.fetch(FetchDescriptor<Goal>()).map(\.id))
        guard draft.reviewedEntryIDs.isSubset(of: entryIDs),
              draft.reviewedHabitIDs.isSubset(of: habitIDs),
              draft.reviewedGoalIDs.isSubset(of: goalIDs) else {
            throw CoreLinkValidationError.missingEndpoint
        }
    }

    private func reviewLinks(
        for reviewID: UUID,
        draft: ReviewCreationDraft,
        createdAt: Date
    ) -> [ObjectLink] {
        let entryLinks = draft.reviewedEntryIDs.map {
            ObjectLink(
                sourceType: .entry,
                sourceID: reviewID,
                targetType: .entry,
                targetID: $0,
                kind: .reviewsEntry,
                createdAt: createdAt
            )
        }
        let habitLinks = draft.reviewedHabitIDs.map {
            ObjectLink(
                sourceType: .entry,
                sourceID: reviewID,
                targetType: .habit,
                targetID: $0,
                kind: .reviewsHabit,
                createdAt: createdAt
            )
        }
        let goalLinks = draft.reviewedGoalIDs.map {
            ObjectLink(
                sourceType: .entry,
                sourceID: reviewID,
                targetType: .goal,
                targetID: $0,
                kind: .reviewsGoal,
                createdAt: createdAt
            )
        }
        return entryLinks + habitLinks + goalLinks
    }
}

@MainActor
protocol EntryDeletingPersistence: AnyObject {
    func deleteLinks(involving objectID: UUID) throws
    func clearHabitLogEntryReferences(linkedTo entryID: UUID) throws
    func deleteContinuations(entryID: UUID) throws
    func delete(_ entry: Entry)
    func save() throws
    func rollback()
}

extension EntryDeletingPersistence {
    func deleteLinks(involving objectID: UUID) throws {}
    func clearHabitLogEntryReferences(linkedTo entryID: UUID) throws {}
    func deleteContinuations(entryID: UUID) throws {}
}

extension ModelContextEntryPersistence: EntryDeletingPersistence {
    func deleteContinuations(entryID: UUID) throws {
        try context.fetch(FetchDescriptor<EntryPin>(predicate: #Predicate { $0.entryID == entryID }))
            .forEach(context.delete)
        try context.fetch(FetchDescriptor<EntryFollowUp>(predicate: #Predicate { $0.entryID == entryID }))
            .forEach(context.delete)
    }

    func deleteLinks(involving objectID: UUID) throws {
        let entryType = LinkObjectType.entry.rawValue
        let descriptor = FetchDescriptor<ObjectLink>(
            predicate: #Predicate {
                ($0.sourceTypeRawValue == entryType && $0.sourceID == objectID)
                    || ($0.targetTypeRawValue == entryType && $0.targetID == objectID)
            }
        )
        try context.fetch(descriptor).forEach(context.delete)
    }

    func clearHabitLogEntryReferences(linkedTo entryID: UUID) throws {
        let descriptor = FetchDescriptor<HabitLog>(
            predicate: #Predicate { $0.linkedEntryID == entryID }
        )
        try context.fetch(descriptor).forEach { $0.linkedEntryID = nil }
    }

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

enum EntryEditingImage {
    case retained(UUID)
    case added(MediaSource)
}

struct EntryEditingDraft {
    let title: String?
    let body: String?
    let occurredAt: Date
    let orderedImages: [EntryEditingImage]

    init(
        title: String?,
        body: String?,
        occurredAt: Date,
        retainedImageIDs: [UUID],
        addedImages: [MediaSource]
    ) {
        self.title = title
        self.body = body
        self.occurredAt = occurredAt
        orderedImages = retainedImageIDs.map(EntryEditingImage.retained)
            + addedImages.map(EntryEditingImage.added)
    }

    init(
        title: String?,
        body: String?,
        occurredAt: Date,
        orderedImages: [EntryEditingImage]
    ) {
        self.title = title
        self.body = body
        self.occurredAt = occurredAt
        self.orderedImages = orderedImages
    }
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
        let retainedImageIDs = draft.orderedImages.compactMap { image -> UUID? in
            guard case .retained(let id) = image else { return nil }
            return id
        }
        let addedImages = draft.orderedImages.compactMap { image -> MediaSource? in
            guard case .added(let source) = image else { return nil }
            return source
        }
        let retained = retainedImageIDs.compactMap { imagesByID[$0] }
        let retainedIDs = Set(retainedImageIDs)
        let removed = imagesByID.values.filter { !retainedIDs.contains($0.id) }
        let finalImageCount = retained.count + addedImages.count
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
            try mediaStore.ensureCapacity(for: addedImages)
            for source in addedImages {
                addedFiles.append(try mediaStore.storeOriginal(source))
            }
            for image in removed {
                trashedFiles.append(try mediaStore.moveToTrash(image.relativePath))
            }

            let timestamp = now()
            let addedMetadata = zip(addedFiles, addedImages).map { pair in
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
                    createdAt: timestamp
                )
            }
            var addedIndex = 0
            let finalImages = draft.orderedImages.compactMap { orderedImage -> ImageMetadata? in
                switch orderedImage {
                case .retained(let id):
                    return imagesByID[id]
                case .added:
                    defer { addedIndex += 1 }
                    return addedMetadata[addedIndex]
                }
            }
            finalImages.enumerated().forEach { index, image in image.sortOrder = index }
            addedMetadata.forEach { $0.entry = entry }
            removed.forEach { persistence.delete($0) }
            entry.title = draft.title
            entry.body = draft.body
            entry.occurredAt = draft.occurredAt
            entry.updatedAt = timestamp
            entry.images = finalImages
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
        try transition(entry, to: .archived)
    }

    func organize(_ entry: Entry) throws {
        try transition(entry, to: .organized)
    }

    func moveToInbox(_ entry: Entry) throws {
        try transition(entry, to: .inbox)
    }

    func restore(_ entry: Entry) throws {
        try transition(entry, to: .organized)
    }

    private func transition(_ entry: Entry, to status: EntryStatus) throws {
        let originalStatus = entry.status
        let originalUpdatedAt = entry.updatedAt
        entry.status = status
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
            try persistence.clearHabitLogEntryReferences(linkedTo: entry.id)
            try persistence.deleteLinks(involving: entry.id)
            try persistence.deleteContinuations(entryID: entry.id)
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

/// These operations never mutate the parent Entry's content or timestamps.
@MainActor
final class EntryContinuationService {
    enum Failure: Error { case missingEntry, archivedEntry, blankBody, missingFollowUp }
    private let context: ModelContext
    private let now: () -> Date
    private let save: () throws -> Void

    init(context: ModelContext, now: @escaping () -> Date = Date.init, save: (() throws -> Void)? = nil) {
        self.context = context
        self.now = now
        self.save = save ?? { try context.save() }
    }

    private func requireEditable(_ entryID: UUID) throws {
        guard let entry = try EntryRepository(context: context).fetch(id: entryID) else {
            throw Failure.missingEntry
        }
        guard entry.status != .archived else { throw Failure.archivedEntry }
    }

    func setPinned(_ pinned: Bool, entryID: UUID) throws {
        try requireEditable(entryID)
        let existing = try context.fetch(FetchDescriptor<EntryPin>(predicate: #Predicate { $0.entryID == entryID }))
        if pinned && !existing.isEmpty || !pinned && existing.isEmpty { return }
        do {
            if pinned { context.insert(EntryPin(entryID: entryID, pinnedAt: now())) }
            else { existing.forEach { context.delete($0) } }
            try save()
        } catch { context.rollback(); throw error }
    }

    @discardableResult
    func add(entryID: UUID, body: String, id: UUID = UUID()) throws -> EntryFollowUp {
        try requireEditable(entryID)
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.blankBody }
        if let existing = try context.fetch(FetchDescriptor<EntryFollowUp>(predicate: #Predicate { $0.id == id })).first {
            guard existing.entryID == entryID else { throw Failure.missingFollowUp }
            return existing
        }
        let followUp = EntryFollowUp(id: id, entryID: entryID, body: body, createdAt: now())
        do {
            context.insert(followUp)
            try save()
            return followUp
        } catch { context.rollback(); throw error }
    }

    func edit(_ followUp: EntryFollowUp, body: String) throws {
        try requireEditable(followUp.entryID)
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.blankBody }
        guard body != followUp.body else { return }
        do {
            followUp.body = body
            followUp.updatedAt = now()
            try save()
        } catch { context.rollback(); throw error }
    }

    func delete(_ followUp: EntryFollowUp) throws {
        try requireEditable(followUp.entryID)
        do {
            context.delete(followUp)
            try save()
        } catch { context.rollback(); throw error }
    }
}

enum EntryPinOrdering {
    static func entries(pins: [EntryPin], entries: [Entry]) -> [Entry] {
        let byID = Dictionary(entries.filter { $0.status != .archived }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return pins.sorted {
            $0.pinnedAt == $1.pinnedAt ? $0.id.uuidString < $1.id.uuidString : $0.pinnedAt > $1.pinnedAt
        }.compactMap { byID[$0.entryID] }
    }
}
