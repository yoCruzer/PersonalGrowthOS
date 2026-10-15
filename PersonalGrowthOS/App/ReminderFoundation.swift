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
final class LocalReminderScheduler {
    static let dailyIdentifier = "com.yocruzer.PersonalGrowthOS.reminder.daily-recording"
    static let weeklyIdentifier = "com.yocruzer.PersonalGrowthOS.reminder.weekly-review"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationIsDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
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
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return .removed
        }

        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined, requestPermission {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            status = granted ? .authorized : .denied
        }
        try Task.checkCancellation()

        switch status {
        case .authorized, .provisional, .ephemeral:
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: dateComponents,
                    repeats: true
                )
            )
            try Task.checkCancellation()
            let pending = await center.pendingNotificationRequests()
            guard pending.contains(where: { $0.identifier == identifier }) || pending.count < 60 else {
                throw NotificationQueueError.full
            }
            try await center.add(request)
            guard await center.pendingNotificationRequests().contains(where: { $0.identifier == identifier }) else { throw NotificationQueueError.notConfirmed }
            return .scheduled
        case .denied:
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return .permissionDenied
        case .notDetermined:
            return .permissionRequired
        @unknown default:
            return .permissionDenied
        }
    }
}

enum NotificationQueueError: Error { case full, notConfirmed }
