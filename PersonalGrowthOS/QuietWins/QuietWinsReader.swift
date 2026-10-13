import Foundation
import SwiftData

/// Created in a detached task: fetch and value mapping stay off the UI executor.
/// No save, insert, bootstrap, migration, notification or network operation belongs here.
@ModelActor
actor QuietWinsReader {
    func read(window: QuietWinsWindow) throws -> QuietWinsProjection {
        modelContext.autosaveEnabled = false
        try Task.checkCancellation()
        let start = window.start, end = window.asOf, fallback = Date.distantPast
        let completed = "completed", ordinary = "quickNote"
        let goals = try modelContext.fetch(FetchDescriptor<Goal>(predicate: #Predicate {
            $0.statusRawValue == completed && ($0.completedAt ?? fallback) >= start && ($0.completedAt ?? fallback) <= end
        }))
        let goalIDs = goals.map(\.id)
        let events = try modelContext.fetch(FetchDescriptor<GoalLifecycleEvent>(predicate: #Predicate { goalIDs.contains($0.goalID) }))
        let eventsByGoal = Dictionary(grouping: events, by: \.goalID)
        var input = QuietWinsInput()
        input.goals = goals.map { goal in
            // At equal timestamps, contradictory status events cannot prove completion.
            let history = eventsByGoal[goal.id] ?? []
            let latestDate = history.map(\.occurredAt).max()
            let latest = history.filter { $0.occurredAt == latestDate }
            let kinds = Set(latest.map(\.kindRawValue))
            return .init(id: goal.id, title: goal.title, isCompleted: goal.status == .completed,
                completedAt: goal.completedAt, latestLifecycleKind: kinds.count == 1 ? kinds.first : (latest.isEmpty ? nil : "ambiguous"),
                latestLifecycleDate: latestDate)
        }
        input.todos = try modelContext.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate {
            $0.stateRawValue == completed && ($0.completedAt ?? fallback) >= start && ($0.completedAt ?? fallback) <= end
        })).map { .init(id: $0.id, title: $0.title, isCompleted: $0.state == .completed, completedAt: $0.completedAt) }
        try Task.checkCancellation()

        let first = window.firstDay.description, last = window.lastDay.description
        let dayMetadata = try modelContext.fetch(FetchDescriptor<HabitLogDayMetadata>(predicate: #Predicate {
            $0.localDayIdentifier >= first && $0.localDayIdentifier <= last
        }))
        let dayLogIDs = dayMetadata.map(\.habitLogID)
        let civilLogs = try modelContext.fetch(FetchDescriptor<HabitLog>(predicate: #Predicate {
            dayLogIDs.contains($0.id) && $0.isCompleted && $0.occurredAt <= end
        }))
        // Also cover legacy logs without metadata. Two-day padding includes global zone offsets.
        let paddedStart = start.addingTimeInterval(-2 * 86_400)
        let instantLogs = try modelContext.fetch(FetchDescriptor<HabitLog>(predicate: #Predicate {
            $0.occurredAt >= paddedStart && $0.occurredAt <= end && $0.isCompleted
        }))
        let logsByID = Dictionary((civilLogs + instantLogs).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let logIDs = Array(logsByID.keys)
        let metadata = try modelContext.fetch(FetchDescriptor<HabitLogDayMetadata>(predicate: #Predicate { logIDs.contains($0.habitLogID) }))
        let daysByLog = Dictionary(metadata.map { ($0.habitLogID, $0.localDayIdentifier) }, uniquingKeysWith: { first, _ in first })
        let habitIDs = Array(Set(logsByID.values.map(\.habitID)))
        input.habits = try modelContext.fetch(FetchDescriptor<Habit>(predicate: #Predicate { habitIDs.contains($0.id) }))
            .map { .init(id: $0.id, title: $0.name) }
        input.logs = logsByID.values.map {
            .init(id: $0.id, habitID: $0.habitID, occurredAt: $0.occurredAt, isCompleted: $0.isCompleted, localDay: daysByLog[$0.id])
        }
        try Task.checkCancellation()

        let entries = try modelContext.fetch(FetchDescriptor<Entry>(predicate: #Predicate {
            $0.kindRawValue == ordinary && $0.occurredAt >= start && $0.occurredAt <= end
        }))
        let entryIDs = entries.map(\.id)
        let externalIDs = Set(try modelContext.fetch(FetchDescriptor<EntryExternalSource>(predicate: #Predicate {
            entryIDs.contains($0.entryID)
        })).map(\.entryID))
        input.entries = entries.map {
            .init(id: $0.id, title: $0.title?.isEmpty == false ? $0.title! : String(localized: "Life record"),
                occurredAt: $0.occurredAt, isOrdinary: $0.kind == .quickNote,
                hasContent: $0.body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || !$0.images.isEmpty,
                isExternal: externalIDs.contains($0.id))
        }
        // Weekly identities are civil strings. Fetch only overlapping canonical weeks;
        // periodStart was stored in a possibly different zone and isn't completion time.
        let firstWeek = try WeeklyReviewPeriod(containing: start, timeZone: window.timeZone).identifier
        let lastWeek = try WeeklyReviewPeriod(containing: end, timeZone: window.timeZone).identifier
        input.reviews = try modelContext.fetch(FetchDescriptor<WeeklyReview>(predicate: #Predicate {
            $0.isCompleted && $0.weekIdentifier >= firstWeek && $0.weekIdentifier <= lastWeek
        })).map { .init(id: $0.id, weekIdentifier: $0.weekIdentifier, isCompleted: $0.isCompleted) }
        try Task.checkCancellation()
        return QuietWinsEngine.build(input, window: window)
    }
}

#if DEBUG
/// Public synthetic data only, reachable exclusively through the existing UI-test launch mode.
@MainActor
enum QuietWinsUITestFixture {
    static func seed(context: ModelContext) throws {
        let now = Date()
        let created = now.addingTimeInterval(-60), completed = now.addingTimeInterval(-30)
        let goalService = GoalService(context: context, now: { created })
        let goal = try goalService.create(title: "Quiet goal", kind: .standard)
        try GoalService(context: context, now: { completed }).transition(goal, to: .completed)
        let todo = try TodoTaskService(context: context, now: { created }).create(TodoDraft(title: "Quiet task"))
        try TodoTaskService(context: context, now: { completed }).transition(id: todo.id, to: .completed)
        let habit = try HabitService(context: context, now: { created }).create(name: "Quiet reading", recordingMode: .oncePerDay)
        let log = HabitLog(habitID: habit.id, occurredAt: completed, isCompleted: true, createdAt: completed)
        context.insert(log)
        context.insert(HabitLogDayMetadata(habitLogID: log.id, localDayIdentifier: HabitLocalDay(date: completed).description,
            localTimeZoneIdentifier: TimeZone.current.identifier, provenance: .capturedAtWrite))
        context.insert(Entry(title: "Quiet life record", body: "A real synthetic record for source navigation.", createdAt: created, occurredAt: completed))
        let period = try WeeklyReviewPeriod(containing: now)
        context.insert(WeeklyReview(weekIdentifier: period.identifier, periodStart: period.start, periodEnd: period.end,
            rememberedText: "Quiet week evidence", isCompleted: true, createdAt: created))
        try context.save()
    }
}
#endif
