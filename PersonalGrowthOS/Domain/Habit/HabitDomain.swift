import Foundation

enum HabitStatus: String, Codable, CaseIterable, Sendable {
    case active
    case paused
    case completed
    case archived
}

enum HabitRecordingMode: String, Codable, CaseIterable, Sendable {
    case oncePerDay
    case multiplePerDay
}

enum HabitValidationError: Error, Equatable {
    case emptyName
    case invalidDailyTarget
}

enum HabitCheckInError: Error, Equatable {
    case inactiveHabit
    case missingHabit
    case alreadyCheckedInToday
    case recentlyCheckedIn
    case checkInIsNotLatest
}

enum HabitRules {
    static func validatedName(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HabitValidationError.emptyName }
        return trimmed
    }

    static func validatedDailyTarget(
        _ value: Int?,
        mode: HabitRecordingMode
    ) throws -> Int? {
        guard mode == .multiplePerDay else { return nil }
        guard let value else { throw HabitValidationError.invalidDailyTarget }
        guard value > 0 else { throw HabitValidationError.invalidDailyTarget }
        return value
    }
}

enum HabitCheckInPolicy {
    static let duplicatePreventionInterval: TimeInterval = 2.5
    static let undoPresentationInterval: TimeInterval = 6
}

struct HabitLogDraft {
    var occurredAt: Date
    var isCompleted: Bool
    var quantity: Double?
    var unit: String?
    var result: String?

    init(
        occurredAt: Date = Date(),
        isCompleted: Bool = true,
        quantity: Double? = nil,
        unit: String? = nil,
        result: String? = nil
    ) {
        self.occurredAt = occurredAt
        self.isCompleted = isCompleted
        self.quantity = quantity
        self.unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.result = result?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
