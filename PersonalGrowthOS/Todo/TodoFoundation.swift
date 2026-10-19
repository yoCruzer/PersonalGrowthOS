import Foundation
import SwiftData

// Reuse the app's strict Gregorian civil-day value without changing Habit storage.
typealias TodoDay = HabitLocalDay

enum TodoTaskState: String, Codable, CaseIterable { case open, completed, canceled }
enum TodoFrequency: String, Codable, CaseIterable { case daily, weekly, monthly, yearly, weekdays, weekends, customWeekdays }
enum TodoEventKind: String, Codable {
    case created, edited, completed, reopened, canceled, skipped, successorWithdrawn, seriesStopped, convertedToSeries
}
enum TodoFailure: Error, LocalizedError {
    case invalidTitle, invalidDate, invalidReminder, invalidReminderOffset, conversionRequiresOpen, missingTask, missingList, missingSource, invalidSeries, corruptData, staleTask
    var errorDescription: String? {
        switch self {
        case .staleTask: return String(localized:"This todo changed. Reload its reminder settings before trying again.")
        case .invalidTitle: return String(localized: "Enter a task title of up to 4,000 characters.")
        case .invalidDate: return String(localized: "Choose a valid calendar day.")
        case .invalidReminder: return String(localized: "Choose a future reminder time.")
        case .invalidReminderOffset: return String(localized: "Repeating reminders must be within 366 days of the occurrence anchor.")
        case .conversionRequiresOpen: return String(localized: "Reopen this task before converting it to a repeating series.")
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
    /// Civil days relative to the fixed occurrence anchor; nil is a legacy candidate.
    var reminderDayOffset: Int?
    var isStopped: Bool
    var createdAt: Date
    var updatedAt: Date
    init(id: UUID = UUID(), frequency: TodoFrequency, anchorDay: String,
         draft: TodoDraft, reminderMinutes: Int?, reminderDayOffset: Int? = nil, createdAt: Date) {
        self.id = id; frequencyRawValue = frequency.rawValue; self.anchorDay = anchorDay
        plannedAnchorDay = draft.plannedDay; deadlineAnchorDay = draft.deadlineDay
        title = draft.title; notes = draft.notes; isImportant = draft.isImportant; listID = draft.listID
        self.reminderMinutes = reminderMinutes; self.reminderDayOffset = reminderDayOffset; isStopped = false
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
    var weekdays: Set<Int> = [1,2,3,4,5]
    var reminderChannel: TodoReminderChannel? = nil

    init(title: String = "", notes: String = "", isImportant: Bool = false,
         plannedDay: String? = nil, deadlineDay: String? = nil, remindAt: Date? = nil,
         listID: UUID? = nil, frequency: TodoFrequency? = nil, weekdays: Set<Int> = [1,2,3,4,5],
         reminderChannel: TodoReminderChannel? = nil) {
        self.title = title; self.notes = notes; self.isImportant = isImportant
        self.plannedDay = plannedDay; self.deadlineDay = deadlineDay; self.remindAt = remindAt
        self.listID = listID; self.frequency = frequency;self.weekdays=weekdays;self.reminderChannel=reminderChannel
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
        if frequency == .customWeekdays {_ = try TodoWeekdayRule.mask(weekdays)}
    }
    func validateReminderForSave(now: Date, existingReminder: Date?, usesExistingFutureTemplate: Bool) throws {
        // A past civil day is a valid reference when updating an existing repeat
        // template. The service still validates its offset against the fixed anchor.
        if let reminder = remindAt, reminder <= now, existingReminder != reminder, !usesExistingFutureTemplate {
            throw TodoFailure.invalidReminder
        }
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

enum TodoWeekdayRule {
    static func mask(_ weekdays: Set<Int>) throws -> Int {
        guard !weekdays.isEmpty,weekdays.allSatisfy({(1...7).contains($0)}) else {throw TodoFailure.invalidSeries}
        return weekdays.reduce(0) {$0 | (1 << ($1-1))}
    }
    static func weekdays(_ mask: Int) throws -> Set<Int> {
        guard (1...127).contains(mask) else {throw TodoFailure.invalidSeries}
        return Set((1...7).filter {mask & (1 << ($0-1)) != 0})
    }
    static func day(anchor: TodoDay,index: Int,mask: Int) throws -> TodoDay {
        guard index >= 0,index <= 3_000_000,let date=anchor.date(timeZone:TodoRecurrence.utc) else {throw TodoFailure.invalidSeries}
        let selected=try weekdays(mask)
        // Index zero is the explicitly dated current occurrence. Only its successors follow this set.
        if index == 0 {return anchor}
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TodoRecurrence.utc
        let native=calendar.component(.weekday,from:date),iso=native == 1 ? 7 : native-1
        let offsets=(1...7).filter {selected.contains((iso+$0-1)%7+1)}
        let offset=((index-1)/offsets.count)*7+offsets[(index-1)%offsets.count]
        guard let next=calendar.date(byAdding:.day,value:offset,to:date) else {throw TodoFailure.invalidSeries}
        let result=TodoDay(date:next,timeZone:TodoRecurrence.utc)
        guard result.year <= 9999 else {throw TodoFailure.invalidSeries}
        return result
    }
}

enum TodoRecurrence {
    static let utc = TimeZone(secondsFromGMT: 0)!
    static func day(anchor: String, frequency: TodoFrequency, index: Int, weekdaysMask: Int? = nil) throws -> TodoDay {
        guard index >= 0, index <= 3_000_000, let anchor = TodoDay(anchor), let date = anchor.date(timeZone: utc) else {
            throw TodoFailure.invalidSeries
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = utc
        let result: Date?
        switch frequency {
        case .daily: result = calendar.date(byAdding: .day, value: index, to: date)
        case .weekly: result = calendar.date(byAdding: .day, value: index * 7, to: date)
        case .weekdays, .weekends, .customWeekdays:
            let mask = frequency == .weekdays ? 31 : frequency == .weekends ? 96 : weekdaysMask
            guard let mask else {throw TodoFailure.invalidSeries}
            return try TodoWeekdayRule.day(anchor:anchor,index:index,mask:mask)
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

    static func nextIndex(anchor: String, frequency: TodoFrequency, after index: Int, today: TodoDay, weekdaysMask: Int? = nil) throws -> Int {
        var low = index + 1, high = low
        while try day(anchor: anchor, frequency: frequency, index: high, weekdaysMask: weekdaysMask) <= today {
            high = min(3_000_000, max(high + 1, high * 2))
            if high == 3_000_000 { throw TodoFailure.invalidSeries }
        }
        while low < high {
            let mid = low + (high - low) / 2
            if try day(anchor: anchor, frequency: frequency, index: mid, weekdaysMask: weekdaysMask) <= today { low = mid + 1 }
            else { high = mid }
        }
        return low
    }

    static func reminderOffset(localDay: String, anchor: String) throws -> Int {
        guard let local = TodoDay(localDay)?.date(timeZone: utc), let anchor = TodoDay(anchor)?.date(timeZone: utc) else { throw TodoFailure.invalidReminder }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = utc
        let offset = calendar.dateComponents([.day], from: anchor, to: local).day!
        guard (-366...366).contains(offset) else { throw TodoFailure.invalidReminderOffset }
        return offset
    }
    static func reminderDay(occurrence: TodoDay, offset: Int) throws -> TodoDay {
        guard (-366...366).contains(offset), let date = occurrence.date(timeZone: utc) else { throw TodoFailure.invalidReminderOffset }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = utc
        guard let shifted = calendar.date(byAdding: .day, value: offset, to: date) else { throw TodoFailure.invalidReminderOffset }
        let day = TodoDay(date: shifted, timeZone: utc)
        guard TodoDay(day.description) != nil else { throw TodoFailure.invalidReminderOffset }
        return day
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
    private func makeSeries(_ draft: TodoDraft, at date: Date) throws -> TodoSeries {
        guard let frequency = draft.frequency, let anchor = draft.plannedDay ?? draft.deadlineDay else { throw TodoFailure.invalidSeries }
        let zone = timeZone()
        let minutes = draft.remindAt.map { instant in
            let parts = WeeklyReviewCalendarPolicy.calendar(timeZone: zone).dateComponents([.hour, .minute], from: instant)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        let offset = try draft.remindAt.map { try TodoRecurrence.reminderOffset(localDay: TodoDay(date: $0, timeZone: zone).description, anchor: anchor) }
        let series=TodoSeries(frequency: frequency, anchorDay: anchor, draft: draft, reminderMinutes: minutes, reminderDayOffset: offset, createdAt: date)
        if frequency == .customWeekdays || (draft.reminderChannel ?? .notification) != .notification {
            context.insert(TodoSeriesPreferences(seriesID:series.id,weekdaysMask:frequency == .customWeekdays ? try TodoWeekdayRule.mask(draft.weekdays) : nil,channel:draft.reminderChannel ?? .notification))
        }
        return series
    }
    @discardableResult
    func create(_ draft: TodoDraft, sourceEntryID: UUID? = nil, id: UUID = UUID(), importantDayID: UUID? = nil, importantDayOccurrence: ImportantCivilDay? = nil) throws -> TodoTask {
        try draft.validate(); try requireList(draft.listID)
        if let sourceEntryID, try context.fetchCount(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == sourceEntryID })) != 1 { throw TodoFailure.missingSource }
        var relatedDay: ImportantDay?
        if let importantDayID {
            guard draft.frequency == nil, importantDayOccurrence.map({ $0.date != nil }) ?? true,
                  let day = try context.fetch(FetchDescriptor<ImportantDay>(predicate: #Predicate { $0.id == importantDayID })).first,
                  !day.isArchived else { throw TodoFailure.missingSource }
            relatedDay = day
        }
        // A caller retry uses the same identity; never overwrite its already committed content.
        if let existing = try context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == id })).first { return existing }
        let date = now()
        return try transaction {
            var seriesID: UUID?
            if draft.frequency != nil {
                let series = try makeSeries(draft, at: date)
                context.insert(series); seriesID = series.id
            }
            let task = TodoTask(id: id, title: draft.title, notes: draft.notes, isImportant: draft.isImportant,
                plannedDay: draft.plannedDay, deadlineDay: draft.deadlineDay, remindAt: draft.remindAt,
                listID: draft.listID, seriesID: seriesID, occurrenceIndex: seriesID == nil ? nil : 0, createdAt: date)
            setReminderWallTime(task, from: draft.remindAt)
            context.insert(task)
            try setIntent(task,channel:draft.reminderChannel ?? .notification,override:false,renew:false)
            try record(task, kind: .created, before: nil, at: date)
            if let sourceEntryID { context.insert(TodoTaskSource(taskID: task.id, entryID: sourceEntryID)) }
            if let relatedDay { context.insert(ImportantDayTodoLink(dayID: relatedDay.id, taskID: task.id,
                occurrence: importantDayOccurrence, dayRevisionAtLink: relatedDay.revision, createdAt: date)) }
            return task
        }
    }
    func preferences(for seriesID: UUID) throws -> TodoSeriesPreferences? {
        try context.fetch(FetchDescriptor<TodoSeriesPreferences>(predicate:#Predicate {$0.id == seriesID})).first
    }
    func occurrence(_ rule: TodoSeries,index: Int) throws -> TodoDay {
        guard let frequency=TodoFrequency(rawValue:rule.frequencyRawValue) else {throw TodoFailure.invalidSeries}
        return try TodoRecurrence.day(anchor:rule.anchorDay,frequency:frequency,index:index,weekdaysMask:preferences(for:rule.id)?.weekdaysMask)
    }
    func reminderIntent(for id: UUID) throws -> TodoReminderIntent? {
        try context.fetch(FetchDescriptor<TodoReminderIntent>(predicate:#Predicate {$0.id == id})).first
    }
    func draft(id: UUID) throws -> TodoDraft {
        let task=try task(id:id)
        var draft=TodoDraft(task)
        if let intent=try reminderIntent(for:id) {
            guard let channel=TodoReminderChannel(rawValue:intent.channelRawValue) else {throw TodoFailure.corruptData}
            draft.reminderChannel=channel
        }
        if let seriesID=task.seriesID,let mask=try preferences(for:seriesID)?.weekdaysMask {draft.weekdays=try TodoWeekdayRule.weekdays(mask)}
        return draft
    }
    private func setIntent(_ task: TodoTask,channel: TodoReminderChannel,override: Bool,renew: Bool) throws {
        if let intent=try reminderIntent(for:task.id) {
            if renew || intent.channelRawValue != channel.rawValue || intent.isInstanceOverride != override {
                guard intent.revision >= 0,intent.revision < Int.max-1 else {throw TodoFailure.corruptData}
                intent.generation=UUID();intent.revision += 1;intent.channelRawValue=channel.rawValue;intent.isInstanceOverride=override
            }
        } else if task.remindAt != nil || channel != .notification || override {
            context.insert(TodoReminderIntent(taskID:task.id,channel:channel,isInstanceOverride:override))
        }
    }
    private func preserveLegacyReminderOffset(_ task: TodoTask) throws {
        if let seriesID=task.seriesID {
            let rule=try series(seriesID)
            if !rule.isStopped,rule.reminderDayOffset == nil,rule.reminderMinutes != nil {rule.reminderDayOffset=try reminderOffset(for:rule)}
        }
    }
    /// A deliberate current-occurrence reminder; never changes the plan, deadline or series anchor.
    func rescheduleReminder(id: UUID,to fireAt: Date,channel: TodoReminderChannel? = nil,
                            expectedRevision: Int? = nil,commit: ((ModelContext) throws -> Void)? = nil) throws {
        let write=ModelContext(context.container);write.autosaveEnabled=false
        let writer=TodoTaskService(context:write,now:now,timeZone:timeZone,save:{try (commit ?? {try $0.save()})(write)})
        try writer.rescheduleOwnedReminder(id:id,to:fireAt,channel:channel,expectedRevision:expectedRevision)
    }
    private func rescheduleOwnedReminder(id: UUID,to fireAt: Date,channel: TodoReminderChannel?,expectedRevision: Int?) throws {
        let task=try task(id:id)
        if let expectedRevision,expectedRevision != task.revision {throw TodoFailure.staleTask}
        guard task.state == .open,fireAt.timeIntervalSinceReferenceDate.isFinite,fireAt > now() else {throw TodoFailure.invalidReminder}
        if let seriesID=task.seriesID,try series(seriesID).isStopped {throw TodoFailure.invalidSeries}
        let existing=try reminderIntent(for:id)
        let selected=try channel ?? existing.map {value in
            guard let channel=TodoReminderChannel(rawValue:value.channelRawValue) else {throw TodoFailure.corruptData};return channel
        } ?? .notification
        try transaction {
            guard task.state == .open,fireAt > now() else {throw TodoFailure.invalidReminder}
            // Freeze a legacy rule while the original wall-day/minutes still exist.
            // This is part of the same transaction as the override and event.
            try preserveLegacyReminderOffset(task)
            let before=try TodoEventValue(task)
            task.remindAt=fireAt;setReminderWallTime(task,from:fireAt)
            try setIntent(task,channel:selected,override:task.seriesID != nil,renew:true)
            try record(task,kind:.edited,before:before,at:now())
        }
    }
    private func reminderOffset(for rule: TodoSeries) throws -> Int {
        if let offset = rule.reminderDayOffset { return offset }
        // A nil rule has no stored policy. Only an unchanged legacy rule can be
        // reconstructed from its original per-occurrence event chain. A later explicit
        // series edit already has a non-nil offset and takes the path above.
        guard let minutes=rule.reminderMinutes else {return 0}
        guard rule.updatedAt == rule.createdAt else {throw TodoFailure.invalidReminderOffset}
        let id=rule.id
        let roots=try context.fetch(FetchDescriptor<TodoTask>(predicate:#Predicate {$0.seriesID == id})).filter {$0.occurrenceIndex == 0}
        guard roots.count == 1,let task=roots.first else {throw TodoFailure.invalidReminderOffset}
        let taskID=task.id
        let history=try context.fetch(FetchDescriptor<TodoTaskEvent>(predicate:#Predicate {$0.taskID == taskID})).sorted {$0.sequence < $1.sequence}
        var previous: TodoEventValue?,source: TodoEventValue?
        var reminderEdits=0,lastEdit: Int?,lastReminderEdit: Int?
        for (sequence,event) in history.enumerated() {
            let after=try JSONDecoder().decode(TodoEventValue.self,from:event.afterValue)
            let before=try event.beforeValue.map {try JSONDecoder().decode(TodoEventValue.self,from:$0)}
            guard event.sequence == sequence,before == previous else {throw TodoFailure.corruptData}
            if source == nil,event.createdAt >= rule.createdAt,after.reminderMinutes == minutes,after.reminderLocalDay != nil,
               event.kindRawValue == TodoEventKind.created.rawValue || event.kindRawValue == TodoEventKind.convertedToSeries.rawValue {
                source=after
            }
            if event.kindRawValue == TodoEventKind.edited.rawValue {
                lastEdit=sequence
                if before?.reminderLocalDay != after.reminderLocalDay || before?.reminderMinutes != after.reminderMinutes {
                    reminderEdits += 1;lastReminderEdit=sequence
                }
            }
            previous=after
        }
        if reminderEdits > 0 {
            // Older events do not label instance vs series edits. Only a single
            // final wall-time edit with an explicit current override has an
            // unambiguous original rule; more complex legacy histories need correction.
            guard try reminderIntent(for:taskID)?.isInstanceOverride == true,
                  reminderEdits == 1,lastEdit == lastReminderEdit else {throw TodoFailure.invalidReminderOffset}
        }
        guard !history.isEmpty,previous == (try TodoEventValue(task)),history.last?.sequence == task.revision else {throw TodoFailure.corruptData}
        guard let source,source.reminderMinutes == minutes,let local=source.reminderLocalDay else {throw TodoFailure.invalidReminderOffset}
        // Original V11 could materialize a successor with a lost lead day.
        // Only the verified root creation/conversion is independent evidence;
        // derived successors, even if consistent, cannot establish the old policy.
        return try TodoRecurrence.reminderOffset(localDay:local,anchor:occurrence(rule,index:0).description)
    }

    private func applyTemplate(_ rule: TodoSeries, to task: TodoTask, at date: Date, reactivating: Bool = false) throws {
        let before = try TodoEventValue(task),oldReminder=task.remindAt
        task.title = rule.title; task.notes = rule.notes; task.isImportant = rule.isImportant; task.listID = rule.listID
        try applyReminder(rule, to: task)
        let channel=try preferences(for:rule.id).flatMap {TodoReminderChannel(rawValue:$0.reminderChannelRawValue)} ?? .notification
        try setIntent(task,channel:channel,override:false,renew:reactivating || oldReminder != task.remindAt)
        try record(task, kind: .edited, before: before, at: date)
    }
    private func applyReminder(_ rule: TodoSeries, to task: TodoTask) throws {
        guard let minutes = rule.reminderMinutes else {
            task.remindAt = nil; setReminderWallTime(task, from: nil); return
        }
        guard TodoFrequency(rawValue: rule.frequencyRawValue) != nil, let index = task.occurrenceIndex else { throw TodoFailure.invalidSeries }
        let occurrence = try occurrence(rule,index:index)
        let day = try TodoRecurrence.reminderDay(occurrence: occurrence, offset: reminderOffset(for: rule))
        guard let reminder = TodoRecurrence.reminder(day: day, minutes: minutes, timeZone: timeZone()) else { throw TodoFailure.invalidReminder }
        task.remindAt = reminder; task.reminderLocalDay = day.description
        task.reminderMinutes = minutes; task.reminderTimeZoneID = timeZone().identifier
    }
    func edit(id: UUID, draft: TodoDraft, futureSeries: Bool = false) throws {
        try draft.validate(); try requireList(draft.listID)
        let task = try task(id: id)
        if let frequency = draft.frequency {
            guard task.state == .open else { throw TodoFailure.conversionRequiresOpen }
            if let seriesID = task.seriesID {
                let rule = try series(seriesID)
                var existing = try self.draft(id:task.id); existing.frequency = frequency
                var requested=draft
                let current=existing.reminderChannel ?? .notification
                existing.reminderChannel=current;requested.reminderChannel=draft.reminderChannel ?? current
                let history = try context.fetch(FetchDescriptor<TodoTaskEvent>(predicate: #Predicate { $0.taskID == id }))
                // A committed conversion retry is idempotent, not an arbitrary rule edit.
                guard rule.frequencyRawValue == frequency.rawValue, existing == requested,
                      history.contains(where: { $0.kindRawValue == TodoEventKind.convertedToSeries.rawValue }) else { throw TodoFailure.invalidSeries }
                return
            }
        }
        let previousIntent=try reminderIntent(for:id)
        let currentChannel=previousIntent.flatMap {TodoReminderChannel(rawValue:$0.channelRawValue)} ?? .notification
        let selectedChannel=draft.reminderChannel ?? currentChannel
        let reminderChanged=task.remindAt != draft.remindAt
        let retainOverride=previousIntent?.isInstanceOverride == true && !reminderChanged && !futureSeries && draft.remindAt != nil
        try transaction {
            if !futureSeries && (reminderChanged || previousIntent?.isInstanceOverride == true) {try preserveLegacyReminderOffset(task)}
            let before = try TodoEventValue(task)
            if draft.frequency != nil {
                let rule = try makeSeries(draft, at: now())
                context.insert(rule)
                task.seriesID = rule.id; task.occurrenceIndex = 0; task.occurrenceKey = "\(rule.id.uuidString)/0"
                setReminderWallTime(task, from: draft.remindAt)
            }
            task.title = draft.title; task.notes = draft.notes; task.isImportant = draft.isImportant
            task.plannedDay = draft.plannedDay; task.deadlineDay = draft.deadlineDay
            if task.remindAt != draft.remindAt { setReminderWallTime(task, from: draft.remindAt) }
            task.remindAt = draft.remindAt; task.listID = draft.listID
            if !retainOverride,let seriesID = task.seriesID, let local = task.reminderLocalDay, let index = task.occurrenceIndex {
                let rule = try series(seriesID)
                guard TodoFrequency(rawValue: rule.frequencyRawValue) != nil else { throw TodoFailure.invalidSeries }
                _ = try TodoRecurrence.reminderOffset(localDay: local, anchor: occurrence(rule,index:index).description)
            }
            if futureSeries, let seriesID = task.seriesID {
                let series = try series(seriesID)
                series.title = draft.title; series.notes = draft.notes; series.isImportant = draft.isImportant
                series.listID = draft.listID
                if let preference=try preferences(for:seriesID) {preference.reminderChannelRawValue=selectedChannel.rawValue}
                else if selectedChannel != .notification {context.insert(TodoSeriesPreferences(seriesID:seriesID,channel:selectedChannel))}
                series.reminderMinutes = task.reminderMinutes
                if let local = task.reminderLocalDay, let index = task.occurrenceIndex, TodoFrequency(rawValue: series.frequencyRawValue) != nil {
                    series.reminderDayOffset = try TodoRecurrence.reminderOffset(localDay: local, anchor: occurrence(series,index:index).description)
                } else { series.reminderDayOffset = nil }
                for successor in try context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.seriesID == seriesID }))
                    where successor.id != task.id && successor.state == .open && (successor.occurrenceIndex ?? -1) > (task.occurrenceIndex ?? -1) {
                    try applyTemplate(series, to: successor, at: now())
                }
                series.updatedAt = TechnicalTimestamp.updated(now: now(), createdAt: series.createdAt, previous: series.updatedAt)
            }
            try setIntent(task,channel:selectedChannel,override:retainOverride,renew:reminderChanged)
            try record(task, kind: draft.frequency == nil ? .edited : .convertedToSeries, before: before, at: now())
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
            if state == .open,let fire=task.remindAt,fire > now(),
               try task.seriesID.map({try !series($0).isStopped}) ?? true {
                let intent=try reminderIntent(for:id)
                let channel=intent.flatMap {TodoReminderChannel(rawValue:$0.channelRawValue)} ?? .notification
                try setIntent(task,channel:channel,override:intent?.isInstanceOverride ?? false,renew:true)
            }
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
        var next = try TodoRecurrence.nextIndex(anchor: series.anchorDay, frequency: frequency, after: index, today: TodoDay(date: date, timeZone: timeZone()),weekdaysMask:preferences(for:series.id)?.weekdaysMask)
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
            try applyTemplate(series, to: existing, at: date, reactivating: true)
            return
        }
        let occurrence = try occurrence(series,index:next)
        func shifted(_ anchor: String?) throws -> String? {
            try anchor.map { value in
                if [.weekdays,.weekends,.customWeekdays].contains(frequency) {
                    guard let origin=TodoDay(series.anchorDay)?.date(timeZone:TodoRecurrence.utc),let endpoint=TodoDay(value)?.date(timeZone:TodoRecurrence.utc),let base=occurrence.date(timeZone:TodoRecurrence.utc) else {throw TodoFailure.invalidSeries}
                    var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TodoRecurrence.utc
                    let offset=calendar.dateComponents([.day],from:origin,to:endpoint).day!
                    guard let result=calendar.date(byAdding:.day,value:offset,to:base) else {throw TodoFailure.invalidSeries}
                    let day=TodoDay(date:result,timeZone:TodoRecurrence.utc)
                    guard TodoDay(day.description) != nil else {throw TodoFailure.invalidSeries}
                    return day.description
                }
                return try TodoRecurrence.day(anchor:value,frequency:frequency,index:next).description
            }
        }
        let planned = try shifted(series.plannedAnchorDay), deadline = try shifted(series.deadlineAnchorDay)
        if series.reminderDayOffset == nil,series.reminderMinutes != nil {series.reminderDayOffset=try reminderOffset(for:series)}
        let reminderDay = try TodoRecurrence.reminderDay(occurrence: occurrence, offset: reminderOffset(for: series))
        let reminder = series.reminderMinutes.flatMap { TodoRecurrence.reminder(day: reminderDay, minutes: $0, timeZone: timeZone()) }
        let nextTask = TodoTask(title: series.title, notes: series.notes, isImportant: series.isImportant,
            plannedDay: planned, deadlineDay: deadline, remindAt: reminder, listID: series.listID,
            seriesID: seriesID, occurrenceIndex: next, createdAt: date)
        if reminder != nil {
            nextTask.reminderTimeZoneID = timeZone().identifier
            nextTask.reminderLocalDay = reminderDay.description
            nextTask.reminderMinutes = series.reminderMinutes
        }
        context.insert(nextTask)
        let channel=try preferences(for:series.id).flatMap {TodoReminderChannel(rawValue:$0.reminderChannelRawValue)} ?? .notification
        try setIntent(nextTask,channel:channel,override:false,renew:false)
        try record(nextTask, kind: .created, before: nil, at: date)
        let sourceTaskID = task.id
        if let source = try context.fetch(FetchDescriptor<TodoTaskSource>(predicate: #Predicate { $0.taskID == sourceTaskID })).first {
            context.insert(TodoTaskSource(taskID: nextTask.id, entryID: source.entryID))
        }
    }
    /// Only an unresolvable legacy policy is local to one task. Storage/integrity
    /// failures still abort reconciliation, before any stale snapshot is scheduled.
    @discardableResult func refreshRepeatingReminderTimes() throws -> Set<UUID> {
        let zone = timeZone()
        let tasks = try context.fetch(FetchDescriptor<TodoTask>()).filter {
            $0.state == .open && $0.seriesID != nil && $0.remindAt != nil && $0.reminderTimeZoneID != zone.identifier
        }
        guard !tasks.isEmpty else { return [] }
        return try transaction {
            var unresolved=Set<UUID>()
            for task in tasks {
                guard let seriesID=task.seriesID,try !series(seriesID).isStopped else {continue}
                do {try preserveLegacyReminderOffset(task)}
                catch TodoFailure.invalidReminderOffset {unresolved.insert(task.id);continue}
                guard let dayString = task.reminderLocalDay, let day = TodoDay(dayString),
                      let minutes = task.reminderMinutes else { throw TodoFailure.corruptData }
                let before = try TodoEventValue(task)
                guard let adjusted = TodoRecurrence.reminder(day: day, minutes: minutes, timeZone: zone) else { throw TodoFailure.invalidReminder }
                task.remindAt = adjusted; task.reminderTimeZoneID = zone.identifier
                try record(task, kind: .edited, before: before, at: now())
            }
            return unresolved
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
            try context.fetch(FetchDescriptor<ImportantDayTodoLink>(predicate: #Predicate { $0.taskID == id })).forEach(context.delete)
            if let intent=try reminderIntent(for:id) {context.delete(intent)}
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
            let tasks=try context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.listID == id }))
            let taskSeriesIDs=Set(tasks.compactMap(\.seriesID))
            let rules=try context.fetch(FetchDescriptor<TodoSeries>()).filter {$0.listID == id || taskSeriesIDs.contains($0.id)}
            // Freeze before either task history or the rule timestamp changes. A
            // single-occurrence list edit can leave task and rule lists different.
            for rule in rules where !rule.isStopped && rule.reminderDayOffset == nil && rule.reminderMinutes != nil {
                do {rule.reminderDayOffset=try reminderOffset(for:rule)}
                catch TodoFailure.invalidReminderOffset {
                    // Unlinking a category does not require inventing a future policy.
                    // Preserve the unknown policy; explicit rule correction stays available.
                }
            }
            for task in tasks {
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
enum TodoStatusFilter: String, CaseIterable { case open, all, completed, canceled }
enum TodoQuery {
    static func matches(_ task: TodoTask, filter: TodoFilter, now: Date, timeZone: TimeZone = .current,
                        status: TodoStatusFilter = .all, listID: UUID? = nil, unclassifiedOnly: Bool = false, keyword: String = "") -> Bool {
        if filter == .all && status != .all && task.stateRawValue != status.rawValue { return false }
        if let listID, task.listID != listID { return false }
        if unclassifiedOnly && task.listID != nil { return false }
        let normalized = TextSearchNormalizer.normalize(keyword)
        if !normalized.isEmpty && !TextSearchNormalizer.normalize(task.title + "\n" + task.notes).contains(normalized) { return false }
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
            entryIDs: Set(context.fetch(FetchDescriptor<Entry>()).map(\.id)),
            preferences:context.fetch(FetchDescriptor<TodoSeriesPreferences>()))
    }
    static func validate(tasks: [TodoTask], events: [TodoTaskEvent], lists: [TodoList],
                         series: [TodoSeries], sources: [TodoTaskSource], entryIDs: Set<UUID>,
                         preferences: [TodoSeriesPreferences] = []) throws {
        func require(_ condition: Bool) throws { if !condition { throw TodoFailure.corruptData } }
        func dates(_ created: Date, _ updated: Date) throws {
            try require(created.timeIntervalSince1970.isFinite && updated.timeIntervalSince1970.isFinite && updated >= created)
        }
        func unique<T: Hashable>(_ values: [T]) throws { try require(Set(values).count == values.count) }
        try unique(tasks.map(\.id)); try unique(events.map(\.id)); try unique(lists.map(\.id))
        try unique(series.map(\.id)); try unique(sources.map(\.id)); try unique(sources.map(\.taskID))
        try unique(tasks.compactMap(\.occurrenceKey))
        let taskIDs = Set(tasks.map(\.id)), listIDs = Set(lists.map(\.id)), seriesIDs = Set(series.map(\.id))
        try unique(preferences.map(\.id))
        let preferencesByID=Dictionary(uniqueKeysWithValues:preferences.map {($0.id,$0)})
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
            if rule.frequencyRawValue == TodoFrequency.customWeekdays.rawValue {
                guard let mask=preferencesByID[rule.id]?.weekdaysMask else {throw TodoFailure.corruptData}
                _ = try TodoWeekdayRule.weekdays(mask)
            }
            try require(rule.anchorDay == (rule.plannedAnchorDay ?? rule.deadlineAnchorDay))
            if let id = rule.listID { try require(listIDs.contains(id)) }
            if let minutes = rule.reminderMinutes { try require((0..<1440).contains(minutes)) }
            if let offset = rule.reminderDayOffset { try require((-366...366).contains(offset) && rule.reminderMinutes != nil) }
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
                _ = try TodoRecurrence.day(anchor: rule.anchorDay, frequency: frequency, index: index,weekdaysMask:preferencesByID[id]?.weekdaysMask)
            } else { try require(task.occurrenceIndex == nil && task.occurrenceKey == nil) }
            let history = (byTask[task.id] ?? []).sorted { $0.sequence < $1.sequence }
            try require(!history.isEmpty && task.revision == history.count - 1)
            var previous: TodoEventValue?
            var previousTechnical = task.createdAt
            var conversions = 0
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
                case .convertedToSeries:
                    conversions += 1
                    try require(index > 0 && conversions == 1 && before?.state == .open && after.state == .open
                        && before?.reminderLocalDay == nil && before?.reminderMinutes == nil
                        && task.seriesID != nil && task.occurrenceIndex == 0)
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

// Additive usage-remediation metadata. Historical TodoTask/TodoSeries layouts remain unchanged.
enum TodoReminderChannel: String, Codable, CaseIterable { case notification, alarm }
@Model final class TodoSeriesPreferences {
    @Attribute(.unique) var id: UUID // Series identity.
    /// ISO weekdays: bit 0 is Monday, bit 6 is Sunday. Nil uses the fixed frequency's rule.
    var weekdaysMask: Int?
    var reminderChannelRawValue: String
    init(seriesID: UUID, weekdaysMask: Int? = nil, channel: TodoReminderChannel = .notification) {
        id=seriesID;self.weekdaysMask=weekdaysMask;reminderChannelRawValue=channel.rawValue
    }
}
@Model final class TodoReminderIntent {
    @Attribute(.unique) var id: UUID // Task/occurrence identity, independent of any OS request.
    var generation: UUID
    var revision: Int
    var channelRawValue: String
    var isInstanceOverride: Bool
    init(taskID: UUID, channel: TodoReminderChannel, isInstanceOverride: Bool = false,
         generation: UUID = UUID(), revision: Int = 0) {
        id=taskID;self.generation=generation;self.revision=revision;channelRawValue=channel.rawValue
        self.isInstanceOverride=isInstanceOverride
    }
}
/// Device-only recovery journal. Never encoded in a user backup or copied as authorization.
@Model final class TodoReminderDeviceRecord {
    @Attribute(.unique) var id: UUID // Native request identity, allocated on this device.
    var taskID: UUID
    var intentGeneration: UUID
    var channelRawValue: String
    var fireAt: Date
    var phaseRawValue: String
    var requestedTitle: String?
    init(id: UUID = UUID(), taskID: UUID, intentGeneration: UUID, channel: TodoReminderChannel,
         fireAt: Date, phase: TodoReminderDevicePhase = .prepared, requestedTitle: String? = nil) {
        self.id=id;self.taskID=taskID;self.intentGeneration=intentGeneration
        channelRawValue=channel.rawValue;self.fireAt=fireAt;phaseRawValue=phase.rawValue;self.requestedTitle=requestedTitle
    }
}
enum TodoReminderDevicePhase: String, Codable {
    case ready, prepared, accepted, cancellationPending, retired, capacityWaiting, capacityCancellationPending
}

struct TodoReminderDisplaySnapshot: Equatable {
    let task: TodoTaskTransfer
    let channel: TodoReminderChannel
    let active: Bool
    let cancellationUnverified: Bool
    static func read(id: UUID,container: ModelContainer) throws -> Self? {
        let read=ModelContext(container)
        var query=FetchDescriptor<TodoTask>(predicate:#Predicate {$0.id == id});query.fetchLimit=1
        guard let task=try read.fetch(query).first else {return nil}
        let intent=try read.fetch(FetchDescriptor<TodoReminderIntent>(predicate:#Predicate {$0.id == id})).first
        let channel=try intent.map {value in
            guard let channel=TodoReminderChannel(rawValue:value.channelRawValue) else {throw TodoFailure.corruptData};return channel
        } ?? .notification
        var active=task.state == .open && task.remindAt != nil
        if let seriesID=task.seriesID {
            let rule=try read.fetch(FetchDescriptor<TodoSeries>(predicate:#Predicate {$0.id == seriesID})).first
            active = active && rule?.isStopped == false
        }
        let records=try read.fetch(FetchDescriptor<TodoReminderDeviceRecord>(predicate:#Predicate {$0.taskID == id}))
        let pending=records.contains {
            $0.phaseRawValue == TodoReminderDevicePhase.cancellationPending.rawValue || $0.phaseRawValue == TodoReminderDevicePhase.capacityCancellationPending.rawValue ||
                (!active && [TodoReminderDevicePhase.prepared.rawValue,TodoReminderDevicePhase.accepted.rawValue].contains($0.phaseRawValue))
        }
        return .init(task:TodoTaskTransfer(task),channel:channel,active:active,cancellationUnverified:pending)
    }
}
enum TodoRescheduleDate {
    static func tomorrow(reminder: Date?,wallMinutes: Int?,now: Date,zone: TimeZone) -> Date? {
        guard let reminder,reminder.timeIntervalSinceReferenceDate.isFinite else {return nil}
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=zone
        let parts=calendar.dateComponents([.hour,.minute],from:reminder)
        let minutes=wallMinutes ?? (parts.hour! * 60 + parts.minute!)
        guard let next=calendar.date(byAdding:.day,value:1,to:calendar.startOfDay(for:now)) else {return nil}
        return TodoRecurrence.reminder(day:TodoDay(date:next,timeZone:zone),minutes:minutes,timeZone:zone)
    }
}
