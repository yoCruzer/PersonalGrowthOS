import SwiftData
import XCTest
import UserNotifications
@testable import PersonalGrowthOS

@MainActor
final class ImportantDayReminderTests: XCTestCase {
    let zone = TimeZone(identifier: "Asia/Shanghai")!
    private var now: Date { ImportantCivilDay(year: 2026, month: 6, day: 1).instant(minutes: 720, timeZone: zone)! }
    private func makeDay(_ context: ModelContext, day: Int = 10, offsets: [Int] = [0, 3]) throws -> ImportantDay {
        var preferences = ImportantDayPreferences(); preferences.reminderOffsets = offsets
        let value = try ImportantDay(title: "Synthetic private title", rule: .init(preset: .anniversary, year: nil, month: 6, day: day), preferences: preferences)
        context.insert(value); try context.save(); return value
    }
    func testPlannerUsesSharedRulesBoundedOccurrencesGenericPrivacyAndDST() throws {
        let rule = ImportantDayDateRule(preset: .anniversary, year: 2000, month: 2, day: 29, leapDayRule: .february28)
        var p = ImportantDayPreferences(); p.reminderOffsets = [0, 7]
        let requests = try ImportantDayReminderPlanner.requests(id: UUID(), title: "Secret", rule: rule, preferences: p, now: now, timeZone: zone)
        XCTAssertEqual(requests.count, 4)
        XCTAssertTrue(requests.allSatisfy { $0.importantDayID != nil && !$0.title.contains("Secret") })
        XCTAssertEqual(ImportantCivilDay(requests[1].fireAt, timeZone: zone), .init(year: 2027, month: 2, day: 28))
        XCTAssertEqual(ImportantCivilDay(requests[3].fireAt, timeZone: zone), .init(year: 2028, month: 2, day: 29))
        p.genericNotification = false
        XCTAssertTrue(try ImportantDayReminderPlanner.requests(id: UUID(), title: "Explicit title", rule: rule, preferences: p, now: now, timeZone: zone).allSatisfy { $0.title == "Explicit title" })
        let future = ImportantDayDateRule(preset: .anniversary, year: 2100, month: 12, day: 31)
        XCTAssertEqual(try ImportantDayReminderPlanner.requests(id: UUID(), title: "Future", rule: future, preferences: p, now: now, timeZone: zone).count, 2)
    }
    func testTodoAndDayCompeteInOneDeterministicCapacityAndBothStatusesRefresh() async throws {
        let container = try PersistenceContainerFactory.makeInMemory(), c = container.mainContext
        let client = TodoNotificationStub(); client.otherIdentifiers = Set((0..<59).map { "reserved-\($0)" })
        let day = try makeDay(c, offsets: [0])
        let task = try TodoTaskService(context: c).create(.init(title: "Closer", remindAt: now.addingTimeInterval(3600)))
        let coordinator = TodoReminderCoordinator(client: client, now: { self.now })
        await coordinator.reconcile(context: c)
        XCTAssertEqual(client.pending.count, 1)
        XCTAssertEqual(coordinator.status(for: task), .scheduled); XCTAssertEqual(coordinator.status(for: day).status, .queueFull)
        try TodoTaskService(context: c).transition(id: task.id, to: .completed)
        await coordinator.reconcile(context: c)
        XCTAssertEqual(client.pending.count, 1); XCTAssertEqual(coordinator.status(for: task), .none)
        XCTAssertEqual(coordinator.status(for: day).scheduledCount, 1)
        XCTAssertEqual(coordinator.status(for: day).status, .queueFull) // second annual occurrence cannot fit
        XCTAssertNotNil(coordinator.status(for: day).nextFire)
        let nextTask = try TodoTaskService(context: c).create(.init(title: "New closer", remindAt: now.addingTimeInterval(7200)))
        await coordinator.reconcile(context: c)
        XCTAssertEqual(coordinator.status(for: nextTask), .scheduled)
        XCTAssertNil(coordinator.status(for: day).nextFire); XCTAssertEqual(coordinator.status(for: day).scheduledCount, 0)
        XCTAssertTrue(client.removed.allSatisfy { $0.hasPrefix(TodoReminderCoordinator.prefix) || $0.hasPrefix(ImportantDayReminderPlanner.prefix) })
    }
    func testDayDeniedFailureOffAndArchiveNeverRemoveOtherBusinessRequests() async throws {
        let container = try PersistenceContainerFactory.makeInMemory(), c = container.mainContext
        let day = try makeDay(c), client = TodoNotificationStub()
        let coordinator = TodoReminderCoordinator(client: client, now: { self.now })
        client.authorization = .notDetermined
        await coordinator.reconcile(context: c)
        XCTAssertEqual(client.permissionCalls, 0); XCTAssertEqual(coordinator.status(for: day).status, .permissionRequired)
        await coordinator.reconcile(context: c, requestPermission: true)
        XCTAssertEqual(client.permissionCalls, 1); XCTAssertEqual(coordinator.status(for: day).status, .scheduled)
        XCTAssertEqual(coordinator.status(for: day).scheduledCount, 4)
        client.shouldFail = true; await coordinator.reconcile(context: c)
        XCTAssertEqual(coordinator.status(for: day).status, .failed); XCTAssertTrue(client.pending.isEmpty)
        client.shouldFail = false; client.authorization = .denied; await coordinator.reconcile(context: c)
        XCTAssertEqual(coordinator.status(for: day).status, .denied)
        client.authorization = .allowed; await coordinator.reconcile(context: c)
        day.isArchived = true; try c.save(); await coordinator.reconcile(context: c)
        XCTAssertEqual(coordinator.status(for: day).status, .none); XCTAssertTrue(client.pending.isEmpty)
        XCTAssertFalse(client.removed.contains(LocalReminderScheduler.dailyIdentifier)); XCTAssertFalse(client.removed.contains(LocalReminderScheduler.weeklyIdentifier))
        XCTAssertEqual(try c.fetchCount(FetchDescriptor<ImportantDay>()), 1)
    }
    func testInterleavedDayEditAndTodoMutationCannotPublishOldGeneration() async throws {
        let container = try PersistenceContainerFactory.makeInMemory(), c = container.mainContext
        let day = try makeDay(c, offsets: [0]), client = TodoNotificationStub()
        let coordinator = TodoReminderCoordinator(client: client, now: { self.now })
        client.whileAdding = {
            day.isArchived = true; try c.save()
            Task { await coordinator.reconcile(context: c) }
        }
        await coordinator.reconcile(context: c); await Task.yield(); await coordinator.reconcile(context: c)
        XCTAssertTrue(client.pending.isEmpty); XCTAssertNil(coordinator.status(for: day).nextFire)
        XCTAssertEqual(coordinator.status(for: day).status, .none)
    }
    func testNoSupportedNextPeriodDiffersFromElapsedAndClockRollbackRebuildsWithoutChangingFacts() async throws {
        let container = try PersistenceContainerFactory.makeInMemory(), c = container.mainContext
        var p = ImportantDayPreferences(); p.reminderOffsets = [0]
        let rule = ImportantDayDateRule(preset: .anniversary, year: nil, month: 1, day: 1)
        let annual = try ImportantDay(title: "Annual range", rule: rule, preferences: p)
        let once = try ImportantDay(title: "Passed one time", rule: .init(year: 2026, month: 1, day: 1), preferences: p)
        c.insert(annual); c.insert(once); try c.save()
        var clock = ImportantCivilDay(year: 2100, month: 12, day: 31).instant(minutes: 720, timeZone: .current)!
        let client = TodoNotificationStub(), coordinator = TodoReminderCoordinator(client: client, now: { clock })
        await coordinator.reconcile(context: c)
        XCTAssertEqual(coordinator.status(for: annual).status, .unsupportedDateRange)
        XCTAssertEqual(coordinator.status(for: once).status, .elapsed)
        let originalBytes = annual.ruleData, revision = annual.revision
        clock = ImportantCivilDay(year: 2026, month: 12, day: 31).instant(minutes: 720, timeZone: .current)!
        await coordinator.reconcile(context: c)
        let first = coordinator.status(for: annual).nextFire
        XCTAssertEqual(first.map { ImportantCivilDay($0) }, .init(year: 2027, month: 1, day: 1))
        clock = ImportantCivilDay(year: 2027, month: 1, day: 2).instant(minutes: 720, timeZone: .current)!
        await coordinator.reconcile(context: c)
        XCTAssertEqual(coordinator.status(for: annual).nextFire.map { ImportantCivilDay($0) }, .init(year: 2028, month: 1, day: 1))
        clock = ImportantCivilDay(year: 2026, month: 12, day: 31).instant(minutes: 720, timeZone: .current)!
        await coordinator.reconcile(context: c)
        XCTAssertEqual(coordinator.status(for: annual).nextFire, first)
        XCTAssertEqual(annual.ruleData, originalBytes); XCTAssertEqual(annual.revision, revision)
    }
    func testGateSerializesIndependentSubmittersAcrossSuspension() async {
        let gate = NotificationMutationGate(), firstEntered = expectation(description: "first")
        var trace: [String] = []
        let first = Task { @MainActor in
            await gate.acquire(); trace.append("a-enter"); firstEntered.fulfill()
            await Task.yield(); trace.append("a-exit"); gate.release()
        }
        await fulfillment(of: [firstEntered], timeout: 2)
        let second = Task { @MainActor in await gate.acquire(); trace.append("b-enter"); gate.release() }
        await first.value; await second.value
        XCTAssertEqual(trace, ["a-enter", "a-exit", "b-enter"])
    }
}

@MainActor
private final class MixedReminderClient: TodoNotificationClient, LocalReminderNotificationClient {
    var records: [String: TodoReminderRequest] = [:]
    var repeats: Set<String> = []
    var others: Set<String> = []
    var allow = true
    var duringPermission: (() async -> Void)?
    var trace: [String] = []
    func permission() async -> TodoNotificationPermission {
        trace.append("batch-permission")
        if let duringPermission { self.duringPermission = nil; await duringPermission() }
        return allow ? .allowed : .denied
    }
    func requestPermission() async throws -> Bool { allow }
    func authorizationStatus() async -> UNAuthorizationStatus { trace.append("repeating-permission"); return allow ? .authorized : .denied }
    func requestAuthorization() async throws -> Bool { allow }
    func pendingIdentifiers() async -> Set<String> { Set(records.keys).union(repeats).union(others) }
    func remove(_ identifiers: [String]) { for id in identifiers { records.removeValue(forKey: id); repeats.remove(id) } }
    func add(_ request: TodoReminderRequest) async throws { records[request.id] = request; trace.append("batch-add") }
    func addRepeating(identifier: String, components: DateComponents, title: String, body: String) async throws { repeats.insert(identifier); trace.append("repeating-add") }
}

@MainActor
extension ImportantDayReminderTests {
    func testRealDailyWeeklyAdapterAndCombinedBatchShareCapacityAndSerialBoundary() async throws {
        let container = try PersistenceContainerFactory.makeInMemory(), c = container.mainContext
        let client = MixedReminderClient(); client.others = Set((0..<59).map { "unknown-\($0)" })
        let repeating = LocalReminderScheduler(client: client)
        let daily = try await repeating.updateDaily(enabled: true, minutesAfterMidnight: 540, requestPermission: false)
        XCTAssertEqual(daily, .scheduled)
        let task = try TodoTaskService(context: c).create(.init(title: "Closer", remindAt: now.addingTimeInterval(3600)))
        let day = try makeDay(c, offsets: [0]), coordinator = TodoReminderCoordinator(client: client, now: { self.now })
        await coordinator.reconcile(context: c)
        XCTAssertEqual(coordinator.status(for: task), .queueFull); XCTAssertEqual(coordinator.status(for: day).status, .queueFull)
        XCTAssertTrue(client.repeats.contains(LocalReminderScheduler.dailyIdentifier))
        _ = try await repeating.updateDaily(enabled: false, minutesAfterMidnight: 540, requestPermission: false)
        await coordinator.reconcile(context: c)
        XCTAssertEqual(coordinator.status(for: task), .scheduled)
        do {
            _ = try await repeating.updateWeekly(enabled: true, weekday: 1, minutesAfterMidnight: 540, requestPermission: false)
            XCTFail("A full shared queue must not silently schedule another request")
        } catch { XCTAssertTrue(error is NotificationQueueError) }
        XCTAssertEqual(client.records.values.filter {$0.taskID == task.id}.count,1)
        XCTAssertFalse(client.records.keys.contains {$0.hasPrefix(TodoIntentScheduling.budgetPrefix)})
        client.others = []
        var weekly: Task<ReminderUpdateResult, Error>?
        client.trace = []
        client.duringPermission = {
            weekly = Task { try await repeating.updateWeekly(enabled: true, weekday: 1, minutesAfterMidnight: 540, requestPermission: false) }
            await Task.yield()
            XCTAssertFalse(client.trace.contains("repeating-permission"))
        }
        await coordinator.reconcile(context: c)
        let result = try await weekly?.value
        XCTAssertEqual(result, .scheduled)
        XCTAssertTrue(client.repeats.contains(LocalReminderScheduler.weeklyIdentifier))
        let lastBatch = try XCTUnwrap(client.trace.lastIndex(of: "batch-add"))
        let repeatingPermission = try XCTUnwrap(client.trace.firstIndex(of: "repeating-permission"))
        XCTAssertLessThan(lastBatch, repeatingPermission)
        XCTAssertEqual(coordinator.status(for: task), .scheduled); XCTAssertEqual(coordinator.status(for: day).status, .scheduled)
    }
}
