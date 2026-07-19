import Foundation
import SwiftData

@Model
final class Habit {
    @Attribute(.unique) var id: UUID
    var name: String
    var normalizedName: String
    var statusRawValue: String
    var createdAt: Date
    var updatedAt: Date

    var status: HabitStatus {
        get { HabitStatus(rawValue: statusRawValue) ?? .active }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        normalizedName: String,
        status: HabitStatus = .active,
        createdAt: Date,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.normalizedName = normalizedName
        statusRawValue = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

@Model
final class HabitLog {
    @Attribute(.unique) var id: UUID
    var habitID: UUID
    var occurredAt: Date
    var isCompleted: Bool
    var quantity: Double?
    var unit: String?
    var result: String?
    var linkedEntryID: UUID?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        habitID: UUID,
        occurredAt: Date,
        isCompleted: Bool,
        quantity: Double? = nil,
        unit: String? = nil,
        result: String? = nil,
        linkedEntryID: UUID? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.habitID = habitID
        self.occurredAt = occurredAt
        self.isCompleted = isCompleted
        self.quantity = quantity
        self.unit = unit
        self.result = result
        self.linkedEntryID = linkedEntryID
        self.createdAt = createdAt
    }
}

@MainActor
final class HabitService {
    private let context: ModelContext
    private let now: () -> Date
    private let save: () throws -> Void

    init(
        context: ModelContext,
        now: @escaping () -> Date = Date.init,
        save: (() throws -> Void)? = nil
    ) {
        self.context = context
        self.now = now
        self.save = save ?? { try context.save() }
    }

    func create(name: String) throws -> Habit {
        let validatedName = try HabitRules.validatedName(name)
        let timestamp = now()
        let habit = Habit(
            name: validatedName,
            normalizedName: TextSearchNormalizer.normalize(validatedName),
            createdAt: timestamp
        )
        context.insert(habit)
        do {
            try save()
            return habit
        } catch {
            context.rollback()
            throw error
        }
    }

    func transition(_ habit: Habit, to status: HabitStatus) throws {
        guard habit.status != status else { return }
        let originalStatus = habit.status
        let originalUpdatedAt = habit.updatedAt
        habit.status = status
        habit.updatedAt = now()
        do {
            try save()
        } catch {
            context.rollback()
            habit.status = originalStatus
            habit.updatedAt = originalUpdatedAt
            throw error
        }
    }

    func permanentlyDelete(_ habit: Habit) throws {
        let habitID = habit.id
        let habitType = LinkObjectType.habit.rawValue
        let logs = try context.fetch(FetchDescriptor<HabitLog>(
            predicate: #Predicate { $0.habitID == habitID }
        ))
        let links = try context.fetch(FetchDescriptor<ObjectLink>(
            predicate: #Predicate {
                ($0.sourceTypeRawValue == habitType && $0.sourceID == habitID)
                    || ($0.targetTypeRawValue == habitType && $0.targetID == habitID)
            }
        ))
        logs.forEach(context.delete)
        links.forEach(context.delete)
        context.delete(habit)
        do {
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

@MainActor
final class HabitCheckInService {
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

    func checkIn(_ habit: Habit, draft: HabitLogDraft = HabitLogDraft()) throws -> HabitLog {
        guard try habitExists(habit.id) else { throw HabitCheckInError.missingHabit }
        guard habit.status == .active else { throw HabitCheckInError.inactiveHabit }
        let log = makeLog(habit: habit, draft: draft, linkedEntryID: nil)
        context.insert(log)
        do {
            try save()
            return log
        } catch {
            context.rollback()
            throw error
        }
    }

    func checkInWithInsight(
        _ habit: Habit,
        logDraft: HabitLogDraft = HabitLogDraft(),
        entryDraft: EntryCreationDraft
    ) throws -> (log: HabitLog, entry: Entry) {
        guard try habitExists(habit.id) else { throw HabitCheckInError.missingHabit }
        guard habit.status == .active else { throw HabitCheckInError.inactiveHabit }
        try EntryRules.validateContent(body: entryDraft.body, imageCount: entryDraft.images.count)
        var storedFiles: [StoredMediaFile] = []
        do {
            try mediaStore.ensureCapacity(for: entryDraft.images)
            for image in entryDraft.images {
                storedFiles.append(try mediaStore.storeOriginal(image))
            }

            let timestamp = now()
            let metadata = zip(storedFiles, entryDraft.images).enumerated().map { index, pair in
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
                status: .organized,
                title: entryDraft.title,
                body: entryDraft.body,
                createdAt: timestamp,
                occurredAt: entryDraft.occurredAt ?? logDraft.occurredAt,
                images: metadata
            )
            metadata.forEach { $0.entry = entry }
            let log = makeLog(habit: habit, draft: logDraft, linkedEntryID: entry.id)
            let link = ObjectLink(
                sourceType: .entry,
                sourceID: entry.id,
                targetType: .habit,
                targetID: habit.id,
                kind: .entryRelatesHabit,
                createdAt: timestamp
            )
            context.insert(entry)
            context.insert(log)
            context.insert(link)
            try save()
            return (log, entry)
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

    private func makeLog(habit: Habit, draft: HabitLogDraft, linkedEntryID: UUID?) -> HabitLog {
        HabitLog(
            habitID: habit.id,
            occurredAt: draft.occurredAt,
            isCompleted: draft.isCompleted,
            quantity: draft.quantity,
            unit: draft.unit,
            result: draft.result,
            linkedEntryID: linkedEntryID,
            createdAt: now()
        )
    }

    private func habitExists(_ id: UUID) throws -> Bool {
        var descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }
}

struct HabitDaySummary: Identifiable, Equatable {
    let day: Date
    let latestOccurredAt: Date
    let logCount: Int
    let habitNames: [String]

    var id: Date { day }
}

enum HabitTimelineAggregator {
    static func summarize(
        logs: [HabitLog],
        habits: [Habit],
        calendar: Calendar = .current
    ) -> [HabitDaySummary] {
        let namesByID = Dictionary(
            habits.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        let ordinaryLogs = logs.filter { $0.linkedEntryID == nil }
        return Dictionary(grouping: ordinaryLogs) { calendar.startOfDay(for: $0.occurredAt) }
            .map { day, logs in
                HabitDaySummary(
                    day: day,
                    latestOccurredAt: logs.map(\.occurredAt).max() ?? day,
                    logCount: logs.count,
                    habitNames: Array(Set(logs.compactMap { namesByID[$0.habitID] })).sorted()
                )
            }
            .sorted { $0.day > $1.day }
    }
}

extension Habit: Identifiable {}
extension HabitLog: Identifiable {}
