import Foundation
import SwiftData
import XCTest
@testable import PersonalGrowthOS

@MainActor
final class GoalFoundationTests: XCTestCase {
    func testGoalKindsAndLifecycleMatchFoundation() throws {
        XCTAssertEqual(Set(GoalKind.allCases), Set([.standard, .flag]))
        XCTAssertEqual(Set(GoalStatus.allCases), Set([.active, .paused, .completed, .abandoned, .archived]))
        XCTAssertThrowsError(try GoalRules.validatedTitle("  ")) {
            XCTAssertEqual($0 as? GoalValidationError, .emptyTitle)
        }
    }

    func testV3StoreMigratesToV4WithoutChangingHabitIdentity() throws {
        let fixture = try GoalFixture()
        defer { fixture.remove() }
        let habitID = UUID()
        let entryID = UUID()
        let logID = UUID()
        do {
            let schema = Schema(versionedSchema: PersonalGrowthSchemaV3.self)
            let configuration = ModelConfiguration(
                "PersonalGrowthOSV1",
                schema: schema,
                url: fixture.storeURL,
                cloudKitDatabase: .none
            )
            let legacy = try ModelContainer(for: schema, configurations: [configuration])
            let entry = Entry(id: entryID, body: "Before S7", createdAt: Date())
            let habit = Habit(
                id: habitID,
                name: "Before S7",
                normalizedName: "before s7",
                createdAt: Date()
            )
            legacy.mainContext.insert(entry)
            legacy.mainContext.insert(habit)
            legacy.mainContext.insert(HabitLog(
                id: logID,
                habitID: habitID,
                occurredAt: Date(),
                isCompleted: true,
                linkedEntryID: entryID,
                createdAt: Date()
            ))
            legacy.mainContext.insert(ObjectLink(
                sourceType: .entry,
                sourceID: entryID,
                targetType: .habit,
                targetID: habitID,
                kind: .entryRelatesHabit,
                createdAt: Date()
            ))
            try legacy.mainContext.save()
        }

        do {
            let migrated = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
            XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<Habit>()).first?.id, habitID)
            XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<HabitLog>()).first?.id, logID)
            XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<ObjectLink>()).count, 1)
            XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<Goal>()).count, 0)
            XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<GoalLifecycleEvent>()).count, 0)
            XCTAssertNoThrow(try LinkIntegrityService.validate(context: migrated.mainContext))
        }

        let reopened = try PersistenceContainerFactory.makeOnDisk(at: fixture.storeURL)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<Habit>()).first?.id, habitID)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<HabitLog>()).first?.linkedEntryID, entryID)
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: reopened.mainContext))
    }

    func testCreateGoalAndFlagEachPublishOneCreatedEvent() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let service = GoalService(context: context, now: { Date(timeIntervalSince1970: 1_000) })

        let goal = try service.create(title: " Ship V1 ", kind: .standard)
        let flag = try service.create(title: "30 days", kind: .flag)

        XCTAssertEqual(goal.title, "Ship V1")
        XCTAssertEqual(flag.kind, .flag)
        let events = try context.fetch(FetchDescriptor<GoalLifecycleEvent>())
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.allSatisfy { $0.kind == .created })
        XCTAssertEqual(Set(events.map(\.goalID)), Set([goal.id, flag.id]))
    }

    func testLifecyclePublishesBoundedEventsAndCompletionBoundary() throws {
        var timestamp = Date(timeIntervalSince1970: 2_000)
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let service = GoalService(context: context, now: {
            defer { timestamp.addTimeInterval(1) }
            return timestamp
        })
        let goal = try service.create(title: "Lifecycle", kind: .standard)

        try service.transition(goal, to: .paused)
        try service.transition(goal, to: .active)
        try service.transition(goal, to: .completed)
        XCTAssertNotNil(goal.completedAt)
        try service.transition(goal, to: .abandoned)
        XCTAssertNil(goal.completedAt)
        try service.transition(goal, to: .archived)
        try service.transition(goal, to: .active)

        XCTAssertEqual(goal.status, .active)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<GoalLifecycleEvent>(sortBy: [
                SortDescriptor(\GoalLifecycleEvent.occurredAt, order: .forward)
            ])).map(\.kind),
            [.created, .paused, .resumed, .completed, .abandoned, .archived, .reactivated]
        )
    }

    func testFailedLifecycleTransitionRollsBackGoalAndEvent() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let goal = try GoalService(context: context).create(title: "Keep", kind: .standard)
        let originalUpdatedAt = goal.updatedAt
        let failing = GoalService(
            context: context,
            now: { originalUpdatedAt.addingTimeInterval(100) },
            save: { throw InjectedGoalFailure.save }
        )

        XCTAssertThrowsError(try failing.transition(goal, to: .completed))

        XCTAssertEqual(goal.status, .active)
        XCTAssertNil(goal.completedAt)
        XCTAssertEqual(goal.updatedAt, originalUpdatedAt)
        XCTAssertEqual(try context.fetch(FetchDescriptor<GoalLifecycleEvent>()).count, 1)
    }

    func testCoreLinksUseApprovedDirectionsAndPreventDuplicates() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let entry = Entry(body: "Related", createdAt: Date())
        context.insert(entry)
        let habit = try HabitService(context: context).create(name: "Read")
        let goal = try GoalService(context: context).create(title: "Learn", kind: .standard)
        let service = CoreLinkService(context: context)

        try service.setEntry(entry, relatesTo: habit, linked: true)
        try service.setEntry(entry, relatesTo: habit, linked: true)
        try service.setEntry(entry, relatesTo: goal, linked: true)
        try service.setHabit(habit, supports: goal, linked: true)

        let links = try context.fetch(FetchDescriptor<ObjectLink>())
        XCTAssertEqual(links.count, 3)
        XCTAssertEqual(Set(links.map(\.kind)), Set([.entryRelatesHabit, .entryRelatesGoal, .habitSupportsGoal]))
        let support = try XCTUnwrap(links.first { $0.kind == .habitSupportsGoal })
        XCTAssertEqual(support.sourceType, .habit)
        XCTAssertEqual(support.sourceID, habit.id)
        XCTAssertEqual(support.targetType, .goal)
        XCTAssertEqual(support.targetID, goal.id)
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: context))
    }

    func testIntegrityRejectsInvalidLinkDirectionAndDanglingEvent() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let habit = try HabitService(context: context).create(name: "Direction")
        let goal = try GoalService(context: context).create(title: "Direction", kind: .standard)
        context.insert(ObjectLink(
            sourceType: .goal,
            sourceID: goal.id,
            targetType: .habit,
            targetID: habit.id,
            kind: .habitSupportsGoal,
            createdAt: Date()
        ))
        try context.save()

        XCTAssertThrowsError(try LinkIntegrityService.validate(context: context)) {
            guard case LinkIntegrityError.danglingLinks(let ids) = $0 else {
                return XCTFail("Expected invalid Link error, got \($0)")
            }
            XCTAssertEqual(ids.count, 1)
        }

        context.rollback()
        try context.fetch(FetchDescriptor<ObjectLink>()).forEach(context.delete)
        context.insert(GoalLifecycleEvent(
            goalID: UUID(),
            kind: .created,
            occurredAt: Date(),
            createdAt: Date()
        ))
        try context.save()
        XCTAssertThrowsError(try LinkIntegrityService.validate(context: context)) {
            guard case LinkIntegrityError.danglingGoalEvents(let ids) = $0 else {
                return XCTFail("Expected dangling Goal event error, got \($0)")
            }
            XCTAssertEqual(ids.count, 1)
        }
    }

    func testCoreLinkServiceRejectsMissingEndpointBeforePublishing() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let entry = Entry(body: "Not inserted", createdAt: Date())
        let goal = try GoalService(context: context).create(title: "Exists", kind: .standard)

        XCTAssertThrowsError(try CoreLinkService(context: context).setEntry(
            entry, relatesTo: goal, linked: true
        )) {
            XCTAssertEqual($0 as? CoreLinkValidationError, .missingEndpoint)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<ObjectLink>()).count, 0)
    }

    func testGoalDeleteCleansEventsAndLinksButPreservesEntryAndHabit() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let entry = Entry(body: "Preserve", createdAt: Date())
        context.insert(entry)
        let habit = try HabitService(context: context).create(name: "Preserve")
        let goal = try GoalService(context: context).create(title: "Delete", kind: .flag)
        try CoreLinkService(context: context).setEntry(entry, relatesTo: goal, linked: true)
        try CoreLinkService(context: context).setHabit(habit, supports: goal, linked: true)

        try GoalService(context: context).permanentlyDelete(goal)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Goal>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<GoalLifecycleEvent>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ObjectLink>()).count, 0)
        XCTAssertNotNil(try EntryRepository(context: context).fetch(id: entry.id))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Habit>()).first?.id, habit.id)
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: context))
    }

    func testFailedGoalDeleteRollsBackGoalEventsAndLinks() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let habit = try HabitService(context: context).create(name: "Rollback")
        let goal = try GoalService(context: context).create(title: "Rollback", kind: .standard)
        try CoreLinkService(context: context).setHabit(habit, supports: goal, linked: true)
        let failing = GoalService(context: context, save: { throw InjectedGoalFailure.save })

        XCTAssertThrowsError(try failing.permanentlyDelete(goal))

        XCTAssertEqual(try context.fetch(FetchDescriptor<Goal>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<GoalLifecycleEvent>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ObjectLink>()).count, 1)
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: context))
    }

    func testGoalAndFlagUseGlobalNormalizedSearch() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        let goal = try GoalService(context: context).create(title: "Ｓｈｉｐ V1", kind: .standard)
        let flag = try GoalService(context: context).create(title: "连续记录三十天", kind: .flag)

        XCTAssertEqual(try LocalSearchService(context: context).search("ship").goals.map(\.id), [goal.id])
        XCTAssertEqual(try LocalSearchService(context: context).search("三十天").goals.map(\.id), [flag.id])
    }
}

private enum InjectedGoalFailure: Error {
    case save
}

private struct GoalFixture {
    let root: URL
    let storeURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PGOS-S7-\(UUID().uuidString)", isDirectory: true)
        storeURL = root.appendingPathComponent("store.sqlite")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
