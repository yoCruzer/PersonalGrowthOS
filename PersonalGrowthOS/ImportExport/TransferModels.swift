import Foundation

struct ExportManifest: Codable, Equatable {
    static let formatIdentifier = "com.yocruzer.PersonalGrowthOS.export"
    static let currentPackageSchemaVersion = 1

    let formatIdentifier: String
    let packageSchemaVersion: Int
    let appVersion: String
    let appBuild: String
    let exportID: UUID
    let exportedAt: Date
    let objectCounts: [String: Int]
    let dataFile: ExportFileRecord
    let mediaFiles: [ExportMediaFileRecord]
}

struct ExportFileRecord: Codable, Equatable {
    let path: String
    let byteCount: Int64
    let sha256: String
}

struct ExportMediaFileRecord: Codable, Equatable {
    let imageID: UUID
    let path: String
    let byteCount: Int64
    let sha256: String
}

struct TransferData: Codable, Equatable {
    let entries: [EntryTransfer]
    let images: [ImageTransfer]
    let tags: [TagTransfer]
    let links: [LinkTransfer]
    let habits: [HabitTransfer]
    let habitLogs: [HabitLogTransfer]
    let goals: [GoalTransfer]
    let goalEvents: [GoalEventTransfer]

    var objectCounts: [String: Int] {
        [
            "entries": entries.count,
            "images": images.count,
            "tags": tags.count,
            "links": links.count,
            "habits": habits.count,
            "habitLogs": habitLogs.count,
            "goals": goals.count,
            "goalEvents": goalEvents.count
        ]
    }

    var totalObjectCount: Int {
        objectCounts.values.reduce(0, +)
    }
}

struct EntryTransfer: Codable, Equatable {
    let id: UUID
    let kind: String
    let status: String
    let title: String?
    let body: String?
    let createdAt: Date
    let occurredAt: Date
    let updatedAt: Date
    let periodStart: Date?
    let periodEnd: Date?
}

struct ImageTransfer: Codable, Equatable {
    let id: UUID
    let entryID: UUID
    let relativePath: String
    let mediaPath: String
    let originalFilename: String
    let contentType: String
    let byteCount: Int64
    let pixelWidth: Int
    let pixelHeight: Int
    let checksum: String
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date
}

struct TagTransfer: Codable, Equatable {
    let id: UUID
    let displayName: String
    let normalizedName: String
    let createdAt: Date
    let updatedAt: Date
}

struct LinkTransfer: Codable, Equatable {
    let id: UUID
    let sourceType: String
    let sourceID: UUID
    let targetType: String
    let targetID: UUID
    let kind: String
    let deduplicationKey: String
    let createdAt: Date
}

struct HabitTransfer: Codable, Equatable {
    let id: UUID
    let name: String
    let normalizedName: String
    let status: String
    let createdAt: Date
    let updatedAt: Date
}

struct HabitLogTransfer: Codable, Equatable {
    let id: UUID
    let habitID: UUID
    let occurredAt: Date
    let isCompleted: Bool
    let quantity: Double?
    let unit: String?
    let result: String?
    let linkedEntryID: UUID?
    let createdAt: Date
}

struct GoalTransfer: Codable, Equatable {
    let id: UUID
    let kind: String
    let title: String
    let normalizedTitle: String
    let status: String
    let createdAt: Date
    let updatedAt: Date
    let completedAt: Date?
}

struct GoalEventTransfer: Codable, Equatable {
    let id: UUID
    let goalID: UUID
    let kind: String
    let occurredAt: Date
    let createdAt: Date
}

enum TransferPackageError: Error, Equatable {
    case invalidFormat
    case unsupportedSchema(Int)
    case corruptManifest
    case corruptData
    case countMismatch
    case objectLimitExceeded
    case duplicateID(String)
    case duplicateNormalizedTag
    case invalidObject(String)
    case missingEndpoint
    case missingMedia
    case mediaMismatch
    case targetNotEmpty
    case interrupted
    case verificationFailed
}

enum TransferValidator {
    static func validate(
        manifest: ExportManifest,
        data: TransferData,
        limits: ZIPImportLimits
    ) throws {
        guard manifest.formatIdentifier == ExportManifest.formatIdentifier else {
            throw TransferPackageError.invalidFormat
        }
        guard manifest.packageSchemaVersion == ExportManifest.currentPackageSchemaVersion else {
            throw TransferPackageError.unsupportedSchema(manifest.packageSchemaVersion)
        }
        guard data.totalObjectCount <= limits.maximumObjectCount else {
            throw TransferPackageError.objectLimitExceeded
        }
        guard manifest.objectCounts == data.objectCounts,
              manifest.dataFile.path == "data.json" else {
            throw TransferPackageError.countMismatch
        }

        try unique(data.entries.map(\.id), type: "entry")
        try unique(data.images.map(\.id), type: "image")
        try unique(data.tags.map(\.id), type: "tag")
        try unique(data.links.map(\.id), type: "link")
        try unique(data.habits.map(\.id), type: "habit")
        try unique(data.habitLogs.map(\.id), type: "habitLog")
        try unique(data.goals.map(\.id), type: "goal")
        try unique(data.goalEvents.map(\.id), type: "goalEvent")

        let imageCounts = Dictionary(grouping: data.images, by: \.entryID).mapValues(\.count)
        let entryIDs = Set(data.entries.map(\.id))
        let entryKinds = Dictionary(uniqueKeysWithValues: try data.entries.map { entry in
            guard let kind = EntryKind(rawValue: entry.kind),
                  EntryStatus(rawValue: entry.status) != nil,
                  entry.updatedAt >= entry.createdAt else {
                throw TransferPackageError.invalidObject("entry")
            }
            try EntryRules.validateContent(
                body: entry.body,
                imageCount: imageCounts[entry.id, default: 0]
            )
            let period: ReviewPeriod? = entry.periodStart == nil && entry.periodEnd == nil
                ? nil
                : try ReviewPeriod(start: entry.periodStart, end: entry.periodEnd)
            try EntryRules.validatePeriod(period, for: kind)
            return (entry.id, kind)
        })
        let tagIDs = Set(data.tags.map(\.id))
        let habitIDs = Set(data.habits.map(\.id))
        let goalIDs = Set(data.goals.map(\.id))

        var mediaByID: [UUID: ExportMediaFileRecord] = [:]
        for record in manifest.mediaFiles {
            guard mediaByID.updateValue(record, forKey: record.imageID) == nil else {
                throw TransferPackageError.duplicateID("manifestMedia")
            }
        }
        guard mediaByID.count == data.images.count else {
            throw TransferPackageError.countMismatch
        }
        for image in data.images {
            guard entryIDs.contains(image.entryID),
                  image.byteCount >= 0,
                  image.byteCount <= MediaStore.maximumOriginalByteCount,
                  image.pixelWidth > 0,
                  image.pixelHeight > 0,
                  image.pixelWidth <= MediaStore.maximumPixelCount / image.pixelHeight,
                  image.sortOrder >= 0,
                  image.updatedAt >= image.createdAt,
                  image.checksum.isSHA256,
                  let media = mediaByID[image.id],
                  media.path == image.mediaPath,
                  media.byteCount == image.byteCount,
                  media.sha256 == image.checksum else {
                throw TransferPackageError.invalidObject("image")
            }
        }

        var normalizedTags = Set<String>()
        for tag in data.tags {
            guard !tag.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  tag.normalizedName == TextSearchNormalizer.normalize(tag.displayName),
                  tag.updatedAt >= tag.createdAt else {
                throw TransferPackageError.invalidObject("tag")
            }
            guard normalizedTags.insert(tag.normalizedName).inserted else {
                throw TransferPackageError.duplicateNormalizedTag
            }
        }
        for habit in data.habits {
            guard HabitStatus(rawValue: habit.status) != nil,
                  !habit.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  habit.normalizedName == TextSearchNormalizer.normalize(habit.name),
                  habit.updatedAt >= habit.createdAt else {
                throw TransferPackageError.invalidObject("habit")
            }
        }
        for goal in data.goals {
            guard GoalKind(rawValue: goal.kind) != nil,
                  GoalStatus(rawValue: goal.status) != nil,
                  !goal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  goal.normalizedTitle == TextSearchNormalizer.normalize(goal.title),
                  goal.updatedAt >= goal.createdAt else {
                throw TransferPackageError.invalidObject("goal")
            }
        }
        for log in data.habitLogs {
            guard habitIDs.contains(log.habitID),
                  log.linkedEntryID.map(entryIDs.contains) ?? true else {
                throw TransferPackageError.missingEndpoint
            }
        }
        for event in data.goalEvents {
            guard goalIDs.contains(event.goalID), GoalLifecycleEventKind(rawValue: event.kind) != nil else {
                throw TransferPackageError.missingEndpoint
            }
        }

        var deduplicationKeys = Set<String>()
        for link in data.links {
            guard let sourceType = LinkObjectType(rawValue: link.sourceType),
                  let targetType = LinkObjectType(rawValue: link.targetType),
                  let kind = ObjectLinkKind(rawValue: link.kind) else {
                throw TransferPackageError.invalidObject("link")
            }
            let canonical = ObjectLink.makeDeduplicationKey(
                sourceType: sourceType,
                sourceID: link.sourceID,
                targetType: targetType,
                targetID: link.targetID,
                kind: kind
            )
            guard link.deduplicationKey == canonical,
                  deduplicationKeys.insert(canonical).inserted,
                  endpointExists(sourceType, link.sourceID, entryIDs, tagIDs, habitIDs, goalIDs),
                  endpointExists(targetType, link.targetID, entryIDs, tagIDs, habitIDs, goalIDs),
                  validShape(link, kind, sourceType, targetType, entryKinds) else {
                throw TransferPackageError.missingEndpoint
            }
        }
    }

    private static func unique(_ ids: [UUID], type: String) throws {
        guard Set(ids).count == ids.count else { throw TransferPackageError.duplicateID(type) }
    }

    private static func endpointExists(
        _ type: LinkObjectType,
        _ id: UUID,
        _ entries: Set<UUID>,
        _ tags: Set<UUID>,
        _ habits: Set<UUID>,
        _ goals: Set<UUID>
    ) -> Bool {
        switch type {
        case .entry: entries.contains(id)
        case .tag: tags.contains(id)
        case .habit: habits.contains(id)
        case .goal: goals.contains(id)
        }
    }

    private static func validShape(
        _ link: LinkTransfer,
        _ kind: ObjectLinkKind,
        _ source: LinkObjectType,
        _ target: LinkObjectType,
        _ entryKinds: [UUID: EntryKind]
    ) -> Bool {
        switch kind {
        case .entryUsesTag: source == .entry && target == .tag
        case .entryRelatesHabit: source == .entry && target == .habit
        case .entryRelatesGoal: source == .entry && target == .goal
        case .habitSupportsGoal: source == .habit && target == .goal
        case .reviewsEntry:
            source == .entry && target == .entry && link.sourceID != link.targetID
                && entryKinds[link.sourceID] == .review
        case .reviewsHabit:
            source == .entry && target == .habit && entryKinds[link.sourceID] == .review
        case .reviewsGoal:
            source == .entry && target == .goal && entryKinds[link.sourceID] == .review
        }
    }
}

private extension String {
    var isSHA256: Bool {
        count == 64 && allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}
