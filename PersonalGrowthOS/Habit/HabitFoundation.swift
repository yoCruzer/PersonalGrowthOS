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

@Model
final class HabitLogDayMetadata {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var habitLogID: UUID
    var localDayIdentifier: String
    var localTimeZoneIdentifier: String
    var provenanceRawValue: String

    var provenance: HabitLogDayProvenance {
        HabitLogDayProvenance(rawValue: provenanceRawValue) ?? .legacyBootstrap
    }

    init(
        id: UUID = UUID(),
        habitLogID: UUID,
        localDayIdentifier: String,
        localTimeZoneIdentifier: String,
        provenance: HabitLogDayProvenance
    ) {
        self.id = id
        self.habitLogID = habitLogID
        self.localDayIdentifier = localDayIdentifier
        self.localTimeZoneIdentifier = localTimeZoneIdentifier
        provenanceRawValue = provenance.rawValue
    }
}

@Model
final class HabitPlanRevision {
    @Attribute(.unique) var id: UUID
    var habitID: UUID
    /// YYYY-MM-DD in the local civil calendar effective at creation/edit time.
    var effectiveLocalDay: String
    var recordingModeRawValue: String
    var periodRawValue: String
    var goalRawValue: String
    var targetCount: Int?
    /// Comma-separated Foundation/Gregorian weekday values. Kept scalar for safe SwiftData migration.
    var weekdaysRawValue: String
    var trustCoverageStartLocalDay: String
    var createdAt: Date
    var originRawValue: String

    init(
        id: UUID = UUID(), habitID: UUID, effectiveLocalDay: String,
        plan: HabitPlan, trustCoverageStartLocalDay: String, createdAt: Date,
        origin: HabitPlanRevisionOrigin = .user
    ) {
        self.id = id
        self.habitID = habitID
        self.effectiveLocalDay = effectiveLocalDay
        recordingModeRawValue = plan.recordingMode.rawValue
        periodRawValue = plan.period.rawValue
        goalRawValue = plan.goal.rawValue
        targetCount = plan.targetCount
        weekdaysRawValue = plan.weekdays.sorted().map(String.init).joined(separator: ",")
        self.trustCoverageStartLocalDay = trustCoverageStartLocalDay
        self.createdAt = createdAt
        originRawValue = origin.rawValue
    }

    var plan: HabitPlan {
        HabitPlan(
            recordingMode: HabitRecordingMode(rawValue: recordingModeRawValue) ?? .multiplePerDay,
            period: HabitPlanPeriod(rawValue: periodRawValue) ?? .trackingOnly,
            goal: HabitPlanGoal(rawValue: goalRawValue) ?? .none,
            targetCount: targetCount,
            weekdays: Set(weekdaysRawValue.split(separator: ",").compactMap { Int($0) })
        )
    }

    var origin: HabitPlanRevisionOrigin {
        HabitPlanRevisionOrigin(rawValue: originRawValue) ?? .user
    }
}

@Model
final class HabitLifecycleEvent {
    @Attribute(.unique) var id: UUID
    var habitID: UUID
    var kindRawValue: String
    var occurredLocalDay: String
    var occurredAt: Date
    var createdAt: Date
    var knownStatusRawValue: String?

    init(
        id: UUID = UUID(), habitID: UUID, kind: HabitLifecycleEventKind,
        occurredLocalDay: String, occurredAt: Date, createdAt: Date? = nil,
        knownStatus: HabitStatus? = nil
    ) {
        self.id = id
        self.habitID = habitID
        kindRawValue = kind.rawValue
        self.occurredLocalDay = occurredLocalDay
        self.occurredAt = occurredAt
        self.createdAt = createdAt ?? occurredAt
        knownStatusRawValue = knownStatus?.rawValue
    }

    var kind: HabitLifecycleEventKind {
        HabitLifecycleEventKind(rawValue: kindRawValue) ?? .migrationBaseline
    }

    var knownStatus: HabitStatus? {
        knownStatusRawValue.flatMap(HabitStatus.init(rawValue:))
    }
}

enum HabitJourneyItemKind: Equatable {
    case plan(HabitPlan)
    case lifecycle(HabitLifecycleEventKind)
}

struct HabitJourneyItem: Identifiable, Equatable {
    let id: String
    let day: HabitLocalDay
    let occurredAt: Date
    let kind: HabitJourneyItemKind
}

enum HabitJourneyBuilder {
    static func items(
        plans: [HabitPlanRevision],
        lifecycleEvents: [HabitLifecycleEvent],
        asOf: Date = Date(),
        timeZone: TimeZone = .current
    ) -> [HabitJourneyItem] {
        let today = HabitLocalDay(date: asOf, timeZone: timeZone)
        let planItems = plans.compactMap { revision -> HabitJourneyItem? in
            guard revision.origin != .migrationBootstrap,
                  let day = HabitLocalDay(revision.effectiveLocalDay),
                  day <= today else { return nil }
            return HabitJourneyItem(
                id: "plan-\(revision.id.uuidString)",
                day: day,
                occurredAt: revision.createdAt,
                kind: .plan(revision.plan)
            )
        }
        let lifecycleItems = lifecycleEvents.compactMap { event -> HabitJourneyItem? in
            guard event.kind != .migrationBaseline,
                  let day = HabitLocalDay(event.occurredLocalDay),
                  day <= today else { return nil }
            return HabitJourneyItem(
                id: "lifecycle-\(event.id.uuidString)",
                day: day,
                occurredAt: event.occurredAt,
                kind: .lifecycle(event.kind)
            )
        }
        return (planItems + lifecycleItems).sorted {
            if $0.day != $1.day { return $0.day > $1.day }
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt > $1.occurredAt }
            return $0.id < $1.id
        }
    }
}

enum HabitAnalyticsSnapshotBuilder {
    static func summary(
        habit: Habit,
        logs: [HabitLog],
        dayMetadata: [HabitLogDayMetadata],
        plans: [HabitPlanRevision],
        lifecycleEvents: [HabitLifecycleEvent],
        legacyConfigurations: [HabitConfiguration],
        asOf: Date = Date(),
        timeZone: TimeZone = .current
    ) -> HabitAnalyticsSummary {
        let habitPlans = plans.filter { $0.habitID == habit.id }
        let metadataByLogID = HabitLogDayResolver.metadataByLogID(dayMetadata)
        let snapshots: [HabitPlanSnapshot]
        if habitPlans.isEmpty {
            let settings = HabitSettingsResolver.settings(
                for: habit.id,
                configurations: legacyConfigurations
            )
            snapshots = [HabitPlanSnapshot(
                effectiveDay: HabitLocalDay(date: habit.createdAt, timeZone: timeZone),
                plan: HabitPlan.legacy(mode: settings.recordingMode, target: settings.dailyTargetCount),
                trustStartDay: HabitLocalDay(date: asOf, timeZone: timeZone)
            )]
        } else {
            snapshots = habitPlans.compactMap {
                guard let effectiveDay = HabitLocalDay($0.effectiveLocalDay),
                      let trustStartDay = HabitLocalDay($0.trustCoverageStartLocalDay) else {
                    return nil
                }
                return HabitPlanSnapshot(
                    effectiveDay: effectiveDay,
                    plan: $0.plan,
                    trustStartDay: trustStartDay,
                    origin: $0.origin
                )
            }
        }
        return HabitAnalyticsEngine.evaluate(
            createdAt: HabitLocalDay(date: habit.createdAt, timeZone: timeZone),
            logs: logs.filter { $0.habitID == habit.id }.map {
                HabitAnalyticsLog(
                    id: $0.id,
                    localDay: HabitLogDayResolver.localDay(
                        for: $0,
                        metadataByLogID: metadataByLogID,
                        fallbackTimeZone: timeZone
                    ),
                    isCompleted: $0.isCompleted,
                    occurredAt: $0.occurredAt
                )
            },
            plans: snapshots,
            lifecycle: lifecycleEvents.filter { $0.habitID == habit.id }.map {
                HabitLifecycleSnapshot(
                    id: $0.id,
                    day: HabitLocalDay($0.occurredLocalDay)
                        ?? HabitLocalDay(date: $0.occurredAt, timeZone: timeZone),
                    kind: $0.kind,
                    knownStatus: $0.knownStatus,
                    occurredAt: $0.occurredAt
                )
            },
            asOf: HabitLocalDay(date: asOf, timeZone: timeZone),
            timeZone: timeZone
        )
    }
}

@Model
final class HabitConfiguration {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var habitID: UUID
    var recordingModeRawValue: String
    var dailyTargetCount: Int?
    var updatedAt: Date

    var recordingMode: HabitRecordingMode {
        get { HabitRecordingMode(rawValue: recordingModeRawValue) ?? .multiplePerDay }
        set { recordingModeRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        habitID: UUID,
        recordingMode: HabitRecordingMode,
        dailyTargetCount: Int? = nil,
        updatedAt: Date
    ) {
        self.id = id
        self.habitID = habitID
        recordingModeRawValue = recordingMode.rawValue
        self.dailyTargetCount = dailyTargetCount
        self.updatedAt = updatedAt
    }
}

struct HabitSettings: Equatable {
    let recordingMode: HabitRecordingMode
    let dailyTargetCount: Int?

    static let legacyDefault = HabitSettings(
        recordingMode: .multiplePerDay,
        dailyTargetCount: nil
    )
}

enum HabitLogDayResolver {
    static func metadataByLogID(
        _ metadata: [HabitLogDayMetadata]
    ) -> [UUID: HabitLogDayMetadata] {
        Dictionary(metadata.map { ($0.habitLogID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func localDay(
        for log: HabitLog,
        metadataByLogID: [UUID: HabitLogDayMetadata],
        fallbackTimeZone: TimeZone = .current
    ) -> HabitLocalDay {
        if let value = metadataByLogID[log.id]?.localDayIdentifier,
           let localDay = HabitLocalDay(value) {
            return localDay
        }
        return HabitLocalDay(date: log.occurredAt, timeZone: fallbackTimeZone)
    }
}

enum HabitPlanResolver {
    static func currentPlan(
        for habitID: UUID,
        on date: Date = Date(),
        plans: [HabitPlanRevision],
        timeZone: TimeZone = .current
    ) -> HabitPlan? {
        let day = HabitLocalDay(date: date, timeZone: timeZone)
        return plans
            .filter { $0.habitID == habitID }
            .compactMap { revision -> (HabitLocalDay, HabitPlanRevision)? in
                HabitLocalDay(revision.effectiveLocalDay).map { ($0, revision) }
            }
            .filter { $0.0 <= day }
            .sorted {
                if $0.0 != $1.0 { return $0.0 < $1.0 }
                if $0.1.createdAt != $1.1.createdAt { return $0.1.createdAt < $1.1.createdAt }
                return $0.1.id.uuidString < $1.1.id.uuidString
            }
            .last?.1.plan
    }

    static func pendingPlanRevision(
        for habitID: UUID,
        on date: Date = Date(),
        plans: [HabitPlanRevision],
        timeZone: TimeZone = .current
    ) -> HabitPlanRevision? {
        let day = HabitLocalDay(date: date, timeZone: timeZone)
        return plans
            .filter { $0.habitID == habitID }
            .compactMap { revision -> (HabitLocalDay, HabitPlanRevision)? in
                HabitLocalDay(revision.effectiveLocalDay).map { ($0, revision) }
            }
            .filter { $0.0 > day }
            .sorted {
                if $0.0 != $1.0 { return $0.0 < $1.0 }
                if $0.1.createdAt != $1.1.createdAt { return $0.1.createdAt > $1.1.createdAt }
                return $0.1.id.uuidString < $1.1.id.uuidString
            }
            .first?.1
    }

    static func isScheduled(
        _ plan: HabitPlan,
        on date: Date,
        timeZone: TimeZone = .current
    ) -> Bool {
        guard plan.period == .day, plan.goal == .selectedWeekdays else { return true }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return plan.weekdays.contains(calendar.component(.weekday, from: date))
    }
}

enum HabitRuntimeResolver {
    static func settings(for plan: HabitPlan) -> HabitSettings {
        HabitSettings(
            recordingMode: plan.recordingMode,
            dailyTargetCount: plan.recordingMode == .multiplePerDay && plan.period == .day
                ? plan.targetCount
                : nil
        )
    }

    static func settings(
        for habitID: UUID,
        on date: Date = Date(),
        plans: [HabitPlanRevision],
        legacyConfigurations: [HabitConfiguration],
        timeZone: TimeZone = .current
    ) -> HabitSettings {
        guard let plan = HabitPlanResolver.currentPlan(
            for: habitID,
            on: date,
            plans: plans,
            timeZone: timeZone
        ) else {
            return HabitSettingsResolver.settings(
                for: habitID,
                configurations: legacyConfigurations
            )
        }
        return settings(for: plan)
    }

    @MainActor
    static func settings(
        for habitID: UUID,
        on date: Date,
        context: ModelContext,
        timeZone: TimeZone = .current
    ) throws -> HabitSettings {
        let plans = try context.fetch(FetchDescriptor<HabitPlanRevision>(
            predicate: #Predicate { $0.habitID == habitID }
        ))
        let configurations = try context.fetch(FetchDescriptor<HabitConfiguration>(
            predicate: #Predicate { $0.habitID == habitID }
        ))
        return settings(
            for: habitID,
            on: date,
            plans: plans,
            legacyConfigurations: configurations,
            timeZone: timeZone
        )
    }
}

/// Lightweight migration can add V8 columns but cannot safely manufacture
/// historical facts. This one-shot bootstrap freezes legacy activity using the
/// migration device's civil calendar, then starts strict plan/lifecycle coverage
/// at that migration boundary.
enum HabitAnalyticsMigrationBootstrap {
    @discardableResult
    static func apply(
        context: ModelContext,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        saveChanges: Bool = true
    ) throws -> Bool {
        let habits = try context.fetch(FetchDescriptor<Habit>())
        let configurations = try context.fetch(FetchDescriptor<HabitConfiguration>())
        let plans = try context.fetch(FetchDescriptor<HabitPlanRevision>())
        let lifecycleEvents = try context.fetch(FetchDescriptor<HabitLifecycleEvent>())
        let logs = try context.fetch(FetchDescriptor<HabitLog>())
        let logDayMetadata = try context.fetch(FetchDescriptor<HabitLogDayMetadata>())
        let boundary = HabitLocalDay(date: now, timeZone: timeZone)
        var changed = false

        var metadataLogIDs = Set(logDayMetadata.map(\.habitLogID))
        for log in logs where !metadataLogIDs.contains(log.id) {
            context.insert(HabitLogDayMetadata(
                habitLogID: log.id,
                localDayIdentifier: HabitLocalDay(date: log.occurredAt, timeZone: timeZone).description,
                localTimeZoneIdentifier: timeZone.identifier,
                provenance: .legacyBootstrap
            ))
            metadataLogIDs.insert(log.id)
            changed = true
        }
        for habit in habits {
            if !plans.contains(where: { $0.habitID == habit.id }) {
                let settings = HabitSettingsResolver.settings(for: habit.id, configurations: configurations)
                context.insert(HabitPlanRevision(
                    habitID: habit.id,
                    effectiveLocalDay: boundary.description,
                    plan: HabitPlan.legacy(mode: settings.recordingMode, target: settings.dailyTargetCount),
                    trustCoverageStartLocalDay: boundary.description,
                    createdAt: now,
                    origin: .migrationBootstrap
                ))
                changed = true
            }
            if !lifecycleEvents.contains(where: { $0.habitID == habit.id }) {
                context.insert(HabitLifecycleEvent(
                    habitID: habit.id,
                    kind: .migrationBaseline,
                    occurredLocalDay: boundary.description,
                    occurredAt: now,
                    knownStatus: habit.status
                ))
                changed = true
            }
        }
        if changed && saveChanges { try context.save() }
        return changed
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

    func create(
        name: String,
        recordingMode: HabitRecordingMode = .multiplePerDay,
        dailyTargetCount: Int? = 2
    ) throws -> Habit {
        let validatedName = try HabitRules.validatedName(name)
        let validatedTarget = try HabitRules.validatedDailyTarget(
            dailyTargetCount,
            mode: recordingMode
        )
        let timestamp = now()
        let habit = Habit(
            name: validatedName,
            normalizedName: TextSearchNormalizer.normalize(validatedName),
            createdAt: timestamp
        )
        context.insert(habit)
        context.insert(HabitConfiguration(
            habitID: habit.id,
            recordingMode: recordingMode,
            dailyTargetCount: validatedTarget,
            updatedAt: timestamp
        ))
        let localDay = HabitLocalDay(date: timestamp)
        let plan = HabitPlan.legacy(mode: recordingMode, target: validatedTarget)
        context.insert(HabitPlanRevision(
            habitID: habit.id,
            effectiveLocalDay: localDay.description,
            plan: plan,
            trustCoverageStartLocalDay: localDay.description,
            createdAt: timestamp
        ))
        context.insert(HabitLifecycleEvent(
            habitID: habit.id,
            kind: .created,
            occurredLocalDay: localDay.description,
            occurredAt: timestamp
        ))
        do {
            try save()
            return habit
        } catch {
            context.rollback()
            throw error
        }
    }

    func create(name: String, plan: HabitPlan) throws -> Habit {
        let plan = try HabitRules.validatedPlan(plan)
        let mode = plan.recordingMode
        let target = plan.period == .day ? plan.targetCount : nil
        let habit = try createLegacyCompatibleHabit(name: name, mode: mode, target: target, plan: plan)
        return habit
    }

    func update(
        _ habit: Habit,
        name: String,
        recordingMode: HabitRecordingMode,
        dailyTargetCount: Int?
    ) throws {
        let validatedName = try HabitRules.validatedName(name)
        let validatedTarget = try HabitRules.validatedDailyTarget(
            dailyTargetCount,
            mode: recordingMode
        )
        guard let persistedHabit = try fetchHabit(habit.id) else {
            throw HabitCheckInError.missingHabit
        }
        let originalName = persistedHabit.name
        let originalNormalizedName = persistedHabit.normalizedName
        let originalUpdatedAt = persistedHabit.updatedAt
        let timestamp = now()
        persistedHabit.name = validatedName
        persistedHabit.normalizedName = TextSearchNormalizer.normalize(validatedName)
        persistedHabit.updatedAt = timestamp

        let existingConfiguration = try fetchConfiguration(habit.id)
        let originalMode = existingConfiguration?.recordingMode
        let originalTarget = existingConfiguration?.dailyTargetCount
        let originalConfigurationUpdatedAt = existingConfiguration?.updatedAt
        if let existingConfiguration {
            existingConfiguration.recordingMode = recordingMode
            existingConfiguration.dailyTargetCount = validatedTarget
            existingConfiguration.updatedAt = timestamp
        } else {
            context.insert(HabitConfiguration(
                habitID: habit.id,
                recordingMode: recordingMode,
                dailyTargetCount: validatedTarget,
                updatedAt: timestamp
            ))
        }

        let currentPlan = HabitPlan.legacy(mode: recordingMode, target: validatedTarget)
        let habitID = habit.id
        let existingPlans = try context.fetch(FetchDescriptor<HabitPlanRevision>(
            predicate: #Predicate { $0.habitID == habitID }
        ))
        let previousPlan = HabitPlanResolver.currentPlan(
            for: habit.id,
            on: timestamp,
            plans: existingPlans
        )
        try replacePendingPlan(
            habitID: habit.id,
            plan: currentPlan,
            effectiveDay: nextEffectiveDay(from: previousPlan, to: currentPlan, at: timestamp),
            timestamp: timestamp
        )

        do {
            try save()
        } catch {
            context.rollback()
            persistedHabit.name = originalName
            persistedHabit.normalizedName = originalNormalizedName
            persistedHabit.updatedAt = originalUpdatedAt
            if let existingConfiguration,
               let originalMode,
               let originalConfigurationUpdatedAt {
                existingConfiguration.recordingMode = originalMode
                existingConfiguration.dailyTargetCount = originalTarget
                existingConfiguration.updatedAt = originalConfigurationUpdatedAt
            }
            throw error
        }
    }

    func update(_ habit: Habit, name: String, plan: HabitPlan) throws {
        try update(habit, name: name, planChange: plan)
    }

    func updateName(_ habit: Habit, name: String) throws {
        try update(habit, name: name, planChange: nil)
    }

    func updatePlan(_ habit: Habit, plan: HabitPlan) throws {
        try update(habit, name: habit.name, planChange: plan)
    }

    func update(_ habit: Habit, name: String, planChange: HabitPlan?) throws {
        let planChange = try planChange.map(HabitRules.validatedPlan)
        let validatedName = try HabitRules.validatedName(name)
        guard let persisted = try fetchHabit(habit.id) else { throw HabitCheckInError.missingHabit }
        let timestamp = now()
        persisted.name = validatedName
        persisted.normalizedName = TextSearchNormalizer.normalize(validatedName)
        persisted.updatedAt = timestamp
        if let plan = planChange {
            let mode = plan.recordingMode
            let target = plan.period == .day ? plan.targetCount : nil
            if let configuration = try fetchConfiguration(habit.id) {
                configuration.recordingMode = mode
                configuration.dailyTargetCount = target
                configuration.updatedAt = timestamp
            } else {
                context.insert(HabitConfiguration(habitID: habit.id, recordingMode: mode, dailyTargetCount: target, updatedAt: timestamp))
            }
            let habitID = habit.id
            let existingPlans = try context.fetch(FetchDescriptor<HabitPlanRevision>(
                predicate: #Predicate { $0.habitID == habitID }
            ))
            let previousPlan = HabitPlanResolver.currentPlan(for: habit.id, on: timestamp, plans: existingPlans)
            try replacePendingPlan(habitID: habit.id, plan: plan, effectiveDay: nextEffectiveDay(from: previousPlan, to: plan, at: timestamp), timestamp: timestamp)
        }
        do { try save() } catch { context.rollback(); throw error }
    }

    func transition(_ habit: Habit, to status: HabitStatus) throws {
        guard habit.status != status else { return }
        let originalStatus = habit.status
        let originalUpdatedAt = habit.updatedAt
        habit.status = status
        let timestamp = now()
        habit.updatedAt = timestamp
        context.insert(HabitLifecycleEvent(
            habitID: habit.id,
            kind: lifecycleKind(from: originalStatus, to: status),
            occurredLocalDay: HabitLocalDay(date: timestamp).description,
            occurredAt: timestamp
        ))
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
        let configurations = try context.fetch(FetchDescriptor<HabitConfiguration>(
            predicate: #Predicate { $0.habitID == habitID }
        ))
        let plans = try context.fetch(FetchDescriptor<HabitPlanRevision>(
            predicate: #Predicate { $0.habitID == habitID }
        ))
        let lifecycleEvents = try context.fetch(FetchDescriptor<HabitLifecycleEvent>(
            predicate: #Predicate { $0.habitID == habitID }
        ))
        let logIDs = Set(logs.map(\.id))
        let logDayMetadata = try context.fetch(FetchDescriptor<HabitLogDayMetadata>())
            .filter { logIDs.contains($0.habitLogID) }
        let links = try context.fetch(FetchDescriptor<ObjectLink>(
            predicate: #Predicate {
                ($0.sourceTypeRawValue == habitType && $0.sourceID == habitID)
                    || ($0.targetTypeRawValue == habitType && $0.targetID == habitID)
            }
        ))
        logs.forEach(context.delete)
        logDayMetadata.forEach(context.delete)
        configurations.forEach(context.delete)
        plans.forEach(context.delete)
        lifecycleEvents.forEach(context.delete)
        links.forEach(context.delete)
        context.delete(habit)
        do {
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func fetchHabit(_ id: UUID) throws -> Habit? {
        var descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func createLegacyCompatibleHabit(
        name: String, mode: HabitRecordingMode, target: Int?, plan: HabitPlan
    ) throws -> Habit {
        let validatedName = try HabitRules.validatedName(name)
        let timestamp = now()
        let habit = Habit(name: validatedName, normalizedName: TextSearchNormalizer.normalize(validatedName), createdAt: timestamp)
        context.insert(habit)
        context.insert(HabitConfiguration(habitID: habit.id, recordingMode: mode, dailyTargetCount: target, updatedAt: timestamp))
        let day = HabitLocalDay(date: timestamp)
        context.insert(HabitPlanRevision(habitID: habit.id, effectiveLocalDay: day.description, plan: plan, trustCoverageStartLocalDay: day.description, createdAt: timestamp))
        context.insert(HabitLifecycleEvent(habitID: habit.id, kind: .created, occurredLocalDay: day.description, occurredAt: timestamp))
        do { try save(); return habit } catch { context.rollback(); throw error }
    }

    private func fetchConfiguration(_ habitID: UUID) throws -> HabitConfiguration? {
        var descriptor = FetchDescriptor<HabitConfiguration>(
            predicate: #Predicate { $0.habitID == habitID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func replacePendingPlan(
        habitID: UUID, plan: HabitPlan, effectiveDay: HabitLocalDay, timestamp: Date
    ) throws {
        let today = HabitLocalDay(date: timestamp)
        let pending = try context.fetch(FetchDescriptor<HabitPlanRevision>(
            predicate: #Predicate { $0.habitID == habitID }
        )).filter {
            guard let day = HabitLocalDay($0.effectiveLocalDay) else { return false }
            return day > today
        }
        pending.forEach(context.delete)
        context.insert(HabitPlanRevision(
            habitID: habitID,
            effectiveLocalDay: effectiveDay.description,
            plan: plan,
            trustCoverageStartLocalDay: effectiveDay.description,
            createdAt: timestamp
        ))
    }

    private func nextEffectiveDay(from oldPlan: HabitPlan?, to newPlan: HabitPlan, at date: Date) -> HabitLocalDay {
        let today = HabitLocalDay(date: date)
        let period = [oldPlan?.period, newPlan.period].compactMap { $0 }.max { rank($0) < rank($1) } ?? .day
        switch period {
        case .trackingOnly, .day:
            return today.adding(days: 1) ?? today
        case .week:
            let calendar = WeeklyReviewCalendarPolicy.calendar()
            let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
            return HabitLocalDay(date: calendar.dateInterval(of: .weekOfYear, for: nextWeek)?.start ?? nextWeek)
        case .month:
            let calendar = Calendar(identifier: .gregorian)
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: date) ?? date
            let parts = calendar.dateComponents([.year, .month], from: nextMonth)
            return HabitLocalDay(year: parts.year ?? today.year, month: parts.month ?? today.month, day: 1)
        }
    }

    private func rank(_ period: HabitPlanPeriod) -> Int {
        switch period { case .trackingOnly, .day: 0; case .week: 1; case .month: 2 }
    }

    private func lifecycleKind(from old: HabitStatus, to new: HabitStatus) -> HabitLifecycleEventKind {
        switch new {
        case .paused: .paused
        case .completed: .completed
        case .archived: .archived
        case .active:
            switch old {
            case .paused: .resumed
            case .completed: .restarted
            case .archived: .restored
            case .active: .resumed
            }
        }
    }
}

enum HabitSettingsResolver {
    static func settings(
        for habitID: UUID,
        configurations: [HabitConfiguration]
    ) -> HabitSettings {
        guard let configuration = configurations.first(where: { $0.habitID == habitID }) else {
            return .legacyDefault
        }
        return HabitSettings(
            recordingMode: configuration.recordingMode,
            dailyTargetCount: configuration.recordingMode == .multiplePerDay
                ? configuration.dailyTargetCount
                : nil
        )
    }

    @MainActor
    static func settings(
        for habitID: UUID,
        context: ModelContext
    ) throws -> HabitSettings {
        var descriptor = FetchDescriptor<HabitConfiguration>(
            predicate: #Predicate { $0.habitID == habitID }
        )
        descriptor.fetchLimit = 1
        return settings(for: habitID, configurations: try context.fetch(descriptor))
    }
}

@MainActor
final class HabitCheckInService {
    private let context: ModelContext
    private let mediaStore: MediaStore
    private let now: () -> Date
    private let calendar: Calendar
    private let duplicatePreventionInterval: TimeInterval
    private let save: () throws -> Void

    init(
        context: ModelContext,
        mediaStore: MediaStore,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        duplicatePreventionInterval: TimeInterval = HabitCheckInPolicy.duplicatePreventionInterval,
        save: (() throws -> Void)? = nil
    ) {
        self.context = context
        self.mediaStore = mediaStore
        self.now = now
        self.calendar = calendar
        self.duplicatePreventionInterval = duplicatePreventionInterval
        self.save = save ?? { try context.save() }
    }

    func checkIn(_ habit: Habit, draft: HabitLogDraft = HabitLogDraft()) throws -> HabitLog {
        try saveCheckIn(habit, draft: draft, preventsImmediateRepeat: true)
    }

    func incrementCount(
        _ habit: Habit,
        occurredAt: Date = Date()
    ) throws -> HabitLog {
        let settings = try HabitRuntimeResolver.settings(
            for: habit.id,
            on: occurredAt,
            context: context,
            timeZone: calendar.timeZone
        )
        return try saveCheckIn(
            habit,
            draft: HabitLogDraft(occurredAt: occurredAt),
            preventsImmediateRepeat: settings.recordingMode != .multiplePerDay
        )
    }

    /// Removes today's latest structured HabitLog only. Linked Entries and their Habit links remain intact.
    @discardableResult
    func removeLatestStructuredCheckIn(
        habitID: UUID,
        on day: Date = Date()
    ) throws -> HabitLog? {
        let requestedDay = HabitLocalDay(date: day, timeZone: calendar.timeZone).description
        let descriptor = FetchDescriptor<HabitLog>(
            predicate: #Predicate { $0.habitID == habitID },
            sortBy: [
                SortDescriptor(\HabitLog.occurredAt, order: .reverse),
                SortDescriptor(\HabitLog.createdAt, order: .reverse),
                SortDescriptor(\HabitLog.id, order: .reverse)
            ]
        )
        let metadataByLogID = HabitLogDayResolver.metadataByLogID(
            try context.fetch(FetchDescriptor<HabitLogDayMetadata>())
        )
        guard let latest = try context.fetch(descriptor).first(where: {
            $0.isCompleted
                && HabitLogDayResolver.localDay(
                    for: $0,
                    metadataByLogID: metadataByLogID,
                    fallbackTimeZone: calendar.timeZone
                ).description == requestedDay
        }) else { return nil }
        if let dayMetadata = metadataByLogID[latest.id] {
            context.delete(dayMetadata)
        }
        context.delete(latest)
        do {
            try save()
            return latest
        } catch {
            context.rollback()
            throw error
        }
    }

    private func saveCheckIn(
        _ habit: Habit,
        draft: HabitLogDraft,
        preventsImmediateRepeat: Bool
    ) throws -> HabitLog {
        guard let persistedHabit = try fetchHabit(habit.id) else {
            throw HabitCheckInError.missingHabit
        }
        guard persistedHabit.status == .active else { throw HabitCheckInError.inactiveHabit }
        let timestamp = now()
        try validateCheckIn(
            habitID: persistedHabit.id,
            occurredAt: draft.occurredAt,
            createdAt: timestamp,
            isCompleted: draft.isCompleted,
            preventsImmediateRepeat: preventsImmediateRepeat
        )
        let created = makeLog(
            habit: persistedHabit,
            draft: draft,
            linkedEntryID: nil,
            createdAt: timestamp
        )
        context.insert(created.log)
        context.insert(created.dayMetadata)
        do {
            try save()
            return created.log
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
        guard let persistedHabit = try fetchHabit(habit.id) else {
            throw HabitCheckInError.missingHabit
        }
        guard persistedHabit.status == .active else { throw HabitCheckInError.inactiveHabit }
        let timestamp = now()
        try validateCheckIn(
            habitID: persistedHabit.id,
            occurredAt: logDraft.occurredAt,
            createdAt: timestamp,
            isCompleted: logDraft.isCompleted
        )
        try EntryRules.validateContent(body: entryDraft.body, imageCount: entryDraft.images.count)
        var storedFiles: [StoredMediaFile] = []
        do {
            try mediaStore.ensureCapacity(for: entryDraft.images)
            for image in entryDraft.images {
                storedFiles.append(try mediaStore.storeOriginal(image))
            }

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
            let created = makeLog(
                habit: persistedHabit,
                draft: logDraft,
                linkedEntryID: entry.id,
                createdAt: timestamp
            )
            let link = ObjectLink(
                sourceType: .entry,
                sourceID: entry.id,
                targetType: .habit,
                targetID: persistedHabit.id,
                kind: .entryRelatesHabit,
                createdAt: timestamp
            )
            context.insert(entry)
            context.insert(created.log)
            context.insert(created.dayMetadata)
            context.insert(link)
            try save()
            return (created.log, entry)
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

    func undoLatestCheckIn(habitID: UUID, logID: UUID) throws {
        var descriptor = FetchDescriptor<HabitLog>(
            predicate: #Predicate { $0.habitID == habitID },
            sortBy: [
                SortDescriptor(\HabitLog.createdAt, order: .reverse),
                SortDescriptor(\HabitLog.id, order: .reverse)
            ]
        )
        descriptor.fetchLimit = 1
        guard let latest = try context.fetch(descriptor).first,
              latest.id == logID else {
            throw HabitCheckInError.checkInIsNotLatest
        }
        let dayMetadata = try context.fetch(FetchDescriptor<HabitLogDayMetadata>())
            .first { $0.habitLogID == logID }
        if let dayMetadata {
            context.delete(dayMetadata)
        }
        context.delete(latest)
        do {
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func validateCheckIn(
        habitID: UUID,
        occurredAt: Date,
        createdAt: Date,
        isCompleted: Bool,
        preventsImmediateRepeat: Bool = true
    ) throws {
        guard occurredAt <= createdAt.addingTimeInterval(5 * 60) else {
            throw HabitCheckInError.futureOccurrence
        }
        let settings = try HabitRuntimeResolver.settings(
            for: habitID,
            on: occurredAt,
            context: context,
            timeZone: calendar.timeZone
        )
        let logs = try context.fetch(FetchDescriptor<HabitLog>(
            predicate: #Predicate { $0.habitID == habitID }
        ))
        let metadataByLogID = HabitLogDayResolver.metadataByLogID(
            try context.fetch(FetchDescriptor<HabitLogDayMetadata>())
        )
        if settings.recordingMode == .oncePerDay, isCompleted {
            let requestedDay = HabitLocalDay(date: occurredAt, timeZone: calendar.timeZone).description
            guard !logs.contains(where: { log in
                log.isCompleted
                    && HabitLogDayResolver.localDay(
                        for: log,
                        metadataByLogID: metadataByLogID,
                        fallbackTimeZone: calendar.timeZone
                    ).description == requestedDay
            }) else {
                throw HabitCheckInError.alreadyCheckedInToday
            }
        }
        if preventsImmediateRepeat {
            let threshold = createdAt.addingTimeInterval(-duplicatePreventionInterval)
            guard !logs.contains(where: {
                $0.isCompleted == isCompleted && $0.createdAt >= threshold
            }) else {
                throw HabitCheckInError.recentlyCheckedIn
            }
        }
    }

    private func makeLog(
        habit: Habit,
        draft: HabitLogDraft,
        linkedEntryID: UUID?,
        createdAt: Date
    ) -> (log: HabitLog, dayMetadata: HabitLogDayMetadata) {
        let localDay = HabitLocalDay(date: draft.occurredAt, timeZone: calendar.timeZone)
        let log = HabitLog(
            habitID: habit.id,
            occurredAt: draft.occurredAt,
            isCompleted: draft.isCompleted,
            quantity: draft.quantity,
            unit: draft.unit,
            result: draft.result,
            linkedEntryID: linkedEntryID,
            createdAt: createdAt
        )
        return (
            log,
            HabitLogDayMetadata(
                habitLogID: log.id,
                localDayIdentifier: localDay.description,
                localTimeZoneIdentifier: calendar.timeZone.identifier,
                provenance: .capturedAtWrite
            )
        )
    }

    private func fetchHabit(_ id: UUID) throws -> Habit? {
        var descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
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
extension HabitConfiguration: Identifiable {}
extension HabitPlanRevision: Identifiable {}
extension HabitLifecycleEvent: Identifiable {}
