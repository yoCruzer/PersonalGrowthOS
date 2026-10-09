import Foundation
import SwiftData

// Reuse the app's strict Gregorian civil-day value without changing Habit storage.
typealias TodoDay = HabitLocalDay

enum TodoTaskState: String, Codable, CaseIterable { case open, completed, canceled }
enum TodoFrequency: String, Codable, CaseIterable { case daily, weekly, monthly, yearly }
enum TodoEventKind: String, Codable {
    case created, edited, completed, reopened, canceled, skipped, successorWithdrawn, seriesStopped
}
enum TodoFailure: Error, LocalizedError {
    case invalidTitle, invalidDate, invalidReminder, missingTask, missingList, missingSource, invalidSeries, corruptData
    var errorDescription: String? {
        switch self {
        case .invalidTitle: return String(localized: "Enter a task title of up to 4,000 characters.")
        case .invalidDate: return String(localized: "Choose a valid calendar day.")
        case .invalidReminder: return String(localized: "Choose a future reminder time.")
        case .missingTask: return String(localized: "This task is no longer available.")
        case .missingList: return String(localized: "This list is no longer available.")
        case .missingSource: return String(localized: "The source entry is no longer available.")
        case .invalidSeries: return String(localized: "A repeating task needs a planned or deadline day. Stop the series to change its rule.")
        case .corruptData: return String(localized: "Task data is inconsistent. No changes were saved.")
        }
    }
}

@Model
final class TodoTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var stateRawValue: String
    var isImportant: Bool
    var plannedDay: String?
    var deadlineDay: String?
    var remindAt: Date?
    var reminderTimeZoneID: String?
    /// Intended wall time for a repeating occurrence; retained through DST gap resolution.
    var reminderLocalDay: String?
    var reminderMinutes: Int?
    var completedAt: Date?
    var canceledAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var listID: UUID?
    var seriesID: UUID?
    var occurrenceIndex: Int?
    @Attribute(.unique) var occurrenceKey: String?
    var revision: Int

    var state: TodoTaskState? { TodoTaskState(rawValue: stateRawValue) }

    init(id: UUID = UUID(), title: String, notes: String = "", isImportant: Bool = false,
         plannedDay: String? = nil, deadlineDay: String? = nil, remindAt: Date? = nil,
         listID: UUID? = nil, seriesID: UUID? = nil, occurrenceIndex: Int? = nil, createdAt: Date) {
        self.id = id; self.title = title; self.notes = notes; self.isImportant = isImportant
        stateRawValue = TodoTaskState.open.rawValue
        self.plannedDay = plannedDay; self.deadlineDay = deadlineDay; self.remindAt = remindAt
        self.listID = listID; self.seriesID = seriesID; self.occurrenceIndex = occurrenceIndex
        occurrenceKey = seriesID.flatMap { series in occurrenceIndex.map { "\(series.uuidString)/\($0)" } }
        self.createdAt = createdAt; updatedAt = createdAt; revision = 0
    }
}

@Model
final class TodoTaskEvent {
    @Attribute(.unique) var id: UUID
    var taskID: UUID
    var sequence: Int
    var kindRawValue: String
    var occurredAt: Date
    var createdAt: Date
    var beforeValue: Data?
    var afterValue: Data
    init(id: UUID = UUID(), taskID: UUID, sequence: Int, kind: TodoEventKind,
         occurredAt: Date, createdAt: Date, beforeValue: Data?, afterValue: Data) {
        self.id = id; self.taskID = taskID; self.sequence = sequence; kindRawValue = kind.rawValue
        self.occurredAt = occurredAt; self.createdAt = createdAt
        self.beforeValue = beforeValue; self.afterValue = afterValue
    }
}

@Model
final class TodoList {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    init(id: UUID = UUID(), name: String, createdAt: Date) {
        self.id = id; self.name = name; self.createdAt = createdAt; updatedAt = createdAt
    }
}

@Model
final class TodoSeries {
    @Attribute(.unique) var id: UUID
    var frequencyRawValue: String
    var anchorDay: String
    var plannedAnchorDay: String?
    var deadlineAnchorDay: String?
    var title: String
    var notes: String
    var isImportant: Bool
    var listID: UUID?
    /// Wall-clock minutes, resolved in the current device time zone for each occurrence.
    var reminderMinutes: Int?
    var isStopped: Bool
    var createdAt: Date
    var updatedAt: Date
    init(id: UUID = UUID(), frequency: TodoFrequency, anchorDay: String,
         draft: TodoDraft, reminderMinutes: Int?, createdAt: Date) {
        self.id = id; frequencyRawValue = frequency.rawValue; self.anchorDay = anchorDay
        plannedAnchorDay = draft.plannedDay; deadlineAnchorDay = draft.deadlineDay
        title = draft.title; notes = draft.notes; isImportant = draft.isImportant; listID = draft.listID
        self.reminderMinutes = reminderMinutes; isStopped = false
        self.createdAt = createdAt; updatedAt = createdAt
    }
}

@Model
final class TodoTaskSource {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var taskID: UUID
    var entryID: UUID
    init(id: UUID = UUID(), taskID: UUID, entryID: UUID) {
        self.id = id; self.taskID = taskID; self.entryID = entryID
    }
}

struct TodoDraft: Equatable {
    var title = ""
    var notes = ""
    var isImportant = false
    var plannedDay: String?
    var deadlineDay: String?
    var remindAt: Date?
    var listID: UUID?
    var frequency: TodoFrequency?

    init(title: String = "", notes: String = "", isImportant: Bool = false,
         plannedDay: String? = nil, deadlineDay: String? = nil, remindAt: Date? = nil,
         listID: UUID? = nil, frequency: TodoFrequency? = nil) {
        self.title = title; self.notes = notes; self.isImportant = isImportant
        self.plannedDay = plannedDay; self.deadlineDay = deadlineDay; self.remindAt = remindAt
        self.listID = listID; self.frequency = frequency
    }
    init(_ task: TodoTask) {
        self.init(title: task.title, notes: task.notes, isImportant: task.isImportant,
                  plannedDay: task.plannedDay, deadlineDay: task.deadlineDay,
                  remindAt: task.remindAt, listID: task.listID)
    }
    func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 4_000, notes.count <= 100_000 else { throw TodoFailure.invalidTitle }
        for value in [plannedDay, deadlineDay].compactMap({ $0 }) {
            guard TodoDay(value) != nil else { throw TodoFailure.invalidDate }
        }
        if let remindAt, !remindAt.timeIntervalSince1970.isFinite { throw TodoFailure.invalidReminder }
        if frequency != nil && plannedDay == nil && deadlineDay == nil { throw TodoFailure.invalidSeries }
    }
}

// Limited event payload: state and scheduling facts, never a second canonical task model.
struct TodoEventValue: Codable, Equatable {
    let state: TodoTaskState
    let plannedDay: String?
    let deadlineDay: String?
    let remindAt: Date?
    let completedAt: Date?
    let canceledAt: Date?
    let reminderLocalDay: String?
    let reminderMinutes: Int?
    init(_ task: TodoTask) throws {
        guard let state = task.state else { throw TodoFailure.corruptData }
        self.state = state; plannedDay = task.plannedDay; deadlineDay = task.deadlineDay
        remindAt = task.remindAt; completedAt = task.completedAt; canceledAt = task.canceledAt
        reminderLocalDay = task.reminderLocalDay; reminderMinutes = task.reminderMinutes
    }
}

enum TodoRecurrence {
    static let utc = TimeZone(secondsFromGMT: 0)!
    static func day(anchor: String, frequency: TodoFrequency, index: Int) throws -> TodoDay {
        guard index >= 0, index <= 3_000_000, let anchor = TodoDay(anchor), let date = anchor.date(timeZone: utc) else {
            throw TodoFailure.invalidSeries
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = utc
        let result: Date?
        switch frequency {
        case .daily: result = calendar.date(byAdding: .day, value: index, to: date)
        case .weekly: result = calendar.date(byAdding: .day, value: index * 7, to: date)
        case .monthly, .yearly:
            let start = calendar.date(from: DateComponents(year: anchor.year, month: anchor.month, day: 1))!
            let shifted = calendar.date(byAdding: frequency == .monthly ? .month : .year, value: index, to: start)
            guard let shifted, let range = calendar.range(of: .day, in: .month, for: shifted) else {
                throw TodoFailure.invalidSeries
            }
            result = calendar.date(byAdding: .day, value: min(anchor.day, range.count) - 1, to: shifted)
        }
        guard let result else { throw TodoFailure.invalidSeries }
        let day = TodoDay(date: result, timeZone: utc)
        guard day.year <= 9999 else { throw TodoFailure.invalidSeries }
        return day
    }

    static func nextIndex(anchor: String, frequency: TodoFrequency, after index: Int, today: TodoDay) throws -> Int {
        var low = index + 1, high = low
        while try day(anchor: anchor, frequency: frequency, index: high) <= today {
            high = min(3_000_000, max(high + 1, high * 2))
            if high == 3_000_000 { throw TodoFailure.invalidSeries }
        }
        while low < high {
            let mid = low + (high - low) / 2
            if try day(anchor: anchor, frequency: frequency, index: mid) <= today { low = mid + 1 }
            else { high = mid }
        }
        return low
    }

    static func reminder(day: TodoDay, minutes: Int, timeZone: TimeZone) -> Date? {
        guard (0..<1440).contains(minutes), let start = day.date(timeZone: timeZone) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        // Missing DST times advance to the next valid time; repeated times use the first occurrence.
        return calendar.nextDate(after: start.addingTimeInterval(-1), matching: DateComponents(hour: minutes / 60, minute: minutes % 60), matchingPolicy: .nextTime, repeatedTimePolicy: .first)
    }
}

@MainActor
final class TodoTaskService {
    private let context: ModelContext
    private let now: () -> Date
    private let timeZone: () -> TimeZone
    private let save: () throws -> Void
    init(context: ModelContext, now: @escaping () -> Date = Date.init,
         timeZone: @escaping () -> TimeZone = { .current }, save: (() throws -> Void)? = nil) {
        self.context = context; self.now = now; self.timeZone = timeZone
        self.save = save ?? { try context.save() }
    }
    private func transaction<T>(_ operation: () throws -> T) throws -> T {
        do { let result = try operation(); try save(); NotificationCenter.default.post(name: .todoTasksChanged, object: context.container); return result }
        catch { context.rollback(); throw error }
    }
    func task(id: UUID) throws -> TodoTask {
        guard let task = try context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == id })).first else { throw TodoFailure.missingTask }
        return task
    }
    private func requireList(_ id: UUID?) throws {
        if let id, try context.fetchCount(FetchDescriptor<TodoList>(predicate: #Predicate { $0.id == id })) != 1 { throw TodoFailure.missingList }
    }
    private func setReminderWallTime(_ task: TodoTask, from instant: Date?) {
        guard task.seriesID != nil, let instant else {
            task.reminderTimeZoneID = nil; task.reminderLocalDay = nil; task.reminderMinutes = nil
            return
        }
        let zone = timeZone()
        let parts = WeeklyReviewCalendarPolicy.calendar(timeZone: zone).dateComponents([.hour, .minute], from: instant)
        task.reminderTimeZoneID = zone.identifier
        task.reminderLocalDay = TodoDay(date: instant, timeZone: zone).description
        task.reminderMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
    private func series(_ id: UUID) throws -> TodoSeries {
        guard let value = try context.fetch(FetchDescriptor<TodoSeries>(predicate: #Predicate { $0.id == id })).first else { throw TodoFailure.invalidSeries }
        return value
    }
    private func record(_ task: TodoTask, kind: TodoEventKind, before: TodoEventValue?, at date: Date) throws {
        if before != nil { task.revision += 1 }
        task.updatedAt = TechnicalTimestamp.updated(now: date, createdAt: task.createdAt, previous: task.updatedAt)
        context.insert(TodoTaskEvent(taskID: task.id, sequence: task.revision, kind: kind,
            occurredAt: date, createdAt: task.updatedAt,
            beforeValue: try before.map { try JSONEncoder().encode($0) },
            afterValue: try JSONEncoder().encode(TodoEventValue(task))))
    }
    @discardableResult
    func create(_ draft: TodoDraft, sourceEntryID: UUID? = nil, id: UUID = UUID()) throws -> TodoTask {
        try draft.validate(); try requireList(draft.listID)
        if let sourceEntryID, try context.fetchCount(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == sourceEntryID })) != 1 { throw TodoFailure.missingSource }
        // A caller retry uses the same identity; never overwrite its already committed content.
        if let existing = try context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == id })).first { return existing }
        let date = now()
        return try transaction {
            var seriesID: UUID?
            if let frequency = draft.frequency {
                let anchor = draft.plannedDay ?? draft.deadlineDay!
                let minutes = draft.remindAt.map { date in
                    let parts = WeeklyReviewCalendarPolicy.calendar(timeZone: timeZone()).dateComponents([.hour, .minute], from: date)
                    return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                }
                let series = TodoSeries(frequency: frequency, anchorDay: anchor, draft: draft, reminderMinutes: minutes, createdAt: date)
                context.insert(series); seriesID = series.id
            }
            let task = TodoTask(id: id, title: draft.title, notes: draft.notes, isImportant: draft.isImportant,
                plannedDay: draft.plannedDay, deadlineDay: draft.deadlineDay, remindAt: draft.remindAt,
                listID: draft.listID, seriesID: seriesID, occurrenceIndex: seriesID == nil ? nil : 0, createdAt: date)
            setReminderWallTime(task, from: draft.remindAt)
            context.insert(task)
            try record(task, kind: .created, before: nil, at: date)
            if let sourceEntryID { context.insert(TodoTaskSource(taskID: task.id, entryID: sourceEntryID)) }
            return task
        }
    }
    func edit(id: UUID, draft: TodoDraft, futureSeries: Bool = false) throws {
        try draft.validate(); try requireList(draft.listID)
        let task = try task(id: id)
        guard draft.frequency == nil else { throw TodoFailure.invalidSeries }
        try transaction {
            let before = try TodoEventValue(task)
            task.title = draft.title; task.notes = draft.notes; task.isImportant = draft.isImportant
            task.plannedDay = draft.plannedDay; task.deadlineDay = draft.deadlineDay
            if task.remindAt != draft.remindAt { setReminderWallTime(task, from: draft.remindAt) }
            task.remindAt = draft.remindAt; task.listID = draft.listID
            if futureSeries, let seriesID = task.seriesID {
                let series = try series(seriesID)
                series.title = draft.title; series.notes = draft.notes; series.isImportant = draft.isImportant
                series.listID = draft.listID
                series.reminderMinutes = task.reminderMinutes
                series.updatedAt = TechnicalTimestamp.updated(now: now(), createdAt: series.createdAt, previous: series.updatedAt)
            }
            try record(task, kind: .edited, before: before, at: now())
        }
    }
    func transition(id: UUID, to state: TodoTaskState, skip: Bool = false) throws {
        let task = try task(id: id)
        guard task.state != state else { return }
        if skip && (state != .canceled || task.seriesID == nil || task.state != .open) { throw TodoFailure.invalidSeries }
        try transaction {
            let date = now(), before = try TodoEventValue(task)
            if state == .open, let seriesID = task.seriesID {
                let others = try context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.seriesID == seriesID }))
                for other in others where other.id != id && other.state == .open {
                    let value = try TodoEventValue(other)
                    other.stateRawValue = TodoTaskState.canceled.rawValue; other.canceledAt = date; other.completedAt = nil
                    try record(other, kind: .successorWithdrawn, before: value, at: date)
                }
            }
            task.stateRawValue = state.rawValue
            task.completedAt = state == .completed ? date : nil
            task.canceledAt = state == .canceled ? date : nil
            try record(task, kind: state == .completed ? .completed : state == .open ? .reopened : skip ? .skipped : .canceled, before: before, at: date)
            if state != .open { try generateNext(after: task, at: date) }
        }
    }
    private func generateNext(after task: TodoTask, at date: Date) throws {
        guard let seriesID = task.seriesID else { return }
        let series = try series(seriesID)
        guard !series.isStopped, let frequency = TodoFrequency(rawValue: series.frequencyRawValue), let index = task.occurrenceIndex else { return }
        let siblings = try context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.seriesID == seriesID }))
        guard !siblings.contains(where: { $0.state == .open }) else { return }
        var next = try TodoRecurrence.nextIndex(anchor: series.anchorDay, frequency: frequency, after: index, today: TodoDay(date: date, timeZone: timeZone()))
        // Completed or deliberately skipped facts are never reopened as a side effect.
        while let existing = siblings.first(where: { $0.occurrenceIndex == next }) {
            let existingID = existing.id
            let last = try context.fetch(FetchDescriptor<TodoTaskEvent>(predicate: #Predicate { $0.taskID == existingID }))
                .max { $0.sequence < $1.sequence }
            if existing.state == .canceled && last?.kindRawValue == TodoEventKind.successorWithdrawn.rawValue { break }
            next += 1
        }
        if let existing = siblings.first(where: { $0.occurrenceIndex == next }) {
            let before = try TodoEventValue(existing)
            existing.stateRawValue = TodoTaskState.open.rawValue; existing.canceledAt = nil; existing.completedAt = nil
            try record(existing, kind: .reopened, before: before, at: date)
            return
        }
        func shifted(_ anchor: String?) throws -> String? {
            try anchor.map { try TodoRecurrence.day(anchor: $0, frequency: frequency, index: next).description }
        }
        let planned = try shifted(series.plannedAnchorDay), deadline = try shifted(series.deadlineAnchorDay)
        let occurrence = try TodoRecurrence.day(anchor: series.anchorDay, frequency: frequency, index: next)
        let reminder = series.reminderMinutes.flatMap { TodoRecurrence.reminder(day: occurrence, minutes: $0, timeZone: timeZone()) }
        let nextTask = TodoTask(title: series.title, notes: series.notes, isImportant: series.isImportant,
            plannedDay: planned, deadlineDay: deadline, remindAt: reminder, listID: series.listID,
            seriesID: seriesID, occurrenceIndex: next, createdAt: date)
        if reminder != nil {
            nextTask.reminderTimeZoneID = timeZone().identifier
            nextTask.reminderLocalDay = occurrence.description
            nextTask.reminderMinutes = series.reminderMinutes
        }
        context.insert(nextTask); try record(nextTask, kind: .created, before: nil, at: date)
        let sourceTaskID = task.id
        if let source = try context.fetch(FetchDescriptor<TodoTaskSource>(predicate: #Predicate { $0.taskID == sourceTaskID })).first {
            context.insert(TodoTaskSource(taskID: nextTask.id, entryID: source.entryID))
        }
    }
    func refreshRepeatingReminderTimes() throws {
        let zone = timeZone()
        let tasks = try context.fetch(FetchDescriptor<TodoTask>()).filter {
            $0.state == .open && $0.seriesID != nil && $0.remindAt != nil && $0.reminderTimeZoneID != zone.identifier
        }
        guard !tasks.isEmpty else { return }
        try transaction {
            for task in tasks {
                guard let dayString = task.reminderLocalDay, let day = TodoDay(dayString),
                      let minutes = task.reminderMinutes else { throw TodoFailure.corruptData }
                let before = try TodoEventValue(task)
                guard let adjusted = TodoRecurrence.reminder(day: day, minutes: minutes, timeZone: zone) else { throw TodoFailure.invalidReminder }
                task.remindAt = adjusted; task.reminderTimeZoneID = zone.identifier
                try record(task, kind: .edited, before: before, at: now())
            }
        }
    }
    func stopSeries(taskID: UUID) throws {
        let task = try task(id: taskID)
        guard let seriesID = task.seriesID else { return }
        let series = try series(seriesID)
        guard !series.isStopped else { return }
        try transaction {
            series.isStopped = true
            series.updatedAt = TechnicalTimestamp.updated(now: now(), createdAt: series.createdAt, previous: series.updatedAt)
            try record(task, kind: .seriesStopped, before: TodoEventValue(task), at: now())
        }
    }
    func delete(id: UUID) throws {
        let task = try task(id: id)
        try transaction {
            // Deleting an occurrence stops generation so a restart cannot resurrect it.
            if let seriesID = task.seriesID {
                let series = try series(seriesID); series.isStopped = true
                series.updatedAt = TechnicalTimestamp.updated(now: now(), createdAt: series.createdAt, previous: series.updatedAt)
            }
            try context.fetch(FetchDescriptor<TodoTaskEvent>(predicate: #Predicate { $0.taskID == id })).forEach(context.delete)
            try context.fetch(FetchDescriptor<TodoTaskSource>(predicate: #Predicate { $0.taskID == id })).forEach(context.delete)
            context.delete(task)
        }
    }
    func createList(name: String) throws -> TodoList {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 200 else { throw TodoFailure.invalidTitle }
        return try transaction { let list = TodoList(name: name, createdAt: now()); context.insert(list); return list }
    }
    func renameList(id: UUID, name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 200 else { throw TodoFailure.invalidTitle }
        guard let list = try context.fetch(FetchDescriptor<TodoList>(predicate: #Predicate { $0.id == id })).first else { throw TodoFailure.missingList }
        try transaction { list.name = name; list.updatedAt = TechnicalTimestamp.updated(now: now(), createdAt: list.createdAt, previous: list.updatedAt) }
    }
    func deleteList(id: UUID) throws {
        guard let list = try context.fetch(FetchDescriptor<TodoList>(predicate: #Predicate { $0.id == id })).first else { throw TodoFailure.missingList }
        try transaction {
            for task in try context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.listID == id })) {
                let before = try TodoEventValue(task); task.listID = nil
                try record(task, kind: .edited, before: before, at: now())
            }
            for series in try context.fetch(FetchDescriptor<TodoSeries>(predicate: #Predicate { $0.listID == id })) {
                series.listID = nil
                series.updatedAt = TechnicalTimestamp.updated(now: now(), createdAt: series.createdAt, previous: series.updatedAt)
            }
            context.delete(list)
        }
    }
}

enum TodoFilter: String, CaseIterable { case today, upcoming, all, completed, canceled, completedToday, completedWeek, open, overdue }
enum TodoQuery {
    static func matches(_ task: TodoTask, filter: TodoFilter, now: Date, timeZone: TimeZone = .current) -> Bool {
        let today = TodoDay(date: now, timeZone: timeZone).description
        let dueToday = task.plannedDay.map { $0 <= today } == true || task.deadlineDay.map { $0 <= today } == true
        switch filter {
        case .today: return task.state == .open && dueToday
        case .upcoming: return task.state == .open && !dueToday && (task.plannedDay.map { $0 > today } == true || task.deadlineDay.map { $0 > today } == true)
        case .all: return true
        case .open: return task.state == .open
        case .overdue: return task.state == .open && task.deadlineDay.map { $0 < today } == true
        case .completed: return task.state == .completed
        case .canceled: return task.state == .canceled
        case .completedToday: return task.state == .completed && task.completedAt.map { TodoDay(date: $0, timeZone: timeZone).description == today } == true
        case .completedWeek: return task.state == .completed && task.completedAt.map { (try? WeeklyReviewPeriod(containing: now, timeZone: timeZone).contains($0)) == true } == true
        }
    }
    static func sorted(_ tasks: [TodoTask]) -> [TodoTask] {
        tasks.sorted {
            if $0.isImportant != $1.isImportant { return $0.isImportant }
            let left = min($0.plannedDay ?? "9999-12-31", $0.deadlineDay ?? "9999-12-31")
            let right = min($1.plannedDay ?? "9999-12-31", $1.deadlineDay ?? "9999-12-31")
            if left != right { return left < right }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

enum TodoIntegrity {
    @MainActor
    static func validate(context: ModelContext) throws {
        try validate(tasks: context.fetch(FetchDescriptor<TodoTask>()),
            events: context.fetch(FetchDescriptor<TodoTaskEvent>()),
            lists: context.fetch(FetchDescriptor<TodoList>()),
            series: context.fetch(FetchDescriptor<TodoSeries>()),
            sources: context.fetch(FetchDescriptor<TodoTaskSource>()),
            entryIDs: Set(context.fetch(FetchDescriptor<Entry>()).map(\.id)))
    }
    static func validate(tasks: [TodoTask], events: [TodoTaskEvent], lists: [TodoList],
                         series: [TodoSeries], sources: [TodoTaskSource], entryIDs: Set<UUID>) throws {
        func require(_ condition: Bool) throws { if !condition { throw TodoFailure.corruptData } }
        func dates(_ created: Date, _ updated: Date) throws {
            try require(created.timeIntervalSince1970.isFinite && updated.timeIntervalSince1970.isFinite && updated >= created)
        }
        func unique<T: Hashable>(_ values: [T]) throws { try require(Set(values).count == values.count) }
        try unique(tasks.map(\.id)); try unique(events.map(\.id)); try unique(lists.map(\.id))
        try unique(series.map(\.id)); try unique(sources.map(\.id)); try unique(sources.map(\.taskID))
        try unique(tasks.compactMap(\.occurrenceKey))
        let taskIDs = Set(tasks.map(\.id)), listIDs = Set(lists.map(\.id)), seriesIDs = Set(series.map(\.id))
        let rulesByID = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0) })
        let byTask = Dictionary(grouping: events, by: \.taskID)
        let openBySeries = Dictionary(grouping: tasks.filter { $0.seriesID != nil && $0.state == .open }, by: { $0.seriesID! })
        func validateValue(_ value: TodoEventValue) throws {
            for day in [value.plannedDay, value.deadlineDay].compactMap({ $0 }) { try require(TodoDay(day) != nil) }
            for date in [value.remindAt, value.completedAt, value.canceledAt].compactMap({ $0 }) { try require(date.timeIntervalSince1970.isFinite) }
            if let day = value.reminderLocalDay { try require(TodoDay(day) != nil && value.reminderMinutes != nil && value.remindAt != nil) }
            if let minutes = value.reminderMinutes { try require((0..<1440).contains(minutes) && value.reminderLocalDay != nil) }
            switch value.state {
            case .open: try require(value.completedAt == nil && value.canceledAt == nil)
            case .completed: try require(value.completedAt != nil && value.canceledAt == nil)
            case .canceled: try require(value.completedAt == nil && value.canceledAt != nil)
            }
        }
        for list in lists {
            try require(!list.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && list.name.count <= 200)
            try dates(list.createdAt, list.updatedAt)
        }
        for rule in series {
            try Task.checkCancellation()
            let draft = TodoDraft(title: rule.title, notes: rule.notes, plannedDay: rule.plannedAnchorDay, deadlineDay: rule.deadlineAnchorDay)
            try draft.validate(); try dates(rule.createdAt, rule.updatedAt)
            try require(TodoFrequency(rawValue: rule.frequencyRawValue) != nil && TodoDay(rule.anchorDay) != nil)
            try require(rule.anchorDay == (rule.plannedAnchorDay ?? rule.deadlineAnchorDay))
            if let id = rule.listID { try require(listIDs.contains(id)) }
            if let minutes = rule.reminderMinutes { try require((0..<1440).contains(minutes)) }
            try require((openBySeries[rule.id]?.count ?? 0) <= 1)
        }
        for task in tasks {
            try TodoDraft(task).validate(); try dates(task.createdAt, task.updatedAt)
            try require(task.revision >= 0)
            let current = try TodoEventValue(task); try validateValue(current)
            if let zone = task.reminderTimeZoneID { try require(task.seriesID != nil && task.remindAt != nil && TimeZone(identifier: zone) != nil) }
            if task.seriesID != nil && task.remindAt != nil {
                try require(task.reminderTimeZoneID != nil && task.reminderLocalDay != nil && task.reminderMinutes != nil)
            } else { try require(task.reminderTimeZoneID == nil && task.reminderLocalDay == nil && task.reminderMinutes == nil) }
            if let id = task.listID { try require(listIDs.contains(id)) }
            if let id = task.seriesID {
                try require(seriesIDs.contains(id))
                guard let index = task.occurrenceIndex else { throw TodoFailure.corruptData }
                try require(index >= 0 && index <= 3_000_000 && task.occurrenceKey == "\(id.uuidString)/\(index)")
                guard let rule = rulesByID[id], let frequency = TodoFrequency(rawValue: rule.frequencyRawValue) else { throw TodoFailure.corruptData }
                _ = try TodoRecurrence.day(anchor: rule.anchorDay, frequency: frequency, index: index)
            } else { try require(task.occurrenceIndex == nil && task.occurrenceKey == nil) }
            let history = (byTask[task.id] ?? []).sorted { $0.sequence < $1.sequence }
            try require(history.count == task.revision + 1)
            var previous: TodoEventValue?
            var previousTechnical = task.createdAt
            for (index, event) in history.enumerated() {
                try Task.checkCancellation()
                guard let kind = TodoEventKind(rawValue: event.kindRawValue) else { throw TodoFailure.corruptData }
                try require(event.sequence == index && event.occurredAt.timeIntervalSince1970.isFinite)
                try require((index == 0) == (kind == .created))
                try dates(task.createdAt, event.createdAt); try require(event.createdAt >= previousTechnical)
                let after = try JSONDecoder().decode(TodoEventValue.self, from: event.afterValue)
                let before = try event.beforeValue.map { try JSONDecoder().decode(TodoEventValue.self, from: $0) }
                try validateValue(after); try require(before == previous)
                switch kind {
                case .created:
                    try require(index == 0 && before == nil && after.state == .open && event.occurredAt == task.createdAt && event.createdAt == task.createdAt)
                case .edited: try require(index > 0 && before?.state == after.state)
                case .seriesStopped:
                    try require(index > 0 && before == after && task.seriesID.flatMap { rulesByID[$0] }?.isStopped == true)
                case .completed: try require(before?.state != .completed && after.state == .completed && after.completedAt == event.occurredAt)
                case .reopened: try require(before?.state != .open && after.state == .open)
                case .canceled, .skipped, .successorWithdrawn:
                    try require(before?.state != .canceled && after.state == .canceled && after.canceledAt == event.occurredAt)
                    if kind != .canceled { try require(task.seriesID != nil && before?.state == .open) }
                }
                previous = after; previousTechnical = event.createdAt
            }
            try require(previous == current && previousTechnical == task.updatedAt)
        }
        for event in events { try require(taskIDs.contains(event.taskID)) }
        for source in sources { try require(taskIDs.contains(source.taskID) && entryIDs.contains(source.entryID)) }
    }
}

extension Notification.Name { static let todoTasksChanged = Notification.Name("TodoTasksChanged") }
