import XCTest
import Foundation
import CryptoKit
@testable import FormalDevelopmentSDK

extension ExecutionLedgerTests {
    private func closeoutFiles(_ c: Context) throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: c.root, includingPropertiesForKeys: nil)
            .map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }
    private func closeoutTarget(_ c: Context, _ binding: ExecutionBinding) throws -> LedgerCloseoutTarget {
        let files = try closeoutFiles(c), name = try XCTUnwrap(files.keys.filter { $0.hasSuffix(".json") }.sorted().last)
        return LedgerCloseoutTarget(run: binding.run, dataset: binding.dataset, planSHA256: binding.planSHA256,
            expectedHeadSequence: try XCTUnwrap(Int(name.prefix(8))),
            expectedHeadFileSHA256: SHA256.hash(data: files[name]!).map { String(format: "%02x", $0) }.joined(),
            approvalSHA256: String(repeating: "e", count: 64))
    }
    func testCloseoutAppendsUnknownAfterExpiryPreservesHistoryAndOnlyNewDistinctPlanCanRun() throws {
        let c = try context(), b = binding(c)
        var ledger: ExecutionLedger? = try enroll(c)
        let oldPermit = try ledger!.consume(.qualificationRead, binding: b)
        let operation = try ledger!.intent(.accountStatus, permit: oldPermit)
        try ledger!.recordObservation(operationID: operation, event: .enqueueRequested, summarySHA256: digest, permit: oldPermit)
        let target = try closeoutTarget(c, b), oldFiles = try closeoutFiles(c)
        ledger = nil
        c.clock.wall += 100_000; c.clock.uptime += 100_000_000_000
        ledger = try c.open()
        let summary = try ledger!.closeoutUnknown(target: target)
        XCTAssertEqual(summary.status, "CLOSED_REMOTE_OUTCOME_UNKNOWN")
        XCTAssertEqual(summary.approvalSHA256, target.approvalSHA256)
        XCTAssertEqual(summary.previousHeadSequence, target.expectedHeadSequence)
        XCTAssertEqual(summary.appendedSequence, target.expectedHeadSequence + 1)
        XCTAssertFalse(ledger!.hasUnresolvedExecutions)
        let newFiles = try closeoutFiles(c)
        XCTAssertEqual(newFiles.count, oldFiles.count + 1)
        for (name, bytes) in oldFiles { XCTAssertEqual(newFiles[name], bytes) }
        let appended = try XCTUnwrap(newFiles[String(format: "%08d.json", summary.appendedSequence)])
        XCTAssertEqual(summary.appendedFileSHA256, SHA256.hash(data: appended).map { String(format: "%02x", $0) }.joined())
        let text = String(decoding: appended, as: UTF8.self)
        XCTAssertTrue(text.contains("ownerClosedUnknown")); XCTAssertTrue(text.contains(target.approvalSHA256))
        XCTAssertThrowsError(try ledger!.intent(.accountStatus, permit: oldPermit))
        ledger = nil; ledger = try c.open() // The new terminal replays with the unchanged anchor identity.
        XCTAssertFalse(ledger!.hasUnresolvedExecutions)
        XCTAssertThrowsError(try ledger!.consume(.qualificationRead, binding: binding(c, plan: b.planSHA256)))
        _ = try ledger!.consume(.qualificationRead, binding: binding(c, plan: String(repeating: "b", count: 64)))
    }
    func testCloseoutWrongHeadRunDatasetPlanAndApprovalLeaveAllBytesUnchanged() throws {
        let c = try context(), b = binding(c)
        var original: ExecutionLedger? = try enroll(c)
        _ = try original!.consume(.qualificationRead, binding: b)
        let t = try closeoutTarget(c, b); original = nil
        let before = try closeoutFiles(c), anchor = c.store.bytes
        let targets = [
            LedgerCloseoutTarget(run: UUID(), dataset: t.dataset, planSHA256: t.planSHA256, expectedHeadSequence: t.expectedHeadSequence, expectedHeadFileSHA256: t.expectedHeadFileSHA256, approvalSHA256: t.approvalSHA256),
            LedgerCloseoutTarget(run: t.run, dataset: UUID(), planSHA256: t.planSHA256, expectedHeadSequence: t.expectedHeadSequence, expectedHeadFileSHA256: t.expectedHeadFileSHA256, approvalSHA256: t.approvalSHA256),
            LedgerCloseoutTarget(run: t.run, dataset: t.dataset, planSHA256: String(repeating: "b", count: 64), expectedHeadSequence: t.expectedHeadSequence, expectedHeadFileSHA256: t.expectedHeadFileSHA256, approvalSHA256: t.approvalSHA256),
            LedgerCloseoutTarget(run: t.run, dataset: t.dataset, planSHA256: t.planSHA256, expectedHeadSequence: t.expectedHeadSequence + 1, expectedHeadFileSHA256: t.expectedHeadFileSHA256, approvalSHA256: t.approvalSHA256),
            LedgerCloseoutTarget(run: t.run, dataset: t.dataset, planSHA256: t.planSHA256, expectedHeadSequence: t.expectedHeadSequence, expectedHeadFileSHA256: String(repeating: "f", count: 64), approvalSHA256: t.approvalSHA256),
            LedgerCloseoutTarget(run: t.run, dataset: t.dataset, planSHA256: t.planSHA256, expectedHeadSequence: t.expectedHeadSequence, expectedHeadFileSHA256: t.expectedHeadFileSHA256, approvalSHA256: String(repeating: "0", count: 64)),
            LedgerCloseoutTarget(run: t.run, dataset: t.dataset, planSHA256: t.planSHA256, expectedHeadSequence: t.expectedHeadSequence, expectedHeadFileSHA256: t.expectedHeadFileSHA256, approvalSHA256: "invalid")
        ]
        let ledger = try c.open()
        for target in targets {
            XCTAssertThrowsError(try ledger.closeoutUnknown(target: target))
            XCTAssertEqual(try closeoutFiles(c), before); XCTAssertEqual(c.store.bytes, anchor)
        }
    }
    func testCloseoutRejectsActiveInstanceAndConcurrentOpen() throws {
        let c = try context(), ledger = try enroll(c), b = binding(c)
        _ = try ledger.consume(.qualificationRead, binding: b)
        let target = try closeoutTarget(c, b), before = try closeoutFiles(c), anchor = c.store.bytes
        XCTAssertThrowsError(try ledger.closeoutUnknown(target: target)) { error in
            guard case LedgerFailure.busy = error else { return XCTFail("must require a fresh instance") }
        }
        XCTAssertThrowsError(try c.open())
        XCTAssertEqual(try closeoutFiles(c), before); XCTAssertEqual(c.store.bytes, anchor)
    }
    func testCloseoutAlreadyTerminalAndRepeatedCloseoutRejectWithoutMutation() throws {
        for ownerClosed in [false, true] {
            let c = try context(), b = binding(c)
            var ledger: ExecutionLedger? = try enroll(c)
            let permit = try ledger!.consume(.qualificationRead, binding: b)
            if ownerClosed {
                let t = try closeoutTarget(c, b); ledger = nil; ledger = try c.open()
                _ = try ledger!.closeoutUnknown(target: t)
            } else { try ledger!.terminateUnknown(reason: .interrupted, permit: permit) }
            let target = try closeoutTarget(c, b), before = try closeoutFiles(c), anchor = c.store.bytes
            ledger = nil; ledger = try c.open()
            XCTAssertThrowsError(try ledger!.closeoutUnknown(target: target))
            XCTAssertEqual(try closeoutFiles(c), before); XCTAssertEqual(c.store.bytes, anchor)
        }
    }
    func testCloseoutAnchorCommitGapPoisonsWithoutRewritingPriorHistory() throws {
        let c = try context(), b = binding(c)
        var ledger: ExecutionLedger? = try enroll(c)
        _ = try ledger!.consume(.qualificationRead, binding: b)
        let t = try closeoutTarget(c, b), before = try closeoutFiles(c), anchor = c.store.bytes
        ledger = nil; ledger = try c.open(); c.store.failNextReplace = true
        XCTAssertThrowsError(try ledger!.closeoutUnknown(target: t))
        let after = try closeoutFiles(c)
        for (name, bytes) in before { XCTAssertEqual(after[name], bytes) }
        XCTAssertEqual(after.count, before.count + 1); XCTAssertEqual(c.store.bytes, anchor)
        XCTAssertThrowsError(try ledger!.closeoutUnknown(target: t))
        XCTAssertEqual(try closeoutFiles(c), after)
        ledger = nil; XCTAssertThrowsError(try c.open())
    }
    func testMultipleUnresolvedAuthenticatedHistoryRejectedBeforeCloseoutAndNeverRepaired() throws {
        let c = try context(), b = binding(c)
        var ledger: ExecutionLedger? = try enroll(c)
        _ = try ledger!.consume(.qualificationRead, binding: b); ledger = nil
        let oldBytes = try Data(contentsOf: c.root.appendingPathComponent("00000001.json"))
        let first = try XCTUnwrap(JSONSerialization.jsonObject(with: oldBytes) as? [String: Any])
        var body = try XCTUnwrap(first["body"] as? [String: Any])
        var event = try XCTUnwrap(body["event"] as? [String: Any])
        var consumed = try XCTUnwrap(event["consumed"] as? [String: Any])
        var binding = try XCTUnwrap(consumed["binding"] as? [String: Any])
        binding["run"] = UUID().uuidString; binding["dataset"] = UUID().uuidString
        binding["ownerWindow"] = UUID().uuidString; binding["approvalInputSHA256"] = String(repeating: "c", count: 64)
        binding["planSHA256"] = String(repeating: "d", count: 64)
        consumed["binding"] = binding; event["consumed"] = consumed; body["event"] = event
        body["sequence"] = 2; body["permitID"] = UUID().uuidString; body["previousMAC"] = first["mac"]
        var anchor = try XCTUnwrap(JSONSerialization.jsonObject(with: c.store.bytes!) as? [String: Any])
        let key = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(anchor["key"] as? String)))
        func canonical(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) }
        let mac = HMAC<SHA256>.authenticationCode(for: try canonical(body), using: SymmetricKey(data: key)).map { String(format: "%02x", $0) }.joined()
        let secondURL = c.root.appendingPathComponent("00000002.json")
        try canonical(["body": body, "mac": mac]).write(to: secondURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secondURL.path)
        anchor["sequence"] = 2; anchor["headMAC"] = mac; c.store.bytes = try canonical(anchor)
        let before = try closeoutFiles(c), anchorBefore = c.store.bytes
        // Valid-MAC fixture deliberately violates the ledger's one-unresolved rule.
        // Normal open must reject before a closeout-capable instance can exist.
        XCTAssertThrowsError(try c.open()) { error in
            guard case LedgerFailure.replay = error else { return XCTFail("expected the one-unresolved invariant, got \(type(of: error))") }
        }
        XCTAssertEqual(try closeoutFiles(c), before); XCTAssertEqual(c.store.bytes, anchorBefore)
        XCTAssertEqual(try Data(contentsOf: c.root.appendingPathComponent("00000001.json")), oldBytes)
    }
}
