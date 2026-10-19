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

@MainActor
final class SystemSettingsLateClient: LocalReminderNotificationClient {
    var pending: [String:DateComponents]=[:]
    var entered: XCTestExpectation?
    var continuation: CheckedContinuation<Void,Error>?
    var suspendFirst=true
    var failCurrent=false
    var failedRemoval=false
    var pendingHook:(@MainActor () async -> Void)?
    var removals=0
    func authorizationStatus() async -> UNAuthorizationStatus {.authorized}
    func requestAuthorization() async throws -> Bool {true}
    func pendingIdentifiers() async -> Set<String> {if let pendingHook {await pendingHook()};return Set(pending.keys)}
    func remove(_ ids:[String]) {removals += 1;guard !failedRemoval else {return};for id in ids {pending.removeValue(forKey:id)}}
    func addRepeating(identifier:String,components:DateComponents,title:String,body:String) async throws {
        if suspendFirst {
            suspendFirst=false
            try await withCheckedThrowingContinuation { continuation in self.continuation=continuation;entered?.fulfill() }
        }
        if failCurrent {throw CocoaError(.fileWriteUnknown)}
        pending[identifier]=components
    }
}

@MainActor
extension ImportantDayReminderTests {
    func testSystemSR05ChangedPreferenceSnapshotRejectsResultsBeforeNextSubmission() async throws {
        for succeeds in [false,true] {
            let owner=ReminderSettingsUpdate(),client=SystemSettingsLateClient()
            let entered=expectation(description:"Actual scheduler add entered");client.entered=entered
            var current=true,applied=false
            let task=owner.submit(operation:{try await LocalReminderScheduler(client:client).updateDaily(enabled:true,minutesAfterMidnight:480,requestPermission:false)},isCurrent:{current},apply:{_ in applied=true})
            await fulfillment(of:[entered],timeout:3)
            current=false // Preference binding changed; its onChange task need not have run yet.
            if succeeds {try XCTUnwrap(client.continuation).resume()} else {try XCTUnwrap(client.continuation).resume(throwing:CocoaError(.fileWriteUnknown))}
            await task.value;XCTAssertFalse(applied)
        }
    }

    func testSystemSR05ActualDailyWeeklySettingsBoundaryRejectsAllLateOutcomes() async throws {
        for weekly in [false,true] {
            for enabled in [false,true] {
                for outcome in 0..<3 {
                    let client=SystemSettingsLateClient(),owner=ReminderSettingsUpdate()
                    let entered=expectation(description:"A entered actual addRepeating");client.entered=entered
                    let scheduler=LocalReminderScheduler(client:client)
                    var applied:[ReminderUpdateResult]=[],failures=0
                    func operation(_ enabled:Bool,_ minutes:Int,_ weekday:Int) async throws -> ReminderUpdateResult {
                        if weekly {return try await scheduler.updateWeekly(enabled:enabled,weekday:weekday,minutesAfterMidnight:minutes,requestPermission:false)}
                        return try await scheduler.updateDaily(enabled:enabled,minutesAfterMidnight:minutes,requestPermission:false)
                    }
                    func apply(_ result:Result<ReminderUpdateResult,Error>) {
                        switch result {case .success(let value):applied.append(value);case .failure:failures += 1}
                    }
                    let old=owner.submit(operation:{try await operation(true,480,2)},apply:apply)
                    await fulfillment(of:[entered],timeout:3)
                    let latest=owner.submit(operation:{try await operation(enabled,690,6)},apply:apply)
                    let continuation=try XCTUnwrap(client.continuation)
                    if outcome == 0 {continuation.resume(throwing:CocoaError(.fileWriteUnknown))}
                    else if outcome == 1 {continuation.resume()}
                    else {continuation.resume(throwing:CancellationError())}
                    await old.value;await latest.value
                    XCTAssertEqual(applied,[enabled ? .scheduled:.removed]);XCTAssertEqual(failures,0)
                    let id=weekly ? LocalReminderScheduler.weeklyIdentifier:LocalReminderScheduler.dailyIdentifier
                    XCTAssertEqual(client.pending[id]?.hour,enabled ? 11:nil)
                    XCTAssertEqual(client.pending[id]?.minute,enabled ? 30:nil)
                    if weekly {XCTAssertEqual(client.pending[id]?.weekday,enabled ? 6:nil)}
                    client.failCurrent=true
                    await owner.submit(operation:{try await operation(true,720,3)},apply:apply).value
                    XCTAssertEqual(failures,1,"A current ordinary failure must still reach settings feedback")
                }
            }
        }
    }
}

@MainActor extension ImportantDayReminderTests {
    func testIntegrationIR03RebuiltSettingsSameValuesRejectOldOutcome() async throws {
        for weekly in [false,true] {
            for outcome in 0..<3 {
                let scope=ReminderSettingsUpdate.Scope()
                let client=SystemSettingsLateClient(),a=ReminderSettingsUpdate(scope:scope),b=ReminderSettingsUpdate(scope:scope)
                let entered=expectation(description:"A owns gate inside native add");client.entered=entered
                let scheduler=LocalReminderScheduler(client:client)
                var enabled=true,oldApplied=0,newApplied=0
                func operation(_ value:Bool) async throws -> ReminderUpdateResult {
                    if weekly {return try await scheduler.updateWeekly(enabled:value,weekday:2,minutesAfterMidnight:480,requestPermission:false)}
                    return try await scheduler.updateDaily(enabled:value,minutesAfterMidnight:480,requestPermission:false)
                }
                let old=a.submit(operation:{try await operation(true)},isCurrent:{enabled},apply:{result in
                    oldApplied += 1
                    if case .failure=result {enabled=false}
                })
                await fulfillment(of:[entered],timeout:3)
                enabled=false
                let off=b.submit(operation:{try await operation(false)},apply:{_ in newApplied += 1})
                enabled=true // Recreated sheet has a new intent with exactly A's parameters.
                let latest=b.submit(operation:{try await operation(true)},isCurrent:{enabled},apply:{_ in newApplied += 1})
                let release=try XCTUnwrap(client.continuation)
                if outcome == 0 {release.resume(throwing:CocoaError(.fileWriteUnknown))}
                else if outcome == 1 {release.resume()}
                else {release.resume(throwing:CancellationError())}
                await old.value;await off.value;await latest.value
                XCTAssertEqual(oldApplied,0);XCTAssertTrue(enabled);XCTAssertEqual(newApplied,1)
                let id=weekly ? LocalReminderScheduler.weeklyIdentifier:LocalReminderScheduler.dailyIdentifier
                XCTAssertEqual(client.pending[id]?.hour,8)
            }
        }
    }
}

@MainActor extension ImportantDayReminderTests {
    func testIntegrationIR03CrossSheetScopeKeepsLegalCompletionExplicitOffAndChannelsIndependent() async throws {
        for weekly in [false,true] {
            for newOff in [false,true] {
                let intents=ReminderSettingsIntents(),client=SystemSettingsLateClient()
                let scope=weekly ? intents.weekly:intents.daily
                let a=ReminderSettingsUpdate(scope:scope),b=ReminderSettingsUpdate(scope:scope)
                let entered=expectation(description:"Legal A began before close");client.entered=entered
                let scheduler=LocalReminderScheduler(client:client)
                var results:[ReminderUpdateResult]=[]
                func update(_ enabled:Bool) async throws -> ReminderUpdateResult {
                    if weekly {return try await scheduler.updateWeekly(enabled:enabled,weekday:2,minutesAfterMidnight:480,requestPermission:false)}
                    return try await scheduler.updateDaily(enabled:enabled,minutesAfterMidnight:480,requestPermission:false)
                }
                let old=a.submit(operation:{try await update(true)},apply:{if case .success(let v)=$0 {results.append(v)}})
                await fulfillment(of:[entered],timeout:3)
                let independent=ReminderSettingsUpdate(scope:weekly ? intents.daily:intents.weekly)
                var otherApplied=false
                await independent.submit(operation:{.removed},apply:{_ in otherApplied=true}).value
                XCTAssertTrue(otherApplied)
                let latest=newOff ? b.submit(operation:{try await update(false)},apply:{if case .success(let v)=$0 {results.append(v)}}):nil
                try XCTUnwrap(client.continuation).resume();await old.value;await latest?.value
                XCTAssertEqual(results,[newOff ? .removed:.scheduled])
                let id=weekly ? LocalReminderScheduler.weeklyIdentifier:LocalReminderScheduler.dailyIdentifier
                XCTAssertEqual(client.pending[id] != nil,!newOff)
                client.failCurrent=true;var currentFailure=false
                await b.submit(operation:{try await update(true)},apply:{if case .failure=$0 {currentFailure=true}}).value
                XCTAssertTrue(currentFailure)
            }
        }
    }
}

@MainActor extension ImportantDayReminderTests {
    func testTerminalIC02StableFailureCleanupLatestIntentAndRetryMatrix() async throws {
        for weekly in [false,true] {
            for newer in 0..<4 { // no B, same value B, changed B, explicit off B
                for outcome in 0..<3 { // ordinary error, success, transport cancellation
                    let client=SystemSettingsLateClient();client.suspendFirst=false
                    let scheduler=LocalReminderScheduler(client:client),scope=ReminderSettingsUpdate.Scope()
                    let owner=ReminderSettingsUpdate(scope:scope)
                    func operation(_ enabled:Bool,_ minutes:Int) async throws -> ReminderUpdateResult {
                        if weekly {return try await scheduler.updateWeekly(enabled:enabled,weekday:2,minutesAfterMidnight:minutes,requestPermission:false)}
                        return try await scheduler.updateDaily(enabled:enabled,minutesAfterMidnight:minutes,requestPermission:false)
                    }
                    _ = try await operation(true,480)
                    client.suspendFirst=true
                    let entered=expectation(description:"Current A owns actual add");client.entered=entered
                    var enabled=true,minutes=540,applied=0
                    func submit(_ on:Bool,_ time:Int) -> Task<Void,Never> {
                        owner.submit(operation:{try await operation(on,time)},isCurrent:{enabled == on && minutes == time},recover:{current in
                            await scheduler.removeAfterFailure(weekly:weekly,isCurrent:current)
                        },apply:{result in applied += 1;if case .failure=result {enabled=false}})
                    }
                    let a=submit(true,540);await fulfillment(of:[entered],timeout:3)
                    var b:Task<Void,Never>?
                    if newer > 0 {enabled=newer != 3;minutes=newer == 2 ? 660:540;b=submit(enabled,minutes)}
                    let release=try XCTUnwrap(client.continuation);client.continuation=nil
                    if outcome == 0 {release.resume(throwing:CocoaError(.fileWriteUnknown))}
                    else if outcome == 1 {release.resume()}
                    else {release.resume(throwing:CancellationError())}
                    await a.value;await b?.value
                    let id=weekly ? LocalReminderScheduler.weeklyIdentifier:LocalReminderScheduler.dailyIdentifier
                    let expectedOn = newer > 0 ? newer != 3:outcome == 1
                    XCTAssertEqual(enabled,expectedOn);XCTAssertEqual(client.pending[id] != nil,expectedOn)
                    if expectedOn {XCTAssertEqual(client.pending[id]?.hour,(newer == 2 ? 660:540)/60)}
                    XCTAssertEqual(applied,1)
                    XCTAssertEqual(scope.failureMessage != nil,newer == 0 && outcome != 1)
                    XCTAssertFalse(scope.cleanupPending)
                }
            }
            let client=SystemSettingsLateClient();client.suspendFirst=false
            let scheduler=LocalReminderScheduler(client:client),scope=ReminderSettingsUpdate.Scope(),owner:ReminderSettingsUpdate
            owner=ReminderSettingsUpdate(scope:scope)
            let id=weekly ? LocalReminderScheduler.weeklyIdentifier:LocalReminderScheduler.dailyIdentifier
            if weekly {_ = try await scheduler.updateWeekly(enabled:true,weekday:2,minutesAfterMidnight:480,requestPermission:false)}
            else {_ = try await scheduler.updateDaily(enabled:true,minutesAfterMidnight:480,requestPermission:false)}
            client.failCurrent=true;client.failedRemoval=true
            await owner.submit(operation:{
                if weekly {return try await scheduler.updateWeekly(enabled:true,weekday:2,minutesAfterMidnight:540,requestPermission:false)}
                return try await scheduler.updateDaily(enabled:true,minutesAfterMidnight:540,requestPermission:false)
            },recover:{await scheduler.removeAfterFailure(weekly:weekly,isCurrent:$0)},apply:{_ in}).value
            XCTAssertTrue(scope.cleanupPending);XCTAssertNotNil(scope.failureMessage);XCTAssertNotNil(client.pending[id])
            client.failedRemoval=false
            await owner.submit(operation:{
                if weekly {return try await scheduler.updateWeekly(enabled:false,weekday:2,minutesAfterMidnight:540,requestPermission:false)}
                return try await scheduler.updateDaily(enabled:false,minutesAfterMidnight:540,requestPermission:false)
            },apply:{if case .success(let value)=$0 {XCTAssertEqual(value,.removed)} else {XCTFail("Confirmed retry must settle")}}).value
            XCTAssertNil(client.pending[id]);XCTAssertFalse(scope.cleanupPending)
        }
    }
}

@MainActor extension ImportantDayReminderTests {
    func testTerminalIC02NewIntentDuringFailureCleanupQueryNeverDeletesLatest() async throws {
        for weekly in [false,true] {
            for newer in 0..<3 {
                let client=SystemSettingsLateClient();client.suspendFirst=false
                let scheduler=LocalReminderScheduler(client:client),scope=ReminderSettingsUpdate.Scope(),owner:ReminderSettingsUpdate
                owner=ReminderSettingsUpdate(scope:scope)
                func operation(_ enabled:Bool,_ minutes:Int) async throws -> ReminderUpdateResult {
                    if weekly {return try await scheduler.updateWeekly(enabled:enabled,weekday:2,minutesAfterMidnight:minutes,requestPermission:false)}
                    return try await scheduler.updateDaily(enabled:enabled,minutesAfterMidnight:minutes,requestPermission:false)
                }
                _ = try await operation(true,480);client.failCurrent=true
                let entered=expectation(description:"Current A cleanup query suspended inside actual gate")
                var release:CheckedContinuation<Void,Never>?,oldApplied=0,latestApplied=0
                let a=owner.submit(operation:{try await operation(true,540)},recover:{current in
                    client.pendingHook={
                        client.pendingHook=nil
                        await withCheckedContinuation {release=$0;entered.fulfill()}
                    }
                    return await scheduler.removeAfterFailure(weekly:weekly,isCurrent:current)
                },apply:{_ in oldApplied += 1})
                await fulfillment(of:[entered],timeout:3)
                client.failCurrent=false
                let enabled=newer != 2,minutes=newer == 1 ? 660:540
                let b=owner.submit(operation:{try await operation(enabled,minutes)},apply:{_ in latestApplied += 1})
                release?.resume();release=nil
                await a.value;await b.value
                let id=weekly ? LocalReminderScheduler.weeklyIdentifier:LocalReminderScheduler.dailyIdentifier
                XCTAssertEqual(oldApplied,0);XCTAssertEqual(latestApplied,1)
                XCTAssertEqual(client.removals,enabled ? 0:1,"Stale cleanup must not mutate fixed identifier after a newer ticket")
                XCTAssertEqual(client.pending[id] != nil,enabled)
                if enabled {XCTAssertEqual(client.pending[id]?.hour,minutes/60)}
                XCTAssertNil(scope.failureMessage);XCTAssertFalse(scope.cleanupPending)
            }
        }
    }
}
