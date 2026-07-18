import XCTest
@testable import PersonalGrowthOS

final class EntryDomainTests: XCTestCase {
    func testEntryIdentityUsesAppOwnedUUID() {
        let uuid = UUID()

        XCTAssertEqual(EntryID(uuid).rawValue, uuid)
    }

    func testEntryKindsAndStatusesMatchFoundationModel() {
        XCTAssertEqual(EntryKind.allCases, [.quickNote, .review])
        XCTAssertEqual(EntryStatus.allCases, [.inbox, .organized, .archived])
    }

    func testEveryDistinctStatusTransitionIsReversible() {
        for source in EntryStatus.allCases {
            for destination in EntryStatus.allCases {
                XCTAssertEqual(source.canTransition(to: destination), source != destination)
            }
        }
    }

    func testTimestampsDistinguishCreationOccurrenceAndUpdate() throws {
        let createdAt = Date(timeIntervalSince1970: 2_000)
        let occurredAt = Date(timeIntervalSince1970: 1_000)
        let updatedAt = Date(timeIntervalSince1970: 3_000)
        var timestamps = EntryTimestamps(createdAt: createdAt, occurredAt: occurredAt)

        try timestamps.recordUpdate(at: updatedAt)

        XCTAssertEqual(timestamps.createdAt, createdAt)
        XCTAssertEqual(timestamps.occurredAt, occurredAt)
        XCTAssertEqual(timestamps.updatedAt, updatedAt)
    }

    func testTimestampDefaultsOccurrenceAndUpdateToCreation() {
        let date = Date(timeIntervalSince1970: 2_000)
        let timestamps = EntryTimestamps(createdAt: date)

        XCTAssertEqual(timestamps.occurredAt, date)
        XCTAssertEqual(timestamps.updatedAt, date)
    }

    func testUpdateCannotPredateCreation() {
        var timestamps = EntryTimestamps(createdAt: Date(timeIntervalSince1970: 2_000))

        XCTAssertThrowsError(try timestamps.recordUpdate(at: Date(timeIntervalSince1970: 1_999))) {
            XCTAssertEqual($0 as? EntryValidationError, .updateBeforeCreation)
        }
    }

    func testContentRequiresTextOrImage() {
        XCTAssertNoThrow(try EntryRules.validateContent(body: "A thought", imageCount: 0))
        XCTAssertNoThrow(try EntryRules.validateContent(body: nil, imageCount: 1))
        XCTAssertNoThrow(try EntryRules.validateContent(body: "A thought", imageCount: 9))

        XCTAssertThrowsError(try EntryRules.validateContent(body: " \n ", imageCount: 0)) {
            XCTAssertEqual($0 as? EntryValidationError, .emptyContent)
        }
    }

    func testContentEnforcesImageCountBounds() {
        XCTAssertThrowsError(try EntryRules.validateContent(body: "Text", imageCount: -1)) {
            XCTAssertEqual($0 as? EntryValidationError, .invalidImageCount)
        }
        XCTAssertThrowsError(try EntryRules.validateContent(body: nil, imageCount: 10)) {
            XCTAssertEqual($0 as? EntryValidationError, .tooManyImages(maximum: 9))
        }
    }

    func testReviewPeriodIsOptionalAndOrdered() throws {
        XCTAssertNoThrow(try ReviewPeriod())
        XCTAssertNoThrow(
            try ReviewPeriod(
                start: Date(timeIntervalSince1970: 1_000),
                end: Date(timeIntervalSince1970: 2_000)
            )
        )
        XCTAssertThrowsError(
            try ReviewPeriod(
                start: Date(timeIntervalSince1970: 2_000),
                end: Date(timeIntervalSince1970: 1_000)
            )
        ) {
            XCTAssertEqual($0 as? EntryValidationError, .reviewPeriodReversed)
        }
    }

    func testOnlyReviewEntriesAcceptAReviewPeriod() throws {
        let period = try ReviewPeriod(start: Date(timeIntervalSince1970: 1_000))

        XCTAssertNoThrow(try EntryRules.validatePeriod(period, for: .review))
        XCTAssertThrowsError(try EntryRules.validatePeriod(period, for: .quickNote)) {
            XCTAssertEqual($0 as? EntryValidationError, .reviewPeriodOnQuickNote)
        }
    }
}
