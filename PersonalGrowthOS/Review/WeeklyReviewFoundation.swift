import Foundation
import SwiftData

enum WeeklyReviewError: Error, Equatable {
    case unavailableWeek
    case missingReview
}

struct WeeklyReviewPeriod: Equatable, Sendable {
    let identifier: String
    let start: Date
    let end: Date
    let endExclusive: Date

    init(containing date: Date, calendar: Calendar = .current) throws {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date),
              let end = calendar.date(byAdding: .day, value: -1, to: interval.end) else {
            throw WeeklyReviewError.unavailableWeek
        }
        let components = calendar.dateComponents(
            [.yearForWeekOfYear, .weekOfYear],
            from: date
        )
        guard let year = components.yearForWeekOfYear,
              let week = components.weekOfYear else {
            throw WeeklyReviewError.unavailableWeek
        }
        identifier = String(format: "%04d-W%02d", year, week)
        start = interval.start
        self.end = end
        endExclusive = interval.end
    }

    func contains(_ date: Date) -> Bool {
        date >= start && date < endExclusive
    }
}

@Model
final class WeeklyReview {
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

    init(
        id: UUID = UUID(),
        weekIdentifier: String,
        periodStart: Date,
        periodEnd: Date,
        rememberedText: String? = nil,
        improvementText: String? = nil,
        nextStepText: String? = nil,
        focusText: String? = nil,
        isCompleted: Bool = false,
        createdAt: Date,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.weekIdentifier = weekIdentifier
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.rememberedText = rememberedText
        self.improvementText = improvementText
        self.nextStepText = nextStepText
        self.focusText = focusText
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

struct WeeklyReviewDraft: Equatable {
    var rememberedText: String
    var improvementText: String
    var nextStepText: String
    var focusText: String
    var isCompleted: Bool
}

enum WeeklyReviewRules {
    static func optionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
final class WeeklyReviewService {
    private let context: ModelContext
    private let calendar: Calendar
    private let now: () -> Date
    private let save: () throws -> Void

    init(
        context: ModelContext,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        save: (() throws -> Void)? = nil
    ) {
        self.context = context
        self.calendar = calendar
        self.now = now
        self.save = save ?? { try context.save() }
    }

    func review(containing date: Date, createIfNeeded: Bool = true) throws -> WeeklyReview? {
        let period = try WeeklyReviewPeriod(containing: date, calendar: calendar)
        if let existing = try fetchReview(identifier: period.identifier) {
            return existing
        }
        guard createIfNeeded else { return nil }
        let timestamp = now()
        let review = WeeklyReview(
            weekIdentifier: period.identifier,
            periodStart: period.start,
            periodEnd: period.end,
            createdAt: timestamp
        )
        context.insert(review)
        do {
            try save()
            return review
        } catch {
            context.rollback()
            throw error
        }
    }

    func update(_ review: WeeklyReview, draft: WeeklyReviewDraft) throws {
        guard let persisted = try fetchReview(id: review.id) else {
            throw WeeklyReviewError.missingReview
        }
        persisted.rememberedText = WeeklyReviewRules.optionalText(draft.rememberedText)
        persisted.improvementText = WeeklyReviewRules.optionalText(draft.improvementText)
        persisted.nextStepText = WeeklyReviewRules.optionalText(draft.nextStepText)
        persisted.focusText = WeeklyReviewRules.optionalText(draft.focusText)
        persisted.isCompleted = draft.isCompleted
        persisted.updatedAt = now()
        do {
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func history() throws -> [WeeklyReview] {
        try context.fetch(FetchDescriptor<WeeklyReview>(sortBy: [
            SortDescriptor(\WeeklyReview.periodStart, order: .reverse),
            SortDescriptor(\WeeklyReview.createdAt, order: .reverse),
            SortDescriptor(\WeeklyReview.id, order: .forward)
        ]))
    }

    private func fetchReview(identifier: String) throws -> WeeklyReview? {
        var descriptor = FetchDescriptor<WeeklyReview>(
            predicate: #Predicate { $0.weekIdentifier == identifier }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchReview(id: UUID) throws -> WeeklyReview? {
        var descriptor = FetchDescriptor<WeeklyReview>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

struct WeeklyHabitHighlight: Equatable {
    let habitID: UUID
    let habitName: String
    let checkInCount: Int
    let activeDayCount: Int
}

struct WeeklyWeightSummary: Equatable {
    let firstKilograms: Double
    let latestKilograms: Double
    let changeKilograms: Double?
}

struct WeeklyRecentEntry: Equatable, Identifiable {
    let id: UUID
    let title: String?
    let body: String?
    let occurredAt: Date
    let imageCount: Int
}

struct WeeklySummary: Equatable {
    let entryCount: Int?
    let entryDayCount: Int?
    let imageEntryCount: Int?
    let habitCheckInCount: Int?
    let habitHighlight: WeeklyHabitHighlight?
    let weight: WeeklyWeightSummary?
    let topTags: [String]
    let recentEntries: [WeeklyRecentEntry]

    var hasActivity: Bool {
        entryCount != nil || habitCheckInCount != nil || weight != nil
    }
}

@MainActor
enum WeeklySummaryService {
    static func make(
        period: WeeklyReviewPeriod,
        entries: [Entry],
        habits: [Habit],
        habitLogs: [HabitLog],
        weightRecords: [WeightRecord],
        tags: [Tag] = [],
        links: [ObjectLink] = [],
        calendar: Calendar = .current
    ) -> WeeklySummary {
        let weeklyEntries = entries.filter {
            $0.kind == .quickNote && period.contains($0.occurredAt)
        }
        let weeklyLogs = habitLogs.filter {
            $0.isCompleted && period.contains($0.occurredAt)
        }
        let weeklyWeights = weightRecords.filter { period.contains($0.recordedAt) }

        return WeeklySummary(
            entryCount: weeklyEntries.isEmpty ? nil : weeklyEntries.count,
            entryDayCount: weeklyEntries.isEmpty
                ? nil
                : Set(weeklyEntries.map { calendar.startOfDay(for: $0.occurredAt) }).count,
            imageEntryCount: optionalPositive(weeklyEntries.filter { !$0.images.isEmpty }.count),
            habitCheckInCount: optionalPositive(weeklyLogs.count),
            habitHighlight: habitHighlight(
                logs: weeklyLogs,
                habits: habits,
                calendar: calendar
            ),
            weight: weightSummary(records: weeklyWeights),
            topTags: topTags(entries: weeklyEntries, tags: tags, links: links),
            recentEntries: weeklyEntries
                .sorted {
                    if $0.occurredAt != $1.occurredAt { return $0.occurredAt > $1.occurredAt }
                    return $0.id.uuidString < $1.id.uuidString
                }
                .prefix(3)
                .map {
                    WeeklyRecentEntry(
                        id: $0.id,
                        title: $0.title,
                        body: $0.body,
                        occurredAt: $0.occurredAt,
                        imageCount: $0.images.count
                    )
                }
        )
    }

    private static func optionalPositive(_ value: Int) -> Int? {
        value > 0 ? value : nil
    }

    private static func habitHighlight(
        logs: [HabitLog],
        habits: [Habit],
        calendar: Calendar
    ) -> WeeklyHabitHighlight? {
        let names = Dictionary(
            habits.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        return Dictionary(grouping: logs, by: \.habitID)
            .compactMap { habitID, logs -> WeeklyHabitHighlight? in
                guard let name = names[habitID] else { return nil }
                return WeeklyHabitHighlight(
                    habitID: habitID,
                    habitName: name,
                    checkInCount: logs.count,
                    activeDayCount: Set(logs.map { calendar.startOfDay(for: $0.occurredAt) }).count
                )
            }
            .sorted {
                if $0.activeDayCount != $1.activeDayCount {
                    return $0.activeDayCount > $1.activeDayCount
                }
                if $0.checkInCount != $1.checkInCount {
                    return $0.checkInCount > $1.checkInCount
                }
                return $0.habitName < $1.habitName
            }
            .first
    }

    private static func weightSummary(records: [WeightRecord]) -> WeeklyWeightSummary? {
        let ordered = WeightRecordOrdering.oldestFirst(records)
        guard let first = ordered.first, let latest = ordered.last else { return nil }
        return WeeklyWeightSummary(
            firstKilograms: first.weightKilograms,
            latestKilograms: latest.weightKilograms,
            changeKilograms: ordered.count >= 2
                ? latest.weightKilograms - first.weightKilograms
                : nil
        )
    }

    private static func topTags(
        entries: [Entry],
        tags: [Tag],
        links: [ObjectLink]
    ) -> [String] {
        let entryIDs = Set(entries.map(\.id))
        let tagNames = Dictionary(
            tags.map { ($0.id, $0.displayName) },
            uniquingKeysWith: { first, _ in first }
        )
        let counts = Dictionary(grouping: links.filter {
            $0.kind == .entryUsesTag
                && entryIDs.contains($0.sourceID)
                && tagNames[$0.targetID] != nil
        }, by: \.targetID).mapValues(\.count)
        return counts
            .compactMap { tagID, count in tagNames[tagID].map { ($0, count) } }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0 < $1.0
            }
            .prefix(3)
            .map(\.0)
    }
}

extension WeeklyReview: Identifiable {}
