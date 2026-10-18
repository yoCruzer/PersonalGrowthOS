import Foundation

/// Frozen civil-day window; today's future instants are never evidence.
struct QuietWinsWindow: Equatable, Sendable {
    let days: Int
    let asOf: Date
    let timeZone: TimeZone
    let start: Date
    let firstDay: HabitLocalDay
    let lastDay: HabitLocalDay

    init(days: Int, asOf: Date, timeZone: TimeZone) {
        precondition([7, 30, 90].contains(days))
        self.days = days; self.asOf = asOf; self.timeZone = timeZone
        let calendar = WeeklyReviewCalendarPolicy.calendar(timeZone: timeZone)
        start = calendar.date(byAdding: .day, value: 1 - days, to: calendar.startOfDay(for: asOf))!
        firstDay = HabitLocalDay(date: start, timeZone: timeZone)
        lastDay = HabitLocalDay(date: asOf, timeZone: timeZone)
    }
    func contains(_ date: Date) -> Bool { date >= start && date <= asOf }
    func contains(_ day: HabitLocalDay) -> Bool { day >= firstDay && day <= lastDay }
}

struct QuietWinsInput: Equatable, Sendable {
    struct Completion: Identifiable, Equatable, Sendable {
        let id: UUID
        let title: String
        let isCompleted: Bool
        let completedAt: Date?
        /// Goal lifecycle may contradict a stale completion field. Nil means no history.
        var latestLifecycleKind: String? = nil
        var latestLifecycleDate: Date? = nil
    }
    struct HabitFact: Identifiable, Equatable, Sendable {
        let id: UUID
        let title: String
    }
    struct Log: Identifiable, Equatable, Sendable {
        let id: UUID
        let habitID: UUID
        let occurredAt: Date
        let isCompleted: Bool
        /// Persisted write-time civil day; malformed metadata is excluded, never reinterpreted.
        let localDay: String?
    }
    struct Record: Identifiable, Equatable, Sendable {
        let id: UUID
        let title: String
        let occurredAt: Date
        let isOrdinary: Bool
        let hasContent: Bool
        let isExternal: Bool
    }
    struct Review: Identifiable, Equatable, Sendable {
        let id: UUID
        let weekIdentifier: String
        let isCompleted: Bool
    }
    var goals: [Completion] = []
    var todos: [Completion] = []
    var habits: [HabitFact] = []
    var logs: [Log] = []
    var entries: [Record] = []
    var reviews: [Review] = []
}

enum QuietWinsKind: String, Sendable { case goal, todos, habit, entries, reviews }
enum QuietWinsSourceKind: String, Sendable { case goal, todo, habitLog, entry, review }

struct QuietWinsSource: Identifiable, Equatable, Sendable {
    let kind: QuietWinsSourceKind
    let sourceID: UUID
    let parentID: UUID?
    let title: String
    let day: HabitLocalDay
    let date: Date?
    let weekIdentifier: String?
    var id: String { "\(kind.rawValue):\(sourceID.uuidString)" }
}

struct QuietWinsCard: Identifiable, Equatable, Sendable {
    let id: String
    let kind: QuietWinsKind
    let title: String
    let count: Int
    let sources: [QuietWinsSource]
    var latestDay: HabitLocalDay { sources.map(\.day).max()! }
}

struct QuietWinsHabitDay: Identifiable, Equatable, Sendable {
    let id: String
    let day: HabitLocalDay
    let sources: [QuietWinsSource]
}
extension QuietWinsCard {
    /// Group identities, never distinct records with matching values. Source order remains factual and stable.
    var habitDays: [QuietWinsHabitDay] {
        guard kind == .habit else { return [] }
        return Dictionary(grouping: sources, by: \.day).map { day, sources in
            QuietWinsHabitDay(id: id + ":" + day.description, day: day, sources: sources)
        }.sorted { $0.day > $1.day }
    }
}

struct QuietWinsProjection: Equatable, Sendable {
    let window: QuietWinsWindow
    let cards: [QuietWinsCard]
    /// Valid current evidence includes facts that are not recommended on the homepage.
    let evidenceCards: [QuietWinsCard]

    func evidenceCard(id: String) -> QuietWinsCard? {
        evidenceCards.first { $0.id == id }
    }
}

enum QuietWinsEngine {
    /// Exact duplicates collapse; conflicting duplicate identities fail closed.
    private static func unique<T: Identifiable & Equatable>(_ values: [T]) -> [T] where T.ID == UUID {
        Dictionary(grouping: values, by: \.id).values.compactMap { group in
            guard let first = group.first, group.allSatisfy({ $0 == first }) else { return nil }
            return first
        }
    }

    static func build(_ input: QuietWinsInput, window: QuietWinsWindow) -> QuietWinsProjection {
        func ordered(_ sources: [QuietWinsSource]) -> [QuietWinsSource] {
            sources.sorted {
                if $0.day != $1.day { return $0.day > $1.day }
                if $0.date != $1.date { return ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                return $0.id < $1.id
            }
        }
        func completionSources(_ values: [QuietWinsInput.Completion], kind: QuietWinsSourceKind) -> [QuietWinsSource] {
            ordered(unique(values).compactMap { value in
                guard value.isCompleted, let date = value.completedAt, window.contains(date) else { return nil }
                if kind == .goal, let lifecycle = value.latestLifecycleKind {
                    guard lifecycle == GoalLifecycleEventKind.completed.rawValue,
                          value.latestLifecycleDate == date else { return nil }
                }
                return QuietWinsSource(kind: kind, sourceID: value.id, parentID: nil, title: value.title,
                    day: HabitLocalDay(date: date, timeZone: window.timeZone), date: date, weekIdentifier: nil)
            })
        }
        let goals = completionSources(input.goals, kind: .goal).map {
            QuietWinsCard(id: $0.id, kind: .goal, title: $0.title, count: 1, sources: [$0])
        }
        let todos = completionSources(input.todos, kind: .todo)
        let habitByID = Dictionary(uniqueKeysWithValues: unique(input.habits).map { ($0.id, $0) })
        let logs = unique(input.logs).compactMap { log -> QuietWinsSource? in
            guard log.isCompleted, log.occurredAt <= window.asOf,
                  let habit = habitByID[log.habitID] else { return nil }
            // An absolute instant cannot establish the original civil day after travel.
            // Normal startup/import/check-in already persist this metadata; fail closed otherwise.
            guard let stored = log.localDay, let day = HabitLocalDay(stored),
                  window.contains(day) else { return nil }
            return QuietWinsSource(kind: .habitLog, sourceID: log.id, parentID: log.habitID, title: habit.title,
                day: day, date: log.occurredAt, weekIdentifier: nil)
        }
        let habits = Dictionary(grouping: logs, by: \.parentID).values.map { group in
            let sources = ordered(group)
            return QuietWinsCard(id: "habit:\(sources[0].parentID!.uuidString)", kind: .habit,
                title: sources[0].title, count: Set(sources.map(\.day)).count, sources: sources)
        }.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            if $0.latestDay != $1.latestDay { return $0.latestDay > $1.latestDay }
            return $0.id < $1.id
        }
        let entries = ordered(unique(input.entries).compactMap { value -> QuietWinsSource? in
            guard value.isOrdinary, value.hasContent, !value.isExternal, window.contains(value.occurredAt) else { return nil }
            return QuietWinsSource(kind: .entry, sourceID: value.id, parentID: nil, title: value.title,
                day: HabitLocalDay(date: value.occurredAt, timeZone: window.timeZone), date: value.occurredAt, weekIdentifier: nil)
        })
        // Weeks are selected by civil-week overlap, never by a guessed completion/edit time.
        let reviews = ordered(unique(input.reviews).compactMap { value -> QuietWinsSource? in
            guard value.isCompleted,
                  let period = try? WeeklyReviewPeriod(identifier: value.weekIdentifier, timeZone: window.timeZone),
                  period.start <= window.asOf, period.endExclusive > window.start else { return nil }
            return QuietWinsSource(kind: .review, sourceID: value.id, parentID: nil, title: value.weekIdentifier,
                day: HabitLocalDay(date: period.start, timeZone: window.timeZone), date: nil, weekIdentifier: value.weekIdentifier)
        })
        // At most one primary card per type, then fill remaining slots with individual goals/habits.
        var cards: [QuietWinsCard] = []
        if let first = goals.first { cards.append(first) }
        if !todos.isEmpty { cards.append(.init(id: "todos", kind: .todos, title: "", count: todos.count, sources: todos)) }
        if let first = habits.first { cards.append(first) }
        if !entries.isEmpty { cards.append(.init(id: "entries", kind: .entries, title: "", count: Set(entries.map(\.day)).count, sources: entries)) }
        if !reviews.isEmpty { cards.append(.init(id: "reviews", kind: .reviews, title: "", count: Set(reviews.compactMap(\.weekIdentifier)).count, sources: reviews)) }
        cards.append(contentsOf: (Array(goals.dropFirst()) + Array(habits.dropFirst())).prefix(5 - cards.count))
        let evidenceCards = goals + habits + cards.filter { $0.kind != .goal && $0.kind != .habit }
        return QuietWinsProjection(window: window, cards: cards, evidenceCards: evidenceCards)
    }
}
