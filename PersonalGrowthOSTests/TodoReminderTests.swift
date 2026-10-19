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
    var failedRemovalIdentifiers: Set<String> = []
    var addCalls: [TodoReminderRequest] = []
    var whileAdding: (() throws -> Void)?
    var afterAdding: ((TodoReminderRequest) async throws -> Void)?
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
    func remove(_ identifiers: [String]) { identifiers.filter {!failedRemovalIdentifiers.contains($0)}.forEach { pending.removeValue(forKey: $0) }; removed += identifiers }
    func add(_ request: TodoReminderRequest) async throws {
        enum Failure: Error { case scheduling }
        addCalls.append(request)
        if shouldFail { throw Failure.scheduling }
        pending[request.id] = request
        if let operation = whileAdding { whileAdding = nil; try operation() }
        try await afterAdding?(request)
        await Task.yield()
    }
}

@MainActor
final class TodoReminderTests: XCTestCase {
    func testReminderStatusReevaluatesElapsedTimeWithoutReconciliationOrQueueMutation() async throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        var now = Date()
        let client = TodoNotificationStub(), coordinator = TodoReminderCoordinator(client: client, now: { now }, sleepPreferences:{.init()})
        let task = try TodoTaskService(context: container.mainContext).create(.init(title: "Parked screen", remindAt: now.addingTimeInterval(60)))
        await coordinator.reconcile(context: container.mainContext)
        XCTAssertEqual(coordinator.status(for: task), .scheduled)
        let pending = client.pending
        now.addTimeInterval(61)
        XCTAssertEqual(coordinator.status(for: task), .elapsed)
        XCTAssertEqual(client.pending, pending)
        try TodoTaskService(context: container.mainContext).transition(id: task.id, to: .completed)
        XCTAssertEqual(coordinator.status(for: task), .cancellationPending)
        await coordinator.reconcile(context:container.mainContext)
        XCTAssertEqual(coordinator.status(for: task), .none)
    }

    func testCreateReplaceCompleteReopenCancelDeleteAndNoOtherCategoryRemoval() async throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let service = TodoTaskService(context: context)
        let client = TodoNotificationStub(), coordinator = TodoReminderCoordinator(client: client, sleepPreferences:{.init()})
        let task = try service.create(TodoDraft(title: "预约", remindAt: Date().addingTimeInterval(3600)))
        await coordinator.reconcile(context: context)
        let originalIdentifier=try XCTUnwrap(client.pending.keys.first)
        XCTAssertEqual(coordinator.status(for: task), .scheduled)
        XCTAssertEqual(client.pending.count, 1)
        var draft = TodoDraft(task); draft.remindAt = Date().addingTimeInterval(7200)
        try service.edit(id: task.id, draft: draft)
        await coordinator.reconcile(context: context)
        XCTAssertEqual(client.pending.count, 1)
        XCTAssertNil(client.pending[originalIdentifier])
        XCTAssertEqual(client.pending.values.first?.taskID,task.id);XCTAssertEqual(client.pending.values.first?.fireAt,draft.remindAt)
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
        let coordinator = TodoReminderCoordinator(client: client, sleepPreferences:{.init()})
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
        try service.rescheduleReminder(id:task.id,to:Date().addingTimeInterval(3600))
        await coordinator.reconcile(context: context)
        XCTAssertEqual(coordinator.status(for: task), .confirmationRequired)
        XCTAssertFalse(client.addCalls.isEmpty);XCTAssertTrue(client.pending.isEmpty)
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
        let coordinator = TodoReminderCoordinator(client: client, sleepPreferences:{.init()})
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
        let client = TodoNotificationStub(), coordinator = TodoReminderCoordinator(client: client, sleepPreferences:{.init()})
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
        let coordinator = TodoReminderCoordinator(client: client, sleepPreferences:{.init()})
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

@MainActor
extension TodoReminderTests {
    func testSaveFeedbackRemainsCheckingWhileDelayedAndDistinguishesPermissionQueueAndFailure() async throws {
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let client = TodoNotificationStub(), coordinator = TodoReminderCoordinator(client: client, sleepPreferences:{.init()})
        let task = try TodoTaskService(context: context).create(TodoDraft(title: "Saved first", remindAt: Date().addingTimeInterval(3600)))
        coordinator.reportSavedTask(task)
        XCTAssertEqual(coordinator.savedTaskID, task.id); XCTAssertEqual(coordinator.status(for: task), .checking)
        client.whileCheckingPermission = {
            XCTAssertEqual(coordinator.status(for: task), .checking)
            XCTAssertEqual(try? context.fetchCount(FetchDescriptor<TodoTask>()), 1)
            await Task.yield()
        }
        await coordinator.reconcile(context: context)
        XCTAssertEqual(coordinator.status(for: task), .scheduled)
        for state in [TodoNotificationPermission.notDetermined, .denied, .allowed] {
            client.authorization = state; client.shouldFail = state == .allowed
            if state == .allowed {try TodoTaskService(context:context).rescheduleReminder(id:task.id,to:Date().addingTimeInterval(3600))}
            await coordinator.reconcile(context: context)
            XCTAssertEqual(coordinator.status(for: task), state == .notDetermined ? .permissionRequired : state == .denied ? .denied : .confirmationRequired)
            XCTAssertEqual(coordinator.savedTaskID, task.id); XCTAssertEqual(client.permissionCalls, 0)
        }
        client.shouldFail = false; client.otherIdentifiers = Set((0..<60).map { "other-\($0)" })
        try TodoTaskService(context:context).rescheduleReminder(id:task.id,to:Date().addingTimeInterval(3600))
        await coordinator.reconcile(context: context)
        XCTAssertEqual(coordinator.status(for: task), .queueFull)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTask>()), 1)
        XCTAssertTrue(client.removed.allSatisfy { $0.hasPrefix(TodoReminderCoordinator.prefix) })
    }
}

@MainActor
extension TodoReminderTests {
    func testFutureTemplateReplacesMaterializedSuccessorRequestAfterSavedMutation() async throws {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let clock = TodoDay("2026-01-10")!.date(timeZone: zone)!.addingTimeInterval(12 * 3600)
        let container = try PersistenceContainerFactory.makeInMemory(), context = container.mainContext
        let service = TodoTaskService(context: context, now: { clock }, timeZone: { zone })
        let first = try service.create(TodoDraft(title: "Before", plannedDay: "2026-01-10", remindAt: TodoRecurrence.reminder(day: TodoDay("2026-01-09")!, minutes: 1200, timeZone: zone), frequency: .monthly))
        try service.transition(id: first.id, to: .completed)
        let next = try XCTUnwrap(context.fetch(FetchDescriptor<TodoTask>()).first { $0.state == .open })
        let client = TodoNotificationStub(), coordinator = TodoReminderCoordinator(client: client, now: { clock }, sleepPreferences:{.init()})
        await coordinator.reconcile(context: context)
        let identifier=try XCTUnwrap(client.pending.keys.first)
        XCTAssertEqual(client.pending.values.first?.taskID,next.id)
        XCTAssertEqual(client.pending[identifier]?.fireAt, TodoRecurrence.reminder(day: TodoDay("2026-02-09")!, minutes: 1200, timeZone: zone))
        var draft = TodoDraft(first); draft.title = "After"; draft.remindAt = TodoRecurrence.reminder(day: TodoDay("2026-01-08")!, minutes: 600, timeZone: zone)
        try service.edit(id: first.id, draft: draft, futureSeries: true)
        coordinator.reportSavedTask(first, affectedOpenSuccessor: next)
        XCTAssertEqual(coordinator.savedTaskID, next.id)
        await coordinator.reconcile(context: context)
        XCTAssertEqual(client.pending.count,1);XCTAssertNil(client.pending[identifier])
        XCTAssertEqual(client.pending.values.first?.taskID,next.id);XCTAssertEqual(client.pending.values.first?.title,"After")
        XCTAssertEqual(client.pending.values.first?.fireAt, TodoRecurrence.reminder(day: TodoDay("2026-02-08")!, minutes: 600, timeZone: zone))
        XCTAssertEqual(coordinator.status(for: next), .scheduled)
        XCTAssertTrue(client.removed.allSatisfy { $0.hasPrefix(TodoReminderCoordinator.prefix) })
        try service.transition(id: next.id, to: .canceled)
        coordinator.reportSavedTask(first, affectedOpenSuccessor: next)
        XCTAssertNil(coordinator.savedTaskID)
    }
}

@MainActor final class TodoAlarmStub: TodoAlarmClient {
    var authorization: TodoAlarmPermission = .allowed
    var permissionResponse: TodoAlarmPermission = .allowed
    var pending: [UUID:TodoAlarmRequest] = [:]
    var scheduleCalls: [TodoAlarmRequest] = []
    var cancelCalls: [UUID] = []
    var stopCalls: [UUID] = []
    var permissionCalls=0
    var errorBeforeSchedule: Error?
    var errorAfterSchedule: Error?
    var failCancel=false
    var failReads=false
    var whileReading: (() async throws -> Void)?
    var whileScheduling: ((TodoAlarmRequest) async throws -> Void)?
    var whileAuthorizing: (() async -> Void)?
    var changed: (@MainActor () -> Void)?
    func permission() async -> TodoAlarmPermission {authorization}
    func requestPermission() async throws -> TodoAlarmPermission {
        permissionCalls += 1
        if let action=whileAuthorizing {whileAuthorizing=nil;await action()}
        authorization=permissionResponse;return authorization
    }
    func pendingIdentifiers() async throws -> Set<UUID> {
        if let action=whileReading {whileReading=nil;try await action()}
        if failReads {throw CocoaError(.fileReadUnknown)}
        return Set(pending.keys)
    }
    func schedule(_ request: TodoAlarmRequest) async throws {
        scheduleCalls.append(request)
        if let errorBeforeSchedule {throw errorBeforeSchedule}
        pending[request.id]=request
        if let action=whileScheduling {whileScheduling=nil;try await action(request)}
        if let errorAfterSchedule {throw errorAfterSchedule}
    }
    func cancel(_ id: UUID) async throws {
        cancelCalls.append(id)
        if failCancel {throw CocoaError(.fileWriteUnknown)}
        pending.removeValue(forKey:id)
    }
    func stop(_ id: UUID) async throws {stopCalls.append(id);pending.removeValue(forKey:id)}
    func observeChanges(_ action: @escaping @MainActor () -> Void) -> [Task<Void,Never>] {changed=action;return []}
}

extension TodoReminderTests {
    func testUsageAlarmPermissionIsExplicitNoFallbackAndUnsupportedOrDeniedPreservesFact() async throws {
        for permission: TodoAlarmPermission in [.notDetermined,.denied,.unsupported] {
            let container=try PersistenceContainerFactory.makeInMemory(),context=container.mainContext,now=Date()
            let notifications=TodoNotificationStub(),alarms=TodoAlarmStub();alarms.authorization=permission
            let service=TodoTaskService(context:context,now:{now})
            let task=try service.create(.init(title:"Synthetic alarm permission",isImportant:true,remindAt:now.addingTimeInterval(600),reminderChannel:.alarm))
            let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
            await coordinator.reconcile(context:context,requestPermission:true)
            XCTAssertEqual(coordinator.status(for:task),permission == .notDetermined ? .alarmPermissionRequired : permission == .denied ? .alarmDenied : .unsupportedAlarm)
            XCTAssertEqual(alarms.permissionCalls,0);XCTAssertTrue(alarms.pending.isEmpty);XCTAssertTrue(notifications.pending.isEmpty)
            XCTAssertTrue(try service.task(id:task.id).isImportant)
            if permission == .notDetermined {
                await coordinator.reconcile(context:context,requestAlarmPermission:true)
                XCTAssertEqual(alarms.permissionCalls,1);XCTAssertEqual(coordinator.status(for:task),.scheduled)
                XCTAssertEqual(alarms.pending.count,1);XCTAssertTrue(notifications.pending.isEmpty)
            } else {
                await coordinator.reconcile(context:context,requestAlarmPermission:true)
                XCTAssertEqual(alarms.permissionCalls,0)
            }
        }
    }
    func testUsageAlarmNativeAcceptanceLocalConfirmationFailureColdRetryDoesNotAddTwice() async throws {
        let container=try PersistenceContainerFactory.makeInMemory(),context=container.mainContext,now=Date()
        let notifications=TodoNotificationStub(),alarms=TodoAlarmStub()
        let task=try TodoTaskService(context:context,now:{now}).create(.init(title:"Synthetic journal recovery",remindAt:now.addingTimeInterval(600),reminderChannel:.alarm))
        var fail=true
        let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms,journalCommit:{write in
            if fail,try write.fetch(FetchDescriptor<TodoReminderDeviceRecord>()).contains(where: {$0.phaseRawValue == "accepted"}) {throw CocoaError(.fileWriteOutOfSpace)}
            try write.save()
        })
        await coordinator.reconcile(context:context)
        XCTAssertEqual(coordinator.status(for:task),.confirmationRequired)
        XCTAssertEqual(alarms.pending.count,1);XCTAssertEqual(alarms.scheduleCalls.count,1)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first?.phaseRawValue,"prepared")
        fail=false
        let cold=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
        await cold.reconcile(context:context)
        XCTAssertEqual(cold.status(for:task),.scheduled);XCTAssertEqual(alarms.scheduleCalls.count,1)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first?.phaseRawValue,"accepted")
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<TodoTaskEvent>()),1)
    }
    func testUsageCancellationFailureBlocksBothChannelReplacementsUntilVerifiedAbsent() async throws {
        let container=try PersistenceContainerFactory.makeInMemory(),context=container.mainContext,now=Date()
        let notifications=TodoNotificationStub(),alarms=TodoAlarmStub(),service=TodoTaskService(context:context,now:{now})
        let task=try service.create(.init(title:"Synthetic channel switch",remindAt:now.addingTimeInterval(600),reminderChannel:.alarm))
        let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
        await coordinator.reconcile(context:context)
        let old=try XCTUnwrap(alarms.pending.keys.first)
        alarms.failCancel=true
        try service.rescheduleReminder(id:task.id,to:now.addingTimeInterval(900),channel:.notification)
        await coordinator.reconcile(context:context)
        XCTAssertEqual(coordinator.status(for:task),.cancellationPending)
        XCTAssertEqual(Set(alarms.pending.keys),[old]);XCTAssertTrue(notifications.pending.isEmpty)
        XCTAssertEqual(try service.reminderIntent(for:task.id)?.channelRawValue,"notification")
        alarms.failCancel=false;await coordinator.reconcile(context:context)
        XCTAssertEqual(coordinator.status(for:task),.scheduled);XCTAssertTrue(alarms.pending.isEmpty);XCTAssertEqual(notifications.pending.count,1)
        let notification=try XCTUnwrap(notifications.pending.keys.first)
        notifications.failedRemovalIdentifiers.insert(notification)
        try service.rescheduleReminder(id:task.id,to:now.addingTimeInterval(1200),channel:.alarm)
        await coordinator.reconcile(context:context)
        XCTAssertEqual(coordinator.status(for:task),.cancellationPending);XCTAssertEqual(alarms.scheduleCalls.count,1)
        notifications.failedRemovalIdentifiers=[];await coordinator.reconcile(context:context)
        XCTAssertEqual(coordinator.status(for:task),.scheduled);XCTAssertTrue(notifications.pending.isEmpty);XCTAssertEqual(alarms.pending.count,1)
        XCTAssertNotEqual(alarms.pending.keys.first,old)
        XCTAssertFalse(notifications.removed.contains(LocalReminderScheduler.dailyIdentifier));XCTAssertFalse(notifications.removed.contains(LocalReminderScheduler.weeklyIdentifier))
    }
    func testUsageStoppedOrElapsedAlarmNeverRearmsAndCurrentRingingAlarmIsNotCanceled() async throws {
        for stopBeforeFire in [true,false] {
            let container=try PersistenceContainerFactory.makeInMemory(),context=container.mainContext
            var now=Date();let fire=now.addingTimeInterval(600)
            let notifications=TodoNotificationStub(),alarms=TodoAlarmStub()
            let task=try TodoTaskService(context:context,now:{now}).create(.init(title:"Synthetic stop is not complete",remindAt:fire,reminderChannel:.alarm))
            let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
            await coordinator.reconcile(context:context);let id=try XCTUnwrap(alarms.pending.keys.first)
            if !stopBeforeFire {
                now=fire.addingTimeInterval(1);await coordinator.reconcile(context:context)
                XCTAssertEqual(alarms.pending.count,1);XCTAssertTrue(alarms.cancelCalls.isEmpty,"A current alarm may be ringing")
            }
            try await alarms.stop(id)
            let cold=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
            await cold.reconcile(context:context);await cold.reconcile(context:context)
            XCTAssertEqual(cold.status(for:task),stopBeforeFire ? .stopped : .elapsed)
            XCTAssertEqual(alarms.scheduleCalls.count,1);XCTAssertTrue(alarms.pending.isEmpty)
            XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<TodoTask>()).first?.state,.open)
            XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<TodoTaskEvent>()),1)
        }
    }
    func testUsageLateAlarmSuccessAfterDeletionCancelsOwnedRequestWithoutResurrectingTask() async throws {
        let container=try PersistenceContainerFactory.makeInMemory(),context=container.mainContext,now=Date()
        let notifications=TodoNotificationStub(),alarms=TodoAlarmStub(),service=TodoTaskService(context:context,now:{now})
        let task=try service.create(.init(title:"Synthetic late callback",remindAt:now.addingTimeInterval(600),reminderChannel:.alarm))
        let id=task.id
        let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
        alarms.whileScheduling={request in
            try service.delete(id:request.taskID)
            await coordinator.reconcile(context:context)
        }
        await coordinator.reconcile(context:context)
        XCTAssertTrue(alarms.pending.isEmpty);XCTAssertEqual(alarms.scheduleCalls.count,1);XCTAssertEqual(alarms.cancelCalls.count,1)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<TodoTask>()),0)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<TodoReminderIntent>()),0)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<TodoReminderDeviceRecord>()),0)
        XCTAssertNil(coordinator.savedTaskID);XCTAssertEqual(id,alarms.scheduleCalls.first?.taskID)
    }
    func testUsageCapacityCanRetryButAmbiguousAttemptNeedsExplicitNewIntent() async throws {
        for knownCapacity in [true,false] {
            let container=try PersistenceContainerFactory.makeInMemory(),context=container.mainContext,now=Date()
            let notifications=TodoNotificationStub(),alarms=TodoAlarmStub(),service=TodoTaskService(context:context,now:{now})
            let task=try service.create(.init(title:"Synthetic failed attempt",remindAt:now.addingTimeInterval(600),reminderChannel:.alarm))
            alarms.errorBeforeSchedule=knownCapacity ? TodoAlarmFailure.queueFull : CocoaError(.fileWriteUnknown)
            let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
            await coordinator.reconcile(context:context)
            XCTAssertEqual(coordinator.status(for:task),knownCapacity ? .alarmQueueFull : .confirmationRequired)
            alarms.errorBeforeSchedule=nil
            let cold=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms);await cold.reconcile(context:context)
            if knownCapacity {XCTAssertEqual(cold.status(for:task),.scheduled);XCTAssertEqual(alarms.scheduleCalls.count,2)}
            else {
                XCTAssertEqual(alarms.scheduleCalls.count,1);XCTAssertTrue(alarms.pending.isEmpty)
                try service.rescheduleReminder(id:task.id,to:now.addingTimeInterval(900),channel:.alarm)
                await cold.reconcile(context:context)
                XCTAssertEqual(cold.status(for:task),.scheduled);XCTAssertEqual(alarms.scheduleCalls.count,2)
            }
        }
    }
}

extension TodoReminderTests {
    func testUsageJournalFailureBeforeNativeCallKeepsOtherUncommittedDraftAndCanRetryReadyIdentity() async throws {
        let container=try PersistenceContainerFactory.makeInMemory(),context=container.mainContext,now=Date()
        let notifications=TodoNotificationStub(),alarms=TodoAlarmStub()
        let task=try TodoTaskService(context:context).create(.init(title:"Synthetic pre-call failure",remindAt:now.addingTimeInterval(600),reminderChannel:.alarm))
        context.autosaveEnabled=false;context.insert(Entry(body:"Synthetic unrelated uncommitted input",createdAt:now))
        var fail=true
        let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms,journalCommit:{write in
            if fail,try write.fetch(FetchDescriptor<TodoReminderDeviceRecord>()).contains(where: {$0.phaseRawValue == "prepared"}) {throw CocoaError(.fileWriteOutOfSpace)}
            try write.save()
        })
        await coordinator.reconcile(context:context)
        XCTAssertTrue(alarms.scheduleCalls.isEmpty);XCTAssertEqual(coordinator.status(for:task),.confirmationRequired)
        let journal=try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first)
        XCTAssertEqual(journal.phaseRawValue,"ready");let id=journal.id
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Entry>()),0);XCTAssertTrue(context.hasChanges)
        fail=false;await coordinator.reconcile(context:context)
        XCTAssertEqual(coordinator.status(for:task),.scheduled);XCTAssertEqual(alarms.scheduleCalls.map(\.id),[id])
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Entry>()),0);XCTAssertTrue(context.hasChanges)
    }
    func testUsageNativeReadFailureKeepsAttemptOwnershipAndResolvesPresentOrStoppedWithoutDuplicate() async throws {
        for remainsQueued in [true,false] {
            let container=try PersistenceContainerFactory.makeInMemory(),context=container.mainContext,now=Date()
            let notifications=TodoNotificationStub(),alarms=TodoAlarmStub()
            let task=try TodoTaskService(context:context).create(.init(title:"Synthetic native read ambiguity",remindAt:now.addingTimeInterval(600),reminderChannel:.alarm))
            alarms.whileScheduling={_ in alarms.failReads=true}
            let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
            await coordinator.reconcile(context:context);await coordinator.reconcile(context:context)
            XCTAssertEqual(coordinator.status(for:task),.confirmationRequired);XCTAssertEqual(alarms.scheduleCalls.count,1)
            XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first?.phaseRawValue,"prepared")
            if !remainsQueued {alarms.pending=[:]}
            alarms.failReads=false
            let cold=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms);await cold.reconcile(context:context)
            XCTAssertEqual(cold.status(for:task),remainsQueued ? .scheduled : .confirmationRequired)
            await cold.reconcile(context:context)
            XCTAssertEqual(cold.status(for:task),remainsQueued ? .scheduled : .stopped)
            XCTAssertEqual(alarms.scheduleCalls.count,1)
        }
    }
    func testUsageLateSuccessOrTransportFailureAfterNewChannelCannotOverwriteNewIntent() async throws {
        for transportFailure in [false,true] {
            let container=try PersistenceContainerFactory.makeInMemory(),context=container.mainContext,now=Date()
            let notifications=TodoNotificationStub(),alarms=TodoAlarmStub(),service=TodoTaskService(context:context,now:{now})
            let task=try service.create(.init(title:"Synthetic newer intent wins",remindAt:now.addingTimeInterval(600),reminderChannel:.alarm)),id=task.id
            let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
            alarms.whileScheduling={_ in
                try service.rescheduleReminder(id:id,to:now.addingTimeInterval(1800),channel:.notification)
                await coordinator.reconcile(context:context)
            }
            if transportFailure {alarms.errorAfterSchedule=CocoaError(.fileWriteUnknown)}
            await coordinator.reconcile(context:context)
            XCTAssertTrue(alarms.pending.isEmpty);XCTAssertEqual(alarms.scheduleCalls.count,1)
            XCTAssertEqual(notifications.pending.count,1);XCTAssertEqual(notifications.pending.values.first?.taskID,id)
            XCTAssertEqual(notifications.pending.values.first?.fireAt,now.addingTimeInterval(1800))
            XCTAssertEqual(coordinator.status(for:task),.scheduled)
            let value=try XCTUnwrap(TodoReminderDisplaySnapshot.read(id:id,container:container))
            XCTAssertEqual(value.channel,.notification);XCTAssertEqual(value.task.remindAt,now.addingTimeInterval(1800))
        }
    }
    func testUsageAuthorizationSuspensionFollowedByCompletionCannotArmClosedTask() async throws {
        let container=try PersistenceContainerFactory.makeInMemory(),context=container.mainContext,now=Date()
        let notifications=TodoNotificationStub(),alarms=TodoAlarmStub(),service=TodoTaskService(context:context,now:{now})
        alarms.authorization = .notDetermined
        let task=try service.create(.init(title:"Synthetic authorization race",remindAt:now.addingTimeInterval(600),reminderChannel:.alarm))
        let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
        alarms.whileAuthorizing={
            try? service.transition(id:task.id,to:.completed)
            await coordinator.reconcile(context:context)
        }
        await coordinator.reconcile(context:context,requestAlarmPermission:true)
        XCTAssertEqual(alarms.permissionCalls,1);XCTAssertTrue(alarms.scheduleCalls.isEmpty);XCTAssertTrue(notifications.pending.isEmpty)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<TodoTask>()).first?.state,.completed)
        XCTAssertEqual(coordinator.status(for:task),.none)
    }
    func testUsageUnconfirmedOldSeriesAlarmBlocksSuccessorUntilCancellationIsVerified() async throws {
        let container=try PersistenceContainerFactory.makeInMemory(),context=container.mainContext,now=Date()
        let notifications=TodoNotificationStub(),alarms=TodoAlarmStub(),service=TodoTaskService(context:context,now:{now})
        let task=try service.create(.init(title:"Synthetic series cancellation",plannedDay:TodoDay(date:now).description,remindAt:now.addingTimeInterval(600),frequency:.daily,reminderChannel:.alarm))
        let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
        await coordinator.reconcile(context:context);alarms.failCancel=true
        try service.transition(id:task.id,to:.completed)
        let successor=try XCTUnwrap(context.fetch(FetchDescriptor<TodoTask>()).first {$0.state == .open})
        await coordinator.reconcile(context:context)
        XCTAssertEqual(coordinator.status(for:task),.cancellationPending);XCTAssertEqual(coordinator.status(for:successor),.cancellationPending)
        XCTAssertEqual(alarms.scheduleCalls.count,1);XCTAssertTrue(coordinator.hasPendingCancellation)
        alarms.failCancel=false;await coordinator.reconcile(context:context)
        XCTAssertEqual(coordinator.status(for:task),.none);XCTAssertEqual(coordinator.status(for:successor),.scheduled)
        XCTAssertEqual(alarms.pending.values.map(\.taskID),[successor.id]);XCTAssertFalse(coordinator.hasPendingCancellation)
    }
    func testUsageCanceledSchedulingPassRetainsNativeOwnershipAndDoesNotContinueAdding() async throws {
        let container=try PersistenceContainerFactory.makeInMemory(),context=container.mainContext,now=Date()
        let notifications=TodoNotificationStub(),alarms=TodoAlarmStub(),service=TodoTaskService(context:context,now:{now})
        let first=try service.create(.init(title:"Synthetic canceled first",remindAt:now.addingTimeInterval(600),reminderChannel:.alarm))
        _ = try service.create(.init(title:"Synthetic canceled second",remindAt:now.addingTimeInterval(1200),reminderChannel:.alarm))
        alarms.whileScheduling={_ in throw CancellationError()}
        let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
        await coordinator.reconcile(context:context)
        XCTAssertEqual(alarms.scheduleCalls.count,1);XCTAssertEqual(coordinator.status(for:first),.confirmationRequired)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first?.phaseRawValue,"prepared")
        await coordinator.reconcile(context:context)
        XCTAssertEqual(alarms.scheduleCalls.count,2);XCTAssertEqual(alarms.pending.count,2)
        XCTAssertEqual(coordinator.status(for:first),.scheduled)
    }
}

extension TodoReminderTests {
    func testReviewCTitleOnlyEditReplacesNativeTextButUnrelatedNotesKeepAcceptedIdentity() async throws {
        for channel in TodoReminderChannel.allCases {
            let container=try PersistenceContainerFactory.makeInMemory(),context=container.mainContext,now=Date()
            let notifications=TodoNotificationStub(),alarms=TodoAlarmStub(),service=TodoTaskService(context:context,now:{now})
            let task=try service.create(.init(title:"Synthetic before title",remindAt:now.addingTimeInterval(600),reminderChannel:channel))
            let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
            await coordinator.reconcile(context:context)
            let before=try XCTUnwrap(service.reminderIntent(for:task.id)).generation
            var draft=try service.draft(id:task.id);draft.notes="Synthetic unrelated notes"
            try service.edit(id:task.id,draft:draft);await coordinator.reconcile(context:context)
            XCTAssertEqual(try service.reminderIntent(for:task.id)?.generation,before)
            draft=try service.draft(id:task.id);draft.title="Synthetic after title"
            try service.edit(id:task.id,draft:draft);await coordinator.reconcile(context:context)
            XCTAssertEqual(coordinator.status(for:task),.scheduled)
            if channel == .alarm {
                XCTAssertEqual(alarms.pending.count,1);XCTAssertEqual(alarms.pending.values.first?.title,"Synthetic after title")
            } else {
                XCTAssertEqual(notifications.pending.count,1);XCTAssertEqual(notifications.pending.values.first?.title,"Synthetic after title")
            }
        }
    }
}

extension TodoReminderTests {
    func testReviewCTitleEditOfStoppedRequestDoesNotRearmEitherChannel() async throws {
        for channel in TodoReminderChannel.allCases {
            let container=try PersistenceContainerFactory.makeInMemory(),context=container.mainContext,now=Date()
            let notifications=TodoNotificationStub(),alarms=TodoAlarmStub(),service=TodoTaskService(context:context,now:{now})
            let task=try service.create(.init(title:"Synthetic stopped before",remindAt:now.addingTimeInterval(600),reminderChannel:channel))
            let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
            await coordinator.reconcile(context:context)
            let generation=try XCTUnwrap(service.reminderIntent(for:task.id)).generation
            notifications.pending=[:];alarms.pending=[:]
            var draft=try service.draft(id:task.id);draft.title="Synthetic stopped after"
            try service.edit(id:task.id,draft:draft)
            await coordinator.reconcile(context:context);await coordinator.reconcile(context:context)
            XCTAssertEqual(coordinator.status(for:task),.stopped)
            XCTAssertEqual(alarms.scheduleCalls.count+notifications.addCalls.count,1)
            XCTAssertTrue(alarms.pending.isEmpty);XCTAssertTrue(notifications.pending.isEmpty)
            XCTAssertEqual(try service.reminderIntent(for:task.id)?.generation,generation)
        }
    }
    func testReviewCLegacyCancellationFailureBlocksNewSeriesSuccessorUntilVerified() async throws {
        let container=try PersistenceContainerFactory.makeInMemory(),context=container.mainContext,now=Date()
        let notifications=TodoNotificationStub(),alarms=TodoAlarmStub(),service=TodoTaskService(context:context,now:{now})
        let task=try service.create(.init(title:"Synthetic V14 legacy series",plannedDay:TodoDay(date:now).description,remindAt:now.addingTimeInterval(600),frequency:.daily))
        // Represents the actual V14→V15 default: an existing task has no new intent or device journal.
        context.delete(try XCTUnwrap(service.reminderIntent(for:task.id)));try context.save()
        let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
        await coordinator.reconcile(context:context)
        let old=TodoReminderCoordinator.identifier(task.id)
        XCTAssertNotNil(notifications.pending[old]);notifications.failedRemovalIdentifiers=[old]
        try service.transition(id:task.id,to:.completed)
        let successor=try XCTUnwrap(context.fetch(FetchDescriptor<TodoTask>()).first {$0.state == .open})
        await coordinator.reconcile(context:context)
        XCTAssertEqual(coordinator.status(for:task),.cancellationPending)
        XCTAssertEqual(coordinator.status(for:successor),.cancellationPending)
        XCTAssertEqual(notifications.pending.count,1);XCTAssertNil(notifications.pending.values.first {$0.taskID == successor.id})
        notifications.failedRemovalIdentifiers=[];await coordinator.reconcile(context:context)
        XCTAssertNil(notifications.pending[old]);XCTAssertEqual(notifications.pending.count,1)
        XCTAssertEqual(notifications.pending.values.first?.taskID,successor.id);XCTAssertEqual(coordinator.status(for:successor),.scheduled)
    }
}


extension TodoReminderTests {
    func testReviewCTitleChangesWhileNativeReadOrScheduleSuspendsCannotKeepOldText() async throws {
        for duringRead in [true,false] {
            let container=try PersistenceContainerFactory.makeInMemory(),context=container.mainContext,now=Date()
            let notifications=TodoNotificationStub(),alarms=TodoAlarmStub(),service=TodoTaskService(context:context,now:{now})
            let task=try service.create(.init(title:"Synthetic suspended before",remindAt:now.addingTimeInterval(600),reminderChannel:.alarm))
            let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
            let change: () async throws -> Void = {
                var draft=try service.draft(id:task.id);draft.title="Synthetic suspended after"
                try service.edit(id:task.id,draft:draft)
                await coordinator.reconcile(context:context)
            }
            if duringRead {await coordinator.reconcile(context:context);alarms.whileReading=change}
            else {alarms.whileScheduling={_ in try await change()}}
            await coordinator.reconcile(context:context)
            XCTAssertEqual(coordinator.status(for:task),.scheduled)
            XCTAssertEqual(alarms.pending.count,1);XCTAssertEqual(alarms.pending.values.first?.title,"Synthetic suspended after")
            XCTAssertEqual(alarms.scheduleCalls.count,2);XCTAssertEqual(alarms.cancelCalls.count,1)
        }
    }
    func testReviewCTitleReplacementWaitsForConfirmedCancellationThenUsesOneNewRequest() async throws {
        let container=try PersistenceContainerFactory.makeInMemory(),context=container.mainContext,now=Date()
        let notifications=TodoNotificationStub(),alarms=TodoAlarmStub(),service=TodoTaskService(context:context,now:{now})
        let task=try service.create(.init(title:"Synthetic blocked title before",remindAt:now.addingTimeInterval(600),reminderChannel:.alarm))
        let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
        await coordinator.reconcile(context:context);alarms.failCancel=true
        var draft=try service.draft(id:task.id);draft.title="Synthetic blocked title after"
        try service.edit(id:task.id,draft:draft);await coordinator.reconcile(context:context)
        XCTAssertEqual(coordinator.status(for:task),.cancellationPending);XCTAssertEqual(alarms.scheduleCalls.count,1)
        XCTAssertEqual(alarms.pending.values.first?.title,"Synthetic blocked title before")
        alarms.failCancel=false;await coordinator.reconcile(context:context)
        XCTAssertEqual(coordinator.status(for:task),.scheduled);XCTAssertEqual(alarms.scheduleCalls.count,2)
        XCTAssertEqual(alarms.pending.count,1);XCTAssertEqual(alarms.pending.values.first?.title,"Synthetic blocked title after")
    }
}

extension TodoReminderTests {
    func testReviewFixF1WithdrawnSuccessorRenewsOnlyOnReactivationBothChannels() async throws {
        for (channel,failCancellation) in [(TodoReminderChannel.notification,false),(.alarm,false),(.notification,true),(.alarm,true)] {
            let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            let url=root.appendingPathComponent("store.sqlite"),container=try PersistenceContainerFactory.makeOnDisk(at:url)
            let zone=TimeZone.current,now=TodoDay("2026-10-18")!.date(timeZone:TimeZone.current)!
            let service=TodoTaskService(context:container.mainContext,now:{now},timeZone:{zone})
            let a=try service.create(.init(title:"F1 cycle",plannedDay:"2026-10-18",remindAt:now.addingTimeInterval(3600),frequency:.daily,reminderChannel:channel))
            try service.transition(id:a.id,to:.completed)
            let b=try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TodoTask>()).first {$0.state == .open})
            let notifications=TodoNotificationStub(),alarms=TodoAlarmStub()
            let coordinator=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
            await coordinator.reconcile(context:container.mainContext)
            let oldGeneration=try XCTUnwrap(service.reminderIntent(for:b.id)).generation
            let oldRecord=try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first {$0.taskID == b.id})
            try service.transition(id:a.id,to:.open)
            // Cancellation may fail; ownership must remain and block the next generation.
            alarms.failCancel=failCancellation;notifications.failedRemovalIdentifiers=failCancellation ? [TodoIntentScheduling.identifier(oldRecord.id)] : []
            await coordinator.reconcile(context:container.mainContext)
            try service.transition(id:a.id,to:.completed)
            let newGeneration=try XCTUnwrap(service.reminderIntent(for:b.id)).generation
            XCTAssertNotEqual(newGeneration,oldGeneration)
            await coordinator.reconcile(context:container.mainContext)
            if failCancellation {
                XCTAssertEqual(coordinator.status(for:b),.cancellationPending)
                XCTAssertEqual(alarms.pending.count+notifications.pending.count,1)
            }
            alarms.failCancel=false;notifications.failedRemovalIdentifiers=[]
            await coordinator.reconcile(context:container.mainContext)
            XCTAssertEqual(coordinator.status(for:b),.scheduled)
            let count=alarms.scheduleCalls.count+notifications.addCalls.count
            let reopened=try PersistenceContainerFactory.makeOnDisk(at:url)
            let cold=TodoReminderCoordinator(client:notifications,now:{now},sleepPreferences:{.init()},alarmClient:alarms)
            await cold.reconcile(context:reopened.mainContext);await cold.reconcile(context:reopened.mainContext)
            XCTAssertEqual(alarms.pending.count+notifications.pending.count,1)
            XCTAssertEqual(alarms.scheduleCalls.count+notifications.addCalls.count,count)
            XCTAssertEqual(try TodoTaskService(context:reopened.mainContext).reminderIntent(for:b.id)?.generation,newGeneration)
            XCTAssertEqual(alarms.pending.values.first?.taskID ?? notifications.pending.values.first?.taskID,b.id)
        }
    }
    func testReviewFixF3AcceptedNotificationReallocatedAndWaitingRestores() async throws {
        let container=try PersistenceContainerFactory.makeInMemory(),now=Date(),c=container.mainContext
        let service=TodoTaskService(context:c,now:{now}),client=TodoNotificationStub()
        client.otherIdentifiers=Set((0..<59).map {"reserved-\($0)"})
        let coordinator=TodoReminderCoordinator(client:client,now:{now},sleepPreferences:{.init()})
        let late=try service.create(.init(title:"L",remindAt:now.addingTimeInterval(7200)))
        await coordinator.reconcile(context:c)
        let lateID=try XCTUnwrap(client.pending.keys.first),generation=try XCTUnwrap(service.reminderIntent(for:late.id)).generation
        let early=try service.create(.init(title:"E",remindAt:now.addingTimeInterval(600)))
        client.failedRemovalIdentifiers=[lateID]
        await coordinator.reconcile(context:c)
        XCTAssertEqual(client.pending.count,1);XCTAssertNil(client.pending.values.first {$0.taskID == early.id})
        client.failedRemovalIdentifiers=[]
        await coordinator.reconcile(context:c)
        XCTAssertEqual(client.pending.values.map(\.taskID),[early.id]);XCTAssertEqual(coordinator.status(for:late),.queueFull)
        try service.transition(id:early.id,to:.completed)
        await coordinator.reconcile(context:c)
        XCTAssertEqual(client.pending.values.map(\.taskID),[late.id]);XCTAssertEqual(coordinator.status(for:late),.scheduled)
        XCTAssertEqual(try service.reminderIntent(for:late.id)?.generation,generation)
        XCTAssertEqual(client.otherIdentifiers.count,59)
        XCTAssertFalse(client.removed.contains {client.otherIdentifiers.contains($0)})
    }
}

extension TodoReminderTests {
    func testReviewFixF3StoppedLateReminderNeverBecomesCapacityRetry() async throws {
        for earlySeconds in [600.0,10000.0] {
        let c=try PersistenceContainerFactory.makeInMemory(),now=Date(),client=TodoNotificationStub()
        client.otherIdentifiers=Set((0..<59).map {"reserved-\($0)"})
        let service=TodoTaskService(context:c.mainContext,now:{now})
        let late=try service.create(.init(title:"Stopped L",remindAt:now.addingTimeInterval(7200)))
        let coordinator=TodoReminderCoordinator(client:client,now:{now},sleepPreferences:{.init()})
        await coordinator.reconcile(context:c.mainContext)
        client.pending.removeAll() // Native user stop, before a capacity allocation can observe it.
        let early=try service.create(.init(title:"E",remindAt:now.addingTimeInterval(earlySeconds)))
        await coordinator.reconcile(context:c.mainContext)
        XCTAssertEqual(client.pending.values.map(\.taskID),[early.id])
        try service.transition(id:early.id,to:.completed)
        await coordinator.reconcile(context:c.mainContext)
        XCTAssertTrue(client.pending.isEmpty);XCTAssertEqual(coordinator.status(for:late),.stopped)
        }
    }
    func testReviewFixF3NewImportantDayDisplacesAcceptedTodoAndArchiveRestoresWaiting() async throws {
        let c=try PersistenceContainerFactory.makeInMemory(),zone=TimeZone.current
        let now=ImportantCivilDay(year:2026,month:10,day:18).instant(minutes:0,timeZone:zone)!
        let client=TodoNotificationStub();client.otherIdentifiers=Set((0..<59).map {"reserved-\($0)"})
        let task=try TodoTaskService(context:c.mainContext,now:{now}).create(.init(title:"Late Todo",remindAt:now.addingTimeInterval(86400*10)))
        let coordinator=TodoReminderCoordinator(client:client,now:{now},sleepPreferences:{.init()})
        await coordinator.reconcile(context:c.mainContext)
        var prefs=ImportantDayPreferences();prefs.reminderOffsets=[0]
        let day=try ImportantDay(title:"Earlier day",rule:.init(preset:.anniversary,year:nil,month:10,day:19),preferences:prefs)
        c.mainContext.insert(day);try c.mainContext.save()
        await coordinator.reconcile(context:c.mainContext)
        XCTAssertEqual(client.pending.count,1);XCTAssertEqual(client.pending.values.first?.importantDayID,day.id)
        XCTAssertEqual(coordinator.status(for:task),.queueFull)
        day.isArchived=true;try c.mainContext.save()
        await coordinator.reconcile(context:c.mainContext)
        XCTAssertEqual(client.pending.values.map(\.taskID),[task.id]);XCTAssertEqual(coordinator.status(for:task),.scheduled)
    }
}

extension TodoReminderTests {
    func testFix2CR01CapacityCancellationConfirmsAfterExpiryAndColdRecheck() async throws {
        for nativeDisappears in [true,false] {
            let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            defer {try? FileManager.default.removeItem(at:root)}
            let url=root.appendingPathComponent("test.sqlite"),c=try PersistenceContainerFactory.makeOnDisk(at:url)
            var now=Date();let client=TodoNotificationStub();client.otherIdentifiers=Set((0..<59).map {"reserved-\($0)"})
            let service=TodoTaskService(context:c.mainContext,now:{now})
            let late=try service.create(.init(title:"L",remindAt:now.addingTimeInterval(120)))
            let coordinator=TodoReminderCoordinator(client:client,now:{now},sleepPreferences:{.init()})
            await coordinator.reconcile(context:c.mainContext)
            let old=try XCTUnwrap(client.pending.keys.first),adds=client.addCalls.count
            _ = try service.create(.init(title:"E",remindAt:now.addingTimeInterval(60)))
            client.failedRemovalIdentifiers=[old];await coordinator.reconcile(context:c.mainContext)
            XCTAssertEqual(coordinator.status(for:late),.cancellationPending)
            now.addTimeInterval(121)
            let reopened=try PersistenceContainerFactory.makeOnDisk(at:url)
            let cold=TodoReminderCoordinator(client:client,now:{now},sleepPreferences:{.init()})
            if nativeDisappears {client.pending.removeValue(forKey:old)}
            await cold.reconcile(context:reopened.mainContext)
            let task=try TodoTaskService(context:reopened.mainContext).task(id:late.id)
            if !nativeDisappears {
                XCTAssertEqual(cold.status(for:task),.cancellationPending)
                client.failedRemovalIdentifiers=[];await cold.reconcile(context:reopened.mainContext)
            }
            for _ in 0..<2 {await cold.reconcile(context:reopened.mainContext)}
            XCTAssertEqual(cold.status(for:task),.elapsed)
            XCTAssertFalse(cold.hasPendingCancellation)
            XCTAssertTrue(client.pending.isEmpty);XCTAssertEqual(client.addCalls.count,adds)
            XCTAssertEqual(try ModelContext(reopened).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first {$0.taskID == late.id}?.phaseRawValue,"retired")
        }
    }
    func testFix2CR02CapacityReasonMustPersistBeforeNativeRemoval() async throws {
        for mode in 0..<3 {
            let c=try PersistenceContainerFactory.makeInMemory();var now=Date()
            let client=TodoNotificationStub();client.otherIdentifiers=Set((0..<59).map {"reserved-\($0)"})
            let service=TodoTaskService(context:c.mainContext,now:{now})
            let late=try service.create(.init(title:"L",remindAt:now.addingTimeInterval(7200)))
            var fail=false,attempts:[String]=[]
            let coordinator=TodoReminderCoordinator(client:client,now:{now},sleepPreferences:{.init()},journalCommit:{write in
                let phase=try write.fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first {$0.taskID == late.id}?.phaseRawValue ?? ""
                if fail && (phase == "capacityCancellationPending" || phase == "capacityWaiting") {
                    attempts.append(phase)
                    if mode == 2 {try write.save();throw CocoaError(.fileWriteUnknown)}
                    if mode == 0 || phase == "capacityWaiting" {throw CocoaError(.fileWriteOutOfSpace)}
                }
                try write.save()
            })
            await coordinator.reconcile(context:c.mainContext)
            let lateID=try XCTUnwrap(client.pending.keys.first),generation=try XCTUnwrap(service.reminderIntent(for:late.id)).generation
            let early=try service.create(.init(title:"E",remindAt:now.addingTimeInterval(600)))
            fail=true;await coordinator.reconcile(context:c.mainContext)
            XCTAssertFalse(attempts.isEmpty)
            if mode == 0 {
                XCTAssertNotNil(client.pending[lateID],"Two phase writes really fail: preserve native ownership before destructive removal")
                XCTAssertFalse(client.removed.contains(lateID))
            } else {XCTAssertNil(client.pending[lateID])}
            let phase=try ModelContext(c).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).first {$0.taskID == late.id}?.phaseRawValue
            XCTAssertEqual(phase,mode == 0 ? "accepted":mode == 1 ? "capacityCancellationPending":"capacityWaiting")
            if mode == 0 {XCTAssertFalse(attempts.contains("capacityWaiting"),"No destructive removal before the first durable reason")}
            else {XCTAssertTrue(attempts.contains("capacityWaiting"))}
            fail=false;await coordinator.reconcile(context:c.mainContext)
            XCTAssertEqual(client.pending.values.map(\.taskID),[early.id]);XCTAssertEqual(coordinator.status(for:late),.queueFull)
            try service.transition(id:early.id,to:.completed)
            let cold=TodoReminderCoordinator(client:client,now:{now},sleepPreferences:{.init()})
            for pass in 0..<2 {
                await cold.reconcile(context:c.mainContext)
                print("FIX2_CR02 mode=\(mode) pass=\(pass) native=\(client.pending.values.map {($0.taskID,$0.fireAt)}) status=\(cold.status(for:late)) phases=\(try ModelContext(c).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).map {($0.taskID,$0.phaseRawValue)}))")
            }
            XCTAssertEqual(client.pending.values.map(\.taskID),[late.id]);XCTAssertEqual(cold.status(for:late),.scheduled)
            XCTAssertEqual(try service.reminderIntent(for:late.id)?.generation,generation)
            XCTAssertLessThanOrEqual(client.pending.count+client.otherIdentifiers.count,60)
            now.addTimeInterval(1)
        }
    }
}
