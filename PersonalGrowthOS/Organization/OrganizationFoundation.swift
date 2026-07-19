import Foundation
import SwiftData

enum TextSearchNormalizer {
    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
            .folding(
                options: [.caseInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }
}

enum TagValidationError: Error, Equatable {
    case emptyName
    case duplicateName
}

@Model
final class Tag {
    @Attribute(.unique) var id: UUID
    var displayName: String
    @Attribute(.unique) var normalizedName: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        normalizedName: String,
        createdAt: Date,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.normalizedName = normalizedName
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

enum LinkObjectType: String, Codable, Sendable {
    case entry
    case tag
    case habit
    case goal
}

enum ObjectLinkKind: String, Codable, Sendable {
    case entryUsesTag
    case entryRelatesHabit
    case entryRelatesGoal
    case habitSupportsGoal
    case reviewsEntry
    case reviewsHabit
    case reviewsGoal
}

@Model
final class ObjectLink {
    @Attribute(.unique) var id: UUID
    var sourceTypeRawValue: String
    var sourceID: UUID
    var targetTypeRawValue: String
    var targetID: UUID
    var kindRawValue: String
    @Attribute(.unique) var deduplicationKey: String
    var createdAt: Date

    var sourceType: LinkObjectType {
        LinkObjectType(rawValue: sourceTypeRawValue) ?? .entry
    }

    var targetType: LinkObjectType {
        LinkObjectType(rawValue: targetTypeRawValue) ?? .tag
    }

    var kind: ObjectLinkKind {
        ObjectLinkKind(rawValue: kindRawValue) ?? .entryUsesTag
    }

    init(
        id: UUID = UUID(),
        sourceType: LinkObjectType,
        sourceID: UUID,
        targetType: LinkObjectType,
        targetID: UUID,
        kind: ObjectLinkKind,
        createdAt: Date
    ) {
        self.id = id
        sourceTypeRawValue = sourceType.rawValue
        self.sourceID = sourceID
        targetTypeRawValue = targetType.rawValue
        self.targetID = targetID
        kindRawValue = kind.rawValue
        deduplicationKey = Self.makeDeduplicationKey(
            sourceType: sourceType,
            sourceID: sourceID,
            targetType: targetType,
            targetID: targetID,
            kind: kind
        )
        self.createdAt = createdAt
    }

    static func makeDeduplicationKey(
        sourceType: LinkObjectType,
        sourceID: UUID,
        targetType: LinkObjectType,
        targetID: UUID,
        kind: ObjectLinkKind
    ) -> String {
        [
            kind.rawValue,
            sourceType.rawValue,
            sourceID.uuidString.lowercased(),
            targetType.rawValue,
            targetID.uuidString.lowercased()
        ].joined(separator: "|")
    }
}

enum LinkIntegrityError: Error, Equatable {
    case danglingLinks([UUID])
    case danglingHabitLogs([UUID])
    case danglingGoalEvents([UUID])
}

@MainActor
enum LinkIntegrityService {
    static func validate(context: ModelContext) throws {
        let links = try context.fetch(FetchDescriptor<ObjectLink>())
        let entries = try context.fetch(FetchDescriptor<Entry>())
        let entryIDs = Set(entries.map(\.id))
        let entryKinds = Dictionary(entries.map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first })
        let tagIDs = Set(try context.fetch(FetchDescriptor<Tag>()).map(\.id))
        let habitIDs = Set(try context.fetch(FetchDescriptor<Habit>()).map(\.id))
        let goalIDs = Set(try context.fetch(FetchDescriptor<Goal>()).map(\.id))
        let danglingIDs = links.compactMap { link -> UUID? in
            switch link.kind {
            case .entryUsesTag:
                guard link.sourceType == .entry,
                      link.targetType == .tag,
                      entryIDs.contains(link.sourceID),
                      tagIDs.contains(link.targetID) else {
                    return link.id
                }
            case .entryRelatesHabit:
                guard link.sourceType == .entry,
                      link.targetType == .habit,
                      entryIDs.contains(link.sourceID),
                      habitIDs.contains(link.targetID) else {
                    return link.id
                }
            case .entryRelatesGoal:
                guard link.sourceType == .entry,
                      link.targetType == .goal,
                      entryIDs.contains(link.sourceID),
                      goalIDs.contains(link.targetID) else {
                    return link.id
                }
            case .habitSupportsGoal:
                guard link.sourceType == .habit,
                      link.targetType == .goal,
                      habitIDs.contains(link.sourceID),
                      goalIDs.contains(link.targetID) else {
                    return link.id
                }
            case .reviewsEntry:
                guard link.sourceType == .entry,
                      link.targetType == .entry,
                      link.sourceID != link.targetID,
                      entryKinds[link.sourceID] == .review,
                      entryIDs.contains(link.targetID) else {
                    return link.id
                }
            case .reviewsHabit:
                guard link.sourceType == .entry,
                      link.targetType == .habit,
                      entryKinds[link.sourceID] == .review,
                      habitIDs.contains(link.targetID) else {
                    return link.id
                }
            case .reviewsGoal:
                guard link.sourceType == .entry,
                      link.targetType == .goal,
                      entryKinds[link.sourceID] == .review,
                      goalIDs.contains(link.targetID) else {
                    return link.id
                }
            }
            return nil
        }
        guard danglingIDs.isEmpty else {
            throw LinkIntegrityError.danglingLinks(danglingIDs.sorted { $0.uuidString < $1.uuidString })
        }

        let danglingLogIDs = try context.fetch(FetchDescriptor<HabitLog>()).compactMap { log -> UUID? in
            guard habitIDs.contains(log.habitID),
                  log.linkedEntryID.map(entryIDs.contains) ?? true else {
                return log.id
            }
            return nil
        }
        guard danglingLogIDs.isEmpty else {
            throw LinkIntegrityError.danglingHabitLogs(
                danglingLogIDs.sorted { $0.uuidString < $1.uuidString }
            )
        }

        let danglingEventIDs = try context.fetch(FetchDescriptor<GoalLifecycleEvent>())
            .compactMap { goalIDs.contains($0.goalID) ? nil : $0.id }
        guard danglingEventIDs.isEmpty else {
            throw LinkIntegrityError.danglingGoalEvents(
                danglingEventIDs.sorted { $0.uuidString < $1.uuidString }
            )
        }
    }
}

@MainActor
final class TagLinkService {
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

    func createTag(displayName: String) throws -> Tag {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = TextSearchNormalizer.normalize(trimmed)
        guard !normalized.isEmpty else { throw TagValidationError.emptyName }
        var descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate { $0.normalizedName == normalized }
        )
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else {
            throw TagValidationError.duplicateName
        }
        let timestamp = now()
        let tag = Tag(
            displayName: trimmed,
            normalizedName: normalized,
            createdAt: timestamp
        )
        context.insert(tag)
        do {
            try save()
            return tag
        } catch {
            context.rollback()
            throw error
        }
    }

    func attach(tag: Tag, to entry: Entry) throws {
        let key = ObjectLink.makeDeduplicationKey(
            sourceType: .entry,
            sourceID: entry.id,
            targetType: .tag,
            targetID: tag.id,
            kind: .entryUsesTag
        )
        var descriptor = FetchDescriptor<ObjectLink>(
            predicate: #Predicate { $0.deduplicationKey == key }
        )
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else { return }
        context.insert(ObjectLink(
            sourceType: .entry,
            sourceID: entry.id,
            targetType: .tag,
            targetID: tag.id,
            kind: .entryUsesTag,
            createdAt: now()
        ))
        do {
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func detach(tag: Tag, from entry: Entry) throws {
        let key = ObjectLink.makeDeduplicationKey(
            sourceType: .entry,
            sourceID: entry.id,
            targetType: .tag,
            targetID: tag.id,
            kind: .entryUsesTag
        )
        let descriptor = FetchDescriptor<ObjectLink>(
            predicate: #Predicate { $0.deduplicationKey == key }
        )
        try context.fetch(descriptor).forEach(context.delete)
        do {
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteTag(_ tag: Tag) throws {
        let tagID = tag.id
        let descriptor = FetchDescriptor<ObjectLink>(
            predicate: #Predicate { $0.targetID == tagID }
        )
        try context.fetch(descriptor).forEach(context.delete)
        context.delete(tag)
        do {
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

struct LocalSearchResults {
    let entries: [Entry]
    let tags: [Tag]
    let habits: [Habit]
    let goals: [Goal]

    init(
        entries: [Entry] = [],
        tags: [Tag] = [],
        habits: [Habit] = [],
        goals: [Goal] = []
    ) {
        self.entries = entries
        self.tags = tags
        self.habits = habits
        self.goals = goals
    }
}

@MainActor
final class LocalSearchService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func search(_ query: String) throws -> LocalSearchResults {
        let normalizedQuery = TextSearchNormalizer.normalize(query)
        guard !normalizedQuery.isEmpty else {
            return LocalSearchResults(entries: [], tags: [])
        }
        let entries = try context.fetch(FetchDescriptor<Entry>(sortBy: [
            SortDescriptor(\Entry.occurredAt, order: .reverse),
            SortDescriptor(\Entry.createdAt, order: .reverse),
            SortDescriptor(\Entry.id, order: .forward)
        ])).filter { entry in
            [entry.title, entry.body]
                .compactMap { $0 }
                .contains { TextSearchNormalizer.normalize($0).contains(normalizedQuery) }
        }
        let tags = try context.fetch(FetchDescriptor<Tag>(sortBy: [
            SortDescriptor(\Tag.normalizedName, order: .forward),
            SortDescriptor(\Tag.id, order: .forward)
        ])).filter { tag in
            tag.normalizedName.contains(normalizedQuery)
                || TextSearchNormalizer.normalize(tag.displayName).contains(normalizedQuery)
        }
        let habits = try context.fetch(FetchDescriptor<Habit>(sortBy: [
            SortDescriptor(\Habit.normalizedName, order: .forward),
            SortDescriptor(\Habit.id, order: .forward)
        ])).filter { habit in
            habit.normalizedName.contains(normalizedQuery)
                || TextSearchNormalizer.normalize(habit.name).contains(normalizedQuery)
        }
        let goals = try context.fetch(FetchDescriptor<Goal>(sortBy: [
            SortDescriptor(\Goal.normalizedTitle, order: .forward),
            SortDescriptor(\Goal.id, order: .forward)
        ])).filter { goal in
            goal.normalizedTitle.contains(normalizedQuery)
                || TextSearchNormalizer.normalize(goal.title).contains(normalizedQuery)
        }
        return LocalSearchResults(entries: entries, tags: tags, habits: habits, goals: goals)
    }
}

extension Tag: Identifiable {}
