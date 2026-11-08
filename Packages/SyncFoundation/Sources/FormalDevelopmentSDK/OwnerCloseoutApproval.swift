import Foundation
import Darwin
import SyncFoundation

/// A separate, explicitly approved local mutation. Neither an old cloud window
/// nor an offline export authorizes closing its unresolved execution. The outer
/// canonical digest binds the reviewed head and is persisted in the terminal event.
struct OwnerCloseoutApproval: Codable {
    let version: Int
    let purpose: String
    let approval: OwnerExecutionApproval
    let expectedHeadSequence: Int
    let expectedHeadFileSHA256: String

    @MainActor static func validate(_ bytes: Data, expectedSHA256: String,
                                    now: Date = Date(), userID: UInt32 = getuid()) throws -> (ValidatedOwnerWindow, LedgerCloseoutTarget) {
        guard bytes.count <= 131_072, RuntimeSigningInspector.isHex(expectedSHA256, bytes: 32),
              syncDigest(bytes) == expectedSHA256 else { throw OwnerWindowError.malformed }
        let value = try JSONDecoder().decode(Self.self, from: bytes)
        guard try json(value) == bytes, value.version == 1, value.purpose == "LOCAL_CLOSEOUT_UNKNOWN",
              value.approval.purpose == "LOCAL_GUARD_CLOSEOUT_UNKNOWN",
              (1...2_048).contains(value.expectedHeadSequence),
              RuntimeSigningInspector.isHex(value.expectedHeadFileSHA256, bytes: 32),
              value.expectedHeadFileSHA256 != String(repeating: "0", count: 64) else { throw OwnerWindowError.malformed }
        let inner = try value.approval.encoded()
        let window = try OwnerExecutionApproval.validate(inner, expectedSHA256: syncDigest(inner), now: now, userID: userID)
        return (window, LedgerCloseoutTarget(run: value.approval.run, dataset: value.approval.dataset,
            planSHA256: value.approval.planSHA256, expectedHeadSequence: value.expectedHeadSequence,
            expectedHeadFileSHA256: value.expectedHeadFileSHA256, approvalSHA256: expectedSHA256))
    }
}

struct LocalCloseoutReport: Encodable {
    let status = "LOCAL_UNRESOLVED_EXECUTION_CLOSED_UNKNOWN"
    let cloudOperations = 0
    let oldRunResumed = false
    let originalFilesRewritten = false
    let p0Passed = false
    let observationPersistence = "STDOUT_DERIVED_TERMINAL_APPROVAL_DIGEST_LEDGER_ANCHORED"
    let closeout: LedgerCloseoutSummary
}
