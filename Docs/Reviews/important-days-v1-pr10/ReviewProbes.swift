import Foundation

// Independent, dependency-free review harness.
// ImportantDayDate.swift beside this file is byte-identical to Git blob
// 456a4cca8a78c51f49fd6f263bafd19f9e712163 at PR #10 delivery HEAD.
// View-state snippets below reproduce the relevant expressions only;
// this is NOT an iOS/SwiftUI/SwiftData/XCTest run.
@main
struct ReviewProbes {
    static func selectedPeriod(rule: ImportantDayDateRule, reference: ImportantCivilDay,
                               occurrenceYear: Int? = nil) throws -> ImportantCivilDay? {
        let next = try ImportantDayDateEngine.evaluate(rule, today: reference).next
        let selectedYear: Int
        if let occurrenceYear, ImportantDayDateEngine.years.contains(occurrenceYear), occurrenceYear >= (rule.year ?? 1901) {
            selectedYear = occurrenceYear
        } else if let next {
            selectedYear = [next.year - 1, next.year].first {
                (try? ImportantDayDateEngine.occurrence(rule, in: $0)) == next
            } ?? reference.year
        } else { selectedYear = max(reference.year, rule.year ?? reference.year) }
        return try ImportantDayDateEngine.explicitPeriod(rule, year: selectedYear)
    }

    static func main() throws {
        print("Environment: Swift Foundation on Linux; no Apple UI or persistence frameworks executed.")
        print("Scope: fixed-source date engine + isolated view/service state expressions.\n")

        // R1: toggling specific-period on without touching its year picker keeps year nil.
        let annual = ImportantDayDateRule(preset: .anniversary, year: 2020, month: 10, day: 15)
        let before = try selectedPeriod(rule: annual, reference: .init(year: 2026, month: 10, day: 15))!
        let after = try selectedPeriod(rule: annual, reference: .init(year: 2026, month: 10, day: 16))!
        let fixed = try selectedPeriod(rule: annual, reference: .init(year: 2026, month: 10, day: 16), occurrenceYear: 2026)!
        assert(before.identifier == "2026-10-15")
        assert(after.identifier == "2027-10-15")
        assert(fixed == before)
        print("R1 OBSERVED: opening period=\(before.identifier); same nil-year selection after midnight=\(after.identifier).")
        print("R1 CONTROL: explicitly frozen year keeps period=\(fixed.identifier).\n")

        // R2: same state/filter expressions from ImportantDayDetailView.
        struct Link { let entryID: String; let occurrenceIdentifier: String? }
        func state(links: [Link], filter: String) -> (periods: [String], entries: [String]) {
            let periods = Array(Set(links.compactMap(\.occurrenceIdentifier))).sorted().reversed()
            let ids = links.filter {
                filter == "all" || (filter == "general" ? $0.occurrenceIdentifier == nil : $0.occurrenceIdentifier == filter)
            }.map(\.entryID)
            return (Array(periods), ids)
        }
        let filter = "2026-10-15"
        let links = [Link(entryID: "general-A", occurrenceIdentifier: nil), Link(entryID: "general-B", occurrenceIdentifier: nil), Link(entryID: "period-note", occurrenceIdentifier: filter)]
        let afterUnlink = links.filter { $0.entryID != "period-note" }
        let stale = state(links: afterUnlink, filter: filter)
        let reset = state(links: afterUnlink, filter: "all")
        assert(stale.periods.isEmpty && stale.entries.isEmpty)
        assert(reset.entries.count == 2)
        print("R2 OBSERVED: remaining links=\(afterUnlink.count), periods=\(stale.periods), filtered entries=\(stale.entries); Picker is hidden.")
        print("R2 CONTROL: resetting filter to all shows \(reset.entries).\n")

        // R3: editor calendar onChange only marks acknowledgment; lunar flag survives.
        var rule = ImportantDayDateRule(preset: .anniversary, calendar: .chinese, year: 2023, month: 2, day: 1,
                                        isLeapMonth: true, leapMonthRule: .regularFallback)
        try rule.validate()
        let lunarOriginal = try ImportantDayDateEngine.original(rule, in: 2023)!
        assert(lunarOriginal.identifier == "2023-03-22")
        rule.calendar = .gregorian
        let leapToggleVisible = rule.calendar == .chinese
        let numericDateValid = ImportantCivilDay(year: 2023, month: 2, day: 1).date != nil
        let validAfterSwitch = (try? rule.validate()) != nil
        assert(numericDateValid && !leapToggleVisible && !validAfterSwitch)
        rule.isLeapMonth = false
        try rule.validate()
        print("R3 OBSERVED: Gregorian numeric date valid=\(numericDateValid), lunar toggle visible=\(leapToggleVisible), saved-rule valid=\(validAfterSwitch).")
        print("R3 CONTROL: clearing incompatible lunar flag makes identical Gregorian date valid.\n")

        // R4: filtered favorite IDs are densely reindexed, but omitted favorites keep old ranks.
        struct Favorite { let id: String; var order: Int }
        func sorted(_ list: [Favorite]) -> [String] {
            list.sorted { $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order }.map(\.id)
        }
        var full = [Favorite(id: "A", order: 0), Favorite(id: "B", order: 1), Favorite(id: "C", order: 2), Favorite(id: "D", order: 3)]
        let filteredMoved = ["D", "C"]
        for (index, id) in filteredMoved.enumerated() { full[full.firstIndex { $0.id == id }!].order = index }
        assert(Set(full.map(\.order)).count != full.count)
        assert(sorted(full) == ["A", "D", "B", "C"])
        print("R4 OBSERVED: moving filtered [C,D] to [D,C] stores \(full.map { "\($0.id)=\($0.order)" }); full order=\(sorted(full)).")
        print("R4 EXPECTED with hidden favorites preserved: [A,B,D,C], or disable reorder while filtering.\n")

        // Additional non-blocking diagnostic: previewDates does not constrain candidate year to rule.year.
        let future = ImportantDayDateRule(preset: .anniversary, year: 2030, month: 12, day: 1)
        let ref = ImportantCivilDay(year: 2026, month: 10, day: 15)
        let next = try ImportantDayDateEngine.evaluate(future, today: ref).next!
        let previewDates = (max(1901, ref.year - 1)...min(2100, ref.year + 8))
            .compactMap { try? ImportantDayDateEngine.occurrence(future, in: $0) }.filter { $0 >= ref }.prefix(3)
        print("Additional diagnostic: future origin next=\(next.identifier), editor preview rows=\(previewDates.map(\.identifier)).")
        print("All 4 counterexample/control probes completed. Assertions verify observed code behavior, not product correctness.")
    }
}
