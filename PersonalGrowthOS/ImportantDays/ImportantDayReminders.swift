import Foundation
import SwiftData

/// The same serial boundary is used by Todo/day batches and daily/weekly settings.
@MainActor
final class NotificationMutationGate {
    static let shared = NotificationMutationGate()
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func acquire() async {
        if !locked { locked = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        if waiters.isEmpty { locked = false } else { waiters.removeFirst().resume() }
    }
}

struct ImportantDayReminderState: Equatable {
    var status: TodoReminderStatus
    var nextFire: Date?
    var coverageEnd: Date?
    var scheduledCount = 0
}
enum ImportantDayReminderPlanner {
    static let prefix = "com.yocruzer.PersonalGrowthOS.important-day."
    /// Bounded two occurrences, up to two offsets each; actual coverage is shown after pending verification.
    static func requests(id: UUID, title: String, rule: ImportantDayDateRule, preferences: ImportantDayPreferences,
                         now: Date, timeZone: TimeZone) throws -> [TodoReminderRequest] {
        try rule.validate(); try preferences.validate()
        guard !preferences.reminderOffsets.isEmpty else { return [] }
        let today = ImportantCivilDay(now, timeZone: timeZone)
        guard ImportantDayDateEngine.years.contains(today.year) else { throw ImportantDayDateError.unsupportedRange }
        var occurrences: [ImportantCivilDay] = []
        if rule.preset == .anniversary {
            for year in max(1901, today.year - 1, rule.year ?? 1901)...2100 {
                if let date = try ImportantDayDateEngine.occurrence(rule, in: year), date >= today {
                    occurrences.append(date); if occurrences.count == 2 { break }
                }
            }
        } else if let year = rule.year, let date = try ImportantDayDateEngine.original(rule, in: year) { occurrences = [date] }
        if rule.preset == .anniversary && occurrences.isEmpty { throw ImportantDayDateError.unsupportedRange }
        var result: [TodoReminderRequest] = []
        for occurrence in occurrences {
            for offset in preferences.reminderOffsets {
                guard let day = occurrence.adding(days: -offset),
                      let fire = day.instant(minutes: preferences.reminderMinutes, timeZone: timeZone), fire > now else { continue }
                let identifier = prefix + id.uuidString.lowercased() + "." + occurrence.identifier + "." + String(offset)
                let body = preferences.genericNotification ? String(localized: "An important day is approaching. Open the app to view it.") : title
                result.append(TodoReminderRequest(id: identifier, taskID: id, title: body, fireAt: fire, importantDayID: id))
            }
        }
        return result.sorted { $0.fireAt == $1.fireAt ? $0.id < $1.id : $0.fireAt < $1.fireAt }
    }
}
