import Foundation
import UserNotifications

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
            return .permissionDenied
        case .notDetermined:
            return .permissionRequired
        @unknown default:
            return .permissionDenied
        }
    }
}

enum NotificationQueueError: Error { case full, notConfirmed }

/// Owns the settings result boundary, separately from the system mutation gate.
/// A canceled transport may still return an ordinary error or success.
@MainActor
final class ReminderSettingsUpdate {
    private var generation=UUID()
    private var task: Task<Void,Never>?
    @discardableResult func submit(
        operation: @escaping @MainActor () async throws -> ReminderUpdateResult,
        isCurrent: @escaping @MainActor () -> Bool = {true},
        apply: @escaping @MainActor (Result<ReminderUpdateResult,Error>) -> Void
    ) -> Task<Void,Never> {
        task?.cancel()
        let token=UUID();generation=token
        let next=Task { @MainActor in
            let result: Result<ReminderUpdateResult,Error>
            do {result = .success(try await operation())}
            catch {result = .failure(error)}
            guard !Task.isCancelled,self.generation == token,isCurrent() else {return}
            if case .failure(let error)=result,error is CancellationError {return}
            apply(result)
        }
        task=next;return next
    }
}
