// Read-only review probe for PersonalGrowthOS PR #11, product SHA:
// 138616cd0970b0f4fba9d0c7d7d44f6ca7d30b53
// Runs on Foundation (Linux/macOS). NOT the iOS test suite.
// timing(), goal semantic functions, and calendar functions below are transcribed
// from the fixed production source. SwiftData models are replaced only by DTOs.
// It does NOT prove SwiftUI lifecycle, SwiftData migrations or notification delivery.
import Foundation

struct ImportantCivilDay: Codable, Hashable, Comparable, Sendable {
    var year: Int
    var month: Int
    var day: Int
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
    static var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c
    }
    var date: Date? {
        let c = Self.utcCalendar
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              let d = c.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              c.component(.year, from: d) == year, c.component(.month, from: d) == month,
              c.component(.day, from: d) == day else { return nil }
        return d
    }
    init(year: Int, month: Int, day: Int) { self.year = year; self.month = month; self.day = day }
    init(_ date: Date, timeZone: TimeZone = .current) {
        var c = Self.utcCalendar; c.timeZone = timeZone
        let p = c.dateComponents([.year, .month, .day], from: date)
        self.init(year: p.year!, month: p.month!, day: p.day!)
    }
    func adding(days: Int) -> Self? {
        guard let date, let next = Self.utcCalendar.date(byAdding: .day, value: days, to: date) else { return nil }
        return Self(next, timeZone: TimeZone(secondsFromGMT: 0)!)
    }
    func distance(to other: Self) -> Int? {
        guard let a = date, let b = other.date else { return nil }
        return Self.utcCalendar.dateComponents([.day], from: a, to: b).day
    }
    func instant(minutes: Int, timeZone: TimeZone) -> Date? {
        guard date != nil, (0..<1440).contains(minutes) else { return nil }
        var c = Self.utcCalendar; c.timeZone = timeZone
        guard let start = c.date(from: DateComponents(year: year, month: month, day: day)),
              let result = c.nextDate(after: start.addingTimeInterval(-1), matching: DateComponents(hour: minutes / 60, minute: minutes % 60), matchingPolicy: .nextTime, repeatedTimePolicy: .first),
              ImportantCivilDay(result, timeZone: timeZone) == self else { return nil }
        return result
    }
    var identifier: String { String(format: "%04d-%02d-%02d", year, month, day) }
}
extension ImportantCivilDay {
    init?(identifier: String) {
        let parts = identifier.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        self.init(year: y, month: m, day: d)
        guard date != nil, self.identifier == identifier, (1901...2100).contains(y) else { return nil }
    }
}
enum SleepFieldTiming: String, CaseIterable {
    case sameDay, nextDay, recalled, unknown
    var included: Bool { self == .sameDay || self == .nextDay }
}
enum SleepRules {
    static func timing(_ stamp: Date?, day: String, zone: TimeZone, now: Date = Date()) -> SleepFieldTiming {
        guard let stamp, stamp <= now, let civil = ImportantCivilDay(identifier: day) else { return .unknown }
        let filled = ImportantCivilDay(stamp, timeZone: zone)
        guard filled >= civil else { return .unknown }
        if filled == civil { return .sameDay }
        if filled == civil.adding(days: 1) { return .nextDay }
        return .recalled
    }
}
let zone = TimeZone(identifier: "Asia/Shanghai")!
let day = ImportantCivilDay(identifier: "2026-10-15")!
let opened = day.instant(minutes: 480, timeZone: zone)!
let initialFill = opened.addingTimeInterval(-60)
let editSaved = opened.addingTimeInterval(60)
let actualAfterSave = editSaved.addingTimeInterval(1)
let control = SleepRules.timing(initialFill, day: day.identifier, zone: zone, now: opened)
let stale = SleepRules.timing(editSaved, day: day.identifier, zone: zone, now: opened)
let fresh = SleepRules.timing(editSaved, day: day.identifier, zone: zone, now: actualAfterSave)
print("R1 normal edit with no clock rollback:")
print("  before edit, initial filling evidence: \(control.rawValue), included=\(control.included)")
print("  after edit, cached review reference:   \(stale.rawValue), included=\(stale.included)")
print("  after edit, actual current reference:  \(fresh.rawValue), included=\(fresh.included)")
precondition(control == .sameDay && stale == .unknown && fresh == .sameDay)
let next = day.adding(days: 1)!
let lateFill = next.instant(minutes: 480, timeZone: zone)!
let later = day.adding(days: 3)!.instant(minutes: 480, timeZone: zone)!
precondition(SleepRules.timing(lateFill, day: day.identifier, zone: zone, now: later) == .nextDay)
precondition(SleepRules.timing(later, day: day.identifier, zone: zone, now: later) == .recalled)
precondition(SleepRules.timing(nil, day: day.identifier, zone: zone, now: later) == .unknown)
print("  controls: next-day / recalled / unknown classifications preserved")

// Goal DTO is the persisted production fields read by SleepGoalSemantics;
// it deliberately does not pretend to be a SwiftData persistent model.
final class SleepGoalRule {
    var effectiveDay: String; var cutoffMinute: Int?; var hasTakenEffect: Bool
    var observationTimeZoneID: String
    init(_ day: String, _ cutoff: Int?, active: Bool, zone: TimeZone) {
        effectiveDay = day; cutoffMinute = cutoff; hasTakenEffect = active
        observationTimeZoneID = zone.identifier
    }
}
enum SleepGoalSemantics {
    static func isEffective(_ rule: SleepGoalRule, now: Date, zone: TimeZone) -> Bool {
        rule.hasTakenEffect || rule.effectiveDay <= ImportantCivilDay(now, timeZone: zone).identifier ||
        TimeZone(identifier: rule.observationTimeZoneID).map { rule.effectiveDay <= ImportantCivilDay(now, timeZone: $0).identifier } == true
    }
    static func proposedDay(rules: [SleepGoalRule], now: Date, zone: TimeZone) -> ImportantCivilDay {
        let today = ImportantCivilDay(now, timeZone: zone)
        guard !rules.isEmpty else { return today }
        let lastActive = rules.filter { isEffective($0, now: now, zone: zone) }.compactMap { ImportantCivilDay(identifier: $0.effectiveDay) }.max()
        return max(today.adding(days: 1)!, lastActive?.adding(days: 1) ?? today)
    }
}
// R2: no-op goal save observation: Save while already disabled
// is wired to setGoal(nil), which inserts today's nil rule into an empty store.
let first = SleepGoalSemantics.proposedDay(rules: [], now: opened, zone: zone)
let disabled = SleepGoalRule(day.identifier, nil, active: true, zone: zone)
let afterDisabledSave = SleepGoalSemantics.proposedDay(rules: [disabled], now: opened, zone: zone)
print("R2 no-op goal save observation:")
print("  first activation without an off-rule: \(first.identifier)")
print("  first activation after saving an already-off goal: \(afterDisabledSave.identifier)")
precondition(first == day && afterDisabledSave == next)

// The following planner/history and reconciliation-tail statements are from
// SleepReminders.swift and TodoReminders.swift at the fixed product SHA.
// Localization and @MainActor are omitted only for this synchronous probe.
struct TodoReminderRequest: Equatable {
    let id: String; let taskID: UUID; let title: String; let fireAt: Date
    var importantDayID: UUID? = nil
    var sleepWakeDay: String? = nil
}
struct SleepReminderPreferences: Equatable {
    var enabled = false
    var minute = 540
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
                title: "A moment to remember last night's rest.", fireAt: fire, sleepWakeDay: day.identifier)
        }
    }
}
final class SleepReminderHistory {
    private let defaults: UserDefaults?
    private let key = "sleep.morningReminder.plannedFires"
    private var fires: [String: Double]
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults; fires = defaults?.dictionary(forKey: key) as? [String: Double] ?? [:]
    }
    func elapsedDays(now: Date) -> Set<String> { Set(fires.filter { $0.value <= now.timeIntervalSinceReferenceDate }.map(\.key)) }
    func confirmCancellation(_ identifiers: Set<String>, now: Date) {
        for identifier in identifiers where identifier.hasPrefix(SleepReminderPlanner.prefix) {
            let day = String(identifier.dropFirst(SleepReminderPlanner.prefix.count))
            if let fire = fires[day], fire > now.timeIntervalSinceReferenceDate { fires.removeValue(forKey: day) }
        }
        defaults?.set(fires, forKey: key)
    }
    func confirm(_ requests: [TodoReminderRequest], now: Date) {
        let elapsed = elapsedDays(now: now)
        for request in requests {
            if let day = request.sleepWakeDay, !elapsed.contains(day) { fires[day] = request.fireAt.timeIntervalSinceReferenceDate }
        }
        defaults?.set(fires, forKey: key)
    }
}
enum RequestStatus { case scheduled, failed }
let beforeFire = day.instant(minutes: 540, timeZone: zone)!.addingTimeInterval(-1)
let afterFire = beforeFire.addingTimeInterval(2)
let todayID = SleepReminderPlanner.prefix + day.identifier
let initialRequests = SleepReminderPlanner.requests(preferences: .init(enabled: true, minute: 540), recordedDays: [], now: beforeFire, zone: zone)
precondition(initialRequests.count == 7)
let history = SleepReminderHistory(defaults: nil)
// All seven add calls have succeeded. The OS delivered today's request between
// its successful add and the end-of-batch pending query. No cancellation/failure.
var requestStatuses = Dictionary(uniqueKeysWithValues: initialRequests.map { ($0.id, RequestStatus.scheduled) })
let confirmed = Set(initialRequests.map(\.id)).subtracting([todayID])
let removedIdentifiers: Set<String> = []
// Verbatim relevant control-flow from TodoReminders.swift 202–207, 216:
history.confirmCancellation(removedIdentifiers.subtracting(confirmed), now: afterFire)
history.confirm(initialRequests.filter { confirmed.contains($0.id) && requestStatuses[$0.id] == .scheduled }, now: afterFire)
for request in initialRequests where requestStatuses[request.id] == .scheduled && !confirmed.contains(request.id) { requestStatuses[request.id] = .failed }
history.confirm(initialRequests.filter { requestStatuses[$0.id] == .scheduled }, now: afterFire)
let replan = SleepReminderPlanner.requests(preferences: .init(enabled: true, minute: 660), recordedDays: [], elapsedPlannedDays: history.elapsedDays(now: afterFire), now: afterFire, zone: zone)
print("R3 delivered during end-of-batch confirmation (OS-valid injected client state):")
print("  successfully submitted today, then delivered before pending query")
print("  final status incorrectly failed: \(requestStatuses[todayID] == .failed)")
print("  ledger remembers today's elapsed plan: \(history.elapsedDays(now: afterFire).contains(day.identifier))")
print("  changing reminder to 11:00 queues today's reminder again: \(replan.contains { $0.id == todayID })")
precondition(requestStatuses[todayID] == .failed)
precondition(!history.elapsedDays(now: afterFire).contains(day.identifier))
precondition(replan.contains { $0.id == todayID })
// Positive control: existing completed-before-delivery scheduling remains protected.
let controlHistory = SleepReminderHistory(defaults: nil)
controlHistory.confirm(initialRequests, now: beforeFire)
let controlReplan = SleepReminderPlanner.requests(preferences: .init(enabled: true, minute: 660), recordedDays: [], elapsedPlannedDays: controlHistory.elapsedDays(now: afterFire), now: afterFire, zone: zone)
precondition(!controlReplan.contains { $0.id == todayID })
print("  control: confirmation completed before delivery correctly prevents requeue")
let canceledHistory = SleepReminderHistory(defaults: nil)
canceledHistory.confirm(initialRequests, now: beforeFire)
canceledHistory.confirmCancellation([todayID], now: beforeFire)
let canceledReplan = SleepReminderPlanner.requests(preferences: .init(enabled: true, minute: 660), recordedDays: [], elapsedPlannedDays: canceledHistory.elapsedDays(now: afterFire), now: afterFire, zone: zone)
precondition(canceledReplan.contains { $0.id == todayID })
print("  control: truly canceled-before-delivery request can be rescheduled")
