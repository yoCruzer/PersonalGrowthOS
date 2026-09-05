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
    /// Immutable civil-day identity captured at write time (V8). Legacy rows are
    /// conservatively frozen during the first analytics bootstrap.
    var localDayIdentifier: String?
    var localTimeZoneIdentifier: String?

    init(
        id: UUID = UUID(),
        habitID: UUID,
        occurredAt: Date,
        isCompleted: Bool,
        quantity: Double? = nil,
        unit: String? = nil,
        result: String? = nil,
        linkedEntryID: UUID? = nil,
        createdAt: Date,
        localDayIdentifier: String? = nil,
        localTimeZoneIdentifier: String? = nil
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
        self.localDayIdentifier = localDayIdentifier
        self.localTimeZoneIdentifier = localTimeZoneIdentifier
    }
}

@Model
final class HabitPlanRevision {
    @Attribute(.unique) var id: UUID
    var habitID: UUID
    /// YYYY-MM-DD in the local civil calendar effective at creation/edit time.
    var effectiveLocalDay: String
    var periodRawValue: String
    var goalRawValue: String
    var targetCount: Int?
    /// Comma-separated ISO weekday values. Kept scalar for safe SwiftData migration.
    var weekdaysRawValue: String
    var trustCoverageStartLocalDay: String
    var createdAt: Date

    init(
        id: UUID = UUID(), habitID: UUID, effectiveLocalDay: String,
        plan: HabitPlan, trustCoverageStartLocalDay: String, createdAt: Date
    ) {
        self.id = id
        self.habitID = habitID
        self.effectiveLocalDay = effectiveLocalDay
        periodRawValue = plan.period.rawValue
        goalRawValue = plan.goal.rawValue
        targetCount = plan.targetCount
        weekdaysRawValue = plan.weekdays.sorted().map(String.init).joined(separator: ",")
        self.trustCoverageStartLocalDay = trustCoverageStartLocalDay
        self.createdAt = createdAt
    }

    var plan: HabitPlan {
        HabitPlan(
            period: HabitPlanPeriod(rawValue: periodRawValue) ?? .trackingOnly,
            goal: HabitPlanGoal(rawValue: goalRawValue) ?? .none,
            targetCount: targetCount,
            weekdays: Set(weekdaysRawValue.split(separator: ",").compactMap { Int($0) })
        )
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

    init(
        id: UUID = UUID(), habitID: UUID, kind: HabitLifecycleEventKind,
        occurredLocalDay: String, occurredAt: Date, createdAt: Date? = nil
    ) {
        self.id = id
        self.habitID = habitID
        kindRawValue = kind.rawValue
        self.occurredLocalDay = occurredLocalDay
        self.occurredAt = occurredAt
        self.createdAt = createdAt ?? occurredAt
    }

    var kind: HabitLifecycleEventKind {
        HabitLifecycleEventKind(rawValue: kindRawValue) ?? .created
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
            .compactMap { revision -> (HabitLocalDay, HabitPlan)? in
                HabitLocalDay(revision.effectiveLocalDay).map { ($0, revision.plan) }
            }
            .filter { $0.0 <= day }
            .sorted { $0.0 < $1.0 }
            .last?.1
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
        let boundary = HabitLocalDay(date: now, timeZone: timeZone)
        var changed = false

        for log in logs where log.localDayIdentifier == nil {
            log.localDayIdentifier = HabitLocalDay(date: log.occurredAt, timeZone: timeZone).description
            log.localTimeZoneIdentifier = timeZone.identifier
            changed = true
        }
        for habit in habits {
            if !plans.contains(where: { $0.habitID == habit.id }) {
                let settings = HabitSettingsResolver.settings(for: habit.id, configurations: configurations)
                context.insert(HabitPlanRevision(
                    habitID: habit.id,
                    effectiveLocalDay: HabitLocalDay(date: habit.createdAt, timeZone: timeZone).description,
                    plan: HabitPlan.legacy(mode: settings.recordingMode, target: settings.dailyTargetCount),
                    trustCoverageStartLocalDay: boundary.description,
                    createdAt: now
                ))
                changed = true
            }
            if !lifecycleEvents.contains(where: { $0.habitID == habit.id }) {
                let kind: HabitLifecycleEventKind
                switch habit.status {
                case .active: kind = .created
                case .paused: kind = .paused
                case .completed: kind = .completed
                case .archived: kind = .archived
                }
                context.insert(HabitLifecycleEvent(
                    habitID: habit.id,
                    kind: kind,
                    occurredLocalDay: boundary.description,
                    occurredAt: now
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
        let mode: HabitRecordingMode = plan.targetCount == 1 && plan.period == .day ? .oncePerDay : .multiplePerDay
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
        try replacePendingPlan(
            habitID: habit.id,
            plan: currentPlan,
            effectiveDay: nextEffectiveDay(for: currentPlan, at: timestamp),
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
        let plan = try HabitRules.validatedPlan(plan)
        let validatedName = try HabitRules.validatedName(name)
        guard let persisted = try fetchHabit(habit.id) else { throw HabitCheckInError.missingHabit }
        let timestamp = now()
        persisted.name = validatedName
        persisted.normalizedName = TextSearchNormalizer.normalize(validatedName)
        persisted.updatedAt = timestamp
        let mode: HabitRecordingMode = plan.targetCount == 1 && plan.period == .day ? .oncePerDay : .multiplePerDay
        let target = plan.period == .day ? plan.targetCount : nil
        if let configuration = try fetchConfiguration(habit.id) {
            configuration.recordingMode = mode
            configuration.dailyTargetCount = target
            configuration.updatedAt = timestamp
        } else {
            context.insert(HabitConfiguration(habitID: habit.id, recordingMode: mode, dailyTargetCount: target, updatedAt: timestamp))
        }
        try replacePendingPlan(habitID: habit.id, plan: plan, effectiveDay: nextEffectiveDay(for: plan, at: timestamp), timestamp: timestamp)
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
        let links = try context.fetch(FetchDescriptor<ObjectLink>(
            predicate: #Predicate {
                ($0.sourceTypeRawValue == habitType && $0.sourceID == habitID)
                    || ($0.targetTypeRawValue == habitType && $0.targetID == habitID)
            }
        ))
        logs.forEach(context.delete)
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
        let pending = try context.fetch(FetchDescriptor<HabitPlanRevision>(
            predicate: #Predicate { $0.habitID == habitID }
        )).filter { $0.effectiveLocalDay == effectiveDay.description }
        pending.forEach(context.delete)
        context.insert(HabitPlanRevision(
            habitID: habitID,
            effectiveLocalDay: effectiveDay.description,
            plan: plan,
            trustCoverageStartLocalDay: effectiveDay.description,
            createdAt: timestamp
        ))
    }

    private func nextEffectiveDay(for plan: HabitPlan, at date: Date) -> HabitLocalDay {
        let today = HabitLocalDay(date: date)
        switch plan.period {
        case .trackingOnly, .day:
            return today.adding(days: 1) ?? today
        case .week:
            let calendar = WeeklyReviewCalendarPolicy.calendar()
            let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
            return HabitLocalDay(date: calendar.dateInterval(of: .weekOfYear, for: nextWeek)?.start ?? nextWeek)
        case .month:
            var calendar = Calendar(identifier: .gregorian)
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: date) ?? date
            let parts = calendar.dateComponents([.year, .month], from: nextMonth)
            return HabitLocalDay(year: parts.year ?? today.year, month: parts.month ?? today.month, day: 1)
        }
    }

    private func lifecycleKind(from old: HabitStatus, to new: HabitStatus) -> HabitLifecycleEventKind {
        switch new {
        case .paused: .paused
        case .completed: .completed
        case .archived: .archived
        case .active: old == .completed || old == .archived ? .restarted : .resumed
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
        let settings = try HabitSettingsResolver.settings(for: habit.id, context: context)
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
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return nil
        }
        var descriptor = FetchDescriptor<HabitLog>(
            predicate: #Predicate {
                $0.habitID == habitID
                    && $0.occurredAt >= dayStart
                    && $0.occurredAt < dayEnd
            },
            sortBy: [
                SortDescriptor(\HabitLog.occurredAt, order: .reverse),
                SortDescriptor(\HabitLog.createdAt, order: .reverse),
                SortDescriptor(\HabitLog.id, order: .reverse)
            ]
        )
        descriptor.fetchLimit = 1
        guard let latest = try context.fetch(descriptor).first else { return nil }
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
            preventsImmediateRepeat: preventsImmediateRepeat
        )
        let log = makeLog(
            habit: persistedHabit,
            draft: draft,
            linkedEntryID: nil,
            createdAt: timestamp
        )
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
        guard let persistedHabit = try fetchHabit(habit.id) else {
            throw HabitCheckInError.missingHabit
        }
        guard persistedHabit.status == .active else { throw HabitCheckInError.inactiveHabit }
        let timestamp = now()
        try validateCheckIn(
            habitID: persistedHabit.id,
            occurredAt: logDraft.occurredAt,
            createdAt: timestamp
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
            let log = makeLog(
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
        preventsImmediateRepeat: Bool = true
    ) throws {
        guard occurredAt <= createdAt.addingTimeInterval(5 * 60) else {
            throw HabitCheckInError.futureOccurrence
        }
        let settings = try HabitSettingsResolver.settings(for: habitID, context: context)
        let plans = try context.fetch(FetchDescriptor<HabitPlanRevision>(
            predicate: #Predicate { $0.habitID == habitID }
        ))
        if let plan = HabitPlanResolver.currentPlan(
            for: habitID,
            on: occurredAt,
            plans: plans,
            timeZone: calendar.timeZone
        ), !HabitPlanResolver.isScheduled(plan, on: occurredAt, timeZone: calendar.timeZone) {
            throw HabitCheckInError.notScheduled
        }
        let logs = try context.fetch(FetchDescriptor<HabitLog>(
            predicate: #Predicate { $0.habitID == habitID }
        ))
        if settings.recordingMode == .oncePerDay {
            let requestedDay = calendar.startOfDay(for: occurredAt)
            guard !logs.contains(where: {
                calendar.startOfDay(for: $0.occurredAt) == requestedDay
            }) else {
                throw HabitCheckInError.alreadyCheckedInToday
            }
        }
        if preventsImmediateRepeat {
            let threshold = createdAt.addingTimeInterval(-duplicatePreventionInterval)
            guard !logs.contains(where: { $0.createdAt >= threshold }) else {
                throw HabitCheckInError.recentlyCheckedIn
            }
        }
    }

    private func makeLog(
        habit: Habit,
        draft: HabitLogDraft,
        linkedEntryID: UUID?,
        createdAt: Date
    ) -> HabitLog {
        let localDay = HabitLocalDay(date: draft.occurredAt, timeZone: calendar.timeZone)
        return HabitLog(
            habitID: habit.id,
            occurredAt: draft.occurredAt,
            isCompleted: draft.isCompleted,
            quantity: draft.quantity,
            unit: draft.unit,
            result: draft.result,
            linkedEntryID: linkedEntryID,
            createdAt: createdAt,
            localDayIdentifier: localDay.description,
            localTimeZoneIdentifier: calendar.timeZone.identifier
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
