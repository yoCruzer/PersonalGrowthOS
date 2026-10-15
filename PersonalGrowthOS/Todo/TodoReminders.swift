import Foundation
import Observation
import OSLog
import SwiftData
import UserNotifications

enum TodoReminderStatus: Equatable {
    case none, checking, scheduled, permissionRequired, denied, failed, queueFull, elapsed, unsupportedDateRange
    var label: String {
        switch self {
        case .none: return String(localized: "No reminder")
        case .checking: return String(localized: "Checking reminder…")
        case .scheduled: return String(localized: "Reminder scheduled on this device")
        case .permissionRequired: return String(localized: "Reminder needs notification permission")
        case .denied: return String(localized: "Notifications are disabled in iOS Settings.")
        case .failed: return String(localized: "Reminder could not be scheduled. Retry when the app is active.")
        case .queueFull: return String(localized: "Reminder not queued: device queue is full. It will be retried in the app.")
        case .unsupportedDateRange: return String(localized: "No next anniversary within the supported date range")
        case .elapsed: return String(localized: "Reminder time has passed")
        }
    }
}
struct TodoReminderRequest: Equatable {
    let id: String
    let taskID: UUID
    let title: String
    let fireAt: Date
    var importantDayID: UUID? = nil
    var sleepWakeDay: String? = nil
}
enum TodoNotificationPermission { case allowed, notDetermined, denied }
@MainActor
protocol TodoNotificationClient {
    func permission() async -> TodoNotificationPermission
    func requestPermission() async throws -> Bool
    func pendingIdentifiers() async -> Set<String>
    func remove(_ identifiers: [String])
    func add(_ request: TodoReminderRequest) async throws
}
@MainActor
final class SystemTodoNotificationClient: TodoNotificationClient {
    private let center: UNUserNotificationCenter
    init(center: UNUserNotificationCenter = .current()) { self.center = center }
    func permission() async -> TodoNotificationPermission {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PGOSUITesting"), ProcessInfo.processInfo.arguments.contains("-PGOSTodoReminderDeniedTest") { return .denied }
        #endif
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }
    func requestPermission() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func pendingIdentifiers() async -> Set<String> { Set(await center.pendingNotificationRequests().map(\.identifier)) }
    func remove(_ identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
    func add(_ request: TodoReminderRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.importantDayID == nil ? String(localized: "Todo Reminder") : String(localized: "Important Day")
        if request.sleepWakeDay != nil { content.title = String(localized: "Sleep and Routine") }
        content.body = request.title; content.sound = .default
        if let wakeDay = request.sleepWakeDay { content.userInfo = ["sleepWakeDay": wakeDay] }
        else if let dayID = request.importantDayID { content.userInfo = ["importantDayID": dayID.uuidString] }
        else { content.userInfo = ["todoTaskID": request.taskID.uuidString] }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: request.fireAt)
        components.calendar = calendar; components.timeZone = calendar.timeZone
        try await center.add(UNNotificationRequest(identifier: request.id, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
    }
}

@MainActor @Observable
final class TodoReminderCoordinator {
    static let prefix = "com.yocruzer.PersonalGrowthOS.todo."
    private static let log = Logger(subsystem: "com.yocruzer.PersonalGrowthOS", category: "TodoReminders")
    private let client: any TodoNotificationClient
    private let now: () -> Date
    private let sleepHistory: SleepReminderHistory
    private let sleepPreferences: () -> SleepReminderPreferences
    private(set) var sleepState = ImportantDayReminderState(status: .none)
    private var confirmedSleepPreferences: SleepReminderPreferences?
    func sleepStatus() -> ImportantDayReminderState {
        guard sleepPreferences().enabled else { return .init(status: .none) }
        if reconciliationFailed { return .init(status: .failed) }
        return confirmedSleepPreferences == sleepPreferences() ? sleepState : .init(status: .checking)
    }
    private var running = false
    private var generation = 0
    private var wantsPermission = false
    private var reconciliationFailed = false
    private var revisions: [UUID: Int] = [:]
    var savedImportantDayID: UUID?
    var savedTaskID: UUID?
    func reportSavedTask(_ task: TodoTask, affectedOpenSuccessor: TodoTask? = nil) {
        let candidate = task.state == .open ? task : affectedOpenSuccessor
        savedTaskID = candidate.flatMap {
            guard $0.state == .open, $0.remindAt != nil,
                  $0.id == task.id || (task.seriesID != nil && $0.seriesID == task.seriesID) else { return nil }
            return $0.id
        }
    }
    private(set) var statuses: [UUID: TodoReminderStatus] = [:]
    private(set) var importantDayStates: [UUID: ImportantDayReminderState] = [:]
    private var dayRevisions: [UUID: Data] = [:]
    func status(for day: ImportantDay) -> ImportantDayReminderState {
        guard !day.isArchived, let p = try? day.preferences(), !p.reminderOffsets.isEmpty else { return .init(status: .none) }
        if reconciliationFailed { return .init(status: .failed) }
        return dayRevisions[day.id] == day.ruleData + day.preferencesData ? importantDayStates[day.id] ?? .init(status: .checking) : .init(status: .checking)
    }
    init(client: (any TodoNotificationClient)? = nil, now: @escaping () -> Date = Date.init, sleepPreferences: @escaping () -> SleepReminderPreferences = { .load() }, sleepHistory: SleepReminderHistory? = nil) {
        self.client = client ?? SystemTodoNotificationClient(); self.now = now; self.sleepPreferences = sleepPreferences; self.sleepHistory = sleepHistory ?? SleepReminderHistory()
    }
    static func identifier(_ taskID: UUID) -> String { prefix + taskID.uuidString.lowercased() }
    func status(for task: TodoTask) -> TodoReminderStatus {
        guard task.state == .open, task.remindAt != nil else { return .none }
        if reconciliationFailed { return .failed }
        return revisions[task.id] == task.revision ? statuses[task.id] ?? .checking : .checking
    }
    func reconcile(context: ModelContext, requestPermission: Bool = false) async {
        generation += 1; wantsPermission = wantsPermission || requestPermission
        if sleepPreferences().enabled { sleepState.status = .checking }
        guard !running else { return }
        running = true; defer { running = false }
        await NotificationMutationGate.shared.acquire()
        defer { NotificationMutationGate.shared.release() }
        while true {
            let pass = generation, explicitPermission = wantsPermission
            do {
                try TodoTaskService(context: context).refreshRepeatingReminderTimes()
                let tasks = try context.fetch(FetchDescriptor<TodoTask>())
                let days = try context.fetch(FetchDescriptor<ImportantDay>())
                var requests: [TodoReminderRequest] = []
                var newStatuses: [UUID: TodoReminderStatus] = [:]
                var dayStates: [UUID: ImportantDayReminderState] = [:]
                for task in tasks {
                    guard task.state == .open, let fire = task.remindAt else { newStatuses[task.id] = TodoReminderStatus.none; continue }
                    guard fire > now() else { newStatuses[task.id] = .elapsed; continue }
                    requests.append(TodoReminderRequest(id: Self.identifier(task.id), taskID: task.id, title: task.title, fireAt: fire))
                }
                for day in days {
                    guard !day.isArchived else { dayStates[day.id] = .init(status: .none); continue }
                    do {
                        let p = try day.preferences()
                        guard !p.reminderOffsets.isEmpty else { dayStates[day.id] = .init(status: .none); continue }
                        let planned = try ImportantDayReminderPlanner.requests(id: day.id, title: day.title, rule: day.rule(), preferences: p, now: now(), timeZone: .current)
                        dayStates[day.id] = .init(status: planned.isEmpty ? .elapsed : .checking)
                        requests += planned
                    } catch ImportantDayDateError.unsupportedRange { dayStates[day.id] = .init(status: .unsupportedDateRange) }
                    catch { dayStates[day.id] = .init(status: .failed) }
                }
                let sleepSettings = sleepPreferences()
                let sleepRecords = try ModelContext(context.container).fetch(FetchDescriptor<SleepRecord>())
                let sleepRequests = SleepReminderPlanner.requests(preferences: sleepSettings, recordedDays: Set(sleepRecords.map(\.wakeDay)), elapsedPlannedDays: sleepHistory.elapsedDays(now: now()), now: now(), zone: .current)
                requests += sleepRequests
                var permission = await client.permission()
                if pass != generation { continue }
                var authorizationFailed = false
                if permission == .notDetermined && explicitPermission && !requests.isEmpty {
                    wantsPermission = false
                    do { permission = try await client.requestPermission() ? .allowed : .denied }
                    catch { authorizationFailed = true; Self.log.error("Notification authorization failed code=\((error as NSError).code, privacy: .public)") }
                }
                if pass != generation { continue }
                let pending = await client.pendingIdentifiers()
                if pass != generation { continue }
                func managed(_ id: String) -> Bool { id.hasPrefix(Self.prefix) || id.hasPrefix(ImportantDayReminderPlanner.prefix) || id.hasPrefix(SleepReminderPlanner.prefix) }
                // Daily/weekly and unknown third-party requests are reserved and never removed by this batch.
                let capacity = max(0, 60 - pending.filter { !managed($0) }.count)
                requests.sort { $0.fireAt == $1.fireAt ? $0.id < $1.id : $0.fireAt < $1.fireAt }
                // When sleep participates, each nonempty category gets a turn in earliest-fire order.
                // With sleep disabled the existing Todo/day chronology is unchanged.
                var allocation = requests
                if !sleepRequests.isEmpty {
                    var groups = [requests.filter { $0.sleepWakeDay != nil }, requests.filter { $0.importantDayID != nil }, requests.filter { $0.sleepWakeDay == nil && $0.importantDayID == nil }].filter { !$0.isEmpty }
                    groups.sort { $0[0].fireAt == $1[0].fireAt ? $0[0].id < $1[0].id : $0[0].fireAt < $1[0].fireAt }
                    allocation = []
                    while groups.contains(where: { !$0.isEmpty }) {
                        for index in groups.indices where !groups[index].isEmpty { allocation.append(groups[index].removeFirst()) }
                    }
                }
                let selected = permission == .allowed && !authorizationFailed ? Set(allocation.prefix(capacity).map(\.id)) : []
                let removedIdentifiers = pending.filter { managed($0) && !selected.contains($0) }
                client.remove(Array(removedIdentifiers))
                if !removedIdentifiers.isEmpty {
                    // Confirm before slow adds can cross the old fire time. An absence observed
                    // only after expiry is conservatively elapsed, not proof of early cancellation.
                    let remaining = await client.pendingIdentifiers()
                    sleepHistory.confirmCancellation(removedIdentifiers.subtracting(remaining), now: now())
                    if pass != generation { continue }
                }
                var failedRemovals: Set<String> = []
                var elapsedReplacements: Set<String> = []
                var requestStatuses: [String: TodoReminderStatus] = [:]
                for request in requests {
                    guard permission == .allowed && !authorizationFailed else {
                        requestStatuses[request.id] = authorizationFailed ? .failed : permission == .denied ? .denied : .permissionRequired
                        continue
                    }
                    guard selected.contains(request.id) else { requestStatuses[request.id] = .queueFull; continue }
                    do {
                        try await client.add(request)
                        let acceptedAt = now()
                        sleepHistory.confirm([request], now: acceptedAt)
                        requestStatuses[request.id] = .scheduled
                        if let day = request.sleepWakeDay, request.fireAt > acceptedAt,
                           sleepHistory.elapsedDays(now: acceptedAt).contains(day) {
                            // Replacement success arrived after an older accepted fire elapsed.
                            // Do not claim delivery, or leave a later same-day prompt pending.
                            client.remove([request.id]); elapsedReplacements.insert(request.id)
                            requestStatuses[request.id] = .elapsed
                        }
                    }
                    catch {
                        Self.log.error("Notification scheduling failed code=\((error as NSError).code, privacy: .public)")
                        client.remove([request.id]); failedRemovals.insert(request.id); requestStatuses[request.id] = .failed
                        let remaining = await client.pendingIdentifiers()
                        if !remaining.contains(request.id) { sleepHistory.confirmCancellation([request.id], now: now()) }
                    }
                    if pass != generation { break }
                }
                // Cancellation is already a system mutation. Confirm and retain that evidence even
                // when a newer generation interrupted add; only status publication stays generation-gated.
                let confirmed = await client.pendingIdentifiers()
                let checkedAt = now()
                let missingFuture = Set(requests.filter { requestStatuses[$0.id] == .scheduled && !confirmed.contains($0.id) && $0.fireAt > checkedAt }.map(\.id))
                sleepHistory.confirmCancellation(removedIdentifiers.union(failedRemovals).union(missingFuture).subtracting(confirmed), now: checkedAt)
                if pass != generation { continue }
                for request in requests where requestStatuses[request.id] == .scheduled {
                    if request.fireAt <= checkedAt { requestStatuses[request.id] = .elapsed }
                    else if !confirmed.contains(request.id) { requestStatuses[request.id] = .failed }
                }
                for id in elapsedReplacements where confirmed.contains(id) { requestStatuses[id] = .failed }
                for request in requests where request.importantDayID == nil && request.sleepWakeDay == nil { newStatuses[request.taskID] = requestStatuses[request.id] }
                for day in days {
                    let planned = requests.filter { $0.importantDayID == day.id }
                    guard !planned.isEmpty else { continue }
                    let scheduled = planned.filter { requestStatuses[$0.id] == .scheduled }.map(\.fireAt).sorted()
                    let states = planned.compactMap { requestStatuses[$0.id] }
                    // Partial capacity/failure is not called a fully scheduled reminder preference.
                    let status: TodoReminderStatus = states.contains(.failed) ? .failed : states.contains(.denied) ? .denied : states.contains(.permissionRequired) ? .permissionRequired : states.contains(.queueFull) ? .queueFull : scheduled.isEmpty ? .elapsed : .scheduled
                    dayStates[day.id] = .init(status: status, nextFire: scheduled.first, coverageEnd: scheduled.last, scheduledCount: scheduled.count)
                }
                let sleepScheduled = sleepRequests.filter { requestStatuses[$0.id] == .scheduled }.map(\.fireAt).sorted()
                let sleepStatuses = sleepRequests.compactMap { requestStatuses[$0.id] }
                let sleepStatus: TodoReminderStatus = !sleepSettings.enabled ? .none : sleepRequests.isEmpty ? .elapsed : sleepStatuses.contains(.failed) ? .failed : sleepStatuses.contains(.denied) ? .denied : sleepStatuses.contains(.permissionRequired) ? .permissionRequired : sleepStatuses.contains(.queueFull) ? .queueFull : sleepScheduled.isEmpty ? .elapsed : .scheduled
                sleepState = .init(status: sleepStatus, nextFire: sleepScheduled.first, coverageEnd: sleepScheduled.last, scheduledCount: sleepScheduled.count)
                confirmedSleepPreferences = sleepSettings
                reconciliationFailed = false
                statuses = newStatuses; revisions = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.revision) })
                importantDayStates = dayStates; dayRevisions = Dictionary(uniqueKeysWithValues: days.map { ($0.id, $0.ruleData + $0.preferencesData) })
            } catch {
                reconciliationFailed = true; statuses = [:]; revisions = [:]; importantDayStates = [:]; dayRevisions = [:]
                Self.log.error("Reminder reconciliation failed code=\((error as NSError).code, privacy: .public)")
            }
            if pass == generation { wantsPermission = false; break }
        }
    }
}
