import Foundation

enum HabitStatus: String, Codable, CaseIterable, Sendable {
    case active
    case paused
    case completed
    case archived
}

enum HabitValidationError: Error, Equatable {
    case emptyName
}

enum HabitCheckInError: Error, Equatable {
    case inactiveHabit
    case missingHabit
}

enum HabitRules {
    static func validatedName(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HabitValidationError.emptyName }
        return trimmed
    }
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
