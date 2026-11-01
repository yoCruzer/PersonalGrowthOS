import Foundation
import SwiftData

enum NetWorthFailure: Error, LocalizedError {
    case invalid, conflict, duplicateDay, archiveBalance, archivedHistory
    var errorDescription: String? {
        switch self {
        case .invalid: String(localized: "Check the amount, date and confirmation status. Your input is kept.")
        case .conflict: String(localized: "This inventory changed elsewhere. Your draft is kept; reopen to compare.")
        case .duplicateDay: String(localized: "A snapshot already exists on this date. Open it to make a correction.")
        case .archiveBalance: String(localized: "Record a confirmed zero balance before archiving this item.")
        case .archivedHistory: String(localized: "Restore the archived item before changing its final zero balance. Your draft is kept.")
        }
    }
}

enum NetWorthMoney {
    static let maximum: Int64 = 9_000_000_000_000_000
    static func parse(_ text: String, locale: Locale = .current) throws -> Int64? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        let separator = locale.decimalSeparator ?? "."
        let normalized = separator == "." ? text : text.replacingOccurrences(of: separator, with: ".")
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), !parts[0].isEmpty,
              parts.allSatisfy({ $0.allSatisfy { $0 >= "0" && $0 <= "9" } }),
              parts.count == 1 || (1...2).contains(parts[1].count),
              let whole = Int64(parts[0]), whole <= maximum / 100 else { throw NetWorthFailure.invalid }
        let fraction = parts.count == 2 ? Int64(parts[1])! * (parts[1].count == 1 ? 10 : 1) : 0
        let cents = whole * 100 + fraction
        guard cents <= maximum else { throw NetWorthFailure.invalid }
        return cents
    }
    static func decimal(_ cents: Int64) -> String {
        let magnitude = cents.magnitude
        return "\(cents < 0 ? "-" : "")\(magnitude / 100)." + String(format: "%02llu", magnitude % 100)
    }
    static func display(_ cents: Int64) -> String { display(cents, locale: .current) }
    static func display(_ cents: Int64, locale: Locale) -> String {
        let formatter = NumberFormatter(); formatter.locale = locale; formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(string: decimal(cents), locale: Locale(identifier: "en_US_POSIX"))) ?? decimal(cents)
    }
    static func sum(_ values: [Int64]) throws -> Int64 {
        try values.reduce(0) { total, value in
            let (sum, overflow) = total.addingReportingOverflow(value)
            guard value >= 0, value <= maximum, !overflow, sum <= maximum else { throw NetWorthFailure.invalid }
            return sum
        }
    }
}

enum NetWorthSide: String, Codable, CaseIterable { case asset, liability
    var title: String { self == .asset ? String(localized: "Assets") : String(localized: "Liabilities") }
}
enum NetWorthCategory: String, Codable, CaseIterable {
    case cash, investments, property, valuables, receivables, mortgage, vehicleLoan, credit, otherDebt
    var side: NetWorthSide { [.mortgage, .vehicleLoan, .credit, .otherDebt].contains(self) ? .liability : .asset }
    var title: String {
        switch self {
        case .cash: String(localized: "Cash and deposits")
        case .investments: String(localized: "Investment assets")
        case .property: String(localized: "Property")
        case .valuables: String(localized: "Vehicles and valuables")
        case .receivables: String(localized: "Receivables and other assets")
        case .mortgage: String(localized: "Mortgage balance")
        case .vehicleLoan: String(localized: "Vehicle loan")
        case .credit: String(localized: "Credit cards and consumer loans")
        case .otherDebt: String(localized: "Other liabilities")
        }
    }
    var guidance: String {
        switch self {
        case .property: String(localized: "Use today's estimated value. Record the remaining mortgage principal separately.")
        case .valuables: String(localized: "Use the estimated current value, not the purchase price.")
        case .credit: String(localized: "Record the unpaid balance, not the credit limit or minimum payment.")
        case .investments: String(localized: "Use the account's current value. If borrowing is already deducted, do not record it twice.")
        default: String(localized: "Record the family's share once. Account totals or separate accounts are both welcome.")
        }
    }
}
enum NetWorthAmountState: String, Codable, CaseIterable { case entered, estimated, carriedForward, unknown
    var title: String {
        switch self {
        case .entered: String(localized: "Updated")
        case .estimated: String(localized: "Estimated")
        case .carriedForward: String(localized: "Carried forward")
        case .unknown: String(localized: "Unknown")
        }
    }
}

struct NetWorthItemValue: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var side: NetWorthSide
    var category: NetWorthCategory
    var ownership = ""
    var note = ""
    var archived = false
    var revision = 0
    @TodoTransferInstant var createdAt: Date = Date()
    @TodoTransferInstant var updatedAt: Date = Date()
    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 160,
              category.side == side, ownership.count <= 80, note.count <= 1000,
              revision >= 0, revision < Int.max - 1, createdAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt.timeIntervalSinceReferenceDate.isFinite, updatedAt >= createdAt else { throw NetWorthFailure.invalid }
    }
}
struct NetWorthSnapshotItem: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var side: NetWorthSide
    var category: NetWorthCategory
    var ownership: String
    var included = true
    var cents: Int64? = nil
    var state: NetWorthAmountState = .unknown
    var amountDay: String? = nil
    var note = ""
    // Draft-only text survives invalid intermediate input and process relaunch.
    var inputText: String? = nil
    var pending = false
    init(_ item: NetWorthItemValue) {
        id = item.id; name = item.name; side = item.side; category = item.category; ownership = item.ownership; note = item.note
    }
    mutating func enter(_ text: String, day: String, estimated: Bool = false, locale: Locale = .current) throws {
        inputText = text
        let amount = try NetWorthMoney.parse(text, locale: locale)
        cents = amount; amountDay = amount == nil ? nil : day
        state = amount == nil ? .unknown : (estimated ? .estimated : .entered); pending = false; inputText = nil
    }
}
struct NetWorthSnapshotValue: Codable, Equatable, Identifiable {
    var version = 1
    var id = UUID()
    var day: String
    var timeZoneID = TimeZone.current.identifier
    var confirmed = false
    var assetsConfirmed = false
    var liabilitiesConfirmed = false
    var scopeAdjusted = false
    var note = ""
    var items: [NetWorthSnapshotItem] = []
    var revision = 0
    var editingID: UUID? = nil
    var editingRevision: Int? = nil
    @TodoTransferInstant var createdAt: Date = Date()
    @TodoTransferInstant var updatedAt: Date = Date()
    @TodoTransferOptionalInstant var completedAt: Date? = nil

    mutating func carryRemaining() {
        for index in items.indices where items[index].pending && items[index].inputText == nil {
            items[index].pending = false
            items[index].state = items[index].cents == nil ? .unknown : .carriedForward
        }
    }
    mutating func finalize(locale: Locale = .current) throws {
        for index in items.indices {
            if let text = items[index].inputText {
                try items[index].enter(text, day: day, estimated: items[index].state == .estimated, locale: locale)
            }
            if items[index].pending {
                items[index].cents = nil; items[index].amountDay = nil; items[index].state = .unknown; items[index].pending = false
            }
        }
        confirmed = true; editingID = nil; editingRevision = nil
    }
    func totals() throws -> NetWorthTotals {
        let included = items.filter(\.included)
        let assets = included.filter { $0.side == .asset }, debts = included.filter { $0.side == .liability }
        let a = try NetWorthMoney.sum(assets.compactMap(\.cents)), d = try NetWorthMoney.sum(debts.compactMap(\.cents))
        return .init(assets: a, liabilities: d,
            assetsComplete: assetsConfirmed && assets.allSatisfy { $0.cents != nil && !$0.pending && $0.inputText == nil },
            liabilitiesComplete: liabilitiesConfirmed && debts.allSatisfy { $0.cents != nil && !$0.pending && $0.inputText == nil })
    }
    func validate() throws {
        guard version == 1, ImportantCivilDay(identifier: day) != nil, let zone = TimeZone(identifier: timeZoneID), items.count <= 10000,
              Set(items.map(\.id)).count == items.count, note.count <= 4000,
              revision >= 0, revision < Int.max - 1,
              createdAt.timeIntervalSinceReferenceDate.isFinite, updatedAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt >= createdAt, confirmed == (completedAt != nil),
              completedAt.map({ $0.timeIntervalSinceReferenceDate.isFinite && $0 >= createdAt && $0 <= updatedAt }) ?? true,
              (editingID == nil) == (editingRevision == nil), editingRevision.map({ $0 >= 0 && $0 < Int.max - 1 }) ?? true,
              !confirmed || editingID == nil else { throw NetWorthFailure.invalid }
        if let completedAt, day > ImportantCivilDay(completedAt, timeZone: zone).identifier { throw NetWorthFailure.invalid }
        for row in items {
            guard !row.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, row.name.count <= 160,
                  row.category.side == row.side, row.ownership.count <= 80, row.note.count <= 1000,
                  row.inputText.map({ $0.count <= 100 }) ?? true,
                  !confirmed || (!row.pending && row.inputText == nil),
                  (row.cents == nil) == (row.amountDay == nil),
                  (!confirmed && row.inputText != nil) || (row.cents == nil) == (row.state == .unknown),
                  row.cents.map({ $0 >= 0 && $0 <= NetWorthMoney.maximum }) ?? true,
                  row.amountDay.map({ ImportantCivilDay(identifier: $0) != nil && $0 <= day }) ?? true else { throw NetWorthFailure.invalid }
        }
        _ = try totals()
    }
}
struct NetWorthTotals: Equatable {
    var assets: Int64; var liabilities: Int64; var assetsComplete: Bool; var liabilitiesComplete: Bool
    var net: Int64? { assetsComplete && liabilitiesComplete ? assets - liabilities : nil }
}

// Two additive entities; frozen typed values are version checked at every persistence boundary.
@Model final class NetWorthItem {
    @Attribute(.unique) var id: UUID
    var payload: Data
    init(_ value: NetWorthItemValue) throws { id = value.id; payload = try JSONEncoder().encode(value) }
    func value() throws -> NetWorthItemValue { let v = try JSONDecoder().decode(NetWorthItemValue.self, from: payload); guard v.id == id else { throw NetWorthFailure.invalid }; try v.validate(); return v }
}
@Model final class NetWorthSnapshot {
    @Attribute(.unique) var id: UUID
    var payload: Data
    init(_ value: NetWorthSnapshotValue) throws { id = value.id; payload = try JSONEncoder().encode(value) }
    func value() throws -> NetWorthSnapshotValue { let v = try JSONDecoder().decode(NetWorthSnapshotValue.self, from: payload); guard v.id == id else { throw NetWorthFailure.invalid }; try v.validate(); return v }
}

struct NetWorthLedger {
    var items: [NetWorthItemValue]
    var snapshots: [NetWorthSnapshotValue]
    var history: [NetWorthSnapshotValue] { snapshots.filter(\.confirmed).sorted { $0.day < $1.day } }
    var draft: NetWorthSnapshotValue? { snapshots.first { !$0.confirmed } }
    var latest: NetWorthSnapshotValue? { history.last }
    func validate() throws {
        guard Set(items.map(\.id)).count == items.count, Set(snapshots.map(\.id)).count == snapshots.count,
              snapshots.filter({ !$0.confirmed }).count <= 1,
              Set(history.map(\.day)).count == history.count else { throw NetWorthFailure.invalid }
        let ids = Set(items.map(\.id))
        for item in items { try item.validate() }
        for snapshot in snapshots { try snapshot.validate(); guard snapshot.items.allSatisfy({ ids.contains($0.id) }) else { throw NetWorthFailure.invalid } }
        for item in items where item.archived {
            let last = history.reversed().compactMap { $0.items.first { $0.id == item.id && $0.included } }.first
            guard last?.cents == 0 else { throw NetWorthFailure.archivedHistory }
        }
    }
}

@MainActor final class NetWorthService {
    private let container: ModelContainer
    private let now: () -> Date
    private let commit: (ModelContext) throws -> Void
    init(context: ModelContext, now: @escaping () -> Date = Date.init, commit: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        container = context.container; self.now = now; self.commit = commit
    }
    nonisolated static func read(_ context: ModelContext) throws -> NetWorthLedger {
        let ledger = NetWorthLedger(items: try context.fetch(FetchDescriptor<NetWorthItem>()).map { try $0.value() },
            snapshots: try context.fetch(FetchDescriptor<NetWorthSnapshot>()).map { try $0.value() })
        try ledger.validate(); return ledger
    }
    func read() throws -> NetWorthLedger { try Self.read(ModelContext(container)) }
    private func write<T>(_ body: (ModelContext) throws -> T) throws -> T {
        try StorePublication.perform(at: StorePublication.root(for: container)) {
            let context = ModelContext(container); context.autosaveEnabled = false
            do { let value = try body(context); _ = try Self.read(context); try Task.checkCancellation(); try commit(context); return value }
            catch { context.rollback(); throw error }
        }
    }
    @discardableResult func saveItem(_ input: NetWorthItemValue) throws -> NetWorthItemValue {
        try write { context in
            var value = input
            let existing = try context.fetch(FetchDescriptor<NetWorthItem>()).first { $0.id == value.id }
            if let existing {
                let old = try existing.value(); guard old.revision == value.revision else { throw NetWorthFailure.conflict }
                value.createdAt = old.createdAt; value.updatedAt = max(now(), old.updatedAt); value.revision += 1
                if value.archived && !old.archived {
                    let latest = try Self.read(context).history.reversed().compactMap { $0.items.first { $0.id == value.id && $0.included } }.first
                    guard let latest, latest.cents == 0 else { throw NetWorthFailure.archiveBalance }
                }
                try value.validate(); existing.payload = try JSONEncoder().encode(value)
            } else {
                value.createdAt = now(); value.updatedAt = value.createdAt; value.revision = 0
                guard !value.archived else { throw NetWorthFailure.invalid }; try value.validate(); context.insert(try NetWorthItem(value))
            }
            return value
        }
    }
    @discardableResult func begin(day: String, editingID: UUID? = nil, resumeExistingDraft: Bool = true) throws -> NetWorthSnapshotValue {
        try write { context in
            let ledger = try Self.read(context)
            if let draft = ledger.draft {
                if let editingID, draft.editingID != editingID { throw NetWorthFailure.conflict }
                if !resumeExistingDraft && (draft.day != day || draft.editingID != editingID) { throw NetWorthFailure.conflict }
                return draft
            }
            guard ImportantCivilDay(identifier: day) != nil else { throw NetWorthFailure.invalid }
            var value: NetWorthSnapshotValue
            if let editingID {
                guard let original = ledger.history.first(where: { $0.id == editingID }) else { throw NetWorthFailure.conflict }
                value = original; value.id = UUID(); value.confirmed = false; value.completedAt = nil
                value.editingID = original.id; value.editingRevision = original.revision
            } else {
                guard !ledger.history.contains(where: { $0.day == day }) else { throw NetWorthFailure.duplicateDay }
                let previous = ledger.history.last { $0.day < day }
                value = .init(day: day)
                value.items = ledger.items.filter { item in
                    if !item.archived { return true }
                    let prior = ledger.history.filter { $0.day < day }.reversed().compactMap { $0.items.first { $0.id == item.id && $0.included } }.first
                    return prior?.cents != 0
                }.sorted { $0.createdAt < $1.createdAt }.map { item in
                    var row = NetWorthSnapshotItem(item)
                    if let old = previous?.items.first(where: { $0.id == item.id }) { row = old; row.name = item.name; row.category = item.category; row.side = item.side; row.ownership = item.ownership; row.note = item.note }
                    row.pending = true; return row
                }
            }
            value.revision = 0; value.createdAt = now(); value.updatedAt = value.createdAt
            context.insert(try NetWorthSnapshot(value)); return value
        }
    }
    @discardableResult func saveDraft(_ input: NetWorthSnapshotValue) throws -> NetWorthSnapshotValue {
        try write { context in
            guard let model = try context.fetch(FetchDescriptor<NetWorthSnapshot>()).first(where: { $0.id == input.id }) else { throw NetWorthFailure.conflict }
            let old = try model.value()
            guard !old.confirmed, !input.confirmed, old.revision == input.revision, old.day == input.day, old.timeZoneID == input.timeZoneID,
                  old.editingID == input.editingID, old.editingRevision == input.editingRevision else { throw NetWorthFailure.conflict }
            var value = input; value.createdAt = old.createdAt; value.updatedAt = max(now(), old.updatedAt); value.revision += 1
            if value.editingID == nil {
                for item in try Self.read(context).items where !item.archived && !value.items.contains(where: { $0.id == item.id }) {
                    value.items.append(NetWorthSnapshotItem(item))
                }
            }
            try value.validate(); model.payload = try JSONEncoder().encode(value); return value
        }
    }
    @discardableResult func confirm(_ input: NetWorthSnapshotValue, locale: Locale = .current) throws -> NetWorthSnapshotValue {
        try write { context in
            let models = try context.fetch(FetchDescriptor<NetWorthSnapshot>())
            guard let draft = models.first(where: { $0.id == input.id }) else { throw NetWorthFailure.conflict }
            let old = try draft.value()
            guard !old.confirmed, !input.confirmed, old.revision == input.revision, old.day == input.day, old.timeZoneID == input.timeZoneID,
                  old.editingID == input.editingID, old.editingRevision == input.editingRevision,
                  input.day <= ImportantCivilDay(now(), timeZone: TimeZone(identifier: old.timeZoneID)!).identifier else { throw NetWorthFailure.conflict }
            var value = input; try value.finalize(locale: locale)
            if old.editingID == nil {
                for item in try Self.read(context).items where !item.archived && !value.items.contains(where: { $0.id == item.id }) {
                    value.items.append(NetWorthSnapshotItem(item))
                }
            }
            let target: NetWorthSnapshot
            if let id = old.editingID {
                guard let original = models.first(where: { $0.id == id }), try original.value().revision == old.editingRevision else { throw NetWorthFailure.conflict }
                let baseline = try original.value(); target = original; value.id = id; value.createdAt = baseline.createdAt; value.revision = baseline.revision + 1
                value.updatedAt = max(value.updatedAt, baseline.updatedAt)
                context.delete(draft)
            } else {
                guard !models.contains(where: { (try? $0.value()).map { $0.confirmed && $0.day == value.day } == true }) else { throw NetWorthFailure.duplicateDay }
                target = draft; value.createdAt = old.createdAt; value.revision = old.revision + 1
            }
            value.updatedAt = max(now(), old.updatedAt, value.createdAt, value.updatedAt); value.completedAt = value.updatedAt
            try value.validate(); target.payload = try JSONEncoder().encode(value); return value
        }
    }
    func delete(id: UUID, revision: Int) throws {
        try write { context in
            guard let model = try context.fetch(FetchDescriptor<NetWorthSnapshot>()).first(where: { $0.id == id }), try model.value().revision == revision else { throw NetWorthFailure.conflict }
            context.delete(model)
        }
    }
}
