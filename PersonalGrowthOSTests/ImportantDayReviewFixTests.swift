import SwiftData
import XCTest
@testable import PersonalGrowthOS

@MainActor
final class ImportantDayReviewFixTests: XCTestCase {
    func testUnconfirmedGregorianRoundTripClearsHiddenLunarFieldsAndKeepsEdits() throws {
        var draft = ImportantDayDraft()
        draft.title = "Edited title"; draft.notes = "Keep this note"
        draft.preferences.cropX = 0.3; draft.preferences.today = .always
        draft.rule = .init(preset: .anniversary, year: 2023, month: 2, day: 1, perspective: .elapsed)
        draft.rule.calendar = .chinese
        XCTAssertTrue(ImportantDayEditorPolicy.calendarSelectionChanged(&draft.rule, acknowledged: .gregorian))
        draft.rule.isLeapMonth = true; draft.rule.leapMonthRule = .regularFallback
        draft.rule.calendar = .gregorian
        XCTAssertFalse(ImportantDayEditorPolicy.calendarSelectionChanged(&draft.rule, acknowledged: .gregorian))
        XCTAssertFalse(draft.rule.isLeapMonth); XCTAssertNil(draft.rule.leapMonthRule)
        XCTAssertEqual(draft.rule.year, 2023); XCTAssertEqual(draft.rule.month, 2); XCTAssertEqual(draft.rule.day, 1)
        XCTAssertEqual(draft.rule.perspective, .elapsed)
        XCTAssertEqual(draft.title, "Edited title"); XCTAssertEqual(draft.notes, "Keep this note")
        XCTAssertEqual(draft.preferences.cropX, 0.3); XCTAssertEqual(draft.preferences.today, .always)
        XCTAssertNoThrow(try draft.validate())
        let (root, container, service) = try store()
        defer { withExtendedLifetime(container) {} }
        let day = try service.save(draft)
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: root.appendingPathComponent("store.sqlite"))
        let saved = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<ImportantDay>()).first { $0.id == day.id })
        let restored = try ImportantDayDraft(saved)
        XCTAssertEqual(restored.title, draft.title); XCTAssertEqual(restored.notes, draft.notes)
        XCTAssertEqual(restored.rule, draft.rule); XCTAssertEqual(restored.preferences, draft.preferences)
    }
    func testUnconfirmedLunarRoundTripClearsGregorianOnlyRuleAndPreservesOriginalLunarFacts() throws {
        var rule = ImportantDayDateRule(preset: .anniversary, calendar: .chinese, year: 2023, month: 2, day: 1, isLeapMonth: true, leapMonthRule: .regularFallback, perspective: .elapsed)
        let original = rule
        rule.calendar = .gregorian
        XCTAssertTrue(ImportantDayEditorPolicy.calendarSelectionChanged(&rule, acknowledged: .chinese))
        rule.leapDayRule = .february28
        rule.calendar = .chinese
        XCTAssertFalse(ImportantDayEditorPolicy.calendarSelectionChanged(&rule, acknowledged: .chinese))
        XCTAssertEqual(rule, original)
        XCTAssertNoThrow(try rule.validate())
    }
    func testCalendarRoundTripNeverClampsChangedNumbersOrSuppliesLeapDayChoice() throws {
        var rule = ImportantDayDateRule(preset: .anniversary, calendar: .chinese, year: 2023, month: 2, day: 30, shortMonthRule: .lastDay)
        rule.calendar = .gregorian
        XCTAssertFalse(ImportantDayEditorPolicy.calendarSelectionChanged(&rule, acknowledged: .gregorian))
        XCTAssertEqual(rule.year, 2023); XCTAssertEqual(rule.month, 2); XCTAssertEqual(rule.day, 30)
        XCTAssertThrowsError(try rule.validate())
        rule.year = 2024; rule.day = 29; rule.leapDayRule = nil
        XCTAssertFalse(ImportantDayEditorPolicy.calendarSelectionChanged(&rule, acknowledged: .gregorian))
        XCTAssertThrowsError(try rule.validate())
        rule.leapDayRule = .march1; XCTAssertNoThrow(try rule.validate())
        rule.isLeapMonth = true; XCTAssertThrowsError(try rule.validate())
    }
    func testCalendarSelectionStillRequiresExplicitConfirmationForDifferentCalendar() throws {
        var rule = ImportantDayDateRule(preset: .anniversary, year: 2024, month: 2, day: 29, leapDayRule: .march1, perspective: .elapsed)
        rule.calendar = .chinese
        XCTAssertTrue(ImportantDayEditorPolicy.calendarSelectionChanged(&rule, acknowledged: .gregorian))
        XCTAssertEqual(rule.leapDayRule, .march1) // no implicit confirmation/normalization of another calendar
        ImportantDayEditorPolicy.confirmCalendar(&rule)
        XCTAssertNil(rule.leapDayRule); XCTAssertEqual(rule.perspective, .elapsed)
        XCTAssertNoThrow(try rule.validate())
        rule.calendar = .gregorian
        XCTAssertTrue(ImportantDayEditorPolicy.calendarSelectionChanged(&rule, acknowledged: .chinese))
        ImportantDayEditorPolicy.confirmCalendar(&rule)
        XCTAssertEqual(rule.day, 29); XCTAssertNil(rule.leapDayRule)
        XCTAssertThrowsError(try rule.validate()) // needs a fresh explicit leap-day policy
    }
    func testCalendarHydrationAndReturnPreserveValidOriginalRules() throws {
        for original in [
            ImportantDayDateRule(preset: .anniversary, year: 2024, month: 2, day: 29, leapDayRule: .march1, perspective: .elapsed),
            ImportantDayDateRule(preset: .anniversary, calendar: .chinese, year: 2023, month: 2, day: 1, isLeapMonth: true, leapMonthRule: .regularFallback, perspective: .elapsed),
            ImportantDayDateRule(preset: .anniversary, calendar: .chinese, year: 2025, month: 1, day: 30, shortMonthRule: .lastDay)
        ] {
            var rule = original; try rule.validate()
            XCTAssertFalse(ImportantDayEditorPolicy.calendarSelectionChanged(&rule, acknowledged: original.calendar))
            XCTAssertEqual(rule, original)
            rule.calendar = original.calendar == .gregorian ? .chinese : .gregorian
            XCTAssertTrue(ImportantDayEditorPolicy.calendarSelectionChanged(&rule, acknowledged: original.calendar))
            rule.calendar = original.calendar
            XCTAssertFalse(ImportantDayEditorPolicy.calendarSelectionChanged(&rule, acknowledged: original.calendar))
            XCTAssertEqual(rule, original); XCTAssertNoThrow(try rule.validate())
        }
    }
    func testDefaultExplicitYearRemainsSelectedAcrossReferenceDayRefresh() throws {
        let rule = ImportantDayDateRule(preset: .anniversary, year: 2020, month: 10, day: 15)
        var selection = ImportantDayPeriodSelection()
        selection.chooseExplicit(true, rule: rule, today: .init(year: 2026, month: 10, day: 15))
        XCTAssertEqual(selection.occurrence(rule: rule, today: .init(year: 2026, month: 10, day: 15))?.identifier, "2026-10-15")
        XCTAssertEqual(selection.occurrence(rule: rule, today: .init(year: 2026, month: 10, day: 16))?.identifier, "2026-10-15")
    }
    func testVanishedPeriodFilterReturnsToAllWhileValidAndGeneralStay() {
        var filter = ImportantDayEntryFilter(selection: "2026-10-15")
        filter.reconcile(periods: [])
        XCTAssertEqual(filter.effectiveSelection(periods: []), "all")
        filter.selection = "2026-10-15"; filter.reconcile(periods: ["2027-10-15"])
        XCTAssertEqual(filter.selection, "all")
        filter.selection = "2027-10-15"; filter.reconcile(periods: ["2027-10-15"])
        XCTAssertEqual(filter.selection, "2027-10-15")
        filter.selection = "general"; filter.reconcile(periods: [])
        XCTAssertEqual(filter.selection, "general")
    }
    func testConfirmedGregorianCalendarClearsHiddenLunarFieldsWithoutChangingNumbers() throws {
        var rule = ImportantDayDateRule(preset: .anniversary, calendar: .chinese, year: 2023, month: 2, day: 1, isLeapMonth: true, leapMonthRule: .regularFallback)
        try rule.validate(); rule.calendar = .gregorian
        ImportantDayEditorPolicy.confirmCalendar(&rule)
        XCTAssertFalse(rule.isLeapMonth); XCTAssertNil(rule.leapMonthRule)
        XCTAssertEqual(rule.year, 2023); XCTAssertEqual(rule.month, 2); XCTAssertEqual(rule.day, 1)
        XCTAssertNoThrow(try rule.validate())
    }
    func testFilteredFavoriteReorderPreservesGlobalSlotsIncludingHiddenArchivedAndReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DayReview-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("store.sqlite"), container = try PersistenceContainerFactory.makeOnDisk(at: url)
        let context = container.mainContext, service = ImportantDayService(context: context, mediaStore: MediaStore(rootURL: root))
        var days: [ImportantDay] = []
        for (index, name) in ["A", "B", "C", "D"].enumerated() {
            var draft = ImportantDayDraft(); draft.title = name; draft.rule = .init(year: 2026, month: 10, day: 15)
            draft.preferences.favoriteOrder = index; draft.archived = name == "B"
            days.append(try service.save(draft, id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!))
        }
        try service.reorderFavorites([days[3].id, days[2].id])
        XCTAssertEqual(try days.map { try $0.preferences().favoriteOrder }, [0, 1, 3, 2])
        XCTAssertTrue(days[1].isArchived)
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: url)
        let ordered = try reopened.mainContext.fetch(FetchDescriptor<ImportantDay>()).sorted { (try! $0.preferences().favoriteOrder!) < (try! $1.preferences().favoriteOrder!) }
        XCTAssertEqual(ordered.map(\.title), ["A", "B", "D", "C"])
    }
    func testAdditionalPreviewRespectsFutureOriginAndSupportedBoundary() {
        let rule = ImportantDayDateRule(preset: .anniversary, year: 2030, month: 12, day: 1)
        XCTAssertEqual(ImportantDayEditorPolicy.previewDates(rule: rule, today: .init(year: 2026, month: 10, day: 15)).map(\.identifier), ["2030-12-01", "2031-12-01", "2032-12-01"])
    }
}

@MainActor
extension ImportantDayReviewFixTests {
    private func store() throws -> (URL, ModelContainer, ImportantDayService) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DayOperations-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Retain this synthetic disk root until the test host releases SQLite handles.
        let container = try PersistenceContainerFactory.makeOnDisk(at: root.appendingPathComponent("store.sqlite"))
        let now = ImportantCivilDay(year: 2026, month: 10, day: 16).instant(minutes: 720, timeZone: .current)!
        return (root, container, .init(context: container.mainContext, mediaStore: MediaStore(rootURL: root), now: { now }))
    }
    private func makeDay(_ service: ImportantDayService) throws -> ImportantDay {
        var draft = ImportantDayDraft(); draft.title = "Stable operation"
        draft.rule = .init(preset: .anniversary, year: 2020, month: 10, day: 15)
        return try service.save(draft)
    }
    func testAllThreeOperationKindsPersistFrozenDefaultAndOrdinaryNilThenReopen() throws {
        let (root, container, service) = try store(), c = container.mainContext
        let day = try makeDay(service)
        var selection = ImportantDayPeriodSelection()
        selection.chooseExplicit(true, rule: try day.rule(), today: .init(year: 2026, month: 10, day: 15))
        let originalOccurredAt = ImportantCivilDay(year: 2001, month: 1, day: 1).date!
        let old = Entry(body: "Existing original", createdAt: originalOccurredAt); c.insert(old); try c.save()
        for kind in ImportantDayAssociationKind.allCases {
            let operation = try ImportantDayAssociationOperation(day: day, kind: kind, selection: selection, today: .init(year: 2026, month: 10, day: 16))
            XCTAssertEqual(operation.occurrence?.identifier, "2026-10-15")
            switch kind {
            case .entry:
                let entry = try operation.createEntry(.init(body: "Written after midnight"), service: service)
                XCTAssertEqual(ImportantCivilDay(entry.occurredAt).identifier, "2026-10-16")
            case .existingEntry: try operation.linkEntry(old.id, service: service)
            case .todo: _ = try operation.createTodo(.init(title: "Independent Todo"), id: UUID(), context: c)
            }
            let ordinary = try ImportantDayAssociationOperation(day: day, kind: kind, selection: .init(), today: .init(year: 2026, month: 10, day: 16))
            XCTAssertNil(ordinary.occurrence)
            switch kind {
            case .entry: _ = try ordinary.createEntry(.init(body: "General related entry"), service: service)
            case .existingEntry:
                let general = Entry(body: "General existing entry", createdAt: originalOccurredAt); c.insert(general); try c.save()
                try ordinary.linkEntry(general.id, service: service)
                XCTAssertEqual(general.occurredAt, originalOccurredAt)
            case .todo: _ = try ordinary.createTodo(.init(title: "General related Todo"), id: UUID(), context: c)
            }
        }
        XCTAssertEqual(old.createdAt, originalOccurredAt); XCTAssertEqual(old.occurredAt, originalOccurredAt)
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: root.appendingPathComponent("store.sqlite"))
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<ImportantDayEntryLink>()).map(\.occurrenceIdentifier).sorted { ($0 ?? "") < ($1 ?? "") }, [nil, nil, "2026-10-15", "2026-10-15"])
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<ImportantDayTodoLink>()).map(\.occurrenceIdentifier).sorted { ($0 ?? "") < ($1 ?? "") }, [nil, "2026-10-15"])
    }
    func testHistoricalLunarYearEndAndCancelReopenProduceExplicitIndependentContexts() throws {
        let (_, container, service) = try store(), day = try makeDay(service)
        defer { withExtendedLifetime(container) {} }
        var edit = try ImportantDayDraft(day); edit.rule = .init(preset: .anniversary, calendar: .chinese, year: nil, month: 12, day: 30, shortMonthRule: .lastDay)
        _ = try service.save(edit, id: day.id)
        var selection = ImportantDayPeriodSelection()
        selection.chooseExplicit(true, rule: edit.rule, today: .init(year: 2024, month: 2, day: 9))
        XCTAssertEqual(selection.year, 2023)
        let operation = try ImportantDayAssociationOperation(day: day, kind: .entry, selection: selection, today: .init(year: 2024, month: 2, day: 10))
        XCTAssertEqual(operation.occurrence?.identifier, "2024-02-09")
        selection.chooseExplicit(false, rule: edit.rule, today: .init(year: 2024, month: 2, day: 10))
        selection.chooseExplicit(true, rule: edit.rule, today: .init(year: 2024, month: 2, day: 10))
        XCTAssertEqual(selection.year, 2024)
        XCTAssertEqual(operation.selectedYear, 2023)
        selection.year = 2020
        let historical = try ImportantDayAssociationOperation(day: day, kind: .existingEntry, selection: selection, today: .init(year: 2026, month: 1, day: 1))
        XCTAssertEqual(historical.occurrence, try ImportantDayDateEngine.explicitPeriod(edit.rule, year: 2020))
    }
    func testOperationRejectsRealDateChangeButAllowsDecorationAndPreservesHistoricalLinks() throws {
        let (root, container, service) = try store(), day = try makeDay(service), c = container.mainContext
        var selection = ImportantDayPeriodSelection(); selection.chooseExplicit(true, rule: try day.rule(), today: .init(year: 2026, month: 10, day: 15))
        let operation = try ImportantDayAssociationOperation(day: day, kind: .entry, selection: selection, today: .init(year: 2026, month: 10, day: 15))
        _ = try operation.createEntry(.init(body: "Historical link"), service: service)
        var edit = try ImportantDayDraft(day); edit.title = "Renamed"; edit.notes = "New note"
        edit.preferences.today = .hidden; edit.preferences.reminderOffsets = [0]; edit.preferences.photoStyle = true
        edit.rule.perspective = .elapsed
        _ = try service.save(edit, id: day.id); XCTAssertNoThrow(try operation.validate(context: c))
        edit.rule.day = 16; _ = try service.save(edit, id: day.id)
        XCTAssertThrowsError(try operation.createEntry(.init(body: "Keep my draft"), service: service)) { XCTAssertEqual($0 as? ImportantDayAssociationError, .dateChanged) }
        let existing = Entry(body: "Unlinked", createdAt: Date()); c.insert(existing); try c.save()
        XCTAssertThrowsError(try operation.linkEntry(existing.id, service: service))
        XCTAssertThrowsError(try operation.createTodo(.init(title: "Keep my Todo draft"), id: UUID(), context: c))
        XCTAssertEqual(try c.fetchCount(FetchDescriptor<TodoTask>()), 0)
        XCTAssertEqual(try c.fetch(FetchDescriptor<ImportantDayEntryLink>()).map(\.occurrenceIdentifier), ["2026-10-15"])
        XCTAssertNoThrow(try ImportantDayIntegrity.validate(context: c))
        XCTAssertNoThrow(try TransferSnapshot.make(context: c)) // Historical periods need not match the edited rule.
        let confirmed = try ImportantDayAssociationOperation(day: day, kind: operation.kind, selection: selection, today: .init(year: 2026, month: 10, day: 16), id: operation.id)
        _ = try confirmed.createEntry(.init(body: "Recovered draft"), service: service)
        XCTAssertEqual(confirmed.id, operation.id); XCTAssertEqual(confirmed.occurrence?.identifier, "2026-10-16")
        edit.archived = true; _ = try service.save(edit, id: day.id)
        XCTAssertThrowsError(try confirmed.validate(context: c))
        try service.delete(id: day.id); XCTAssertThrowsError(try confirmed.validate(context: c))
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: root.appendingPathComponent("store.sqlite"))
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<Entry>()), 3)
    }
    func testActualUnlinkAndEntryDeletionNormalizeFilterWithoutReplacingEntries() throws {
        let (root, container, service) = try store(), day = try makeDay(service), c = container.mainContext
        let a = try service.createEntry(.init(body: "General A"), dayID: day.id)
        _ = try service.createEntry(.init(body: "General B"), dayID: day.id)
        let period = try service.createEntry(.init(body: "Explicit"), dayID: day.id, occurrence: .init(year: 2026, month: 10, day: 15))
        let another = try service.createEntry(.init(body: "Other year"), dayID: day.id, occurrence: .init(year: 2025, month: 10, day: 15))
        func periods() throws -> [String] { try c.fetch(FetchDescriptor<ImportantDayEntryLink>()).compactMap(\.occurrenceIdentifier) }
        var filter = ImportantDayEntryFilter(selection: "2026-10-15")
        try service.unlinkEntry(dayID: day.id, entryID: period.id); filter.reconcile(periods: try periods())
        XCTAssertEqual(filter.selection, "all"); XCTAssertEqual(try c.fetchCount(FetchDescriptor<Entry>()), 4)
        filter.selection = "2025-10-15"; filter.reconcile(periods: try periods()); XCTAssertEqual(filter.selection, "2025-10-15")
        try EntryDeletionService(persistence: ModelContextEntryPersistence(context: c), mediaStore: MediaStore(rootURL: root)).permanentlyDelete(another)
        filter.reconcile(periods: try periods()); XCTAssertEqual(filter.selection, "all")
        XCTAssertTrue(try periods().isEmpty); XCTAssertEqual(try c.fetchCount(FetchDescriptor<ImportantDayEntryLink>()), 2)
        try service.unlinkEntry(dayID: day.id, entryID: a.id)
        let remaining = try XCTUnwrap(c.fetch(FetchDescriptor<ImportantDayEntryLink>()).first)
        try service.unlinkEntry(dayID: day.id, entryID: remaining.entryID); filter.reconcile(periods: try periods())
        XCTAssertEqual(filter.selection, "all"); XCTAssertEqual(try c.fetchCount(FetchDescriptor<ImportantDayEntryLink>()), 0)
    }
    func testConfirmedCalendarNeverClampsInvalidDayOrSuppliesRequiredLeapDayPolicy() throws {
        var leap = ImportantDayDateRule(preset: .anniversary, year: 2024, month: 2, day: 29)
        ImportantDayEditorPolicy.confirmCalendar(&leap); XCTAssertNil(leap.leapDayRule); XCTAssertThrowsError(try leap.validate())
        var invalid = ImportantDayDateRule(preset: .anniversary, year: nil, month: 1, day: 31)
        invalid.calendar = .chinese; ImportantDayEditorPolicy.confirmCalendar(&invalid)
        XCTAssertEqual(invalid.day, 31); XCTAssertThrowsError(try invalid.validate())
        invalid.day = 30; XCTAssertNil(invalid.shortMonthRule); XCTAssertThrowsError(try invalid.validate())
        var ordinary = ImportantDayDateRule(preset: .anniversary, calendar: .chinese, year: 2023, month: 2, day: 1, perspective: .elapsed)
        ordinary.calendar = .gregorian; ImportantDayEditorPolicy.confirmCalendar(&ordinary)
        XCTAssertNoThrow(try ordinary.validate()); XCTAssertEqual(ordinary.perspective, .elapsed)
        XCTAssertEqual(ordinary.month, 2); XCTAssertEqual(ordinary.day, 1)
    }
    func testPreviewAtRangeEndAndNoNextOccurrenceIsBounded() {
        let today = ImportantCivilDay(year: 2099, month: 12, day: 31)
        let rule = ImportantDayDateRule(preset: .anniversary, year: 2100, month: 12, day: 31)
        XCTAssertEqual(ImportantDayEditorPolicy.previewDates(rule: rule, today: today).map(\.identifier), ["2100-12-31"])
        let leap = ImportantDayDateRule(preset: .anniversary, year: nil, month: 2, day: 29, leapDayRule: .leapYearsOnly)
        XCTAssertTrue(ImportantDayEditorPolicy.previewDates(rule: leap, today: today).isEmpty)
        XCTAssertTrue(ImportantDayEditorPolicy.previewDates(rule: rule, today: .init(year: 2101, month: 1, day: 1)).isEmpty)
    }
}

@MainActor
extension ImportantDayReviewFixTests {
    func testGlobalFavoriteReorderValidatesDomainAndRollsBackAllSlots() throws {
        let (root, container, service) = try store(), c = container.mainContext
        var ids: [UUID] = []
        for index in 0..<4 {
            var draft = ImportantDayDraft(); draft.title = "Favorite \(index)"
            draft.preferences.favoriteOrder = index; draft.archived = index == 1
            ids.append(try service.save(draft).id)
        }
        func ranks() throws -> [Int?] { try ids.map { try service.day(id: $0).preferences().favoriteOrder } }
        XCTAssertFalse(ImportantDayFavoritePolicy.canReorder(query: " pair "))
        XCTAssertTrue(ImportantDayFavoritePolicy.canReorder(query: "  "))
        XCTAssertThrowsError(try service.reorderFavorites([ids[0], ids[0]])); XCTAssertEqual(try ranks(), [0, 1, 2, 3])
        XCTAssertThrowsError(try service.reorderFavorites([UUID()])); XCTAssertEqual(try ranks(), [0, 1, 2, 3])
        let nonFavorite = try makeDay(service)
        XCTAssertThrowsError(try service.reorderFavorites([nonFavorite.id])); XCTAssertNil(try nonFavorite.preferences().favoriteOrder)
        let failing = ImportantDayService(context: c, mediaStore: MediaStore(rootURL: root), commit: { throw CocoaError(.fileWriteOutOfSpace) })
        XCTAssertThrowsError(try failing.reorderFavorites([ids[3], ids[2]])); XCTAssertEqual(try ranks(), [0, 1, 2, 3])
        try service.reorderFavorites([ids[3], ids[2], ids[1], ids[0]])
        XCTAssertEqual(try ranks(), [3, 2, 1, 0])
        var restored = try ImportantDayDraft(service.day(id: ids[1])); restored.archived = false; _ = try service.save(restored, id: ids[1])
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: root.appendingPathComponent("store.sqlite"))
        let all = try reopened.mainContext.fetch(FetchDescriptor<ImportantDay>()).filter { (try? $0.preferences().favoriteOrder) != nil }
        XCTAssertEqual(all.sorted { (try! $0.preferences().favoriteOrder!) < (try! $1.preferences().favoriteOrder!) }.map(\.id), Array(ids.reversed()))
        XCTAssertFalse(try XCTUnwrap(all.first { $0.id == ids[1] }).isArchived)
    }
}
