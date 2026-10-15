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
    static func requests(preferences: SleepReminderPreferences, recordedDays: Set<String>, now: Date, zone: TimeZone) -> [TodoReminderRequest] {
        guard preferences.enabled, (0..<1440).contains(preferences.minute) else { return [] }
        let today = ImportantCivilDay(now, timeZone: zone)
        return (0..<7).compactMap { offset in
            guard let day = today.adding(days: offset), !recordedDays.contains(day.identifier),
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
