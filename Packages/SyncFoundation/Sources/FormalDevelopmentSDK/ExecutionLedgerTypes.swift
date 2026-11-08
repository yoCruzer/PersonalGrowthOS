import Foundation
import Darwin

// Internal bookkeeping only: no constructor or token here proves Owner approval,
// signing, account identity or permission to call CloudKit.
enum LedgerFailure: Error { case missingAnchor, corrupt, busy, pathChanged, permission, replay, transition, expired, accountMismatch, poisoned, capacity, anchorFailure, io }
enum LedgerPermission: String, Codable { case qualificationRead, developmentBatch }
enum LedgerStage: String, Codable, CaseIterable { case zoneProbe, zoneSave, assetsSave, mutationsSave, exactFetch }
enum LedgerOperation: Codable, Equatable {
    case accountStatus, userRecordID
    case accountCheckBefore(LedgerStage), transport(LedgerStage), accountCheckAfter(LedgerStage)
}
enum LedgerReturnStatus: String, Codable { case success, failure, unknown }
enum LedgerStopReason: String, Codable { case cancelled, accountChanged, expired, validationFailed, transportFailed, evidenceFailed, interrupted }
enum LedgerObservation: String, Codable { case enqueueRequested, recordReturned, operationReturned, cancellationRequested, lateCallback, callbackRejected, validationEvidence, reportPrepared, reportPublished }

/// Exact, externally approved historic head. This is a comparison input, never a
/// permit or authority to execute a CloudKit operation.
struct LedgerCloseoutTarget {
    let run: UUID
    let dataset: UUID
    let planSHA256: String
    let expectedHeadSequence: Int
    let expectedHeadFileSHA256: String
    let approvalSHA256: String
}
struct LedgerCloseoutSummary: Encodable {
    let status = "CLOSED_REMOTE_OUTCOME_UNKNOWN"
    let run: UUID
    let dataset: UUID
    let planSHA256: String
    let approvalSHA256: String
    let previousHeadSequence: Int
    let previousHeadFileSHA256: String
    let appendedSequence: Int
    let appendedFileSHA256: String
}

struct ExecutionBinding: Codable, Equatable {
    let ownerWindow: UUID
    let approvalInputSHA256: String
    let ownerDecisionSHA256: String
    let windowStartMS: Int64
    let windowEndMS: Int64
    let planSHA256: String
    let run: UUID
    let dataset: UUID
    let schemaSHA256: String
    let binarySHA256: String
    let codeDirectoryHash: String
    let profileSHA256: String
    let packagingReceiptSHA256: String
    let sourcePinsSHA256: String
    let osUserID: UInt32
    let osSessionSHA256: String
    let ownerConfirmedAccountSessionSHA256: String
    /// nil only for explicitly consumed first qualification. Not a wildcard write grant.
    let accountSHA256: String?

    func validate() throws {
        let hashes = [approvalInputSHA256, packagingReceiptSHA256, sourcePinsSHA256, ownerDecisionSHA256, planSHA256, schemaSHA256, binarySHA256, profileSHA256,
                      osSessionSHA256, ownerConfirmedAccountSessionSHA256] + (accountSHA256.map { [$0] } ?? [])
        guard hashes.allSatisfy({ ledgerHex($0, 64) }), ledgerHex(codeDirectoryHash, 40) || ledgerHex(codeDirectoryHash, 64),
              schemaSHA256 == "6fcf5478c3307685f8a45154b44eeeaec6a907c33412a2c388a6cb8831f04003",
              osUserID == getuid(), windowStartMS >= 0, windowEndMS > windowStartMS,
              windowEndMS - windowStartMS <= 900_000 else { throw LedgerFailure.permission }
    }
    func sameApproval(as other: Self) -> Bool {
        ownerWindow == other.ownerWindow && approvalInputSHA256 == other.approvalInputSHA256 &&
        packagingReceiptSHA256 == other.packagingReceiptSHA256 && sourcePinsSHA256 == other.sourcePinsSHA256 &&
        ownerDecisionSHA256 == other.ownerDecisionSHA256 && windowStartMS == other.windowStartMS && windowEndMS == other.windowEndMS &&
        planSHA256 == other.planSHA256 && run == other.run && dataset == other.dataset && schemaSHA256 == other.schemaSHA256 &&
        binarySHA256 == other.binarySHA256 && codeDirectoryHash == other.codeDirectoryHash && profileSHA256 == other.profileSHA256 &&
        osUserID == other.osUserID && osSessionSHA256 == other.osSessionSHA256 &&
        ownerConfirmedAccountSessionSHA256 == other.ownerConfirmedAccountSessionSHA256
    }
}
func ledgerHex(_ text: String, _ count: Int) -> Bool {
    text.utf8.count == count && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
}
func ledgerEncode<T: Encodable>(_ value: T) throws -> Data {
    let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return try e.encode(value)
}
struct LedgerTime: Codable { let wallMS: Int64; let uptimeNS: UInt64 }
@MainActor protocol LedgerClock { func now() -> LedgerTime }
@MainActor struct SystemLedgerClock: LedgerClock {
    func now() -> LedgerTime { LedgerTime(wallMS: Int64(Date().timeIntervalSince1970 * 1_000), uptimeNS: DispatchTime.now().uptimeNanoseconds) }
}
