import XCTest
import Foundation
import Darwin
import FormalProbeCore
import SyncFoundation
@testable import FormalDevelopmentSDK

final class IndependentEvidenceExportTests: XCTestCase {
    private func fixture() throws -> (URL, UUID, URL, URL) {
        let root = URL(fileURLWithPath: "/private/tmp/PGOS-Independent-Export-" + UUID().uuidString)
        _ = try ProbeDirectory(root, create: true)
        let run = UUID(), url = root.appendingPathComponent("com.yocruzer.PersonalGrowthOS.FormalSyncProbe.Run-" + run.uuidString.lowercased())
        let ledger = root.appendingPathComponent("com.yocruzer.PersonalGrowthOS.FormalSyncProbe.ExecutionGuard-v1")
        _ = try ProbeDirectory(url, create: true); _ = try ProbeDirectory(ledger, create: true)
        return (root, run, url, ledger)
    }
    private func report(_ root: URL, _ run: UUID) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: FormalDevelopmentEvidenceExport.capture(root: root, run: run)) as? [String: Any])
    }
    func testHardlinkWithAllowedNameCannotExportOutsideSyntheticBytes() throws {
        for ledgerCase in [false, true] {
            let (root, run, url, ledger) = try fixture()
            let outside = root.appendingPathComponent("outside-private-fixture")
            try Data("MUST_NOT_EXPORT_SYNTHETIC_EXTERNAL_FILE".utf8).write(to: outside)
            let linked = (ledgerCase ? ledger : url).appendingPathComponent(ledgerCase ? "00000001.json" : "fatal-unknown.json")
            try FileManager.default.linkItem(at: outside, to: linked)
            let r = try report(root, run)
            XCTAssertEqual(r["unavailableSections"] as? [String], [ledgerCase ? "ledger" : "run"])
            XCTAssertTrue((r["files"] as! [[String: Any]]).isEmpty)
        }
    }
    func testExactBytesHashAndReadOnlyClaimRemainDistinctFromLedgerAuthentication() throws {
        let (root, run, url, ledger) = try fixture()
        let raw = Data([0, 1, 255, 10, 13])
        try ProbeDirectory(url, create: false).write("000000-callback.json", bytes: raw)
        try ProbeDirectory(ledger, create: false).write("00000001.json", bytes: raw)
        try ProbeDirectory(ledger, create: false).write("guard.lock", bytes: Data("DO_NOT_EXPORT_LOCK".utf8))
        let r = try report(root, run), files = r["files"] as! [[String: Any]]
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(r["unavailableSections"] as? [String], [])
        XCTAssertEqual(r["ledgerAuthentication"] as? String, "NOT_PERFORMED_NO_KEYCHAIN_ACCESS")
        XCTAssertEqual(r["cloudOperations"] as? Int, 0); XCTAssertEqual(r["keychainOperations"] as? Int, 0)
        for f in files { XCTAssertEqual(Data(base64Encoded: f["bytes"] as! String), raw); XCTAssertEqual(f["sha256"] as? String, syncDigest(raw)) }
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("000000-callback.json")), raw)
    }
    func testRootSymlinkAndOversizedMemberNeverClaimCompleteSection() throws {
        let (root, run, url, ledger) = try fixture()
        let other = root.appendingPathComponent("saved-run")
        try FileManager.default.moveItem(at: url, to: other)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: other)
        try ProbeDirectory(ledger, create: false).write("00000001.json", bytes: Data(repeating: 1, count: 65_537))
        let r = try report(root, run)
        XCTAssertEqual(r["unavailableSections"] as? [String], ["run", "ledger"])
        XCTAssertTrue((r["files"] as! [[String: Any]]).isEmpty)
    }
}
