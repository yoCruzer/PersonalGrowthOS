import Foundation

/// A Gregorian civil date, independent of an instant or the device's time zone.
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
        // Explicit policy for DST gaps: next valid wall time on this same civil day.
        guard let start = c.date(from: DateComponents(year: year, month: month, day: day)),
              let result = c.nextDate(after: start.addingTimeInterval(-1), matching: DateComponents(hour: minutes / 60, minute: minutes % 60), matchingPolicy: .nextTime, repeatedTimePolicy: .first),
              ImportantCivilDay(result, timeZone: timeZone) == self else { return nil }
        return result
    }
    var identifier: String { String(format: "%04d-%02d-%02d", year, month, day) }
}

enum ImportantDayPreset: String, Codable, CaseIterable, Sendable { case anticipated, beginning, anniversary }
enum ImportantDayCalendar: String, Codable, CaseIterable, Sendable { case gregorian, chinese }
enum ImportantDayPerspective: String, Codable, CaseIterable, Sendable { case next, elapsed }
enum ImportantDayTodayPolicy: String, Codable, CaseIterable, Sendable { case automatic, always, hidden }
enum ImportantLeapDayRule: String, Codable, CaseIterable, Sendable { case february28, march1, leapYearsOnly }
enum ImportantLeapMonthRule: String, Codable, CaseIterable, Sendable { case regularFallback, leapYearsOnly }
enum ImportantShortMonthRule: String, Codable, CaseIterable, Sendable { case lastDay, skip }
enum ImportantDayDateError: Error, Equatable { case unsupportedRange, invalidDate, ruleRequired, unknownYear }

struct ImportantDayDateRule: Codable, Equatable, Sendable {
    var preset: ImportantDayPreset = .anticipated
    var calendar: ImportantDayCalendar = .gregorian
    /// Chinese year means the Gregorian year in which that lunar year begins, never a cyclical year.
    var year: Int? = ImportantCivilDay(Date()).year
    var month: Int = 1
    var day: Int = 1
    var isLeapMonth = false
    var leapDayRule: ImportantLeapDayRule?
    var leapMonthRule: ImportantLeapMonthRule?
    var shortMonthRule: ImportantShortMonthRule?
    var perspective: ImportantDayPerspective = .next

    func validate() throws {
        guard (1...12).contains(month), (1...31).contains(day) else { throw ImportantDayDateError.invalidDate }
        if let year, !ImportantDayDateEngine.years.contains(year) { throw ImportantDayDateError.unsupportedRange }
        guard year != nil || preset == .anniversary else { throw ImportantDayDateError.unknownYear }
        guard year != nil || perspective == .next else { throw ImportantDayDateError.unknownYear }
        if calendar == .gregorian {
            guard !isLeapMonth, ImportantCivilDay(year: year ?? 2000, month: month, day: day).date != nil else { throw ImportantDayDateError.invalidDate }
            if preset == .anniversary && month == 2 && day == 29 && leapDayRule == nil { throw ImportantDayDateError.ruleRequired }
        } else {
            guard day <= 30 else { throw ImportantDayDateError.invalidDate }
            if isLeapMonth && leapMonthRule == nil { throw ImportantDayDateError.ruleRequired }
            if day == 30 && shortMonthRule == nil { throw ImportantDayDateError.ruleRequired }
            if let year, try ImportantDayDateEngine.original(self, in: year) == nil { throw ImportantDayDateError.invalidDate }
        }
    }
}

struct ImportantDayDateResult: Equatable, Sendable {
    let original: ImportantCivilDay?
    let next: ImportantCivilDay?
    let displayDay: ImportantCivilDay
    /// Positive = future; negative = past. Natural Gregorian days, never seconds / 86400.
    let signedDays: Int
    let anniversaryNumber: Int?
}

enum ImportantDayDateEngine {
    static let years = 1901...2100
    static let lunarTimeZone = TimeZone(identifier: "Asia/Shanghai")!
    private static var chinese: Calendar {
        var c = Calendar(identifier: .chinese); c.timeZone = lunarTimeZone; return c
    }
    private static var shanghai: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = lunarTimeZone; return c
    }
    /// Locate the actual Chinese new year, then traverse months; no cyclical-year arithmetic.
    private static func lunarMonths(year: Int) throws -> [(month: Int, leap: Bool, start: Date, count: Int)] {
        guard years.contains(year) else { throw ImportantDayDateError.unsupportedRange }
        let g = shanghai, c = chinese
        var date = g.date(from: DateComponents(year: year, month: 1, day: 1, hour: 12))!
        var start: Date?
        for _ in 0..<65 {
            let p = c.dateComponents([.month, .day, .isLeapMonth], from: date)
            if p.month == 1 && p.day == 1 && p.isLeapMonth != true { start = c.startOfDay(for: date); break }
            date = g.date(byAdding: .day, value: 1, to: date)!
        }
        guard var cursor = start else { throw ImportantDayDateError.invalidDate }
        var result: [(Int, Bool, Date, Int)] = []
        for index in 0..<13 {
            let p = c.dateComponents([.month, .day, .isLeapMonth], from: cursor)
            if index > 0 && p.month == 1 && p.isLeapMonth != true { break }
            guard p.day == 1, let range = c.range(of: .day, in: .month, for: cursor),
                  let end = c.date(byAdding: .day, value: range.count, to: cursor) else { throw ImportantDayDateError.invalidDate }
            result.append((p.month!, p.isLeapMonth == true, cursor, range.count)); cursor = end
        }
        return result
    }
    static func original(_ rule: ImportantDayDateRule, in year: Int) throws -> ImportantCivilDay? {
        guard years.contains(year) else { throw ImportantDayDateError.unsupportedRange }
        if rule.calendar == .gregorian {
            let day = ImportantCivilDay(year: year, month: rule.month, day: rule.day)
            return day.date == nil ? nil : day
        }
        let months = try lunarMonths(year: year)
        guard let month = months.first(where: { $0.month == rule.month && $0.leap == rule.isLeapMonth }), rule.day <= month.count,
              let date = chinese.date(byAdding: .day, value: rule.day - 1, to: month.start) else { return nil }
        return ImportantCivilDay(date, timeZone: lunarTimeZone)
    }
    static func occurrence(_ rule: ImportantDayDateRule, in year: Int) throws -> ImportantCivilDay? {
        if rule.calendar == .gregorian {
            if let exact = try original(rule, in: year) { return exact }
            guard rule.month == 2 && rule.day == 29 else { return nil }
            switch rule.leapDayRule {
            case .february28: return ImportantCivilDay(year: year, month: 2, day: 28)
            case .march1: return ImportantCivilDay(year: year, month: 3, day: 1)
            case .leapYearsOnly: return nil
            case nil: throw ImportantDayDateError.ruleRequired
            }
        }
        let months = try lunarMonths(year: year)
        let exact = months.first { $0.month == rule.month && $0.leap == rule.isLeapMonth }
        let chosen: (month: Int, leap: Bool, start: Date, count: Int)?
        if let exact { chosen = exact }
        else if rule.isLeapMonth && rule.leapMonthRule == .regularFallback { chosen = months.first { $0.month == rule.month && !$0.leap } }
        else { return nil }
        guard let chosen else { return nil }
        var day = rule.day
        if day > chosen.count {
            guard rule.shortMonthRule == .lastDay else { return nil }
            day = chosen.count
        }
        guard let date = chinese.date(byAdding: .day, value: day - 1, to: chosen.start) else { return nil }
        return ImportantCivilDay(date, timeZone: lunarTimeZone)
    }
    static func evaluate(_ rule: ImportantDayDateRule, today: ImportantCivilDay) throws -> ImportantDayDateResult {
        try rule.validate()
        guard years.contains(today.year), today.date != nil else { throw ImportantDayDateError.unsupportedRange }
        let original = try rule.year.flatMap { try original(rule, in: $0) }
        var next: ImportantCivilDay?
        var occurrenceYear: Int?
        if rule.preset == .anniversary {
            for year in max(years.lowerBound, today.year - 1, rule.year ?? years.lowerBound)...years.upperBound {
                if let candidate = try occurrence(rule, in: year), candidate >= today {
                    next = candidate; occurrenceYear = year; break
                }
            }
        } else if let original, original >= today { next = original }
        let display: ImportantCivilDay
        if rule.preset == .anniversary && rule.perspective == .next {
            guard let next else { throw ImportantDayDateError.unsupportedRange }; display = next
        } else {
            guard let original else { throw ImportantDayDateError.unknownYear }; display = original
        }
        guard let distance = today.distance(to: display) else { throw ImportantDayDateError.invalidDate }
        return ImportantDayDateResult(original: original, next: next, displayDay: display, signedDays: distance,
            anniversaryNumber: rule.year.flatMap { first in occurrenceYear.map { $0 - first } })
    }
}

struct ImportantDayTodayCandidate: Sendable {
    let id: UUID
    let rule: ImportantDayDateRule
    let policy: ImportantDayTodayPolicy
    let archived: Bool
    let stableOrder: Int
}
enum ImportantDayTodaySelector {
    static func select(_ candidates: [ImportantDayTodayCandidate], today: ImportantCivilDay) -> [UUID] {
        candidates.compactMap { item -> (UUID, Int, ImportantCivilDay, Int)? in
            guard !item.archived, item.policy != .hidden,
                  let result = try? ImportantDayDateEngine.evaluate(item.rule, today: today) else { return nil }
            let day = result.next ?? result.original!
            let distance = today.distance(to: day)!
            guard item.policy == .always || (0...7).contains(distance) else { return nil }
            return (item.id, distance == 0 ? 0 : item.policy == .always ? 1 : 2, day, item.stableOrder)
        }.sorted { a, b in
            if a.1 != b.1 { return a.1 < b.1 }; if a.2 != b.2 { return a.2 < b.2 }
            if a.3 != b.3 { return a.3 < b.3 }; return a.0.uuidString < b.0.uuidString
        }.prefix(2).map { $0.0 }
    }
}
