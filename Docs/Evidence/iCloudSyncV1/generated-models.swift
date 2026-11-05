import Foundation
import SwiftData
@Model final class Entry {
@Attribute(.unique) var id: UUID
var kindRawValue: String
var statusRawValue: String
var title: String?
var body: String?
var createdAt: Date
var occurredAt: Date
var updatedAt: Date
var periodStart: Date?
var periodEnd: Date?
@Relationship(deleteRule: .cascade, inverse: \ImageMetadata.entry)
var images: [ImageMetadata]
init() {
self.id = UUID()
self.kindRawValue = ""
self.statusRawValue = ""
self.title = nil
self.body = nil
self.createdAt = Date(timeIntervalSince1970:0)
self.occurredAt = Date(timeIntervalSince1970:0)
self.updatedAt = Date(timeIntervalSince1970:0)
self.periodStart = nil
self.periodEnd = nil
self.images = []
}
}
@Model final class ImageMetadata {
@Attribute(.unique) var id: UUID
var relativePath: String
var originalFilename: String
var contentType: String
var byteCount: Int64
var pixelWidth: Int
var pixelHeight: Int
var checksum: String
var sortOrder: Int
var createdAt: Date
var updatedAt: Date
var entry: Entry?
init() {
self.id = UUID()
self.relativePath = ""
self.originalFilename = ""
self.contentType = ""
self.byteCount = 0
self.pixelWidth = 0
self.pixelHeight = 0
self.checksum = ""
self.sortOrder = 0
self.createdAt = Date(timeIntervalSince1970:0)
self.updatedAt = Date(timeIntervalSince1970:0)
self.entry = nil
}
}
@Model final class Tag {
@Attribute(.unique) var id: UUID
var displayName: String
@Attribute(.unique) var normalizedName: String
var createdAt: Date
var updatedAt: Date
init() {
self.id = UUID()
self.displayName = ""
self.normalizedName = ""
self.createdAt = Date(timeIntervalSince1970:0)
self.updatedAt = Date(timeIntervalSince1970:0)
}
}
@Model final class ObjectLink {
@Attribute(.unique) var id: UUID
var sourceTypeRawValue: String
var sourceID: UUID
var targetTypeRawValue: String
var targetID: UUID
var kindRawValue: String
@Attribute(.unique) var deduplicationKey: String
var createdAt: Date
init() {
self.id = UUID()
self.sourceTypeRawValue = ""
self.sourceID = UUID()
self.targetTypeRawValue = ""
self.targetID = UUID()
self.kindRawValue = ""
self.deduplicationKey = ""
self.createdAt = Date(timeIntervalSince1970:0)
}
}
@Model final class Habit {
@Attribute(.unique) var id: UUID
var name: String
var normalizedName: String
var statusRawValue: String
var createdAt: Date
var updatedAt: Date
init() {
self.id = UUID()
self.name = ""
self.normalizedName = ""
self.statusRawValue = ""
self.createdAt = Date(timeIntervalSince1970:0)
self.updatedAt = Date(timeIntervalSince1970:0)
}
}
@Model final class HabitLog {
@Attribute(.unique) var id: UUID
var habitID: UUID
var occurredAt: Date
var isCompleted: Bool
var quantity: Double?
var unit: String?
var result: String?
var linkedEntryID: UUID?
var createdAt: Date
init() {
self.id = UUID()
self.habitID = UUID()
self.occurredAt = Date(timeIntervalSince1970:0)
self.isCompleted = false
self.quantity = nil
self.unit = nil
self.result = nil
self.linkedEntryID = nil
self.createdAt = Date(timeIntervalSince1970:0)
}
}
@Model final class HabitConfiguration {
@Attribute(.unique) var id: UUID
@Attribute(.unique) var habitID: UUID
var recordingModeRawValue: String
var dailyTargetCount: Int?
var updatedAt: Date
init() {
self.id = UUID()
self.habitID = UUID()
self.recordingModeRawValue = ""
self.dailyTargetCount = nil
self.updatedAt = Date(timeIntervalSince1970:0)
}
}
@Model final class HabitLogDayMetadata {
@Attribute(.unique) var id: UUID
@Attribute(.unique) var habitLogID: UUID
var localDayIdentifier: String
var localTimeZoneIdentifier: String
var provenanceRawValue: String
init() {
self.id = UUID()
self.habitLogID = UUID()
self.localDayIdentifier = ""
self.localTimeZoneIdentifier = ""
self.provenanceRawValue = ""
}
}
@Model final class HabitPlanRevision {
@Attribute(.unique) var id: UUID
var habitID: UUID
var effectiveLocalDay: String
var recordingModeRawValue: String
var periodRawValue: String
var goalRawValue: String
var targetCount: Int?
var weekdaysRawValue: String
var trustCoverageStartLocalDay: String
var createdAt: Date
var originRawValue: String
init() {
self.id = UUID()
self.habitID = UUID()
self.effectiveLocalDay = ""
self.recordingModeRawValue = ""
self.periodRawValue = ""
self.goalRawValue = ""
self.targetCount = nil
self.weekdaysRawValue = ""
self.trustCoverageStartLocalDay = ""
self.createdAt = Date(timeIntervalSince1970:0)
self.originRawValue = ""
}
}
@Model final class HabitLifecycleEvent {
@Attribute(.unique) var id: UUID
var habitID: UUID
var kindRawValue: String
var occurredLocalDay: String
var occurredAt: Date
var createdAt: Date
var knownStatusRawValue: String?
init() {
self.id = UUID()
self.habitID = UUID()
self.kindRawValue = ""
self.occurredLocalDay = ""
self.occurredAt = Date(timeIntervalSince1970:0)
self.createdAt = Date(timeIntervalSince1970:0)
self.knownStatusRawValue = nil
}
}
@Model final class Goal {
@Attribute(.unique) var id: UUID
var kindRawValue: String
var title: String
var normalizedTitle: String
var statusRawValue: String
var createdAt: Date
var updatedAt: Date
var completedAt: Date?
init() {
self.id = UUID()
self.kindRawValue = ""
self.title = ""
self.normalizedTitle = ""
self.statusRawValue = ""
self.createdAt = Date(timeIntervalSince1970:0)
self.updatedAt = Date(timeIntervalSince1970:0)
self.completedAt = nil
}
}
@Model final class GoalLifecycleEvent {
@Attribute(.unique) var id: UUID
var goalID: UUID
var kindRawValue: String
var occurredAt: Date
var createdAt: Date
init() {
self.id = UUID()
self.goalID = UUID()
self.kindRawValue = ""
self.occurredAt = Date(timeIntervalSince1970:0)
self.createdAt = Date(timeIntervalSince1970:0)
}
}
@Model final class WeightRecord {
@Attribute(.unique) var id: UUID
var weightKilograms: Double
var recordedAt: Date
var createdAt: Date
var updatedAt: Date
init() {
self.id = UUID()
self.weightKilograms = 0
self.recordedAt = Date(timeIntervalSince1970:0)
self.createdAt = Date(timeIntervalSince1970:0)
self.updatedAt = Date(timeIntervalSince1970:0)
}
}
@Model final class WeeklyReview {
@Attribute(.unique) var id: UUID
@Attribute(.unique) var weekIdentifier: String
var periodStart: Date
var periodEnd: Date
var rememberedText: String?
var improvementText: String?
var nextStepText: String?
var focusText: String?
var isCompleted: Bool
var createdAt: Date
var updatedAt: Date
init() {
self.id = UUID()
self.weekIdentifier = ""
self.periodStart = Date(timeIntervalSince1970:0)
self.periodEnd = Date(timeIntervalSince1970:0)
self.rememberedText = nil
self.improvementText = nil
self.nextStepText = nil
self.focusText = nil
self.isCompleted = false
self.createdAt = Date(timeIntervalSince1970:0)
self.updatedAt = Date(timeIntervalSince1970:0)
}
}
@Model final class EntryPin {
@Attribute(.unique) var id: UUID
@Attribute(.unique) var entryID: UUID
var pinnedAt: Date
init() {
self.id = UUID()
self.entryID = UUID()
self.pinnedAt = Date(timeIntervalSince1970:0)
}
}
@Model final class EntryFollowUp {
@Attribute(.unique) var id: UUID
var entryID: UUID
var body: String
var createdAt: Date
var updatedAt: Date
init() {
self.id = UUID()
self.entryID = UUID()
self.body = ""
self.createdAt = Date(timeIntervalSince1970:0)
self.updatedAt = Date(timeIntervalSince1970:0)
}
}
@Model final class EntryExternalSource {
@Attribute(.unique) var entryID: UUID
var encodedSource: Data
init() {
self.entryID = UUID()
self.encodedSource = Data()
}
}
@Model final class CaptureImportReceipt {
@Attribute(.unique) var id: UUID
var importedAt: Date
init() {
self.id = UUID()
self.importedAt = Date(timeIntervalSince1970:0)
}
}
@Model final class TodoTask {
@Attribute(.unique) var id: UUID
var title: String
var notes: String
var stateRawValue: String
var isImportant: Bool
var plannedDay: String?
var deadlineDay: String?
var remindAt: Date?
var reminderTimeZoneID: String?
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
init() {
self.id = UUID()
self.title = ""
self.notes = ""
self.stateRawValue = ""
self.isImportant = false
self.plannedDay = nil
self.deadlineDay = nil
self.remindAt = nil
self.reminderTimeZoneID = nil
self.reminderLocalDay = nil
self.reminderMinutes = nil
self.completedAt = nil
self.canceledAt = nil
self.createdAt = Date(timeIntervalSince1970:0)
self.updatedAt = Date(timeIntervalSince1970:0)
self.listID = nil
self.seriesID = nil
self.occurrenceIndex = nil
self.occurrenceKey = nil
self.revision = 0
}
}
@Model final class TodoTaskEvent {
@Attribute(.unique) var id: UUID
var taskID: UUID
var sequence: Int
var kindRawValue: String
var occurredAt: Date
var createdAt: Date
var beforeValue: Data?
var afterValue: Data
init() {
self.id = UUID()
self.taskID = UUID()
self.sequence = 0
self.kindRawValue = ""
self.occurredAt = Date(timeIntervalSince1970:0)
self.createdAt = Date(timeIntervalSince1970:0)
self.beforeValue = nil
self.afterValue = Data()
}
}
@Model final class TodoList {
@Attribute(.unique) var id: UUID
var name: String
var createdAt: Date
var updatedAt: Date
init() {
self.id = UUID()
self.name = ""
self.createdAt = Date(timeIntervalSince1970:0)
self.updatedAt = Date(timeIntervalSince1970:0)
}
}
@Model final class TodoSeries {
@Attribute(.unique) var id: UUID
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
var createdAt: Date
var updatedAt: Date
init() {
self.id = UUID()
self.frequencyRawValue = ""
self.anchorDay = ""
self.plannedAnchorDay = nil
self.deadlineAnchorDay = nil
self.title = ""
self.notes = ""
self.isImportant = false
self.listID = nil
self.reminderMinutes = nil
self.reminderDayOffset = nil
self.isStopped = false
self.createdAt = Date(timeIntervalSince1970:0)
self.updatedAt = Date(timeIntervalSince1970:0)
}
}
@Model final class TodoTaskSource {
@Attribute(.unique) var id: UUID
@Attribute(.unique) var taskID: UUID
var entryID: UUID
init() {
self.id = UUID()
self.taskID = UUID()
self.entryID = UUID()
}
}
@Model final class ImportantDay {
@Attribute(.unique) var id: UUID
var title: String
var notes: String
var ruleData: Data
var preferencesData: Data
var isArchived: Bool
var createdAt: Date
var updatedAt: Date
var revision: Int
init() {
self.id = UUID()
self.title = ""
self.notes = ""
self.ruleData = Data()
self.preferencesData = Data()
self.isArchived = false
self.createdAt = Date(timeIntervalSince1970:0)
self.updatedAt = Date(timeIntervalSince1970:0)
self.revision = 0
}
}
@Model final class ImportantDayEntryLink {
@Attribute(.unique) var id: UUID
@Attribute(.unique) var pairKey: String
var dayID: UUID
var entryID: UUID
var occurrenceIdentifier: String?
var createdAt: Date
init() {
self.id = UUID()
self.pairKey = ""
self.dayID = UUID()
self.entryID = UUID()
self.occurrenceIdentifier = nil
self.createdAt = Date(timeIntervalSince1970:0)
}
}
@Model final class ImportantDayTodoLink {
@Attribute(.unique) var id: UUID
@Attribute(.unique) var pairKey: String
var dayID: UUID
var taskID: UUID
var occurrenceIdentifier: String?
var dayRevisionAtLink: Int
var createdAt: Date
init() {
self.id = UUID()
self.pairKey = ""
self.dayID = UUID()
self.taskID = UUID()
self.occurrenceIdentifier = nil
self.dayRevisionAtLink = 0
self.createdAt = Date(timeIntervalSince1970:0)
}
}
@Model final class ImportantDayCover {
@Attribute(.unique) var id: UUID
@Attribute(.unique) var dayID: UUID
var relativePath: String
var originalFilename: String
var contentType: String
var byteCount: Int64
var pixelWidth: Int
var pixelHeight: Int
var checksum: String
var createdAt: Date
init() {
self.id = UUID()
self.dayID = UUID()
self.relativePath = ""
self.originalFilename = ""
self.contentType = ""
self.byteCount = 0
self.pixelWidth = 0
self.pixelHeight = 0
self.checksum = ""
self.createdAt = Date(timeIntervalSince1970:0)
}
}
@Model final class SleepRecord {
@Attribute(.unique) var id: UUID
@Attribute(.unique) var wakeDay: String
var timeZoneID: String
var valueData: Data
var createdAt: Date
var updatedAt: Date
var revision: Int
var observedAt: Date
init() {
self.id = UUID()
self.wakeDay = ""
self.timeZoneID = ""
self.valueData = Data()
self.createdAt = Date(timeIntervalSince1970:0)
self.updatedAt = Date(timeIntervalSince1970:0)
self.revision = 0
self.observedAt = Date(timeIntervalSince1970:0)
}
}
@Model final class SleepGoalRule {
@Attribute(.unique) var id: UUID
@Attribute(.unique) var effectiveDay: String
var observedAt: Date
var observationTimeZoneID: String
var hasTakenEffect: Bool
var cutoffMinute: Int?
var createdAt: Date
init() {
self.id = UUID()
self.effectiveDay = ""
self.observedAt = Date(timeIntervalSince1970:0)
self.observationTimeZoneID = ""
self.hasTakenEffect = false
self.cutoffMinute = nil
self.createdAt = Date(timeIntervalSince1970:0)
}
}
@Model final class InvestmentParticipant {
@Attribute(.unique) var id: UUID
var name: String
var isDefault: Bool
var isArchived: Bool
var sortOrder: Int
init() {
self.id = UUID()
self.name = ""
self.isDefault = false
self.isArchived = false
self.sortOrder = 0
}
}
@Model final class InvestmentActivity {
@Attribute(.unique) var id: UUID
var participantID: UUID
var name: String
var isArchived: Bool
init() {
self.id = UUID()
self.participantID = UUID()
self.name = ""
self.isArchived = false
}
}
@Model final class InvestmentSession {
@Attribute(.unique) var id: UUID
var participantID: UUID
var activityID: UUID
var recorderID: UUID
var valueData: Data
var createdAt: Date
var updatedAt: Date
var revision: Int
init() {
self.id = UUID()
self.participantID = UUID()
self.activityID = UUID()
self.recorderID = UUID()
self.valueData = Data()
self.createdAt = Date(timeIntervalSince1970:0)
self.updatedAt = Date(timeIntervalSince1970:0)
self.revision = 0
}
}
@Model final class InvestmentOperation {
@Attribute(.unique) var id: UUID
var participantID: UUID
var activityID: UUID
var recorderID: UUID
var payload: Data
var revision: Int
var createdAt: Date
var updatedAt: Date
init() {
self.id = UUID()
self.participantID = UUID()
self.activityID = UUID()
self.recorderID = UUID()
self.payload = Data()
self.revision = 0
self.createdAt = Date(timeIntervalSince1970:0)
self.updatedAt = Date(timeIntervalSince1970:0)
}
}
@Model final class TodoSeriesPreferences {
@Attribute(.unique) var id: UUID
var weekdaysMask: Int?
var reminderChannelRawValue: String
init() {
self.id = UUID()
self.weekdaysMask = nil
self.reminderChannelRawValue = ""
}
}
@Model final class TodoReminderIntent {
@Attribute(.unique) var id: UUID
var generation: UUID
var revision: Int
var channelRawValue: String
var isInstanceOverride: Bool
init() {
self.id = UUID()
self.generation = UUID()
self.revision = 0
self.channelRawValue = ""
self.isInstanceOverride = false
}
}
@Model final class TodoReminderDeviceRecord {
@Attribute(.unique) var id: UUID
var taskID: UUID
var intentGeneration: UUID
var channelRawValue: String
var fireAt: Date
var phaseRawValue: String
var requestedTitle: String?
init() {
self.id = UUID()
self.taskID = UUID()
self.intentGeneration = UUID()
self.channelRawValue = ""
self.fireAt = Date(timeIntervalSince1970:0)
self.phaseRawValue = ""
self.requestedTitle = nil
}
}
@Model final class BodyReferenceSettings {
@Attribute(.unique) var id: UUID
var heightCentimeters: Double?
var referenceRawValue: String
init() {
self.id = UUID()
self.heightCentimeters = nil
self.referenceRawValue = ""
}
}
@Model final class NetWorthItem {
@Attribute(.unique) var id: UUID
var payload: Data
init() {
self.id = UUID()
self.payload = Data()
}
}
@Model final class NetWorthSnapshot {
@Attribute(.unique) var id: UUID
var payload: Data
init() {
self.id = UUID()
self.payload = Data()
}
}
let auditModelTypes: [any PersistentModel.Type] = [Entry.self, ImageMetadata.self, Tag.self, ObjectLink.self, Habit.self, HabitLog.self, HabitConfiguration.self, HabitLogDayMetadata.self, HabitPlanRevision.self, HabitLifecycleEvent.self, Goal.self, GoalLifecycleEvent.self, WeightRecord.self, WeeklyReview.self, EntryPin.self, EntryFollowUp.self, EntryExternalSource.self, CaptureImportReceipt.self, TodoTask.self, TodoTaskEvent.self, TodoList.self, TodoSeries.self, TodoTaskSource.self, ImportantDay.self, ImportantDayEntryLink.self, ImportantDayTodoLink.self, ImportantDayCover.self, SleepRecord.self, SleepGoalRule.self, InvestmentParticipant.self, InvestmentActivity.self, InvestmentSession.self, InvestmentOperation.self, TodoSeriesPreferences.self, TodoReminderIntent.self, TodoReminderDeviceRecord.self, BodyReferenceSettings.self, NetWorthItem.self, NetWorthSnapshot.self]