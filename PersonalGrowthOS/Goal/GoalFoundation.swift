import Foundation
import SwiftData

@Model
final class Goal {
    @Attribute(.unique) var id: UUID
    var kindRawValue: String
    var title: String
    var normalizedTitle: String
    var statusRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    var kind: GoalKind {
        get { GoalKind(rawValue: kindRawValue) ?? .standard }
        set { kindRawValue = newValue.rawValue }
    }

    var status: GoalStatus {
        get { GoalStatus(rawValue: statusRawValue) ?? .active }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        kind: GoalKind = .standard,
        title: String,
        normalizedTitle: String,
        status: GoalStatus = .active,
        createdAt: Date,
        updatedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        kindRawValue = kind.rawValue
        self.title = title
        self.normalizedTitle = normalizedTitle
        statusRawValue = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.completedAt = completedAt
    }
}

@Model
final class GoalLifecycleEvent {
    @Attribute(.unique) var id: UUID
    var goalID: UUID
    var kindRawValue: String
    var occurredAt: Date
    var createdAt: Date

    var kind: GoalLifecycleEventKind {
        GoalLifecycleEventKind(rawValue: kindRawValue) ?? .created
    }

    init(
        id: UUID = UUID(),
        goalID: UUID,
        kind: GoalLifecycleEventKind,
        occurredAt: Date,
        createdAt: Date
    ) {
        self.id = id
        self.goalID = goalID
        kindRawValue = kind.rawValue
        self.occurredAt = occurredAt
        self.createdAt = createdAt
    }
}

@MainActor
final class GoalService {
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

    func create(title: String, kind: GoalKind) throws -> Goal {
        let validatedTitle = try GoalRules.validatedTitle(title)
        let timestamp = now()
        let goal = Goal(
            kind: kind,
            title: validatedTitle,
            normalizedTitle: TextSearchNormalizer.normalize(validatedTitle),
            createdAt: timestamp
        )
        context.insert(goal)
        context.insert(GoalLifecycleEvent(
            goalID: goal.id,
            kind: .created,
            occurredAt: timestamp,
            createdAt: timestamp
        ))
        do {
            try save()
            return goal
        } catch {
            context.rollback()
            throw error
        }
    }

    func transition(_ goal: Goal, to status: GoalStatus) throws {
        guard goal.status != status else { return }
        let originalStatus = goal.status
        let originalUpdatedAt = goal.updatedAt
        let originalCompletedAt = goal.completedAt
        let timestamp = now()
        goal.status = status
        goal.updatedAt = timestamp
        goal.completedAt = status == .completed ? timestamp : nil
        context.insert(GoalLifecycleEvent(
            goalID: goal.id,
            kind: eventKind(from: originalStatus, to: status),
            occurredAt: timestamp,
            createdAt: timestamp
        ))
        do {
            try save()
        } catch {
            context.rollback()
            goal.status = originalStatus
            goal.updatedAt = originalUpdatedAt
            goal.completedAt = originalCompletedAt
            throw error
        }
    }

    func permanentlyDelete(_ goal: Goal) throws {
        let goalID = goal.id
        let events = try context.fetch(FetchDescriptor<GoalLifecycleEvent>(
            predicate: #Predicate { $0.goalID == goalID }
        ))
        let links = try context.fetch(FetchDescriptor<ObjectLink>(
            predicate: #Predicate {
                $0.sourceID == goalID || $0.targetID == goalID
            }
        ))
        events.forEach(context.delete)
        links.forEach(context.delete)
        context.delete(goal)
        do {
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func eventKind(from oldStatus: GoalStatus, to newStatus: GoalStatus) -> GoalLifecycleEventKind {
        switch newStatus {
        case .active: oldStatus == .paused ? .resumed : .reactivated
        case .paused: .paused
        case .completed: .completed
        case .abandoned: .abandoned
        case .archived: .archived
        }
    }
}

@MainActor
final class CoreLinkService {
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

    func setEntry(_ entry: Entry, relatesTo habit: Habit, linked: Bool) throws {
        guard try entryExists(entry.id), try habitExists(habit.id) else {
            throw CoreLinkValidationError.missingEndpoint
        }
        try set(
            sourceType: .entry,
            sourceID: entry.id,
            targetType: .habit,
            targetID: habit.id,
            kind: .entryRelatesHabit,
            linked: linked
        )
    }

    func setEntry(_ entry: Entry, relatesTo goal: Goal, linked: Bool) throws {
        guard try entryExists(entry.id), try goalExists(goal.id) else {
            throw CoreLinkValidationError.missingEndpoint
        }
        try set(
            sourceType: .entry,
            sourceID: entry.id,
            targetType: .goal,
            targetID: goal.id,
            kind: .entryRelatesGoal,
            linked: linked
        )
    }

    func setHabit(_ habit: Habit, supports goal: Goal, linked: Bool) throws {
        guard try habitExists(habit.id), try goalExists(goal.id) else {
            throw CoreLinkValidationError.missingEndpoint
        }
        try set(
            sourceType: .habit,
            sourceID: habit.id,
            targetType: .goal,
            targetID: goal.id,
            kind: .habitSupportsGoal,
            linked: linked
        )
    }

    private func set(
        sourceType: LinkObjectType,
        sourceID: UUID,
        targetType: LinkObjectType,
        targetID: UUID,
        kind: ObjectLinkKind,
        linked: Bool
    ) throws {
        let key = ObjectLink.makeDeduplicationKey(
            sourceType: sourceType,
            sourceID: sourceID,
            targetType: targetType,
            targetID: targetID,
            kind: kind
        )
        let descriptor = FetchDescriptor<ObjectLink>(
            predicate: #Predicate { $0.deduplicationKey == key }
        )
        let existing = try context.fetch(descriptor)
        if linked && existing.isEmpty {
            context.insert(ObjectLink(
                sourceType: sourceType,
                sourceID: sourceID,
                targetType: targetType,
                targetID: targetID,
                kind: kind,
                createdAt: now()
            ))
        } else if !linked {
            existing.forEach(context.delete)
        } else {
            return
        }
        do {
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func entryExists(_ id: UUID) throws -> Bool {
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    private func habitExists(_ id: UUID) throws -> Bool {
        var descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    private func goalExists(_ id: UUID) throws -> Bool {
        var descriptor = FetchDescriptor<Goal>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }
}

extension Goal: Identifiable {}
extension GoalLifecycleEvent: Identifiable {}
