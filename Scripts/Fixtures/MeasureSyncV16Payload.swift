// Append to fixed 96f72339a1a3082c43018e06d6115dd93df1df97 NetWorthTests.swift.
// Only synthetic in-memory domain values; does not open any user database.
@MainActor final class SyncV16PayloadCapacityTests: XCTestCase {
    func testActualValidTenThousandRowUnicodePayloadExceedsInitialCandidateLimit() throws {
        let output = URL(fileURLWithPath: "/tmp/pgos-sync-v16-capacity-20261107")
        guard !FileManager.default.fileExists(atPath: output.path) else { throw CocoaError(.fileWriteFileExists) }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_793_600_000)
        var snapshot = NetWorthSnapshotValue(day: "2026-09-22", timeZoneID: "Asia/Shanghai")
        snapshot.createdAt = date; snapshot.updatedAt = date
        snapshot.confirmed = true; snapshot.completedAt = date
        snapshot.assetsConfirmed = true; snapshot.liabilitiesConfirmed = true
        for i in 0..<10_000 {
            var item = NetWorthItemValue(name: String(repeating: "财", count: 160), side: .asset, category: .cash)
            item.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", i))!
            item.ownership = String(repeating: "归", count: 80)
            item.note = String(repeating: "🧪", count: 1000)
            item.createdAt = date; item.updatedAt = date
            try item.validate()
            var row = NetWorthSnapshotItem(item)
            try row.enter("0.01", day: snapshot.day, locale: Locale(identifier: "en_US_POSIX"))
            snapshot.items.append(row)
        }
        try snapshot.validate()
        XCTAssertEqual(try snapshot.totals().net, 10_000)
        let bytes = try JSONEncoder().encode(snapshot)
        XCTAssertGreaterThan(bytes.count, 40 * 1_024 * 1_024)
        XCTAssertEqual(try JSONDecoder().decode(NetWorthSnapshotValue.self, from: bytes), snapshot)
        try bytes.write(to: output.appendingPathComponent("actual-v16-payload.json"), options: .withoutOverwriting)
        let report: [String: Any] = ["sourceCommit": "96f72339a1a3082c43018e06d6115dd93df1df97", "rowCount": 10_000,
            "actualDomainValidation": true, "bytes": bytes.count, "sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            "netMinorUnits": 10_000, "initialCandidateLimit": 16 * 1_024 * 1_024,
            "initialCandidateFits": false, "synthetic": true]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("report.json"))
    }
}
