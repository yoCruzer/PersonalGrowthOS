import Foundation
import SwiftData

extension TransferData {
    func validateNetWorth(packageVersion: Int) throws {
        guard packageVersion >= 12 || (netWorthItems.isEmpty && netWorthSnapshots.isEmpty) else { throw NetWorthFailure.invalid }
        try NetWorthLedger(items: netWorthItems, snapshots: netWorthSnapshots).validate()
    }
    func insertNetWorth(into context: ModelContext) throws {
        for item in netWorthItems { try Task.checkCancellation(); context.insert(try NetWorthItem(item)) }
        for snapshot in netWorthSnapshots { try Task.checkCancellation(); context.insert(try NetWorthSnapshot(snapshot)) }
    }
}

enum NetWorthCSV {
    static func make(_ ledger: NetWorthLedger) throws -> String {
        try ledger.validate()
        func cell(_ input: String) -> String {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            let safe = trimmed.first.map { "=+-@\t\r\n".contains($0) } == true ? "'" + input : input
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var lines = ["snapshot_id,date,currency,assets_scope_confirmed,liabilities_scope_confirmed,scope_adjusted,snapshot_note,item_id,name,side,category,ownership,included,amount,amount_state,amount_date,item_note"]
        for snapshot in ledger.history {
            let prefix = [snapshot.id.uuidString, snapshot.day, "CNY", String(snapshot.assetsConfirmed), String(snapshot.liabilitiesConfirmed), String(snapshot.scopeAdjusted), snapshot.note]
            if snapshot.items.isEmpty { lines.append((prefix + Array(repeating: "", count: 10)).map(cell).joined(separator: ",")) }
            for row in snapshot.items {
                lines.append((prefix + [row.id.uuidString, row.name, row.side.rawValue, row.category.rawValue, row.ownership, String(row.included), row.cents.map(NetWorthMoney.decimal) ?? "", row.state.rawValue, row.amountDay ?? "", row.note]).map(cell).joined(separator: ","))
            }
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }
}
