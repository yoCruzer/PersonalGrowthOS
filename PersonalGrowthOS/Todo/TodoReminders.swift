import Foundation
import Observation
import OSLog
import SwiftData
import UserNotifications

enum TodoReminderStatus: Equatable {
    case none, checking, scheduled, permissionRequired, denied, failed, queueFull, elapsed
    var label: String {
        switch self {
        case .none: return String(localized: "No reminder")
        case .checking: return String(localized: "Checking reminder…")
        case .scheduled: return String(localized: "Reminder scheduled on this device")
        case .permissionRequired: return String(localized: "Reminder needs notification permission")
        case .denied: return String(localized: "Notifications are disabled in iOS Settings.")
        case .failed: return String(localized: "Reminder could not be scheduled. Retry when the app is active.")
        case .queueFull: return String(localized: "Reminder not queued: device queue is full. It will be retried in the app.")
        case .elapsed: return String(localized: "Reminder time has passed")
        }
    }
}
struct TodoReminderRequest: Equatable {
    let id: String
    let taskID: UUID
    let title: String
    let fireAt: Date
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
        content.title = String(localized: "Todo Reminder"); content.body = request.title; content.sound = .default
        content.userInfo = ["todoTaskID": request.taskID.uuidString]
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
    private var running = false
    private var generation = 0
    private var wantsPermission = false
    private var reconciliationFailed = false
    private var revisions: [UUID: Int] = [:]
    private(set) var statuses: [UUID: TodoReminderStatus] = [:]
    init(client: (any TodoNotificationClient)? = nil, now: @escaping () -> Date = Date.init) {
        self.client = client ?? SystemTodoNotificationClient(); self.now = now
    }
    static func identifier(_ taskID: UUID) -> String { prefix + taskID.uuidString.lowercased() }
    func status(for task: TodoTask) -> TodoReminderStatus {
        guard task.state == .open, task.remindAt != nil else { return .none }
        if reconciliationFailed { return .failed }
        return revisions[task.id] == task.revision ? statuses[task.id] ?? .checking : .checking
    }
    func reconcile(context: ModelContext, requestPermission: Bool = false) async {
        generation += 1; wantsPermission = wantsPermission || requestPermission
        guard !running else { return }
        running = true; defer { running = false }
        while true {
            let pass = generation, explicitPermission = wantsPermission
            do {
                try TodoTaskService(context: context).refreshRepeatingReminderTimes()
                let tasks = try context.fetch(FetchDescriptor<TodoTask>())
                var requests: [(TodoTask, TodoReminderRequest)] = []
                var newStatuses: [UUID: TodoReminderStatus] = [:]
                for task in tasks {
                    guard task.state == .open, let fire = task.remindAt else { newStatuses[task.id] = TodoReminderStatus.none; continue }
                    guard fire > now() else { newStatuses[task.id] = .elapsed; continue }
                    requests.append((task, TodoReminderRequest(id: Self.identifier(task.id), taskID: task.id, title: task.title, fireAt: fire)))
                }
                var permission = await client.permission()
                if pass != generation { continue }
                if permission == .notDetermined && explicitPermission && !requests.isEmpty {
                    wantsPermission = false
                    do { permission = try await client.requestPermission() ? .allowed : .denied }
                    catch {
                        Self.log.error("Notification authorization failed code=\((error as NSError).code, privacy: .public)")
                        requests.forEach { newStatuses[$0.0.id] = .failed }
                    }
                }
                if pass != generation { continue }
                let pending = await client.pendingIdentifiers()
                if pass != generation { continue }
                let wanted = permission == .allowed ? Set(requests.map { $0.1.id }) : []
                client.remove(Array(pending.filter { $0.hasPrefix(Self.prefix) && !wanted.contains($0) }))
                // Conservative queue budget includes other categories, which are never removed here.
                let capacity = max(0, 60 - pending.filter { !$0.hasPrefix(Self.prefix) }.count)
                requests.sort { $0.1.fireAt == $1.1.fireAt ? $0.1.id < $1.1.id : $0.1.fireAt < $1.1.fireAt }
                for (index, pair) in requests.enumerated() {
                    let (task, request) = pair
                    guard permission == .allowed else {
                        if newStatuses[task.id] != .failed { newStatuses[task.id] = permission == .denied ? .denied : .permissionRequired }
                        continue
                    }
                    guard index < capacity else {
                        client.remove([request.id]); newStatuses[task.id] = .queueFull; continue
                    }
                    do { try await client.add(request); newStatuses[task.id] = .scheduled }
                    catch {
                        Self.log.error("Notification scheduling failed code=\((error as NSError).code, privacy: .public)")
                        client.remove([request.id]); newStatuses[task.id] = .failed
                    }
                    if pass != generation { break }
                }
                if pass != generation { continue }
                // Confirm actual pending membership before reporting a successful schedule.
                let confirmed = await client.pendingIdentifiers()
                if pass != generation { continue }
                for (task, request) in requests where newStatuses[task.id] == .scheduled && !confirmed.contains(request.id) {
                    newStatuses[task.id] = .failed
                }
                reconciliationFailed = false
                statuses = newStatuses; revisions = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.revision) })
            } catch {
                // Keep a truthful unresolved status; persistent task data remains intact.
                reconciliationFailed = true
                statuses = [:]; revisions = [:]
                Self.log.error("Todo reconciliation failed code=\((error as NSError).code, privacy: .public)")
            }
            if pass == generation { wantsPermission = false; break }
        }
    }
}
