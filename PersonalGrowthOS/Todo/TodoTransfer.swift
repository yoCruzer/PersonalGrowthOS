import Foundation
import SwiftData

// Backup-only values. Persisted domain objects remain canonical.
// Todo V7 instants use the persisted Date reference epoch (2001-01-01), matching
// event JSON. Converting through the legacy outer 1970 strategy can lose one
// Double ULP and make a valid task disagree with its exact event snapshot.
@propertyWrapper
struct TodoTransferInstant: Codable, Equatable {
    var wrappedValue: Date
    init(wrappedValue: Date) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        wrappedValue = Date(timeIntervalSinceReferenceDate: try decoder.singleValueContainer().decode(Double.self))
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue.timeIntervalSinceReferenceDate)
    }
}
@propertyWrapper
struct TodoTransferOptionalInstant: Codable, Equatable {
    var wrappedValue: Date?
    init(wrappedValue: Date?) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = container.decodeNil() ? nil : Date(timeIntervalSinceReferenceDate: try container.decode(Double.self))
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue { try container.encode(wrappedValue.timeIntervalSinceReferenceDate) }
        else { try container.encodeNil() }
    }
}

struct TodoTaskTransfer: Codable, Equatable {
    var id: UUID
    var title: String
    var notes: String
    var stateRawValue: String
    var isImportant: Bool
    var plannedDay: String?
    var deadlineDay: String?
    @TodoTransferOptionalInstant var remindAt: Date?
    var reminderTimeZoneID: String?
    var reminderLocalDay: String?
    var reminderMinutes: Int?
    @TodoTransferOptionalInstant var completedAt: Date?
    @TodoTransferOptionalInstant var canceledAt: Date?
    @TodoTransferInstant var createdAt: Date
    @TodoTransferInstant var updatedAt: Date
    var listID: UUID?
    var seriesID: UUID?
    var occurrenceIndex: Int?
    var occurrenceKey: String?
    var revision: Int
    init(_ value: TodoTask) {
        id = value.id
        title = value.title
        notes = value.notes
        stateRawValue = value.stateRawValue
        isImportant = value.isImportant
        plannedDay = value.plannedDay
        deadlineDay = value.deadlineDay
        remindAt = value.remindAt
        reminderTimeZoneID = value.reminderTimeZoneID
        reminderLocalDay = value.reminderLocalDay; reminderMinutes = value.reminderMinutes
        completedAt = value.completedAt
        canceledAt = value.canceledAt
        createdAt = value.createdAt
        updatedAt = value.updatedAt
        listID = value.listID
        seriesID = value.seriesID
        occurrenceIndex = value.occurrenceIndex
        occurrenceKey = value.occurrenceKey
        revision = value.revision
    }
    func model() throws -> TodoTask {
        try Task.checkCancellation()
        let value = TodoTask(id: id, title: title, notes: notes, isImportant: isImportant, plannedDay: plannedDay, deadlineDay: deadlineDay, remindAt: remindAt, listID: listID, seriesID: seriesID, occurrenceIndex: occurrenceIndex, createdAt: createdAt)
        value.stateRawValue = stateRawValue; value.completedAt = completedAt; value.canceledAt = canceledAt
        value.updatedAt = updatedAt; value.revision = revision; value.occurrenceKey = occurrenceKey
        value.reminderTimeZoneID = reminderTimeZoneID
        value.reminderLocalDay = reminderLocalDay; value.reminderMinutes = reminderMinutes
        return value
    }
}

struct TodoTaskEventTransfer: Codable, Equatable {
    var id: UUID
    var taskID: UUID
    var sequence: Int
    var kindRawValue: String
    @TodoTransferInstant var occurredAt: Date
    @TodoTransferInstant var createdAt: Date
    var beforeValue: Data?
    var afterValue: Data
    init(_ value: TodoTaskEvent) {
        id = value.id
        taskID = value.taskID
        sequence = value.sequence
        kindRawValue = value.kindRawValue
        occurredAt = value.occurredAt
        createdAt = value.createdAt
        beforeValue = value.beforeValue
        afterValue = value.afterValue
    }
    func model() throws -> TodoTaskEvent {
        try Task.checkCancellation()
        guard let kind = TodoEventKind(rawValue: kindRawValue) else { throw TodoFailure.corruptData }
        let value = TodoTaskEvent(id: id, taskID: taskID, sequence: sequence, kind: kind, occurredAt: occurredAt, createdAt: createdAt, beforeValue: beforeValue, afterValue: afterValue)
        return value
    }
}

struct TodoListTransfer: Codable, Equatable {
    var id: UUID
    var name: String
    @TodoTransferInstant var createdAt: Date
    @TodoTransferInstant var updatedAt: Date
    init(_ value: TodoList) {
        id = value.id
        name = value.name
        createdAt = value.createdAt
        updatedAt = value.updatedAt
    }
    func model() throws -> TodoList {
        try Task.checkCancellation()
        let value = TodoList(id: id, name: name, createdAt: createdAt)
        value.updatedAt = updatedAt
        return value
    }
}

struct TodoSeriesTransfer: Codable, Equatable {
    var id: UUID
    var frequencyRawValue: String
    var anchorDay: String
    var plannedAnchorDay: String?
    var deadlineAnchorDay: String?
    var title: String
    var notes: String
    var isImportant: Bool
    var listID: UUID?
    var reminderMinutes: Int?
    var reminderDayOffset: Int?
    var isStopped: Bool
    @TodoTransferInstant var createdAt: Date
    @TodoTransferInstant var updatedAt: Date
    init(_ value: TodoSeries) {
        id = value.id
        frequencyRawValue = value.frequencyRawValue
        anchorDay = value.anchorDay
        plannedAnchorDay = value.plannedAnchorDay
        deadlineAnchorDay = value.deadlineAnchorDay
        title = value.title
        notes = value.notes
        isImportant = value.isImportant
        listID = value.listID
        reminderMinutes = value.reminderMinutes
        reminderDayOffset = value.reminderDayOffset
        isStopped = value.isStopped
        createdAt = value.createdAt
        updatedAt = value.updatedAt
    }
    func model() throws -> TodoSeries {
        try Task.checkCancellation()
        guard let frequency = TodoFrequency(rawValue: frequencyRawValue) else { throw TodoFailure.corruptData }
        let draft = TodoDraft(title: title, notes: notes, isImportant: isImportant, plannedDay: plannedAnchorDay, deadlineDay: deadlineAnchorDay, listID: listID)
        let value = TodoSeries(id: id, frequency: frequency, anchorDay: anchorDay, draft: draft, reminderMinutes: reminderMinutes, reminderDayOffset: reminderDayOffset, createdAt: createdAt)
        value.isStopped = isStopped; value.updatedAt = updatedAt
        return value
    }
}

struct TodoTaskSourceTransfer: Codable, Equatable {
    var id: UUID
    var taskID: UUID
    var entryID: UUID
    init(_ value: TodoTaskSource) {
        id = value.id
        taskID = value.taskID
        entryID = value.entryID
    }
    func model() throws -> TodoTaskSource {
        try Task.checkCancellation()
        let value = TodoTaskSource(id: id, taskID: taskID, entryID: entryID)
        return value
    }
}

extension TransferData {
    func validateTodos() throws {
        try TodoIntegrity.validate(tasks: todoTasks.map { try $0.model() }, events: todoEvents.map { try $0.model() },
            lists: todoLists.map { try $0.model() }, series: todoSeries.map { try $0.model() },
            sources: todoSources.map { try $0.model() }, entryIDs: Set(entries.map(\.id)))
    }
    func insertTodos(into context: ModelContext) throws {
        for value in todoLists { context.insert(try value.model()) }
        for value in todoSeries { context.insert(try value.model()) }
        for value in todoTasks { context.insert(try value.model()) }
        for value in todoEvents { context.insert(try value.model()) }
        for value in todoSources { context.insert(try value.model()) }
    }
}
