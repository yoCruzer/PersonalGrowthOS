import Foundation

struct EntryID: Hashable, Codable, Sendable {
    let rawValue: UUID

    init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

enum EntryKind: String, Codable, CaseIterable, Sendable {
    case quickNote
    case review
}

enum EntryStatus: String, Codable, CaseIterable, Sendable {
    case inbox
    case organized
    case archived

    func canTransition(to destination: EntryStatus) -> Bool {
        destination != self
    }
}

struct EntryTimestamps: Equatable, Sendable {
    let createdAt: Date
    var occurredAt: Date
    private(set) var updatedAt: Date

    init(createdAt: Date, occurredAt: Date? = nil) {
        self.createdAt = createdAt
        self.occurredAt = occurredAt ?? createdAt
        updatedAt = createdAt
    }

    mutating func recordUpdate(at date: Date) throws {
        guard date >= createdAt else {
            throw EntryValidationError.updateBeforeCreation
        }
        updatedAt = date
    }
}

struct ReviewPeriod: Equatable, Sendable {
    let start: Date?
    let end: Date?

    init(start: Date? = nil, end: Date? = nil) throws {
        if let start, let end, end < start {
            throw EntryValidationError.reviewPeriodReversed
        }
        self.start = start
        self.end = end
    }
}

enum EntryValidationError: Error, Equatable {
    case emptyContent
    case invalidImageCount
    case tooManyImages(maximum: Int)
    case reviewPeriodOnQuickNote
    case updateBeforeCreation
    case reviewPeriodReversed
}

enum EntryRules {
    static let maximumImageCount = 9

    static func validateContent(body: String?, imageCount: Int) throws {
        guard imageCount >= 0 else {
            throw EntryValidationError.invalidImageCount
        }
        guard imageCount <= maximumImageCount else {
            throw EntryValidationError.tooManyImages(maximum: maximumImageCount)
        }

        let hasText = body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        guard hasText || imageCount > 0 else {
            throw EntryValidationError.emptyContent
        }
    }

    static func validatePeriod(_ period: ReviewPeriod?, for kind: EntryKind) throws {
        if kind == .quickNote, period != nil {
            throw EntryValidationError.reviewPeriodOnQuickNote
        }
    }
}
