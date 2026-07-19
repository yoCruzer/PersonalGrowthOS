import Foundation

enum GoalKind: String, Codable, CaseIterable, Sendable {
    case standard
    case flag
}

enum GoalStatus: String, Codable, CaseIterable, Sendable {
    case active
    case paused
    case completed
    case abandoned
    case archived
}

enum GoalLifecycleEventKind: String, Codable, CaseIterable, Sendable {
    case created
    case paused
    case resumed
    case completed
    case abandoned
    case archived
    case reactivated
}

enum GoalValidationError: Error, Equatable {
    case emptyTitle
}

enum CoreLinkValidationError: Error, Equatable {
    case missingEndpoint
    case invalidReviewSource
    case reviewTargetsItself
}

enum GoalRules {
    static func validatedTitle(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GoalValidationError.emptyTitle }
        return trimmed
    }
}
