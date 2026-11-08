import XCTest
import Foundation
import FormalProbeCore
import SyncFoundation
@testable import FormalDevelopmentSDK

final class EvidenceExportTests: XCTestCase {
    private func fixture() throws -> (URL, UUID, URL, URL) {
        let root = URL(fileURLWithPath: "/private/tmp/PGOS-Export-Test-" + UUID().uuidString)
        _ = try ProbeDirectory(root, create: true)
        let run = UUID()
        let runURL = root.appendingPathComponent("com.yocruzer.PersonalGrowthOS.FormalSyncProbe.Run-" + run.uuidString.lowercased())
        let ledger = root.appendingPathComponent("com.yocruzer.PersonalGrowthOS.FormalSyncProbe.ExecutionGuard-v1")
        _ = try ProbeDirectory(runURL, create: true); _ = try ProbeDirectory(ledger, create: true)
        return (root, run, runURL, ledger)
    }
    private func report(_ root: URL, _ run: UUID) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: FormalDevelopmentEvidenceExport.capture(root: root, run: run)) as? [String: Any])
    }
    func testExactRawBytesAndHashesWithoutMutationOrAuthenticationClaim() throws {
        let (root, run, runURL, ledger) = try fixture()
        let raw = Data("{\"synthetic\":true}\n".utf8)
        try ProbeDirectory(runURL, create: false).write("fatal-unknown.json", bytes: raw)
        try ProbeDirectory(ledger, create: false).write("00000001.json", bytes: raw)
        try ProbeDirectory(ledger, create: false).write("guard.lock", bytes: Data())
        let r = try report(root, run), files = try XCTUnwrap(r["files"] as? [[String: Any]])
        XCTAssertEqual(files.count, 2); XCTAssertEqual(r["cloudOperations"] as? Int, 0); XCTAssertEqual(r["keychainOperations"] as? Int, 0)
        XCTAssertEqual(r["ledgerAuthentication"] as? String, "NOT_PERFORMED_NO_KEYCHAIN_ACCESS")
        for f in files { XCTAssertEqual(f["sha256"] as? String, syncDigest(raw)); XCTAssertEqual(Data(base64Encoded: f["bytes"] as! String), raw) }
        XCTAssertEqual(try Data(contentsOf: runURL.appendingPathComponent("fatal-unknown.json")), raw)
    }
    func testSymlinkOrUnexpectedFileRejectsWholeSectionWithoutFollowing() throws {
        for name in ["private.txt", "fatal-unknown.json"] {
            let (root, run, runURL, _) = try fixture()
            let outside = root.appendingPathComponent("outside"); try Data("DO_NOT_EXPORT".utf8).write(to: outside)
            try FileManager.default.createSymbolicLink(at: runURL.appendingPathComponent(name), withDestinationURL: outside)
            let r = try report(root, run)
            XCTAssertEqual(r["unavailableSections"] as? [String], ["run"])
            XCTAssertTrue((r["files"] as! [[String: Any]]).isEmpty)
        }
    }
    func testMissingRunNeverCreatesItAndStillPreservesLedgerBytes() throws {
        let (root, _, _, ledger) = try fixture(), other = UUID()
        try ProbeDirectory(ledger, create: false).write("00000001.json", bytes: Data("synthetic".utf8))
        let r = try report(root, other)
        XCTAssertEqual(r["unavailableSections"] as? [String], ["run"])
        XCTAssertEqual((r["files"] as! [[String: Any]]).count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("com.yocruzer.PersonalGrowthOS.FormalSyncProbe.Run-" + other.uuidString.lowercased()).path))
    }
}
