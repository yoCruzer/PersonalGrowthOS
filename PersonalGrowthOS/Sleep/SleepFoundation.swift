import Foundation
import SwiftData

extension ImportantCivilDay {
    init?(identifier: String) {
        let parts = identifier.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        self.init(year: y, month: m, day: d)
        guard date != nil, self.identifier == identifier, (1901...2100).contains(y) else { return nil }
    }
}

/// Civil evidence is kept independently of absolute instants and the device's later time zone.
struct SleepRange: Codable, Equatable {
    var day: String
    var minute: Int
    var precision: Int // 0 = manually recalled exact minute; otherwise the original bucket width.
    var utcOffset: Int? = nil // Explicit occurrence for a repeated DST wall time.

    func validateCivil() throws {
        guard ImportantCivilDay(identifier: day) != nil, (0..<1440).contains(minute),
              [0, 15, 30, 60].contains(precision), utcOffset.map({ (-86400...86400).contains($0) }) ?? true else { throw SleepFailure.invalidTime }
    }
    private static func candidates(day: ImportantCivilDay, minute: Int, zone: TimeZone) -> [Date] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let components = DateComponents(year: day.year, month: day.month, day: day.day,
                                        hour: minute / 60, minute: minute % 60, second: 0)
        guard let prior = day.adding(days: -1), let anchor = prior.instant(minutes: 720, timeZone: zone) else { return [] }
        return Array(Set([Calendar.RepeatedTimePolicy.first, .last].compactMap {
            calendar.nextDate(after: anchor, matching: components, matchingPolicy: .strict, repeatedTimePolicy: $0, direction: .forward)
        }.filter { ImportantCivilDay($0, timeZone: zone) == day })).sorted()
    }
    private func endpointCandidates(zone: TimeZone) -> (lower: [Date], upper: [Date])? {
        guard (try? validateCivil()) != nil, let civil = ImportantCivilDay(identifier: day) else { return nil }
        let total = minute + precision
        guard let endDay = total >= 1440 ? civil.adding(days: 1) : civil else { return nil }
        var lower = Self.candidates(day: civil, minute: minute, zone: zone)
        var upper = Self.candidates(day: endDay, minute: total % 1440, zone: zone)
        if let utcOffset {
            lower = lower.filter { zone.secondsFromGMT(for: $0) == utcOffset }
            if upper.count > 1 { upper = upper.filter { zone.secondsFromGMT(for: $0) == utcOffset } }
        }
        return (lower, upper)
    }
    func possibleBounds(zone: TimeZone) -> [ClosedRange<Date>] {
        guard let endpoints = endpointCandidates(zone: zone) else { return [] }
        return endpoints.lower.flatMap { lower in endpoints.upper.compactMap { upper in (precision == 0 ? lower == upper : lower <= upper) ? lower...upper : nil } }
    }
    func bounds(zone: TimeZone) throws -> ClosedRange<Date> {
        try validateCivil()
        guard let endpoints = endpointCandidates(zone: zone) else { throw SleepFailure.invalidTime }
        if utcOffset != nil && endpoints.lower.isEmpty {
            // A provided offset must match the chosen lower occurrence; it is not decorative evidence.
            throw SleepFailure.invalidTime
        }
        guard endpoints.lower.count == 1, endpoints.upper.count == 1 else { throw SleepFailure.ambiguousTime }
        let lower = endpoints.lower[0], upper = endpoints.upper[0]
        guard lower <= upper else { throw SleepFailure.invalidTime }
        return lower...upper
    }
}

struct SleepValues: Codable, Equatable {
    var bedtime: SleepRange?
    var wake: SleepRange?
    var feeling: Int?
    var note = ""
    @TodoTransferOptionalInstant var bedtimeFilledAt: Date? = nil
    @TodoTransferOptionalInstant var wakeFilledAt: Date? = nil
    @TodoTransferOptionalInstant var feelingFilledAt: Date? = nil
    var hasContent: Bool { bedtime != nil || wake != nil || feeling != nil || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

@Model final class SleepRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var wakeDay: String
    var timeZoneID: String
    var valueData: Data
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var observedAt: Date
    init(id: UUID = UUID(), wakeDay: String, timeZoneID: String, values: SleepValues, createdAt: Date) throws {
        self.id = id; self.wakeDay = wakeDay; self.timeZoneID = timeZoneID
        valueData = try JSONEncoder().encode(values); self.createdAt = createdAt; updatedAt = createdAt; revision = 0; observedAt = createdAt
    }
    func values() throws -> SleepValues { try JSONDecoder().decode(SleepValues.self, from: valueData) }
}

@Model final class SleepGoalRule {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var effectiveDay: String
    var observedAt: Date
    var observationTimeZoneID: String
    var hasTakenEffect: Bool
    var cutoffMinute: Int? // nil is a dated disable rule.
    var createdAt: Date
    init(id: UUID = UUID(), effectiveDay: String, cutoffMinute: Int?, createdAt: Date,
         observationTimeZoneID: String = TimeZone.current.identifier, hasTakenEffect: Bool = true) {
        self.id = id; self.effectiveDay = effectiveDay; self.cutoffMinute = cutoffMinute; self.createdAt = createdAt; observedAt = createdAt
        self.observationTimeZoneID = observationTimeZoneID; self.hasTakenEffect = hasTakenEffect
    }
}

enum SleepFailure: Error, LocalizedError {
    case empty, invalidTime, ambiguousTime, invalidDay, future, conflict, missing, corrupt, clockRollback
    var errorDescription: String? {
        switch self {
        case .clockRollback: return String(localized: "The clock is earlier than a saved observation. Correct the clock before changing bedtime goals; sleep facts can still be recorded with unknown filling time.")
        case .empty: return String(localized: "Choose a time, feeling or note before saving.")
        case .invalidTime: return String(localized: "Check the time range and its dates. Wake time must follow bedtime.")
        case .ambiguousTime: return String(localized: "This local time is repeated or does not exist due to daylight saving. Choose an explicit valid time or leave it unknown.")
        case .invalidDay: return String(localized: "Check the wake day and recording time zone.")
        case .future: return String(localized: "A sleep record cannot describe a future wake day or a wholly future time range.")
        case .conflict: return String(localized: "This day already has a record or was changed elsewhere. Your draft is retained; reopen the saved record to compare.")
        case .missing: return String(localized: "This sleep record is no longer available. Your draft is retained.")
        case .corrupt: return String(localized: "Sleep data could not be verified. Your original data is retained.")
        }
    }
}

enum SleepFieldTiming: String, CaseIterable {
    case sameDay, nextDay, recalled, unknown
    var included: Bool { self == .sameDay || self == .nextDay }
    var label: String {
        switch self {
        case .sameDay: String(localized: "Filled on wake day")
        case .nextDay: String(localized: "Filled next day")
        case .recalled: String(localized: "Recalled later")
        case .unknown: String(localized: "Filling time unknown")
        }
    }
}

enum SleepGoalResult: String, CaseIterable {
    case met, missed, uncertain, missing, noGoal, excluded, nonNight
    var label: String {
        switch self {
        case .met: String(localized: "Clearly met")
        case .missed: String(localized: "Clearly missed")
        case .uncertain: String(localized: "Uncertain at cutoff")
        case .missing: String(localized: "Bedtime unknown")
        case .noGoal: String(localized: "No goal for this night")
        case .excluded: String(localized: "Bedtime excluded from basic review")
        case .nonNight: String(localized: "Not comparable to a night goal")
        }
    }
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
    static func validate(day: String, zoneID: String, values: SleepValues, now: Date? = nil) throws {
        guard let civil = ImportantCivilDay(identifier: day), let zone = TimeZone(identifier: zoneID) else { throw SleepFailure.invalidDay }
        guard values.hasContent, values.note.count <= 4000, values.feeling.map({ (1...5).contains($0) }) ?? true else { throw SleepFailure.empty }
        let previous = civil.adding(days: -1)!.identifier
        if let bed = values.bedtime, bed.day != previous && bed.day != day { throw SleepFailure.invalidDay }
        if let wake = values.wake, wake.day != day { throw SleepFailure.invalidDay }
        try values.bedtime?.validateCivil(); try values.wake?.validateCivil()
        // Legal civil evidence can be retained when DST prevents a unique absolute interpretation.
        // Only malformed ranges are rejected; interval and goal derivation stay unavailable.
        func resolved(_ range: SleepRange?) throws -> ClosedRange<Date>? {
            guard let range else { return nil }
            do { return try range.bounds(zone: zone) }
            catch SleepFailure.ambiguousTime { return nil }
        }
        let bed = try resolved(values.bedtime), wake = try resolved(values.wake)
        let bedPossibilities = values.bedtime.map { $0.possibleBounds(zone: zone) } ?? []
        let wakePossibilities = values.wake.map { $0.possibleBounds(zone: zone) } ?? []
        if let earliestBed = bedPossibilities.map(\.lowerBound).min(),
           let latestWake = wakePossibilities.map(\.upperBound).max(), latestWake < earliestBed { throw SleepFailure.invalidTime }
        if let now {
            let localNow = ImportantCivilDay(now, timeZone: zone)
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            let currentMinute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
            for range in [values.bedtime, values.wake].compactMap({ $0 }) {
                if (try? range.bounds(zone: zone)) == nil {
                    if let earliest = range.possibleBounds(zone: zone).map(\.lowerBound).min() {
                        guard earliest <= now else { throw SleepFailure.future }
                    } else {
                        guard range.day < localNow.identifier || (range.day == localNow.identifier && range.minute <= currentMinute) else { throw SleepFailure.future }
                    }
                }
            }
            guard civil <= localNow,
                  bed.map({ $0.lowerBound <= now }) ?? true,
                  wake.map({ $0.lowerBound <= now }) ?? true else { throw SleepFailure.future }
        }
    }
    static func interval(_ values: SleepValues, zone: TimeZone) -> ClosedRange<TimeInterval>? {
        guard let b = values.bedtime, let w = values.wake, let bed = try? b.bounds(zone: zone),
              let wake = try? w.bounds(zone: zone), wake.lowerBound > bed.upperBound else { return nil }
        return wake.lowerBound.timeIntervalSince(bed.upperBound)...wake.upperBound.timeIntervalSince(bed.lowerBound)
    }
    static func goal(day: String, zone: TimeZone, values: SleepValues, rules: [SleepGoalRule], now: Date = Date()) -> SleepGoalResult {
        guard let rule = rules.filter({ $0.effectiveDay <= day }).max(by: { $0.effectiveDay < $1.effectiveDay }),
              let minute = rule.cutoffMinute else { return .noGoal }
        guard let b = values.bedtime else { return .missing }
        guard timing(values.bedtimeFilledAt, day: day, zone: zone, now: now).included else { return .excluded }
        // A main sleep beginning from noon to early evening is factual, but outside a conventional night goal.
        guard let civil = ImportantCivilDay(identifier: day),
              (b.day == civil.adding(days: -1)!.identifier && b.minute >= 1080) || (b.day == day && b.minute < 720) else { return .nonNight }
        guard
              let bed = try? b.bounds(zone: zone),
              let cutoff = try? SleepRange(day: (minute >= 720 ? civil.adding(days: -1)! : civil).identifier,
                                           minute: minute, precision: 0).bounds(zone: zone).lowerBound else { return .nonNight }
        if bed.upperBound <= cutoff { return .met }
        if bed.lowerBound > cutoff { return .missed }
        return .uncertain
    }
}

struct SleepDraft: Equatable {
    var id: UUID? = nil
    var expectedRevision: Int? = nil
    var wakeDay: String
    var timeZoneID: String
    var values = SleepValues()
    init(day: String, zone: TimeZone = .current) { wakeDay = day; timeZoneID = zone.identifier }
    init(_ record: SleepRecord) throws {
        id = record.id; expectedRevision = record.revision; wakeDay = record.wakeDay
        timeZoneID = record.timeZoneID; values = try record.values()
    }
}

extension Notification.Name { static let sleepRecordsChanged = Notification.Name("sleepRecordsChanged") }

/// Transactions run on the main actor; a fresh context detects edits made by another entry point/context.
@MainActor final class SleepService {
    private let owner: ModelContext
    private let now: () -> Date
    private let commit: ((ModelContext) throws -> Void)?
    init(context: ModelContext, now: @escaping () -> Date = Date.init, commit: ((ModelContext) throws -> Void)? = nil) {
        owner = context; self.now = now; self.commit = commit
    }
    @discardableResult func save(_ draft: SleepDraft) throws -> UUID {
        let timestamp = now()
        try SleepRules.validate(day: draft.wakeDay, zoneID: draft.timeZoneID, values: draft.values, now: timestamp)
        let context = ModelContext(owner.container); context.autosaveEnabled = false
        let all = try context.fetch(FetchDescriptor<SleepRecord>())
        guard !all.contains(where: { $0.wakeDay == draft.wakeDay && $0.id != draft.id }) else { throw SleepFailure.conflict }
        let record: SleepRecord
        if let id = draft.id {
            guard let existing = all.first(where: { $0.id == id }) else { throw SleepFailure.missing }
            guard existing.revision == draft.expectedRevision else { throw SleepFailure.conflict }
            record = existing
        } else {
            record = try SleepRecord(wakeDay: draft.wakeDay, timeZoneID: draft.timeZoneID, values: .init(), createdAt: timestamp)
            context.insert(record)
        }
        let old = try record.values()
        var values = draft.values
        let goalObservations = try context.fetch(FetchDescriptor<SleepGoalRule>()).map(\.observedAt)
        let knownUpperBound = (all.map(\.observedAt) + goalObservations).max() ?? timestamp
        let reliable = timestamp >= knownUpperBound
        let changedDay = record.wakeDay != draft.wakeDay || record.timeZoneID != draft.timeZoneID
        func filled(_ changed: Bool, exists: Bool, previous: Date?) -> Date? {
            exists ? (changed ? (reliable ? timestamp : nil) : previous) : nil
        }
        values.bedtimeFilledAt = filled(changedDay || old.bedtime != values.bedtime, exists: values.bedtime != nil, previous: old.bedtimeFilledAt)
        values.wakeFilledAt = filled(changedDay || old.wake != values.wake, exists: values.wake != nil, previous: old.wakeFilledAt)
        values.feelingFilledAt = filled(changedDay || old.feeling != values.feeling, exists: values.feeling != nil, previous: old.feelingFilledAt)
        if old == values && !changedDay && draft.id != nil { return record.id }
        record.wakeDay = draft.wakeDay; record.timeZoneID = draft.timeZoneID
        record.valueData = try JSONEncoder().encode(values)
        record.updatedAt = TechnicalTimestamp.updated(now: timestamp, createdAt: record.createdAt, previous: record.updatedAt)
        record.revision += 1; record.observedAt = max(record.observedAt, timestamp)
        do { if let commit { try commit(context) } else { try context.save() } }
        catch { context.rollback(); throw error }
        NotificationCenter.default.post(name: .sleepRecordsChanged, object: owner.container)
        return record.id
    }
    func delete(id: UUID, revision: Int) throws {
        let context = ModelContext(owner.container); context.autosaveEnabled = false
        guard let record = try context.fetch(FetchDescriptor<SleepRecord>()).first(where: { $0.id == id }) else { throw SleepFailure.missing }
        guard record.revision == revision else { throw SleepFailure.conflict }
        context.delete(record)
        do { if let commit { try commit(context) } else { try context.save() } }
        catch { context.rollback(); throw error }
        NotificationCenter.default.post(name: .sleepRecordsChanged, object: owner.container)
    }
    func setGoal(cutoffMinute: Int?, timeZone: TimeZone = .current) throws {
        guard cutoffMinute.map({ (0..<1440).contains($0) }) ?? true else { throw SleepFailure.invalidTime }
        let context = ModelContext(owner.container); context.autosaveEnabled = false
        let rules = try context.fetch(FetchDescriptor<SleepGoalRule>())
        let timestamp = now()
        let observations = rules.map(\.observedAt) + (try context.fetch(FetchDescriptor<SleepRecord>())).map(\.observedAt)
        guard timestamp >= observations.max() ?? timestamp else { throw SleepFailure.clockRollback }
        let today = ImportantCivilDay(timestamp, timeZone: timeZone)
        for rule in rules where !rule.hasTakenEffect && SleepGoalSemantics.isEffective(rule, now: timestamp, zone: timeZone) {
            rule.hasTakenEffect = true; rule.observedAt = max(rule.observedAt, timestamp)
        }
        let effective = SleepGoalSemantics.proposedDay(rules: rules, now: timestamp, zone: timeZone)
        if let pending = rules.first(where: { $0.effectiveDay == effective.identifier }) {
            guard !SleepGoalSemantics.isEffective(pending, now: timestamp, zone: timeZone) else { throw SleepFailure.clockRollback }
            pending.cutoffMinute = cutoffMinute; pending.observedAt = timestamp
        }
        else { context.insert(SleepGoalRule(effectiveDay: effective.identifier, cutoffMinute: cutoffMinute, createdAt: timestamp,
            observationTimeZoneID: timeZone.identifier, hasTakenEffect: effective <= today)) }
        do { if let commit { try commit(context) } else { try context.save() } }
        catch { context.rollback(); throw error }
        NotificationCenter.default.post(name: .sleepRecordsChanged, object: owner.container)
    }
}

enum SleepIntegrity {
    static func validate(context: ModelContext) throws {
        let records = try context.fetch(FetchDescriptor<SleepRecord>())
        let goals = try context.fetch(FetchDescriptor<SleepGoalRule>())
        guard Set(records.map(\.id)).count == records.count, Set(records.map(\.wakeDay)).count == records.count,
              Set(goals.map(\.id)).count == goals.count, Set(goals.map(\.effectiveDay)).count == goals.count else { throw SleepFailure.corrupt }
        for record in records {
            let values = try record.values()
            try SleepRules.validate(day: record.wakeDay, zoneID: record.timeZoneID, values: values)
            guard record.revision >= 0, record.updatedAt >= record.createdAt,
                  record.createdAt.timeIntervalSinceReferenceDate.isFinite, record.updatedAt.timeIntervalSinceReferenceDate.isFinite,
                  record.observedAt.timeIntervalSinceReferenceDate.isFinite, record.observedAt >= record.createdAt else { throw SleepFailure.corrupt }
            for (exists, stamp) in [(values.bedtime != nil, values.bedtimeFilledAt), (values.wake != nil, values.wakeFilledAt), (values.feeling != nil, values.feelingFilledAt)] {
                guard exists || stamp == nil, stamp.map({ $0.timeIntervalSinceReferenceDate.isFinite && $0 >= record.createdAt && $0 <= record.updatedAt }) ?? true else { throw SleepFailure.corrupt }
            }
        }
        for goal in goals {
            guard ImportantCivilDay(identifier: goal.effectiveDay) != nil, goal.cutoffMinute.map({ (0..<1440).contains($0) }) ?? true,
                  TimeZone(identifier: goal.observationTimeZoneID) != nil,
                  goal.createdAt.timeIntervalSinceReferenceDate.isFinite, goal.observedAt.timeIntervalSinceReferenceDate.isFinite, goal.observedAt >= goal.createdAt else { throw SleepFailure.corrupt }
        }
    }
}

/// A rule that has ever taken effect cannot become editable merely because travel moves the civil day backward.
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
    @MainActor static func observe(context owner: ModelContext, now: Date = Date(), zone: TimeZone = .current) throws {
        let context = ModelContext(owner.container); context.autosaveEnabled = false
        let rules = try context.fetch(FetchDescriptor<SleepGoalRule>())
        var changed = false
        for rule in rules where !rule.hasTakenEffect && isEffective(rule, now: now, zone: zone) {
            rule.hasTakenEffect = true; rule.observedAt = max(rule.observedAt, now); changed = true
        }
        if changed { try context.save() }
    }
}
