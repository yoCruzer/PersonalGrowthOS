import Foundation

struct ExportManifest: Codable, Equatable {
    static let formatIdentifier = "com.yocruzer.PersonalGrowthOS.export"
    static let currentPackageSchemaVersion = 4
    static let supportedPackageSchemaVersions = 1...currentPackageSchemaVersion

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
    let weightRecords: [WeightRecordTransfer]
    let weeklyReviews: [WeeklyReviewTransfer]
    let habitPlanRevisions: [HabitPlanRevisionTransfer]
    let habitLifecycleEvents: [HabitLifecycleEventTransfer]

    init(
        entries: [EntryTransfer],
        images: [ImageTransfer],
        tags: [TagTransfer],
        links: [LinkTransfer],
        habits: [HabitTransfer],
        habitLogs: [HabitLogTransfer],
        goals: [GoalTransfer],
        goalEvents: [GoalEventTransfer],
        weightRecords: [WeightRecordTransfer] = [],
        weeklyReviews: [WeeklyReviewTransfer] = [],
        habitPlanRevisions: [HabitPlanRevisionTransfer] = [],
        habitLifecycleEvents: [HabitLifecycleEventTransfer] = []
    ) {
        self.entries = entries
        self.images = images
        self.tags = tags
        self.links = links
        self.habits = habits
        self.habitLogs = habitLogs
        self.goals = goals
        self.goalEvents = goalEvents
        self.weightRecords = weightRecords
        self.weeklyReviews = weeklyReviews
        self.habitPlanRevisions = habitPlanRevisions
        self.habitLifecycleEvents = habitLifecycleEvents
    }

    private enum CodingKeys: String, CodingKey {
        case entries
        case images
        case tags
        case links
        case habits
        case habitLogs
        case goals
        case goalEvents
        case weightRecords
        case weeklyReviews
        case habitPlanRevisions
        case habitLifecycleEvents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decode([EntryTransfer].self, forKey: .entries)
        images = try container.decode([ImageTransfer].self, forKey: .images)
        tags = try container.decode([TagTransfer].self, forKey: .tags)
        links = try container.decode([LinkTransfer].self, forKey: .links)
        habits = try container.decode([HabitTransfer].self, forKey: .habits)
        habitLogs = try container.decode([HabitLogTransfer].self, forKey: .habitLogs)
        goals = try container.decode([GoalTransfer].self, forKey: .goals)
        goalEvents = try container.decode([GoalEventTransfer].self, forKey: .goalEvents)
        weightRecords = try container.decodeIfPresent(
            [WeightRecordTransfer].self,
            forKey: .weightRecords
        ) ?? []
        weeklyReviews = try container.decodeIfPresent(
            [WeeklyReviewTransfer].self,
            forKey: .weeklyReviews
        ) ?? []
        habitPlanRevisions = try container.decodeIfPresent(
            [HabitPlanRevisionTransfer].self, forKey: .habitPlanRevisions
        ) ?? []
        habitLifecycleEvents = try container.decodeIfPresent(
            [HabitLifecycleEventTransfer].self, forKey: .habitLifecycleEvents
        ) ?? []
    }

    var objectCounts: [String: Int] {
        [
            "entries": entries.count,
            "images": images.count,
            "tags": tags.count,
            "links": links.count,
            "habits": habits.count,
            "habitLogs": habitLogs.count,
            "goals": goals.count,
            "goalEvents": goalEvents.count,
            "weightRecords": weightRecords.count,
            "weeklyReviews": weeklyReviews.count,
            "habitPlanRevisions": habitPlanRevisions.count,
            "habitLifecycleEvents": habitLifecycleEvents.count
        ]
    }

    func objectCounts(forPackageSchemaVersion version: Int) -> [String: Int] {
        objectCounts.filter { key, _ in
            (version != 1 || key != "weightRecords")
                && (version >= 3 || key != "weeklyReviews")
                && (version >= 4 || (key != "habitPlanRevisions" && key != "habitLifecycleEvents"))
        }
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
    let recordingMode: String?
    let dailyTargetCount: Int?
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
    let localDayIdentifier: String?
    let localTimeZoneIdentifier: String?
    let localDayProvenance: String?

    init(id: UUID, habitID: UUID, occurredAt: Date, isCompleted: Bool, quantity: Double?, unit: String?, result: String?, linkedEntryID: UUID?, createdAt: Date, localDayIdentifier: String? = nil, localTimeZoneIdentifier: String? = nil, localDayProvenance: String? = nil) {
        self.id = id; self.habitID = habitID; self.occurredAt = occurredAt; self.isCompleted = isCompleted
        self.quantity = quantity; self.unit = unit; self.result = result; self.linkedEntryID = linkedEntryID; self.createdAt = createdAt
        self.localDayIdentifier = localDayIdentifier; self.localTimeZoneIdentifier = localTimeZoneIdentifier; self.localDayProvenance = localDayProvenance
    }

    private enum CodingKeys: String, CodingKey { case id, habitID, occurredAt, isCompleted, quantity, unit, result, linkedEntryID, createdAt, localDayIdentifier, localTimeZoneIdentifier, localDayProvenance }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); habitID = try c.decode(UUID.self, forKey: .habitID); occurredAt = try c.decode(Date.self, forKey: .occurredAt); isCompleted = try c.decode(Bool.self, forKey: .isCompleted)
        quantity = try c.decodeIfPresent(Double.self, forKey: .quantity); unit = try c.decodeIfPresent(String.self, forKey: .unit); result = try c.decodeIfPresent(String.self, forKey: .result); linkedEntryID = try c.decodeIfPresent(UUID.self, forKey: .linkedEntryID); createdAt = try c.decode(Date.self, forKey: .createdAt)
        localDayIdentifier = try c.decodeIfPresent(String.self, forKey: .localDayIdentifier); localTimeZoneIdentifier = try c.decodeIfPresent(String.self, forKey: .localTimeZoneIdentifier); localDayProvenance = try c.decodeIfPresent(String.self, forKey: .localDayProvenance)
    }
}

struct HabitPlanRevisionTransfer: Codable, Equatable {
    let id: UUID; let habitID: UUID; let effectiveLocalDay: String; let period: String; let goal: String
    let targetCount: Int?; let weekdays: String; let trustCoverageStartLocalDay: String; let createdAt: Date
}

struct HabitLifecycleEventTransfer: Codable, Equatable {
    let id: UUID; let habitID: UUID; let kind: String; let occurredLocalDay: String; let occurredAt: Date; let createdAt: Date
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

struct WeightRecordTransfer: Codable, Equatable {
    let id: UUID
    let weightKilograms: Double
    let recordedAt: Date
    let createdAt: Date
    let updatedAt: Date
}

struct WeeklyReviewTransfer: Codable, Equatable {
    let id: UUID
    let weekIdentifier: String
    let periodStart: Date
    let periodEnd: Date
    let rememberedText: String?
    let improvementText: String?
    let nextStepText: String?
    let focusText: String?
    let isCompleted: Bool
    let createdAt: Date
    let updatedAt: Date
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
        guard ExportManifest.supportedPackageSchemaVersions.contains(
            manifest.packageSchemaVersion
        ) else {
            throw TransferPackageError.unsupportedSchema(manifest.packageSchemaVersion)
        }
        guard manifest.packageSchemaVersion != 1 || data.weightRecords.isEmpty else {
            throw TransferPackageError.invalidObject("weightRecord")
        }
        guard manifest.packageSchemaVersion >= 3 || data.weeklyReviews.isEmpty else {
            throw TransferPackageError.invalidObject("weeklyReview")
        }
        guard data.totalObjectCount <= limits.maximumObjectCount else {
            throw TransferPackageError.objectLimitExceeded
        }
        guard manifest.objectCounts == data.objectCounts(
            forPackageSchemaVersion: manifest.packageSchemaVersion
        ),
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
        try unique(data.weightRecords.map(\.id), type: "weightRecord")
        try unique(data.weeklyReviews.map(\.id), type: "weeklyReview")
        try unique(data.habitPlanRevisions.map(\.id), type: "habitPlanRevision")
        try unique(data.habitLifecycleEvents.map(\.id), type: "habitLifecycleEvent")
        guard Set(data.weeklyReviews.map(\.weekIdentifier)).count == data.weeklyReviews.count else {
            throw TransferPackageError.duplicateID("weeklyReviewIdentifier")
        }

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
            if let rawMode = habit.recordingMode {
                guard let mode = HabitRecordingMode(rawValue: rawMode) else {
                    throw TransferPackageError.invalidObject("habit")
                }
                _ = try validatedImportedDailyTarget(habit.dailyTargetCount, mode: mode)
            } else if habit.dailyTargetCount != nil {
                throw TransferPackageError.invalidObject("habit")
            }
        }
        for plan in data.habitPlanRevisions {
            guard habitIDs.contains(plan.habitID), HabitLocalDay(plan.effectiveLocalDay) != nil,
                  HabitLocalDay(plan.trustCoverageStartLocalDay) != nil,
                  let period = HabitPlanPeriod(rawValue: plan.period),
                  let goal = HabitPlanGoal(rawValue: plan.goal) else {
                throw TransferPackageError.invalidObject("habitPlanRevision")
            }
            let weekdays = Set(plan.weekdays.split(separator: ",").compactMap { Int($0) })
            guard (try? HabitRules.validatedPlan(HabitPlan(period: period, goal: goal, targetCount: plan.targetCount, weekdays: weekdays))) != nil else {
                throw TransferPackageError.invalidObject("habitPlanRevision")
            }
        }
        for event in data.habitLifecycleEvents {
            guard habitIDs.contains(event.habitID), HabitLifecycleEventKind(rawValue: event.kind) != nil,
                  HabitLocalDay(event.occurredLocalDay) != nil else {
                throw TransferPackageError.invalidObject("habitLifecycleEvent")
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
        for record in data.weightRecords {
            guard (try? WeightRules.validatedKilograms(record.weightKilograms)) != nil,
                  record.updatedAt >= record.createdAt else {
                throw TransferPackageError.invalidObject("weightRecord")
            }
        }
        for review in data.weeklyReviews {
            let texts = [
                review.rememberedText,
                review.improvementText,
                review.nextStepText,
                review.focusText
            ].compactMap { $0 }
            guard !review.weekIdentifier.isEmpty,
                  review.periodEnd >= review.periodStart,
                  review.updatedAt >= review.createdAt,
                  texts.allSatisfy({
                      !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  }) else {
                throw TransferPackageError.invalidObject("weeklyReview")
            }
        }
        for log in data.habitLogs {
            guard habitIDs.contains(log.habitID),
                  log.linkedEntryID.map(entryIDs.contains) ?? true else {
                throw TransferPackageError.missingEndpoint
            }
            if let localDayIdentifier = log.localDayIdentifier {
                guard HabitLocalDay(localDayIdentifier) != nil,
                      let timeZoneIdentifier = log.localTimeZoneIdentifier,
                      TimeZone(identifier: timeZoneIdentifier) != nil,
                      log.localDayProvenance.map({ HabitLogDayProvenance(rawValue: $0) != nil }) ?? true else {
                    throw TransferPackageError.invalidObject("habitLog")
                }
            } else if log.localTimeZoneIdentifier != nil || log.localDayProvenance != nil {
                throw TransferPackageError.invalidObject("habitLog")
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

    static func validatedImportedDailyTarget(
        _ value: Int?,
        mode: HabitRecordingMode
    ) throws -> Int? {
        guard value.map({ $0 > 0 }) ?? true else {
            throw TransferPackageError.invalidObject("habit")
        }
        return mode == .multiplePerDay ? value : nil
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
