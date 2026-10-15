import Foundation
import SwiftData

// Local, transient UI policy. No persistence or historical association validation.
struct ImportantDayPeriodSelection {
    var isExplicit = false
    var year: Int?
    mutating func chooseExplicit(_ enabled: Bool, rule: ImportantDayDateRule, today: ImportantCivilDay) {
        if enabled { year = selectedYear(rule: rule, today: today) }
        else { year = nil }
        isExplicit = enabled
    }
    func selectedYear(rule: ImportantDayDateRule, today: ImportantCivilDay) -> Int {
        if let year, ImportantDayDateEngine.years.contains(year), year >= (rule.year ?? 1901) { return year }
        guard let next = try? ImportantDayDateEngine.evaluate(rule, today: today).next else { return max(today.year, rule.year ?? today.year) }
        return [next.year - 1, next.year].first { (try? ImportantDayDateEngine.occurrence(rule, in: $0)) == next } ?? today.year
    }
    func occurrence(rule: ImportantDayDateRule, today: ImportantCivilDay) -> ImportantCivilDay? {
        guard isExplicit else { return nil }
        return try? ImportantDayDateEngine.explicitPeriod(rule, year: selectedYear(rule: rule, today: today))
    }
}

struct ImportantDayEntryFilter {
    var selection = "all"
    func effectiveSelection(periods: [String]) -> String {
        selection == "all" || selection == "general" || periods.contains(selection) ? selection : "all"
    }
    mutating func reconcile(periods: [String]) { selection = effectiveSelection(periods: periods) }
}

enum ImportantDayEditorPolicy {
    static func calendarSelectionChanged(_ rule: inout ImportantDayDateRule, acknowledged: ImportantDayCalendar) -> Bool {
        guard rule.calendar == acknowledged else { return true }
        // Returning from an unconfirmed excursion keeps the edited numbers and clears only
        // fields that do not apply to the already acknowledged calendar.
        confirmCalendar(&rule)
        return false
    }

    static func confirmCalendar(_ rule: inout ImportantDayDateRule) {
        // Reinterpret the same numbers, never convert the absolute date or clamp invalid days.
        if rule.calendar == .gregorian {
            rule.isLeapMonth = false; rule.leapMonthRule = nil; rule.shortMonthRule = nil
            if rule.preset != .anniversary || rule.month != 2 || rule.day != 29 { rule.leapDayRule = nil }
        } else {
            rule.leapDayRule = nil
            if !rule.isLeapMonth { rule.leapMonthRule = nil }
            if rule.day != 30 { rule.shortMonthRule = nil }
        }
    }
    static func previewDates(rule: ImportantDayDateRule, today: ImportantCivilDay) -> [ImportantCivilDay] {
        guard rule.preset == .anniversary, (try? rule.validate()) != nil,
              ImportantDayDateEngine.years.contains(today.year) else { return [] }
        let firstYear = max(ImportantDayDateEngine.years.lowerBound, today.year - 1, rule.year ?? 1901)
        guard firstYear <= ImportantDayDateEngine.years.upperBound else { return [] }
        var dates: [ImportantCivilDay] = []
        for year in firstYear...ImportantDayDateEngine.years.upperBound {
            if let date = try? ImportantDayDateEngine.explicitPeriod(rule, year: year), date >= today {
                dates.append(date); if dates.count == 3 { break }
            }
        }
        return dates
    }
}

extension ImportantDayDateRule {
    var associationDateRule: Self {
        var value = self; value.perspective = .next; return value
    }
}

enum ImportantDayAssociationKind: CaseIterable { case entry, existingEntry, todo }
enum ImportantDayAssociationError: Error, LocalizedError, Equatable {
    case unavailable, dateChanged, invalidPeriod
    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "This day was removed or archived. Your draft was kept. Restore the day before saving.")
        case .dateChanged: String(localized: "This day's date changed. Confirm the association below before saving. Your draft was kept.")
        case .invalidPeriod: String(localized: "Choose a valid anniversary year before saving.")
        }
    }
}

/// One transient user operation. Neither the clock nor a re-render can change its intent.
@MainActor
struct ImportantDayAssociationOperation: Identifiable {
    let id: UUID
    let kind: ImportantDayAssociationKind
    let dayID: UUID
    let rule: ImportantDayDateRule
    let selectedYear: Int?
    let occurrence: ImportantCivilDay?
    init(day: ImportantDay, kind: ImportantDayAssociationKind, selection: ImportantDayPeriodSelection,
         today: ImportantCivilDay, id: UUID = UUID()) throws {
        guard !day.isArchived else { throw ImportantDayAssociationError.unavailable }
        let rule = try day.rule(); try rule.validate()
        let year = selection.isExplicit ? selection.selectedYear(rule: rule, today: today) : nil
        let occurrence: ImportantCivilDay?
        if let year {
            guard let date = try ImportantDayDateEngine.explicitPeriod(rule, year: year) else { throw ImportantDayAssociationError.invalidPeriod }
            occurrence = date
        } else { occurrence = nil }
        self.id = id; self.kind = kind; dayID = day.id; self.rule = rule; selectedYear = year; self.occurrence = occurrence
    }
    func validate(day: ImportantDay?) throws {
        guard let day, day.id == dayID, !day.isArchived else { throw ImportantDayAssociationError.unavailable }
        let current = try day.rule(); try current.validate()
        guard current.associationDateRule == rule.associationDateRule else { throw ImportantDayAssociationError.dateChanged }
    }
    func validate(context: ModelContext) throws {
        let target = dayID
        try validate(day: context.fetch(FetchDescriptor<ImportantDay>(predicate: #Predicate { $0.id == target })).first)
    }
    func createEntry(_ draft: EntryCreationDraft, service: ImportantDayService) throws -> Entry {
        try validate(day: service.day(id: dayID))
        return try service.createEntry(draft, dayID: dayID, occurrence: occurrence)
    }
    func linkEntry(_ entryID: UUID, service: ImportantDayService) throws {
        try validate(day: service.day(id: dayID))
        try service.linkEntry(dayID: dayID, entryID: entryID, occurrence: occurrence)
    }
    func createTodo(_ draft: TodoDraft, id: UUID, context: ModelContext) throws -> TodoTask {
        try validate(context: context)
        return try TodoTaskService(context: context).create(draft, id: id, importantDayID: dayID, importantDayOccurrence: occurrence)
    }
}

// Only the Important Days display clock is replaceable in an isolated DEBUG UI fixture.
// Entry creation and system time keep their normal clock.
@MainActor
enum ImportantDayReferenceClock {
    static func now() -> Date {
        #if DEBUG
        if ImportantDayUITestFixture.isReviewTest, let date = ImportantDayUITestFixture.referenceDateOverride { return date }
        #endif
        return Date()
    }
}

enum ImportantDayFavoritePolicy {
    static func canReorder(query: String) -> Bool { TextSearchNormalizer.normalize(query).isEmpty }
}
