import Foundation
import Observation

struct SleepReminderPreferences: Equatable {
    var enabled = false
    var minute = 540
    static let enabledKey = "sleep.morningReminder.enabled"
    static let minuteKey = "sleep.morningReminder.minute"
    static func load(_ defaults: UserDefaults = .standard) -> Self {
        .init(enabled: defaults.bool(forKey: enabledKey), minute: defaults.object(forKey: minuteKey) as? Int ?? 540)
    }
}
enum SleepReminderPlanner {
    static let prefix = "com.yocruzer.PersonalGrowthOS.sleep."
    static let identity = UUID(uuidString: "016DDA58-A22C-4DCA-A641-753861406279")!
    static func requests(preferences: SleepReminderPreferences, recordedDays: Set<String>, elapsedPlannedDays: Set<String> = [], now: Date, zone: TimeZone) -> [TodoReminderRequest] {
        guard preferences.enabled, (0..<1440).contains(preferences.minute) else { return [] }
        let today = ImportantCivilDay(now, timeZone: zone)
        return (0..<7).compactMap { offset in
            guard let day = today.adding(days: offset), !recordedDays.contains(day.identifier), !elapsedPlannedDays.contains(day.identifier),
                  let fire = day.instant(minutes: preferences.minute, timeZone: zone), fire > now else { return nil }
            return TodoReminderRequest(id: prefix + day.identifier, taskID: identity,
                title: String(localized: "A moment to remember last night's rest."), fireAt: fire, sleepWakeDay: day.identifier)
        }
    }
}

struct SleepExternalRoute: Identifiable, Equatable { let id: String }
@MainActor @Observable final class SleepExternalRouter {
    static let shared = SleepExternalRouter()
    var pending: SleepExternalRoute?
    func receive(day: String) {
        guard ImportantCivilDay(identifier: day) != nil else { return }
        pending = .init(id: day)
    }
}

/// Device scheduling metadata, independent of sleep facts and never restored as notification authorization.
@MainActor final class SleepReminderHistory {
    private let defaults: UserDefaults?
    private let key = "sleep.morningReminder.plannedFires"
    private var fires: [String: Double]
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults; fires = defaults?.dictionary(forKey: key) as? [String: Double] ?? [:]
    }
    func elapsedDays(now: Date) -> Set<String> { Set(fires.filter { $0.value <= now.timeIntervalSinceReferenceDate }.map(\.key)) }
    func confirm(_ requests: [TodoReminderRequest], now: Date) {
        // An elapsed plan cannot be moved into the future to prompt the same day again.
        let elapsed = elapsedDays(now: now)
        for request in requests {
            if let day = request.sleepWakeDay, !elapsed.contains(day) { fires[day] = request.fireAt.timeIntervalSinceReferenceDate }
        }
        defaults?.set(fires, forKey: key)
    }
}

enum SleepWallClock {
    static func pickerDate(minutes: Int, zone: TimeZone) -> Date {
        // A stable ordinary date avoids treating a DST day as 86400 elapsed seconds.
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: minutes / 60, minute: minutes % 60))!
    }
    static func minutes(_ date: Date, zone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
}
