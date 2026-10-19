import Foundation
import UserNotifications
import Observation

enum ReminderScheduleCalculator {
    static func dailyComponents(minutesAfterMidnight: Int) -> DateComponents {
        timeComponents(minutesAfterMidnight: minutesAfterMidnight)
    }

    static func weeklyComponents(
        weekday: Int,
        minutesAfterMidnight: Int
    ) -> DateComponents {
        var components = timeComponents(minutesAfterMidnight: minutesAfterMidnight)
        components.weekday = min(max(weekday, 1), 7)
        return components
    }

    private static func timeComponents(minutesAfterMidnight: Int) -> DateComponents {
        let clampedMinutes = min(max(minutesAfterMidnight, 0), 23 * 60 + 59)
        return DateComponents(
            hour: clampedMinutes / 60,
            minute: clampedMinutes % 60
        )
    }
}

enum ReminderUpdateResult: Equatable {
    case scheduled
    case removed
    case permissionDenied
    case permissionRequired
}

@MainActor
protocol LocalReminderNotificationClient {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func pendingIdentifiers() async -> Set<String>
    func remove(_ identifiers: [String])
    func addRepeating(identifier: String, components: DateComponents, title: String, body: String) async throws
}
@MainActor
final class SystemLocalReminderNotificationClient: LocalReminderNotificationClient {
    private let center: UNUserNotificationCenter
    init(center: UNUserNotificationCenter = .current()) { self.center = center }
    func authorizationStatus() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func pendingIdentifiers() async -> Set<String> { Set(await center.pendingNotificationRequests().map(\.identifier)) }
    func remove(_ identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
    func addRepeating(identifier: String, components: DateComponents, title: String, body: String) async throws {
        let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
        try await center.add(UNNotificationRequest(identifier: identifier, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
    }
}

@MainActor
final class LocalReminderScheduler {
    static let dailyIdentifier = "com.yocruzer.PersonalGrowthOS.reminder.daily-recording"
    static let weeklyIdentifier = "com.yocruzer.PersonalGrowthOS.reminder.weekly-review"

    private let client: any LocalReminderNotificationClient

    init(center: UNUserNotificationCenter = .current(), client: (any LocalReminderNotificationClient)? = nil) {
        self.client = client ?? SystemLocalReminderNotificationClient(center: center)
    }

    func authorizationIsDenied() async -> Bool {
        await client.authorizationStatus() == .denied
    }

    func updateDaily(
        enabled: Bool,
        minutesAfterMidnight: Int,
        requestPermission: Bool
    ) async throws -> ReminderUpdateResult {
        try await update(
            identifier: Self.dailyIdentifier,
            enabled: enabled,
            dateComponents: ReminderScheduleCalculator.dailyComponents(
                minutesAfterMidnight: minutesAfterMidnight
            ),
            title: String(localized: "A moment to record today"),
            body: String(localized: "Save a thought or photo while it is still fresh."),
            requestPermission: requestPermission
        )
    }

    func updateWeekly(
        enabled: Bool,
        weekday: Int,
        minutesAfterMidnight: Int,
        requestPermission: Bool
    ) async throws -> ReminderUpdateResult {
        try await update(
            identifier: Self.weeklyIdentifier,
            enabled: enabled,
            dateComponents: ReminderScheduleCalculator.weeklyComponents(
                weekday: weekday,
                minutesAfterMidnight: minutesAfterMidnight
            ),
            title: String(localized: "Weekly Review"),
            body: String(localized: "Look back on your week and choose one focus for the next."),
            requestPermission: requestPermission
        )
    }

    /// The caller's ticket is checked inside the shared mutation gate, including
    /// after the native query yields. An old failure cannot delete a later intent.
    func removeAfterFailure(weekly:Bool,isCurrent: @escaping @MainActor () -> Bool) async -> Bool {
        await NotificationMutationGate.shared.acquire()
        defer {NotificationMutationGate.shared.release()}
        guard isCurrent() else {return false}
        let identifier=weekly ? Self.weeklyIdentifier:Self.dailyIdentifier
        _ = await client.pendingIdentifiers()
        guard isCurrent() else {return false}
        client.remove([identifier])
        let absent = await !client.pendingIdentifiers().contains(identifier)
        return isCurrent() && absent
    }

    private func update(
        identifier: String,
        enabled: Bool,
        dateComponents: DateComponents,
        title: String,
        body: String,
        requestPermission: Bool
    ) async throws -> ReminderUpdateResult {
        await NotificationMutationGate.shared.acquire()
        defer { NotificationMutationGate.shared.release() }
        guard enabled else {
            client.remove([identifier])
            guard await !client.pendingIdentifiers().contains(identifier) else {throw NotificationQueueError.notConfirmed}
            return .removed
        }

        var status = await client.authorizationStatus()
        if status == .notDetermined, requestPermission {
            let granted = try await client.requestAuthorization()
            status = granted ? .authorized : .denied
        }
        try Task.checkCancellation()

        switch status {
        case .authorized, .provisional, .ephemeral:
            try Task.checkCancellation()
            let pending = await client.pendingIdentifiers()
            guard pending.contains(identifier) || pending.count < 60 else { throw NotificationQueueError.full }
            try Task.checkCancellation()
            try await client.addRepeating(identifier: identifier, components: dateComponents, title: title, body: body)
            guard await client.pendingIdentifiers().contains(identifier) else { throw NotificationQueueError.notConfirmed }
            return .scheduled
        case .denied:
            client.remove([identifier])
            guard await !client.pendingIdentifiers().contains(identifier) else {throw NotificationQueueError.notConfirmed}
            return .permissionDenied
        case .notDetermined:
            client.remove([identifier])
            guard await !client.pendingIdentifiers().contains(identifier) else {throw NotificationQueueError.notConfirmed}
            return .permissionRequired
        @unknown default:
            client.remove([identifier])
            guard await !client.pendingIdentifiers().contains(identifier) else {throw NotificationQueueError.notConfirmed}
            return .permissionDenied
        }
    }
}

enum NotificationQueueError: Error { case full, notConfirmed }

/// Owns the settings result boundary, separately from the system mutation gate.
/// A canceled transport may still return an ordinary error or success.
@MainActor
final class ReminderSettingsIntents {
    let daily=ReminderSettingsUpdate.Scope()
    let weekly=ReminderSettingsUpdate.Scope()
}

@MainActor
final class ReminderSettingsUpdate {
    /// Root-owned tickets survive sheet removal; a new same-value request is a new intent.
    @Observable final class Scope {
        var failureMessage:String?
        var cleanupPending=false
        var generation=UUID()
        var task: Task<Void,Never>?
    }
    private let scope: Scope
    init(scope: Scope = Scope()) {self.scope=scope}
    @discardableResult func submit(
        operation: @escaping @MainActor () async throws -> ReminderUpdateResult,
        isCurrent: @escaping @MainActor () -> Bool = {true},
        recover: (@MainActor (@escaping @MainActor () -> Bool) async -> Bool)? = nil,
        apply: @escaping @MainActor (Result<ReminderUpdateResult,Error>) -> Void
    ) -> Task<Void,Never> {
        scope.task?.cancel()
        let token=UUID();scope.generation=token
        let next=Task { @MainActor in
            let result: Result<ReminderUpdateResult,Error>
            do {result = .success(try await operation())}
            catch {result = .failure(error)}
            guard !Task.isCancelled,self.scope.generation == token,isCurrent() else {return}
            if case .failure(let error)=result,error is CancellationError,recover == nil {return}
            if case .failure=result,let recover {
                let confirmed=await recover {!Task.isCancelled && self.scope.generation == token && isCurrent()}
                guard !Task.isCancelled,self.scope.generation == token,isCurrent() else {return}
                self.scope.cleanupPending = !confirmed
                self.scope.failureMessage = confirmed
                    ? String(localized:"The reminder could not be updated. Please try again.")
                    : String(localized:"Reminder removal is not confirmed. Please try again.")
            } else if case .success(let value)=result {
                self.scope.cleanupPending=false
                if value != .removed {self.scope.failureMessage=nil}
            }
            apply(result)
        }
        scope.task=next
        #if DEBUG
        ReminderSettingsUpdateProbe.didSubmit?(scope)
        #endif
        return next
    }
}

#if DEBUG
@MainActor enum ReminderSettingsUpdateProbe {
    static var didSubmit: ((ReminderSettingsUpdate.Scope) -> Void)?
}
#endif
