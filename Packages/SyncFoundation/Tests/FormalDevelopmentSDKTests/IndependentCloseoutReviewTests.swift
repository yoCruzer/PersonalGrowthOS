import XCTest
import Foundation
import CryptoKit
import FormalProbeCore
import SyncFoundation
@testable import FormalDevelopmentSDK

extension ExecutionLedgerTests {
    private func independentSnapshot(_ c: Context) throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: c.root, includingPropertiesForKeys: nil)
            .map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }
    private func independentTarget(_ c: Context, _ b: ExecutionBinding) throws -> LedgerCloseoutTarget {
        let files = try independentSnapshot(c)
        let name = try XCTUnwrap(files.keys.filter { $0.hasSuffix(".json") }.sorted().last)
        return LedgerCloseoutTarget(run: b.run, dataset: b.dataset, planSHA256: b.planSHA256,
            expectedHeadSequence: try XCTUnwrap(Int(name.prefix(8))),
            expectedHeadFileSHA256: syncDigest(files[name]!), approvalSHA256: String(repeating: "e", count: 64))
    }
    func testIndependentCloseoutRejectsHeadAdvancedByLateObservation() throws {
        let c = try context(), b = binding(c)
        var ledger: ExecutionLedger? = try enroll(c)
        let permit = try ledger!.consume(.qualificationRead, binding: b)
        let operation = try ledger!.intent(.accountStatus, permit: permit)
        let approvedHead = try independentTarget(c, b)
        try ledger!.recordObservation(operationID: operation, event: .lateCallback, summarySHA256: digest, permit: permit)
        ledger = nil
        let before = try independentSnapshot(c), anchor = c.store.bytes
        ledger = try c.open()
        XCTAssertThrowsError(try ledger!.closeoutUnknown(target: approvedHead))
        XCTAssertTrue(ledger!.hasUnresolvedExecutions)
        XCTAssertEqual(try independentSnapshot(c), before); XCTAssertEqual(c.store.bytes, anchor)
    }
    func testIndependentCloseoutOfBatchCannotReuseAnyOldIdentityOrQualification() throws {
        let c = try context(), b = binding(c)
        var ledger: ExecutionLedger? = try enroll(c)
        let account = try qualify(c, ledger: ledger!, binding: b)
        let batch = batchBinding(b, account: account)
        let permit = try ledger!.consume(.developmentBatch, binding: batch)
        try ledger!.intent(.accountCheckBefore(.zoneProbe), permit: permit)
        let target = try independentTarget(c, b), original = try independentSnapshot(c)
        ledger = nil; ledger = try c.open()
        _ = try ledger!.closeoutUnknown(target: target)
        ledger = nil; ledger = try c.open()
        let closed = try independentSnapshot(c), anchor = c.store.bytes
        for (name, bytes) in original { XCTAssertEqual(closed[name], bytes) }
        for candidate in [
            binding(c, run: b.run, plan: String(repeating: "1", count: 64)),
            binding(c, dataset: b.dataset, plan: String(repeating: "2", count: 64)),
            binding(c, plan: b.planSHA256),
            binding(c, plan: String(repeating: "3", count: 64), window: b.ownerWindow),
            binding(c, plan: String(repeating: "4", count: 64), approval: b.approvalInputSHA256)
        ] { XCTAssertThrowsError(try ledger!.consume(.qualificationRead, binding: candidate)) }
        XCTAssertThrowsError(try ledger!.consume(.developmentBatch, binding: batch))
        let distinct = binding(c, plan: String(repeating: "5", count: 64))
        XCTAssertThrowsError(try ledger!.consume(.developmentBatch, binding: batchBinding(distinct, account: account)))
        XCTAssertEqual(try independentSnapshot(c), closed); XCTAssertEqual(c.store.bytes, anchor)
        _ = try ledger!.consume(.qualificationRead, binding: distinct)
    }
    func testIndependentOuterApprovalDigestPersistsExactlyAndOldBytesRemainAuthoritative() throws {
        let c = try context(), fixture = try ProbeFixture.make(run: UUID(), dataset: UUID())
        let b = binding(c, run: fixture.plan.run, dataset: fixture.plan.dataset, plan: try fixture.plan.digest)
        var ledger: ExecutionLedger? = try enroll(c)
        _ = try ledger!.consume(.qualificationRead, binding: b)
        let head = try independentTarget(c, b), old = try independentSnapshot(c)
        ledger = nil
        let receipt = Data("INVALID SYNTHETIC RECEIPT".utf8), pins = Data("INVALID SYNTHETIC PINS".utf8)
        let start = Int64(Date().timeIntervalSince1970) - 1
        let owner = OwnerExecutionApproval(version: 1, disposition: "OWNER_APPROVED_DEVELOPMENT_WINDOW",
            purpose: "LOCAL_GUARD_CLOSEOUT_UNKNOWN", ownerDecisionSHA256: digest, ownerSessionSHA256: digest,
            window: UUID(), startsAt: start, expiresAt: start + 300, osUserID: b.osUserID,
            run: b.run, dataset: b.dataset, planSHA256: b.planSHA256, schemaSHA256: b.schemaSHA256,
            runtime: ApprovedRuntimeBinding(signedBinarySHA256: digest, codeDirectoryHash: b.codeDirectoryHash,
                profileSHA256: digest, packagingReceiptSHA256: syncDigest(receipt), sourcePinsSHA256: syncDigest(pins)),
            packagingReceipt: receipt, sourcePins: pins)
        let bytes = try json(OwnerCloseoutApproval(version: 1, purpose: "LOCAL_CLOSEOUT_UNKNOWN", approval: owner,
            expectedHeadSequence: head.expectedHeadSequence, expectedHeadFileSHA256: head.expectedHeadFileSHA256))
        let (window, target) = try OwnerCloseoutApproval.validate(bytes, expectedSHA256: syncDigest(bytes))
        XCTAssertNotEqual(window.inputSHA256, target.approvalSHA256)
        ledger = try c.open()
        let result = try ledger!.closeoutUnknown(target: target)
        let appended = try Data(contentsOf: c.root.appendingPathComponent(String(format: "%08d.json", result.appendedSequence)))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: appended) as? [String: Any])
        let body = try XCTUnwrap(object["body"] as? [String: Any]), event = try XCTUnwrap(body["event"] as? [String: Any])
        let terminal = try XCTUnwrap(event["terminal"] as? [String: Any]), value = try XCTUnwrap(terminal["_0"] as? [String: Any])
        let closed = try XCTUnwrap(value["ownerClosedUnknown"] as? [String: Any])
        XCTAssertEqual(closed["approvalSHA256"] as? String, syncDigest(bytes))
        for (name, original) in old { XCTAssertEqual(try Data(contentsOf: c.root.appendingPathComponent(name)), original) }
        ledger = nil
        let first = c.root.appendingPathComponent("00000001.json")
        try (old["00000001.json"]! + Data([10])).write(to: first)
        let tampered = try independentSnapshot(c), anchor = c.store.bytes
        XCTAssertThrowsError(try c.open())
        XCTAssertEqual(try independentSnapshot(c), tampered); XCTAssertEqual(c.store.bytes, anchor)
    }
}
