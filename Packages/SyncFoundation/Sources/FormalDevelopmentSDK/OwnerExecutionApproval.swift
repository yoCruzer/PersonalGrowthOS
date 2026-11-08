import Foundation
import Darwin
import FormalProbeCore
import SyncFoundation

enum OwnerWindowError: String, Error {
    case malformed, bindingMismatch, wrongUser, outsideWindow, clockMovedBackwards
}

struct ApprovedRuntimeBinding: Codable, Equatable {
    let signedBinarySHA256: String
    let codeDirectoryHash: String
    let profileSHA256: String
    let packagingReceiptSHA256: String
    let sourcePinsSHA256: String

    func expectation() throws -> RuntimeSigningExpectation {
        try RuntimeSigningExpectation(signedBinarySHA256: signedBinarySHA256,
            codeDirectoryHash: codeDirectoryHash, profileSHA256: profileSHA256,
            packagingReceiptSHA256: packagingReceiptSHA256, sourcePinsSHA256: sourcePinsSHA256)
    }
}

/// A reviewed, explicitly supplied Owner decision reference. The JSON is not a
/// cryptographic proof of human consent. The operator must obtain that decision
/// before creating this input; an offline request/template cannot grant permission.
/// It never substitutes for real self-signing, account qualification or the ledger.
struct OwnerExecutionApproval: Codable, Equatable {
    let version: Int
    let disposition: String
    let purpose: String
    let ownerDecisionSHA256: String
    let ownerSessionSHA256: String
    let window: UUID
    let startsAt: Int64
    let expiresAt: Int64
    let osUserID: UInt32
    let run: UUID
    let dataset: UUID
    let planSHA256: String
    let schemaSHA256: String
    let runtime: ApprovedRuntimeBinding
    let packagingReceipt: Data
    let sourcePins: Data

    func encoded() throws -> Data { try json(self) }

    @MainActor
    static func validate(_ bytes: Data, expectedSHA256: String, now: Date = Date(),
                         userID: UInt32 = getuid()) throws -> ValidatedOwnerWindow {
        guard bytes.count <= 131_072, RuntimeSigningInspector.isHex(expectedSHA256, bytes: 32),
              syncDigest(bytes) == expectedSHA256 else { throw OwnerWindowError.malformed }
        let value = try JSONDecoder().decode(Self.self, from: bytes)
        guard try value.encoded() == bytes, value.version == 1,
              value.disposition == "OWNER_APPROVED_DEVELOPMENT_WINDOW",
              ["LOCAL_GUARD_ENROLLMENT", "FIXED_SYNTHETIC_DEVELOPMENT_BATCH", "LOCAL_GUARD_CLOSEOUT_UNKNOWN"].contains(value.purpose),
              [value.ownerDecisionSHA256, value.ownerSessionSHA256, value.planSHA256, value.schemaSHA256]
                .allSatisfy({ RuntimeSigningInspector.isHex($0, bytes: 32) && $0 != String(repeating: "0", count: 64) }),
              value.osUserID > 0, value.startsAt > 0, value.expiresAt > value.startsAt,
              value.expiresAt - value.startsAt <= 900,
              value.packagingReceipt.count <= 65_536, !value.packagingReceipt.isEmpty,
              value.sourcePins.count <= 65_536, !value.sourcePins.isEmpty else { throw OwnerWindowError.malformed }
        guard value.osUserID == userID else { throw OwnerWindowError.wrongUser }
        let fixture = try ProbeFixture.make(run: value.run, dataset: value.dataset)
        guard try fixture.plan.digest == value.planSHA256,
              value.schemaSHA256 == FormalProbeIdentity.schemaSHA256,
              syncDigest(value.packagingReceipt) == value.runtime.packagingReceiptSHA256,
              syncDigest(value.sourcePins) == value.runtime.sourcePinsSHA256 else { throw OwnerWindowError.bindingMismatch }
        _ = try value.runtime.expectation()
        let window = ValidatedOwnerWindow(approval: value, inputSHA256: expectedSHA256)
        try window.check(now: now)
        return window
    }
}

@MainActor final class ValidatedOwnerWindow {
    let approval: OwnerExecutionApproval
    let inputSHA256: String
    private var lastObserved: Date?
    private var monotonicDeadline: TimeInterval?
    private var lastUptime: TimeInterval?
    private var invalidReason: OwnerWindowError?
    fileprivate init(approval: OwnerExecutionApproval, inputSHA256: String) {
        self.approval = approval; self.inputSHA256 = inputSHA256
    }
    /// Bounded local wait budget, anchored when this window was first validated.
    /// A suspended SDK callback must not extend the approved execution window.
    func remainingDuration() throws -> TimeInterval {
        try check()
        let remaining = min(monotonicDeadline! - ProcessInfo.processInfo.systemUptime,
                            Double(approval.expiresAt) - Date().timeIntervalSince1970)
        guard remaining > 0 else { throw OwnerWindowError.outsideWindow }
        return remaining
    }
    func check(now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) throws {
        if let invalidReason { throw invalidReason }
        do {
            if let lastObserved, now < lastObserved { throw OwnerWindowError.clockMovedBackwards }
            if let lastUptime, uptime < lastUptime { throw OwnerWindowError.clockMovedBackwards }
            guard uptime.isFinite, now.timeIntervalSince1970.isFinite,
                  now.timeIntervalSince1970 >= Double(approval.startsAt),
                  now.timeIntervalSince1970 < Double(approval.expiresAt) else { throw OwnerWindowError.outsideWindow }
            if monotonicDeadline == nil { monotonicDeadline = uptime + Double(approval.expiresAt) - now.timeIntervalSince1970 }
            guard uptime < monotonicDeadline! else { throw OwnerWindowError.outsideWindow }
            lastObserved = now; lastUptime = uptime
        } catch let error as OwnerWindowError {
            invalidReason = error; throw error
        }
    }
}
