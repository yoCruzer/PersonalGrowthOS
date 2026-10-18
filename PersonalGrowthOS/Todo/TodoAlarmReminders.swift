import AlarmKit
import AppIntents
import Foundation
import Observation
import SwiftUI
import SwiftData

enum TodoAlarmPermission: Equatable, Sendable {case allowed, notDetermined, denied, unsupported}
struct TodoAlarmRequest: Equatable, Sendable {
    let id: UUID
    let taskID: UUID
    let title: String
    let fireAt: Date
}
enum TodoAlarmFailure: Error, Equatable, LocalizedError {
    case unsupported, queueFull, invalidRequest
    var errorDescription: String? {
        switch self {
        case .unsupported: return String(localized:"Alarm reminders require iOS 26 or later.")
        case .queueFull: return String(localized:"Alarm not queued: waiting for an available system slot.")
        case .invalidRequest: return String(localized:"This alarm request is no longer available.")
        }
    }
}
@MainActor protocol TodoAlarmClient {
    func permission() async -> TodoAlarmPermission
    func requestPermission() async throws -> TodoAlarmPermission
    func pendingIdentifiers() async throws -> Set<UUID>
    func schedule(_ request: TodoAlarmRequest) async throws
    func cancel(_ id: UUID) async throws
    func stop(_ id: UUID) async throws
    func observeChanges(_ changed: @escaping @MainActor () -> Void) -> [Task<Void,Never>]
}
extension TodoAlarmClient {
    func observeChanges(_ changed: @escaping @MainActor () -> Void) -> [Task<Void,Never>] {[]}
}
@MainActor final class SystemTodoAlarmClient: TodoAlarmClient {
    func permission() async -> TodoAlarmPermission {
        guard #available(iOS 26.0, *) else {return .unsupported}
        return Self.permission(AlarmManager.shared.authorizationState)
    }
    func requestPermission() async throws -> TodoAlarmPermission {
        guard #available(iOS 26.0, *) else {return .unsupported}
        return Self.permission(try await AlarmManager.shared.requestAuthorization())
    }
    func pendingIdentifiers() async throws -> Set<UUID> {
        guard #available(iOS 26.0, *) else {return []}
        return Set(try AlarmManager.shared.alarms.map(\.id))
    }
    func schedule(_ request: TodoAlarmRequest) async throws {
        guard #available(iOS 26.0, *) else {throw TodoAlarmFailure.unsupported}
        let open=AlarmButton(text:"Open Todo",textColor:.white,systemImageName:"checklist")
        let title=LocalizedStringResource("\(request.title)")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = .init(title:title,secondaryButton:open,secondaryButtonBehavior:.custom)
        } else {
            alert = .init(title:title,stopButton:.init(text:"Stop alarm",textColor:.white,systemImageName:"stop.fill"),secondaryButton:open,secondaryButtonBehavior:.custom)
        }
        let attributes=AlarmAttributes(presentation:.init(alert:alert),metadata:TodoAlarmMetadata(taskID:request.taskID),tintColor:Color.accentColor)
        do {
            _ = try await AlarmManager.shared.schedule(id:request.id,configuration:.alarm(schedule:.fixed(request.fireAt),attributes:attributes,
                stopIntent:StopTodoAlarmIntent(requestID:request.id.uuidString),secondaryIntent:OpenTodoAlarmIntent(taskID:request.taskID.uuidString)))
        } catch AlarmManager.AlarmError.maximumLimitReached {throw TodoAlarmFailure.queueFull}
    }
    func cancel(_ id: UUID) async throws {
        guard #available(iOS 26.0, *) else {throw TodoAlarmFailure.unsupported}
        try AlarmManager.shared.cancel(id:id)
    }
    func stop(_ id: UUID) async throws {
        guard #available(iOS 26.0, *) else {throw TodoAlarmFailure.unsupported}
        try AlarmManager.shared.stop(id:id)
    }
    func observeChanges(_ changed: @escaping @MainActor () -> Void) -> [Task<Void,Never>] {
        guard #available(iOS 26.0, *) else {return []}
        let alarms=Task {for await _ in AlarmManager.shared.alarmUpdates {if Task.isCancelled {return};changed()}}
        let permission=Task {for await _ in AlarmManager.shared.authorizationUpdates {if Task.isCancelled {return};changed()}}
        return [alarms,permission]
    }
    @available(iOS 26.0, *) private static func permission(_ value: AlarmManager.AuthorizationState) -> TodoAlarmPermission {
        switch value {
        case .authorized: return .allowed
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        @unknown default: return .denied
        }
    }
}
@available(iOS 26.0, *) private struct TodoAlarmMetadata: AlarmMetadata {let taskID: UUID}
struct TodoExternalRoute: Identifiable, Equatable {let id: UUID}
@MainActor @Observable final class TodoExternalRouter {
    static let shared=TodoExternalRouter()
    var pending: TodoExternalRoute?
    func receive(id: UUID) {pending = .init(id:id)}
}
@available(iOS 26.0, *) struct StopTodoAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource="Stop Todo alarm"
    static var isDiscoverable=false
    @Parameter(title:"Alarm") var requestID: String
    init() {}
    init(requestID: String) {self.requestID=requestID}
    func perform() async throws -> some IntentResult {
        guard let id=UUID(uuidString:requestID) else {throw TodoAlarmFailure.invalidRequest}
        // Stopping the native presentation never changes TodoTask or its event history.
        try AlarmManager.shared.stop(id:id)
        return .result()
    }
}
@available(iOS 26.0, *) struct OpenTodoAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource="Open Todo"
    static var isDiscoverable=false
    static var openAppWhenRun=true
    @Parameter(title:"Todo") var taskID: String
    init() {}
    init(taskID: String) {self.taskID=taskID}
    func perform() async throws -> some IntentResult {
        guard let id=UUID(uuidString:taskID) else {throw TodoAlarmFailure.invalidRequest}
        await MainActor.run {TodoExternalRouter.shared.receive(id:id)}
        return .result()
    }
}

// This helper runs inside TodoReminderCoordinator's existing mutation gate, never a second UN coordinator.
struct TodoIntentTarget: Equatable {
    let id: UUID
    let generation: UUID
    let channel: TodoReminderChannel
    let fireAt: Date?
    let title: String
    let active: Bool
    let seriesID: UUID?
}
private struct TodoDeviceRequest: Equatable {
    let id: UUID
    let taskID: UUID
    let generation: UUID
    let channel: TodoReminderChannel
    let fireAt: Date
    let title: String?
    var phase: TodoReminderDevicePhase
    init(_ value: TodoReminderDeviceRecord) throws {
        guard let channel=TodoReminderChannel(rawValue:value.channelRawValue),let phase=TodoReminderDevicePhase(rawValue:value.phaseRawValue) else {throw TodoAlarmFailure.invalidRequest}
        id=value.id;taskID=value.taskID;generation=value.intentGeneration;self.channel=channel;fireAt=value.fireAt;title=value.requestedTitle;self.phase=phase
    }
    init(target: TodoIntentTarget,fireAt: Date) {
        id=UUID();taskID=target.id;generation=target.generation;channel=target.channel;self.fireAt=fireAt;title=target.title;phase = .ready
    }
    func matches(_ target: TodoIntentTarget?) -> Bool {
        guard let target else {return false}
        return target.active && target.generation == generation && target.channel == channel && target.fireAt == fireAt
    }
}
struct TodoIntentSchedulingResult {
    var states: [UUID:TodoReminderStatus] = [:]
    var stale=false
}
@MainActor final class TodoIntentScheduling {
    static let notificationPrefix=TodoReminderCoordinator.prefix+"intent."
    static let budgetPrefix=TodoReminderCoordinator.prefix+"budget."
    private let notifications: any TodoNotificationClient
    private let alarms: any TodoAlarmClient
    private let now: () -> Date
    private let commit: (ModelContext) throws -> Void
    init(notifications: any TodoNotificationClient,alarms: any TodoAlarmClient,now: @escaping () -> Date,
         commit: @escaping (ModelContext) throws -> Void = {try $0.save()}) {
        self.notifications=notifications;self.alarms=alarms;self.now=now;self.commit=commit
    }
    static func identifier(_ id: UUID) -> String {notificationPrefix+id.uuidString.lowercased()}
    private func targets(_ container: ModelContainer) throws -> [UUID:TodoIntentTarget] {
        let read=ModelContext(container)
        let tasks=Dictionary(uniqueKeysWithValues:try read.fetch(FetchDescriptor<TodoTask>()).map {($0.id,$0)})
        let series=Dictionary(uniqueKeysWithValues:try read.fetch(FetchDescriptor<TodoSeries>()).map {($0.id,$0)})
        var result: [UUID:TodoIntentTarget] = [:]
        for intent in try read.fetch(FetchDescriptor<TodoReminderIntent>()) {
            guard let channel=TodoReminderChannel(rawValue:intent.channelRawValue) else {throw TodoAlarmFailure.invalidRequest}
            guard let task=tasks[intent.id] else {continue}
            let active=task.state == .open && task.remindAt != nil && (task.seriesID.map {series[$0]?.isStopped == false} ?? true)
            result[task.id] = .init(id:task.id,generation:intent.generation,channel:channel,fireAt:task.remindAt,title:task.title,active:active,seriesID:task.seriesID)
        }
        return result
    }
    private func current(_ request: TodoDeviceRequest,_ container: ModelContainer,includingTitle: Bool = true) throws -> Bool {
        let read=ModelContext(container),id=request.taskID
        var query=FetchDescriptor<TodoTask>(predicate:#Predicate {$0.id == id});query.fetchLimit=1
        var intentQuery=FetchDescriptor<TodoReminderIntent>(predicate:#Predicate {$0.id == id});intentQuery.fetchLimit=1
        guard let task=try read.fetch(query).first,task.state == .open,task.remindAt == request.fireAt,
              let intent=try read.fetch(intentQuery).first,intent.generation == request.generation,intent.channelRawValue == request.channel.rawValue else {return false}
        if includingTitle,task.title != request.title {return false}
        if let seriesID=task.seriesID {
            var seriesQuery=FetchDescriptor<TodoSeries>(predicate:#Predicate {$0.id == seriesID});seriesQuery.fetchLimit=1
            guard try read.fetch(seriesQuery).first?.isStopped == false else {return false}
        }
        return true
    }
    private func records(_ container: ModelContainer) throws -> [TodoDeviceRequest] {
        try ModelContext(container).fetch(FetchDescriptor<TodoReminderDeviceRecord>()).map(TodoDeviceRequest.init).sorted {$0.id.uuidString < $1.id.uuidString}
    }
    private func write(_ request: TodoDeviceRequest,_ container: ModelContainer,delete: Bool = false) throws {
        let write=ModelContext(container);write.autosaveEnabled=false
        let id=request.id
        let old=try write.fetch(FetchDescriptor<TodoReminderDeviceRecord>(predicate:#Predicate {$0.id == id})).first
        if let old {
            guard old.taskID == request.taskID,old.intentGeneration == request.generation,old.channelRawValue == request.channel.rawValue,old.fireAt == request.fireAt,old.requestedTitle == request.title else {throw TodoAlarmFailure.invalidRequest}
            if delete {write.delete(old)} else {old.phaseRawValue=request.phase.rawValue}
        } else if !delete {
            write.insert(TodoReminderDeviceRecord(id:request.id,taskID:request.taskID,intentGeneration:request.generation,channel:request.channel,fireAt:request.fireAt,phase:request.phase,requestedTitle:request.title))
        }
        do {try commit(write)} catch {
            // A reported failure after a committed journal write is acknowledged only by exact canonical data.
            let check=try records(container).first {$0.id == request.id}
            guard delete ? check == nil : check == request else {throw error}
        }
    }
    private func present(_ request: TodoDeviceRequest) async throws -> Bool {
        if request.channel == .alarm {return try await alarms.pendingIdentifiers().contains(request.id)}
        return await notifications.pendingIdentifiers().contains(Self.identifier(request.id))
    }
    private func cancel(_ request: TodoDeviceRequest,_ container: ModelContainer,delete: Bool) async -> Bool {
        var pending=request;pending.phase = .cancellationPending
        // Ownership already exists on disk. Even if this phase write fails, still try to stop the owned request.
        do {try write(pending,container)}
        catch TodoAlarmFailure.invalidRequest {return false}
        catch { /* Existing ownership remains available for a verified native cancellation. */ }
        do {
            if try await present(request) {
                do {
                    if request.channel == .alarm {try await alarms.cancel(request.id)}
                    else {notifications.remove([Self.identifier(request.id)])}
                } catch {
                    // An error alone is not proof of cancellation; the following actual absence is required.
                }
                guard try await !present(request) else {return false}
            }
            pending.phase = .retired
            try write(pending,container,delete:delete)
            return true
        } catch {return false}
    }
    private func cancelLegacy(_ id: UUID) async -> Bool {
        let legacy=TodoReminderCoordinator.identifier(id)
        if await notifications.pendingIdentifiers().contains(legacy) {
            notifications.remove([legacy])
            return await !notifications.pendingIdentifiers().contains(legacy)
        }
        return true
    }
    func retireObsoleteRequests(container: ModelContainer,isCurrent: () -> Bool) async throws -> TodoIntentSchedulingResult {
        let desired=try targets(container)
        var result=TodoIntentSchedulingResult(),blocked=Set<UUID>()
        // Retire old identities and confirm absence before attempting any replacement on that task.
        try Task.checkCancellation()
        for record in try records(container) {
            try Task.checkCancellation()
            let target=desired[record.taskID]
            let changedFutureTitle=target?.active == true && record.fireAt > now() && record.title != target?.title
            if !record.matches(target) || record.phase == .cancellationPending || record.phase == .retired || changedFutureTitle {
                let sameGeneration=target?.generation == record.generation
                var existed=false
                do {existed=try await present(record)} catch {blocked.insert(record.taskID);result.states[record.taskID] = .cancellationPending;continue}
                if record.phase == .retired && !existed {
                    if !sameGeneration {do {try write(record,container,delete:true)} catch {blocked.insert(record.taskID);result.states[record.taskID] = .cancellationPending}}
                    continue
                }
                let changedLiveContent=sameGeneration && target?.active == true && (target?.fireAt != record.fireAt || changedFutureTitle) && existed && record.phase != .retired
                let safeTitleReplacement=changedFutureTitle && [.ready,.capacityWaiting,.cancellationPending].contains(record.phase)
                if !(await cancel(record,container,delete:!sameGeneration || changedLiveContent || safeTitleReplacement)) {
                    blocked.insert(record.taskID);result.states[record.taskID] = .cancellationPending
                }
            }
        }
        let blockedSeries=Set(blocked.compactMap {desired[$0]?.seriesID})
        for target in desired.values where target.seriesID.map({blockedSeries.contains($0)}) == true {
            blocked.insert(target.id);result.states[target.id] = .cancellationPending
        }
        if !isCurrent() {result.stale=true;return result}
        return result
    }
    func reconcile(container: ModelContainer,requestNotifications: Bool,requestAlarms: Bool,
                   blockedTaskIDs: Set<UUID> = [],isCurrent: () -> Bool) async throws -> TodoIntentSchedulingResult {
        var result=try await retireObsoleteRequests(container:container,isCurrent:isCurrent)
        if result.stale {return result}
        let desired=try targets(container)
        for id in blockedTaskIDs {result.states[id] = .cancellationPending}
        let blocked=Set(result.states.compactMap {$0.value == .cancellationPending ? $0.key : nil})
        var notificationPermission=await notifications.permission(),alarmPermission=await alarms.permission()
        if !isCurrent() {result.stale=true;return result}
        let active=desired.values.filter {$0.active && ($0.fireAt.map {$0 > now()} ?? false)}
        if notificationPermission == .notDetermined && requestNotifications && active.contains(where: {$0.channel == .notification}) {
            do {notificationPermission=try await notifications.requestPermission() ? .allowed : .denied}
            catch {for target in active where target.channel == .notification {result.states[target.id] = .failed}}
        }
        if alarmPermission == .notDetermined && requestAlarms && active.contains(where: {$0.channel == .alarm}) {
            do {alarmPermission=try await alarms.requestPermission()}
            catch {for target in active where target.channel == .alarm {result.states[target.id] = .failed}}
        }
        if !isCurrent() {result.stale=true;return result}
        try Task.checkCancellation()
        for target in desired.values.sorted(by: {($0.fireAt ?? .distantFuture,$0.id.uuidString) < ($1.fireAt ?? .distantFuture,$1.id.uuidString)}) {
            try Task.checkCancellation()
            if blocked.contains(target.id) {continue}
            guard await cancelLegacy(target.id) else {result.states[target.id] = .cancellationPending;continue}
            guard target.active,let fire=target.fireAt else {result.states[target.id] = TodoReminderStatus.none;continue}
            let same=try records(container).filter {$0.taskID == target.id && $0.generation == target.generation}
            if same.count > 1 {
                for record in same {_ = await cancel(record,container,delete:false)}
                result.states[target.id] = .confirmationRequired;continue
            }
            let permissionUnavailable=target.channel == .alarm ? alarmPermission != .allowed : notificationPermission != .allowed
            if result.states[target.id] == .failed || permissionUnavailable {
                var canceled=true
                for record in same where record.phase != .retired {
                    if !(await cancel(record,container,delete:false)) {canceled=false}
                }
                if !canceled {result.states[target.id] = .cancellationPending}
                else if result.states[target.id] != .failed {
                    if target.channel == .alarm {result.states[target.id] = alarmPermission == .unsupported ? .unsupportedAlarm : alarmPermission == .denied ? .alarmDenied : .alarmPermissionRequired}
                    else {result.states[target.id] = notificationPermission == .denied ? .denied : .permissionRequired}
                }
                continue
            }
            var record=same.first ?? TodoDeviceRequest(target:target,fireAt:fire)
            if record.phase == .retired {result.states[target.id] = fire <= now() ? .elapsed : .stopped;continue}
            if let existing=same.first {
                do {
                    let exists=try await present(existing)
                    if exists {
                        guard try current(record,container,includingTitle:false) else {
                            _ = await cancel(record,container,delete:true);result.stale=true;return result
                        }
                        record.phase = .accepted
                        do {try write(record,container);result.states[target.id] = fire <= now() ? .elapsed : .scheduled}
                        catch {result.states[target.id] = .confirmationRequired}
                        // A current accepted alarm is allowed to ring after its fire time. Never cancel it on refresh.
                        continue
                    }
                    if existing.phase == .prepared || existing.phase == .accepted {
                        record.phase = .retired;try write(record,container)
                        result.states[target.id] = fire <= now() ? .elapsed : existing.phase == .accepted ? .stopped : .confirmationRequired
                        continue
                    }
                } catch {result.states[target.id] = .confirmationRequired;continue}
            }
            guard fire > now() else {result.states[target.id] = .elapsed;continue}
            if !isCurrent() {result.stale=true;return result}
            do {
                guard try current(record,container) else {result.stale=true;return result}
                if target.channel == .notification {
                    let pending=await notifications.pendingIdentifiers()
                    guard pending.count < 60 else {result.states[target.id] = .queueFull;continue}
                }
                if same.isEmpty {try write(record,container)}
                record.phase = .prepared;try write(record,container)
                guard try current(record,container),fire > now() else {result.stale=true;return result}
                do {
                    if target.channel == .alarm {try await alarms.schedule(.init(id:record.id,taskID:target.id,title:target.title,fireAt:fire))}
                    else {try await notifications.add(.init(id:Self.identifier(record.id),taskID:target.id,title:target.title,fireAt:fire))}
                } catch is CancellationError {throw CancellationError()}
                catch TodoAlarmFailure.queueFull {
                    record.phase = .capacityWaiting;try write(record,container)
                    result.states[target.id] = .alarmQueueFull;continue
                } catch {
                    // The attempted request may have been accepted before a transport failure. Keep its identity.
                    guard try current(record,container) else {
                        _ = await cancel(record,container,delete:true);result.stale=true;return result
                    }
                    if try await present(record) {
                        record.phase = .accepted;try write(record,container)
                    }
                    result.states[target.id] = .confirmationRequired
                    continue
                }
                guard try current(record,container) else {
                    if !(await cancel(record,container,delete:true)) {result.states[target.id] = .cancellationPending}
                    result.stale=true;return result
                }
                if try await present(record) {
                    record.phase = .accepted;try write(record,container)
                    result.states[target.id] = fire <= now() ? .elapsed : .scheduled
                } else {
                    record.phase = .retired;try write(record,container)
                    result.states[target.id] = fire <= now() ? .elapsed : .confirmationRequired
                }
            } catch is CancellationError {throw CancellationError()}
            catch {result.states[target.id] = .confirmationRequired}
            if !isCurrent() {result.stale=true;return result}
        }
        return result
    }
}
