import Foundation

enum HabitStatus: String, Codable, CaseIterable, Sendable {
    case active
    case paused
    case completed
    case archived
}

enum HabitRecordingMode: String, Codable, CaseIterable, Sendable {
    case oncePerDay
    case multiplePerDay
}

enum HabitLogDayProvenance: String, Codable, CaseIterable, Sendable {
    case capturedAtWrite
    case legacyBootstrap
}

/// A persisted civil date. It intentionally has no time-zone offset: once written,
/// activity keeps belonging to this day even when the device later changes zones.
struct HabitLocalDay: Hashable, Comparable, Codable, Sendable, Identifiable {
    let year: Int
    let month: Int
    let day: Int

    var id: String { description }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 1970
        month = components.month ?? 1
        day = components.day ?? 1
    }

    init?(_ value: String) {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else {
            return nil
        }
        year = parts[0]
        month = parts[1]
        day = parts[2]
    }

    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    func date(timeZone: TimeZone = .current) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    func adding(days: Int, timeZone: TimeZone = .current) -> Self? {
        guard let date = date(timeZone: timeZone),
              let result = WeeklyReviewCalendarPolicy.calendar(timeZone: timeZone)
                .date(byAdding: .day, value: days, to: date) else { return nil }
        return Self(date: result, timeZone: timeZone)
    }
}

enum HabitPlanPeriod: String, Codable, CaseIterable, Sendable {
    case trackingOnly
    case day
    case week
    case month
}

enum HabitPlanGoal: String, Codable, CaseIterable, Sendable {
    case none
    case everyDay
    case selectedWeekdays
    case count
}

enum HabitLifecycleEventKind: String, Codable, CaseIterable, Sendable {
    case created
    case paused
    case resumed
    case completed
    case archived
    case restarted
}

struct HabitPlan: Equatable, Sendable {
    let recordingMode: HabitRecordingMode
    let period: HabitPlanPeriod
    let goal: HabitPlanGoal
    let targetCount: Int?
    /// ISO weekday values (1 is Sunday, 7 is Saturday), empty for every-day/count schedules.
    let weekdays: Set<Int>

    static func trackingOnly(recordingMode: HabitRecordingMode) -> Self {
        HabitPlan(
            recordingMode: recordingMode,
            period: .trackingOnly,
            goal: .none,
            targetCount: nil,
            weekdays: []
        )
    }

    var isTrackingOnly: Bool { period == .trackingOnly || goal == .none }
    var supportsStrictMetrics: Bool { !isTrackingOnly && (targetCount ?? 0) > 0 }

    static func legacy(mode: HabitRecordingMode, target: Int?) -> Self {
        switch mode {
        case .oncePerDay:
            return HabitPlan(recordingMode: mode, period: .day, goal: .everyDay, targetCount: 1, weekdays: [])
        case .multiplePerDay:
            guard let target, target > 0 else { return .trackingOnly(recordingMode: mode) }
            return HabitPlan(recordingMode: mode, period: .day, goal: .everyDay, targetCount: target, weekdays: [])
        }
    }
}

enum HabitValidationError: Error, Equatable {
    case emptyName
    case invalidDailyTarget
    case invalidPlan
}

enum HabitCheckInError: Error, Equatable {
    case inactiveHabit
    case missingHabit
    case alreadyCheckedInToday
    case recentlyCheckedIn
    case checkInIsNotLatest
    case futureOccurrence
    case notScheduled
}

enum HabitRules {
    static func validatedName(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HabitValidationError.emptyName }
        return trimmed
    }

    static func validatedPlan(_ plan: HabitPlan) throws -> HabitPlan {
        guard !plan.isTrackingOnly else { return .trackingOnly(recordingMode: plan.recordingMode) }
        guard let target = plan.targetCount, target > 0 else { throw HabitValidationError.invalidPlan }
        if plan.goal == .selectedWeekdays {
            guard plan.period == .day, !plan.weekdays.isEmpty,
                  plan.weekdays.allSatisfy({ (1...7).contains($0) }) else {
                throw HabitValidationError.invalidPlan
            }
        }
        guard (plan.period == .day && (plan.goal == .everyDay || plan.goal == .selectedWeekdays))
                || ((plan.period == .week || plan.period == .month) && plan.goal == .count) else {
            throw HabitValidationError.invalidPlan
        }
        return HabitPlan(
            recordingMode: plan.recordingMode,
            period: plan.period,
            goal: plan.goal,
            targetCount: target,
            weekdays: plan.weekdays
        )
    }

    static func validatedDailyTarget(
        _ value: Int?,
        mode: HabitRecordingMode
    ) throws -> Int? {
        guard mode == .multiplePerDay else { return nil }
        guard let value else { throw HabitValidationError.invalidDailyTarget }
        guard value > 0 else { throw HabitValidationError.invalidDailyTarget }
        return value
    }
}

struct HabitAnalyticsLog: Equatable, Sendable {
    let id: UUID
    let localDay: HabitLocalDay
    let isCompleted: Bool
    let occurredAt: Date
}

struct HabitPlanSnapshot: Equatable, Sendable {
    let effectiveDay: HabitLocalDay
    let plan: HabitPlan
    let trustStartDay: HabitLocalDay
}

struct HabitLifecycleSnapshot: Equatable, Sendable {
    let day: HabitLocalDay
    let kind: HabitLifecycleEventKind
}

enum HabitPeriodOutcome: Equatable, Sendable {
    case open
    case achieved
    case missed
    case notEvaluated(HabitPeriodNotEvaluatedReason)
}

enum HabitPeriodNotEvaluatedReason: String, Equatable, Sendable {
    case trackingOnly, notScheduled, inactive, lifecycleTransition, partialCoverage, beforeTrustedCoverage, missingPlan, future
}

struct HabitPeriodEvaluation: Identifiable, Equatable, Sendable {
    let id: String
    let start: HabitLocalDay
    let end: HabitLocalDay
    let period: HabitPlanPeriod
    let actual: Int
    let target: Int?
    let progress: Double?
    let outcome: HabitPeriodOutcome
    let plan: HabitPlan?
}

struct HabitAnalyticsSummary: Equatable, Sendable {
    let current: HabitPeriodEvaluation?
    let evaluations: [HabitPeriodEvaluation]
    let adherence: Double?
    let consistency: Double?
    let currentStreak: Int?
    let bestStreak: Int?
    let streakUnit: String?
    let activityByDay: [HabitLocalDay: Int]
    let coverageStart: HabitLocalDay?
}

/// The single source of derived Habit mathematics. It receives immutable value
/// snapshots so ordering of SwiftData fetches cannot change results.
enum HabitAnalyticsEngine {
    static func evaluate(
        createdAt: HabitLocalDay,
        logs: [HabitAnalyticsLog],
        plans: [HabitPlanSnapshot],
        lifecycle: [HabitLifecycleSnapshot],
        asOf: HabitLocalDay = HabitLocalDay(date: Date()),
        timeZone: TimeZone = .current
    ) -> HabitAnalyticsSummary {
        let sortedPlans = plans.sorted { $0.effectiveDay < $1.effectiveDay }
        let sortedEvents = lifecycle.sorted { $0.day < $1.day }
        let activity = Dictionary(grouping: logs.filter(\.isCompleted), by: \.localDay)
            .mapValues { $0.count }
        guard let first = ([createdAt] + activity.keys + sortedPlans.map(\.effectiveDay)).min() else {
            return HabitAnalyticsSummary(current: nil, evaluations: [], adherence: nil, consistency: nil, currentStreak: nil, bestStreak: nil, streakUnit: nil, activityByDay: activity, coverageStart: nil)
        }
        let days = sequence(from: first, through: asOf, timeZone: timeZone)
        let evaluations = makeEvaluations(
            days: days, activity: activity, plans: sortedPlans, lifecycle: sortedEvents,
            asOf: asOf, timeZone: timeZone
        )
        let currentPlan = plan(on: asOf, plans: sortedPlans)
        let comparable = evaluations.filter { evaluation in
            evaluation.plan?.period == currentPlan?.plan.period && evaluation.plan?.isTrackingOnly == false
        }
        let evaluated = comparable.filter {
            $0.end < asOf && ($0.outcome == .achieved || $0.outcome == .missed)
        }
        let adherence = evaluated.isEmpty ? nil : Double(evaluated.filter { $0.outcome == .achieved }.count) / Double(evaluated.count)
        let consistencyValues = evaluated.compactMap(\.progress)
        let consistency = consistencyValues.isEmpty ? nil : consistencyValues.reduce(0, +) / Double(consistencyValues.count)
        let streak = streaks(evaluations: comparable, currentPlan: currentPlan?.plan)
        let current = evaluations.last(where: { $0.start <= asOf && $0.end >= asOf })
        return HabitAnalyticsSummary(
            current: current,
            evaluations: evaluations,
            adherence: adherence,
            consistency: consistency,
            currentStreak: currentPlan?.plan.isTrackingOnly == true ? nil : streak.current,
            bestStreak: currentPlan?.plan.isTrackingOnly == true ? nil : streak.best,
            streakUnit: currentPlan.map { streakUnit($0.plan) },
            activityByDay: activity,
            coverageStart: currentPlan.map(\.trustStartDay)
        )
    }

    private static func makeEvaluations(
        days: [HabitLocalDay], activity: [HabitLocalDay: Int], plans: [HabitPlanSnapshot],
        lifecycle: [HabitLifecycleSnapshot], asOf: HabitLocalDay, timeZone: TimeZone
    ) -> [HabitPeriodEvaluation] {
        var emitted = Set<String>()
        return days.compactMap { day in
            guard let plan = plan(on: day, plans: plans) else {
                return period(start: day, end: day, plan: nil, activity: activity, outcome: .notEvaluated(.missingPlan))
            }
            let bounds = periodBounds(for: day, period: plan.plan.period, timeZone: timeZone)
            let key = "\(plan.plan.period.rawValue)-\(bounds.start.description)"
            guard emitted.insert(key).inserted else { return nil }
            let periodDays = sequence(from: bounds.start, through: bounds.end, timeZone: timeZone)
            let eventsInPeriod = lifecycle.filter { bounds.start <= $0.day && $0.day <= bounds.end }
            let transition = eventsInPeriod.contains { $0.kind != .created }
            let active = isActive(on: day, events: lifecycle)
            let isFuture = bounds.start > asOf
            let isOpen = bounds.end >= asOf
            let coverage = plan.trustStartDay <= bounds.start
            let actual = periodDays.reduce(0) { total, currentDay in
                let raw = activity[currentDay] ?? 0
                let credit = plan.plan.recordingMode == .oncePerDay
                    ? min(raw, 1)
                    : raw
                return total + credit
            }
            let outcome: HabitPeriodOutcome
            if isFuture { outcome = .notEvaluated(.future) }
            else if plan.plan.isTrackingOnly { outcome = .notEvaluated(.trackingOnly) }
            else if transition { outcome = .notEvaluated(.lifecycleTransition) }
            else if !active { outcome = .notEvaluated(.inactive) }
            else if plan.plan.period != .day && (
                plan.effectiveDay > bounds.start
                || plans.contains(where: { bounds.start < $0.effectiveDay && $0.effectiveDay <= bounds.end })
            ) { outcome = .notEvaluated(.partialCoverage) }
            else if !coverage { outcome = .notEvaluated(.beforeTrustedCoverage) }
            else if plan.plan.period == .day && plan.plan.goal == .selectedWeekdays && !isScheduled(day, plan: plan.plan, timeZone: timeZone) { outcome = .notEvaluated(.notScheduled) }
            else if let target = plan.plan.targetCount, actual >= target { outcome = .achieved }
            else if isOpen { outcome = .open }
            else { outcome = .missed }
            return period(start: bounds.start, end: bounds.end, plan: plan.plan, activity: activity, outcome: outcome, actual: actual)
        }
    }

    private static func period(
        start: HabitLocalDay, end: HabitLocalDay, plan: HabitPlan?, activity: [HabitLocalDay: Int],
        outcome: HabitPeriodOutcome, actual: Int? = nil
    ) -> HabitPeriodEvaluation {
        let total = actual ?? activity[start, default: 0]
        let target = plan?.targetCount
        return HabitPeriodEvaluation(
            id: "\(plan?.period.rawValue ?? "none")-\(start.description)", start: start, end: end,
            period: plan?.period ?? .trackingOnly, actual: total, target: target,
            progress: target.map { min(Double(total) / Double($0), 1) }, outcome: outcome, plan: plan
        )
    }

    private static func plan(on day: HabitLocalDay, plans: [HabitPlanSnapshot]) -> HabitPlanSnapshot? {
        plans.last { $0.effectiveDay <= day }
    }

    private static func isActive(on day: HabitLocalDay, events: [HabitLifecycleSnapshot]) -> Bool {
        let last = events.last { $0.day <= day }?.kind ?? .created
        return last == .created || last == .resumed || last == .restarted
    }

    private static func isScheduled(_ day: HabitLocalDay, plan: HabitPlan, timeZone: TimeZone) -> Bool {
        guard plan.goal == .selectedWeekdays, let date = day.date(timeZone: timeZone) else { return true }
        return plan.weekdays.contains(WeeklyReviewCalendarPolicy.calendar(timeZone: timeZone).component(.weekday, from: date))
    }

    private static func periodBounds(
        for day: HabitLocalDay, period: HabitPlanPeriod, timeZone: TimeZone
    ) -> (start: HabitLocalDay, end: HabitLocalDay) {
        guard let date = day.date(timeZone: timeZone) else { return (day, day) }
        let calendar = WeeklyReviewCalendarPolicy.calendar(timeZone: timeZone)
        switch period {
        case .trackingOnly, .day: return (day, day)
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: date)!
            return (HabitLocalDay(date: interval.start, timeZone: timeZone), HabitLocalDay(date: calendar.date(byAdding: .day, value: -1, to: interval.end)!, timeZone: timeZone))
        case .month:
            let interval = calendar.dateInterval(of: .month, for: date)!
            return (HabitLocalDay(date: interval.start, timeZone: timeZone), HabitLocalDay(date: calendar.date(byAdding: .day, value: -1, to: interval.end)!, timeZone: timeZone))
        }
    }

    private static func sequence(from first: HabitLocalDay, through last: HabitLocalDay, timeZone: TimeZone) -> [HabitLocalDay] {
        var result: [HabitLocalDay] = []
        var current: HabitLocalDay? = first
        while let day = current, day <= last {
            result.append(day)
            current = day.adding(days: 1, timeZone: timeZone)
        }
        return result
    }

    private static func streaks(evaluations: [HabitPeriodEvaluation], currentPlan: HabitPlan?) -> (current: Int, best: Int) {
        guard currentPlan?.isTrackingOnly == false else { return (0, 0) }
        var best = 0, running = 0, current = 0
        for evaluation in evaluations {
            switch evaluation.outcome {
            case .achieved:
                running += 1; best = max(best, running); current = running
            case .missed:
                running = 0; current = 0
            case .notEvaluated(.lifecycleTransition):
                running = 0
                current = 0
            case .open, .notEvaluated:
                break
            }
        }
        return (current, best)
    }

    private static func streakUnit(_ plan: HabitPlan) -> String {
        switch plan.period { case .day: "days"; case .week: "weeks"; case .month: "months"; case .trackingOnly: "" }
    }
}

enum HabitCheckInPolicy {
    static let duplicatePreventionInterval: TimeInterval = 2.5
    static let undoPresentationInterval: TimeInterval = 6
}

struct HabitLogDraft {
    var occurredAt: Date
    var isCompleted: Bool
    var quantity: Double?
    var unit: String?
    var result: String?

    init(
        occurredAt: Date = Date(),
        isCompleted: Bool = true,
        quantity: Double? = nil,
        unit: String? = nil,
        result: String? = nil
    ) {
        self.occurredAt = occurredAt
        self.isCompleted = isCompleted
        self.quantity = quantity
        self.unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.result = result?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
