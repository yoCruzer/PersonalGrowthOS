import Foundation
import CloudKit
import FormalProbeCore

enum GuardedAccountError: String, Error { case unavailable, changed, cancelled, busy, invalidIdentity, wrongPermission }

/// Notification delivery may be on any queue. Invalidate synchronously there,
/// before scheduling MainActor cancellation, so a queued callback cannot race
/// ahead of the account-change fence and authorize the next operation.
final class AccountEpochLatch: @unchecked Sendable {
    let epoch = UUID()
    private let lock = NSLock()
    private var reason: GuardedAccountError?
    func invalidate(_ reason: GuardedAccountError = .changed) {
        lock.lock(); if self.reason == nil { self.reason = reason }; lock.unlock()
    }
    func check() throws {
        lock.lock(); let reason = reason; lock.unlock()
        if let reason { throw reason }
    }
}

@MainActor protocol BatchAccountProvider: AnyObject {
    func bindOperationEvidence(_ sink: @escaping TransportEvidenceSink, onFailure: @escaping TransportEvidenceFailure) throws
    func authorizeRead(_ operation: LedgerOperation, operationID: UUID, permit: ExecutionPermit) throws
    func requestCancellation()
    func checkEpoch() throws
    func available() async throws
    /// Opaque value stays in memory. The caller stores only the ledger-keyed HMAC.
    func userRecordName() async throws -> String
}

/// Pure local bookkeeping, not a runtime/account qualification or CloudKit capability.
/// Production and offline tests use the same durable-intent/one-shot/budget checks.
@MainActor final class AccountReadPolicy {
    struct Ticket {
        fileprivate let operation: LedgerOperation
        fileprivate let id: UUID
        fileprivate let permit: ExecutionPermit
    }
    private let ledger: ExecutionLedger
    private let qualificationBinding: ExecutionBinding
    private var pending: Ticket?
    private var activeID: UUID?
    private var usedIDs = Set<UUID>()
    private(set) var apiInvocations = 0

    init(ledger: ExecutionLedger, qualificationBinding: ExecutionBinding) {
        self.ledger = ledger; self.qualificationBinding = qualificationBinding
    }
    func authorize(_ operation: LedgerOperation, operationID: UUID, permit: ExecutionPermit) throws {
        guard pending == nil, activeID == nil, !usedIDs.contains(operationID), apiInvocations < 12 else {
            throw GuardedAccountError.wrongPermission
        }
        switch operation { case .accountStatus, .userRecordID, .accountCheckBefore, .accountCheckAfter: break
        default: throw GuardedAccountError.wrongPermission }
        let binding = try ledger.requirePendingIntent(operation, operationID: operationID, permit: permit)
        guard qualificationBinding.sameApproval(as: binding) else { throw GuardedAccountError.wrongPermission }
        pending = Ticket(operation: operation, id: operationID, permit: permit)
    }
    func take(status: Bool) throws -> Ticket {
        guard let ticket = pending, (ticket.operation == .accountStatus) == status else {
            throw GuardedAccountError.wrongPermission
        }
        _ = try ledger.requirePendingIntent(ticket.operation, operationID: ticket.id, permit: ticket.permit)
        pending = nil; usedIDs.insert(ticket.id); activeID = ticket.id
        return ticket
    }
    /// Called synchronously immediately before the actual SDK call. Consuming the
    /// ticket happens only once, even when the durable intent is still pending.
    func beforeEnqueue(_ ticket: Ticket) throws {
        guard activeID == ticket.id, apiInvocations < 12 else { throw GuardedAccountError.wrongPermission }
        _ = try ledger.requirePendingIntent(ticket.operation, operationID: ticket.id, permit: ticket.permit)
        activeID = nil; apiInvocations += 1
    }
}

/// This is the only planned production owner of the fixed container. No caller
/// database or account identifier is accepted as a proof of qualification.
/// Construction itself requires an already durable qualification permit.
@MainActor final class GuardedAccountSession: BatchAccountProvider {
    private let container: CKContainer
    private let window: ValidatedOwnerWindow
    private let latch: AccountEpochLatch
    private let ledger: ExecutionLedger
    private let qualificationBinding: ExecutionBinding
    private var sink: TransportEvidenceSink
    private var onFailure: TransportEvidenceFailure
    private var observer: NSObjectProtocol?
    private var cancelLookup: (() -> Void)?
    private var cancelBatch: (() -> Void)?
    private var busy = false
    private let reads: AccountReadPolicy
    var apiInvocations: Int { reads.apiInvocations }

    private init(window: ValidatedOwnerWindow, ledger: ExecutionLedger, binding: ExecutionBinding, sink: @escaping TransportEvidenceSink,
                 onFailure: @escaping TransportEvidenceFailure) {
        self.window = window; self.sink = sink; self.onFailure = onFailure
        self.ledger = ledger; qualificationBinding = binding
        reads = AccountReadPolicy(ledger: ledger, qualificationBinding: binding)
        let latch = AccountEpochLatch(); self.latch = latch
        // Never called by offline parser/replay/tests. The factory below checks
        // the real self-qualification, Owner window and durable permit first.
        container = CKContainer(identifier: FormalProbeIdentity.container)
        observer = NotificationCenter.default.addObserver(forName: .CKAccountChanged,
            object: nil, queue: nil) { [weak self, latch] _ in
                latch.invalidate()
                DispatchQueue.main.async { self?.cancelLookup?(); self?.cancelBatch?() }
            }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    static func create(qualification: RuntimeSigningQualification, window: ValidatedOwnerWindow,
                       ledger: ExecutionLedger, permit: ExecutionPermit, expectedBinding: ExecutionBinding,
                       sink: @escaping TransportEvidenceSink,
                       onFailure: @escaping TransportEvidenceFailure) throws -> GuardedAccountSession {
        try window.check()
        let actual = try ledger.binding(for: permit, requiring: .qualificationRead)
        let owner = window.approval
        let expectedRuntime = try owner.runtime.expectation()
        let (startMS, startOverflow) = owner.startsAt.multipliedReportingOverflow(by: 1_000)
        let (endMS, endOverflow) = owner.expiresAt.multipliedReportingOverflow(by: 1_000)
        guard owner.purpose == "FIXED_SYNTHETIC_DEVELOPMENT_BATCH", actual == expectedBinding,
              !startOverflow, !endOverflow, actual.windowStartMS == startMS, actual.windowEndMS == endMS,
              actual.accountSHA256 == nil, actual.ownerDecisionSHA256 == owner.ownerDecisionSHA256,
              actual.ownerWindow == owner.window, actual.approvalInputSHA256 == window.inputSHA256,
              actual.osUserID == owner.osUserID, actual.ownerConfirmedAccountSessionSHA256 == owner.ownerSessionSHA256,
              actual.run == owner.run, actual.dataset == owner.dataset, actual.planSHA256 == owner.planSHA256,
              actual.binarySHA256 == owner.runtime.signedBinarySHA256,
              actual.codeDirectoryHash == owner.runtime.codeDirectoryHash,
              actual.profileSHA256 == owner.runtime.profileSHA256,
              actual.packagingReceiptSHA256 == owner.runtime.packagingReceiptSHA256,
              actual.sourcePinsSHA256 == owner.runtime.sourcePinsSHA256,
              qualification.binding == expectedRuntime,
              Date().timeIntervalSince(qualification.observedAt) >= 0,
              Date().timeIntervalSince(qualification.observedAt) < 30,
              qualification.profileExpiresAt.timeIntervalSince1970 > Double(owner.expiresAt) else {
            throw GuardedAccountError.wrongPermission
        }
        return GuardedAccountSession(window: window, ledger: ledger, binding: actual, sink: sink, onFailure: onFailure)
    }

    func checkEpoch() throws { try window.check(); try latch.check(); try Task.checkCancellation() }

    func bindOperationEvidence(_ sink: @escaping TransportEvidenceSink, onFailure: @escaping TransportEvidenceFailure) throws {
        guard !busy else { throw GuardedAccountError.busy }
        // Each new bridge captures these values. Rebinding for the batch does
        // not redirect late qualification callbacks into a different permit.
        self.sink = sink; self.onFailure = onFailure
    }
    func requestCancellation() { latch.invalidate(.cancelled); cancelLookup?(); cancelBatch?() }
    func authorizeRead(_ operation: LedgerOperation, operationID: UUID, permit: ExecutionPermit) throws {
        try checkEpoch(); guard !busy else { throw GuardedAccountError.busy }
        try reads.authorize(operation, operationID: operationID, permit: permit)
    }
    private func beforeReadEnqueue(_ ticket: AccountReadPolicy.Ticket) throws {
        try checkEpoch(); try reads.beforeEnqueue(ticket)
    }

    func available() async throws {
        try checkEpoch(); guard !busy else { throw GuardedAccountError.busy }; busy = true
        defer { busy = false; cancelLookup = nil }
        let permission = try reads.take(status: true)
        let bridge = OperationCallbackBridge<String, CKAccountStatus, CKAccountStatus>(
            stage: "account-status", expected: ["account-status"], label: { $0 }, validValue: { _, _ in true },
            sink: sink, onFailure: onFailure, cancellationScope: .localWaitOnly) { items, result in
                try result.get(); guard let item = items["account-status"] else { throw GuardedAccountError.unavailable }
                return try item.get()
            }
        cancelLookup = { bridge.requestCancellation() }
        // These CKContainer convenience reads expose no cancellable CKOperation.
        // This local handle cancels only our wait; a late response is still sent
        // to the captured original sink. It does not claim server cancellation.
        let status = try await bridge.execute(operation: Operation()) {
            do { try beforeReadEnqueue(permission) } catch { bridge.complete(.failure(error)); return }
            container.accountStatus { status, error in
                if let error { bridge.receive("account-status", .failure(error)); bridge.complete(.failure(error)) }
                else { bridge.receive("account-status", .success(status)); bridge.complete(.success(())) }
            }
        }
        try checkEpoch(); guard status == .available else { throw GuardedAccountError.unavailable }
    }

    func userRecordName() async throws -> String {
        try checkEpoch(); guard !busy else { throw GuardedAccountError.busy }; busy = true
        defer { busy = false; cancelLookup = nil }
        let permission = try reads.take(status: false)
        let bridge = OperationCallbackBridge<String, String, String>(
            stage: "account-record-id", expected: ["account-record-id"], label: { $0 },
            validValue: { _, value in !value.isEmpty && value.utf8.count <= 1_024 },
            sink: sink, onFailure: onFailure, cancellationScope: .localWaitOnly) { items, result in
                try result.get(); guard let item = items["account-record-id"] else { throw GuardedAccountError.invalidIdentity }
                return try item.get()
            }
        cancelLookup = { bridge.requestCancellation() }
        let name = try await bridge.execute(operation: Operation()) {
            do { try beforeReadEnqueue(permission) } catch { bridge.complete(.failure(error)); return }
            container.fetchUserRecordID { identifier, error in
                if let error { bridge.receive("account-record-id", .failure(error)); bridge.complete(.failure(error)) }
                else if let identifier {
                    bridge.receive("account-record-id", .success(identifier.recordName)); bridge.complete(.success(()))
                } else { bridge.complete(.failure(GuardedAccountError.invalidIdentity)) }
            }
        }
        try checkEpoch(); return name
    }

    func batchTransport(ledger: ExecutionLedger, permit: ExecutionPermit,
                        expectedBinding: ExecutionBinding) throws -> CloudKitDevelopmentAdapter {
        try checkEpoch()
        let actual = try ledger.binding(for: permit, requiring: .developmentBatch)
        guard actual == expectedBinding, actual.accountSHA256 != nil,
              actual.sameApproval(as: qualificationBinding),
              actual.ownerWindow == window.approval.window,
              actual.approvalInputSHA256 == window.inputSHA256 else { throw GuardedAccountError.wrongPermission }
        let adapter = CloudKitDevelopmentAdapter(unauthenticatedDatabase: container.privateCloudDatabase)
        cancelBatch = { [weak adapter] in adapter?.requestCancellation() }
        return adapter
    }
}
