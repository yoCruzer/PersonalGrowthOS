import Foundation
import SwiftData
import XCTest
@testable import PersonalGrowthOS

@MainActor
final class TodoNotificationStub: TodoNotificationClient {
    var authorization: TodoNotificationPermission = .allowed
    var pending: [String: TodoReminderRequest] = [:]
    var otherIdentifiers: Set<String> = [LocalReminderScheduler.dailyIdentifier, LocalReminderScheduler.weeklyIdentifier]
    var permissionCalls = 0
    var shouldFail = false
    var shouldFailAuthorization = false
    var whileCheckingPermission: (() async -> Void)?
    var removed: [String] = []
    var whileAdding: (() throws -> Void)?
    func permission() async -> TodoNotificationPermission {
        if let operation = whileCheckingPermission { whileCheckingPermission = nil; await operation() }
        return authorization
    }
    func requestPermission() async throws -> Bool {
        permissionCalls += 1
        if shouldFailAuthorization { throw NSError(domain: "SyntheticAuthorization", code: 1) }
        authorization = .allowed; return true
    }
    func pendingIdentifiers() async -> Set<String> { Set(pending.keys).union(otherIdentifiers) }
    func remove(_ identifiers: [String]) { identifiers.forEach { pending.removeValue(forKey: $0) }; removed += identifiers }
    func add(_ request: TodoReminderRequest) async throws {
        enum Failure: Error { case scheduling }
        if shouldFail { throw Failure.scheduling }
        pending[request.id] = request
        if let operation = whileAdding { whileAdding = nil; try operation() }
        await Task.yield()
    }
}

@MainActor
final class TodoReminderTests: XCTestCase {
    func testCreateReplaceCompleteReopenCancelDeleteAndNoOtherCategoryRemoval() async throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let service = TodoTaskService(context: context)
        let client = TodoNotificationStub(), coordinator = TodoReminderCoordinator(client: client)
        let task = try service.create(TodoDraft(title: "预约", remindAt: Date().addingTimeInterval(3600)))
        await coordinator.reconcile(context: context)
        let identifier = TodoReminderCoordinator.identifier(task.id)
        XCTAssertEqual(coordinator.status(for: task), .scheduled)
        XCTAssertEqual(client.pending.count, 1)
        var draft = TodoDraft(task); draft.remindAt = Date().addingTimeInterval(7200)
        try service.edit(id: task.id, draft: draft)
        await coordinator.reconcile(context: context)
        XCTAssertEqual(client.pending.count, 1); XCTAssertEqual(client.pending[identifier]?.fireAt, draft.remindAt)
        try service.transition(id: task.id, to: .completed)
        await coordinator.reconcile(context: context)
        XCTAssertTrue(client.pending.isEmpty)
        try service.transition(id: task.id, to: .open)
        await coordinator.reconcile(context: context)
        XCTAssertEqual(client.pending.count, 1)
        try service.transition(id: task.id, to: .canceled)
        await coordinator.reconcile(context: context)
        XCTAssertTrue(client.pending.isEmpty)
        try service.transition(id: task.id, to: .open); try service.delete(id: task.id)
        await coordinator.reconcile(context: context)
        XCTAssertTrue(client.pending.isEmpty)
        XCTAssertFalse(client.removed.contains(LocalReminderScheduler.dailyIdentifier))
        XCTAssertFalse(client.removed.contains(LocalReminderScheduler.weeklyIdentifier))
    }
    func testAuthorizationIsOnlyRequestedFromExplicitReminderActionAndFailuresAreHonest() async throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let client = TodoNotificationStub(); client.authorization = .notDetermined
        let coordinator = TodoReminderCoordinator(client: client)
        let service = TodoTaskService(context: context)
        _ = try service.create(TodoDraft(title: "默认无提醒"))
        await coordinator.reconcile(context: context)
        XCTAssertEqual(client.permissionCalls, 0)
        let task = try service.create(TodoDraft(title: "需提醒", remindAt: Date().addingTimeInterval(3600)))
        await coordinator.reconcile(context: context)
        XCTAssertEqual(client.permissionCalls, 0); XCTAssertEqual(coordinator.status(for: task), .permissionRequired)
        await coordinator.reconcile(context: context, requestPermission: true)
        XCTAssertEqual(client.permissionCalls, 1); XCTAssertEqual(coordinator.status(for: task), .scheduled)
        client.authorization = .denied
        await coordinator.reconcile(context: context)
        XCTAssertEqual(coordinator.status(for: task), .denied); XCTAssertTrue(client.pending.isEmpty)
        client.authorization = .allowed; client.shouldFail = true
        await coordinator.reconcile(context: context)
        XCTAssertEqual(coordinator.status(for: task), .failed)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTask>()), 2)
    }
    func testStartupReconciliationDropsStaleRequestsAndHonorsConservativeQueueBudget() async throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let client = TodoNotificationStub()
        let stale = TodoReminderCoordinator.identifier(UUID())
        client.pending[stale] = TodoReminderRequest(id: stale, taskID: UUID(), title: "stale", fireAt: Date().addingTimeInterval(9999))
        client.otherIdentifiers = Set((0..<59).map { "other-\($0)" })
        let service = TodoTaskService(context: context)
        let first = try service.create(TodoDraft(title: "先", remindAt: Date().addingTimeInterval(3600)))
        let second = try service.create(TodoDraft(title: "后", remindAt: Date().addingTimeInterval(7200)))
        let past = try service.create(TodoDraft(title: "已过", remindAt: Date().addingTimeInterval(-3600)))
        let coordinator = TodoReminderCoordinator(client: client)
        await coordinator.reconcile(context: context)
        XCTAssertNil(client.pending[stale]); XCTAssertEqual(client.pending.count, 1)
        XCTAssertEqual(coordinator.status(for: first), .scheduled)
        XCTAssertEqual(coordinator.status(for: second), .queueFull)
        XCTAssertEqual(coordinator.status(for: past), .elapsed)
    }
    func testMutationDuringSchedulingIsReconciledBeforeReportingSuccess() async throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let service = TodoTaskService(context: context)
        let task = try service.create(TodoDraft(title: "竞争", remindAt: Date().addingTimeInterval(3600)))
        let client = TodoNotificationStub(), coordinator = TodoReminderCoordinator(client: client)
        client.whileAdding = {
            try service.transition(id: task.id, to: .completed)
            Task { await coordinator.reconcile(context: context) }
        }
        await coordinator.reconcile(context: context)
        await Task.yield()
        await coordinator.reconcile(context: context)
        XCTAssertTrue(client.pending.isEmpty); XCTAssertEqual(coordinator.status(for: task), .none)
    }

    func testExplicitPermissionSurvivesAConcurrentPassAndAuthorizationErrorIsVisible() async throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let task = try TodoTaskService(context: context).create(TodoDraft(title: "显式提醒", remindAt: Date().addingTimeInterval(3600)))
        let client = TodoNotificationStub(); client.authorization = .notDetermined
        let coordinator = TodoReminderCoordinator(client: client)
        client.whileCheckingPermission = { await coordinator.reconcile(context: context) }
        await coordinator.reconcile(context: context, requestPermission: true)
        XCTAssertEqual(client.permissionCalls, 1)
        XCTAssertEqual(coordinator.status(for: task), .scheduled)
        client.authorization = .notDetermined; client.shouldFailAuthorization = true
        await coordinator.reconcile(context: context, requestPermission: true)
        XCTAssertEqual(coordinator.status(for: task), .failed)
        XCTAssertTrue(client.pending.isEmpty)
    }
}
