import Foundation
import CryptoKit
import Darwin

@MainActor final class ExecutionPermit {
    fileprivate let ledgerNonce: UUID
    fileprivate let id: UUID
    fileprivate init(ledgerNonce: UUID, id: UUID) { self.ledgerNonce = ledgerNonce; self.id = id }
}
private struct LedgerAnchor: Codable, Equatable {
    let version: Int
    let enrollmentDecisionSHA256: String
    let rootDevice: UInt64
    let rootInode: UInt64
    let lockDevice: UInt64
    let lockInode: UInt64
    let key: Data
    var sequence: Int
    var headMAC: String
    var wallHighWaterMS: Int64
}
private enum LedgerTerminal: Codable {
    case qualificationCompleted(accountSHA256: String), batchCompleted, remoteOutcomeUnknown(LedgerStopReason)
}
private enum LedgerEvent: Codable {
    case consumed(permission: LedgerPermission, binding: ExecutionBinding, clock: LedgerTime)
    case intent(operation: LedgerOperation, operationID: UUID)
    case returned(operation: LedgerOperation, status: LedgerReturnStatus, summarySHA256: String, accountSHA256: String?)
    case validated(operation: LedgerOperation)
    case observation(operationID: UUID, event: LedgerObservation, summarySHA256: String)
    case terminal(LedgerTerminal)
}
private struct LedgerBody: Codable {
    let sequence: Int
    let previousMAC: String
    let permitID: UUID
    let wallMS: Int64
    let event: LedgerEvent
}
private struct LedgerRecord: Codable { let body: LedgerBody; let mac: String }
private enum LedgerPattern: Equatable { case intent(LedgerOperation), returned(LedgerOperation), validated(LedgerOperation) }
private struct LedgerReturn { let status: LedgerReturnStatus; let account: String? }
private struct LedgerExecution {
    let permission: LedgerPermission
    let binding: ExecutionBinding
    let consumedAt: LedgerTime
    var position = 0
    var operations: [UUID: LedgerOperation] = [:]
    var returns: [String: LedgerReturn] = [:]
    var failed = false
    var terminal: LedgerTerminal?
    var pattern: [LedgerPattern] {
        switch permission {
        case .qualificationRead:
            return [.accountStatus, .userRecordID].flatMap { [.intent($0), .returned($0), .validated($0)] }
        case .developmentBatch:
            return LedgerStage.allCases.flatMap { stage in
                [.intent(.accountCheckBefore(stage)), .returned(.accountCheckBefore(stage)), .validated(.accountCheckBefore(stage)),
                 .intent(.transport(stage)), .returned(.transport(stage)),
                 .intent(.accountCheckAfter(stage)), .returned(.accountCheckAfter(stage)), .validated(.accountCheckAfter(stage)),
                 .validated(.transport(stage))]
            }
        }
    }
}

/// Synchronous MainActor durability boundary. Internal only; never a live authority
/// factory. The production root and Keychain identity cannot be selected by --output.
@MainActor final class ExecutionLedger {
    private let files: ExecutionLedgerFiles
    private let store: ExecutionAnchorStore
    private let clock: LedgerClock
    private let nonce = UUID()
    private let openedUptime: UInt64
    private let openedWallMS: Int64
    private var lastUptime: UInt64
    private var anchor: LedgerAnchor
    private var anchorBytes: Data
    private var executions: [UUID: LedgerExecution] = [:]
    private var poisoned = false
    var hasUnresolvedExecutions: Bool { executions.values.contains { $0.terminal == nil } }
    private static var productionRoot: URL {
        // OS supplies the current user's (sandbox-aware) Application Support root.
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.yocruzer.PersonalGrowthOS.FormalSyncProbe.ExecutionGuard-v1", isDirectory: true)
    }
    static func openProduction() throws -> ExecutionLedger {
        try ExecutionLedger(root: productionRoot, store: KeychainExecutionAnchorStore(), clock: SystemLedgerClock(), enrollment: nil)
    }
    /// An explicit upstream Owner-enrollment gate is required. Merely supplying this
    /// reference does not prove it. No host calls this method and no reset API exists.
    static func enrollProduction(ownerDecisionSHA256: String) throws -> ExecutionLedger {
        try ExecutionLedger(root: productionRoot, store: KeychainExecutionAnchorStore(), clock: SystemLedgerClock(), enrollment: ownerDecisionSHA256)
    }
    static func openForTesting(root: URL, anchorStore: ExecutionAnchorStore, clock: LedgerClock) throws -> ExecutionLedger {
        try ExecutionLedger(root: root, store: anchorStore, clock: clock, enrollment: nil)
    }
    static func enrollForTesting(root: URL, anchorStore: ExecutionAnchorStore, clock: LedgerClock, ownerDecisionSHA256: String) throws -> ExecutionLedger {
        try ExecutionLedger(root: root, store: anchorStore, clock: clock, enrollment: ownerDecisionSHA256)
    }
    private init(root: URL, store: ExecutionAnchorStore, clock: LedgerClock, enrollment: String?) throws {
        self.store = store; self.clock = clock
        let time = clock.now(); openedUptime = time.uptimeNS; openedWallMS = time.wallMS; lastUptime = time.uptimeNS
        guard time.wallMS >= 0 else { throw LedgerFailure.expired }
        let existing = try store.load()
        if let enrollment {
            guard ledgerHex(enrollment, 64), existing == nil else { throw LedgerFailure.replay }
            files = try ExecutionLedgerFiles(url: root, enroll: true)
            let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            anchor = LedgerAnchor(version: 1, enrollmentDecisionSHA256: enrollment, rootDevice: files.device, rootInode: files.inode,
                lockDevice: files.lockDevice, lockInode: files.lockInode, key: key, sequence: 0, headMAC: String(repeating: "0", count: 64), wallHighWaterMS: time.wallMS)
            anchorBytes = try ledgerEncode(anchor)
            try store.create(anchorBytes)
            guard try store.load() == anchorBytes else { throw LedgerFailure.anchorFailure }
        } else {
            guard let existing else { throw LedgerFailure.missingAnchor }
            files = try ExecutionLedgerFiles(url: root, enroll: false)
            anchor = try JSONDecoder().decode(LedgerAnchor.self, from: existing); anchorBytes = existing
            guard try ledgerEncode(anchor) == existing else { throw LedgerFailure.corrupt }
        }
        guard anchor.version == 1, anchor.key.count == 32, ledgerHex(anchor.enrollmentDecisionSHA256, 64),
              anchor.sequence >= 0, anchor.sequence <= 2_048, ledgerHex(anchor.headMAC, 64),
              anchor.rootDevice == files.device, anchor.rootInode == files.inode,
              anchor.lockDevice == files.lockDevice, anchor.lockInode == files.lockInode else { throw LedgerFailure.corrupt }
        try verifyAll()
    }
    private func mac(_ bytes: Data) -> String {
        HMAC<SHA256>.authenticationCode(for: bytes, using: SymmetricKey(data: anchor.key)).map { String(format: "%02x", $0) }.joined()
    }
    /// Opaque ID exists only transiently in memory. Return is private local binding,
    /// not a wire/public report field. Stable only under this immutable anchor key.
    func accountDigest(_ recordName: String) throws -> String {
        try integrity()
        guard !recordName.isEmpty, recordName.utf8.count <= 1_024, !recordName.utf8.contains(0) else { throw LedgerFailure.accountMismatch }
        return mac(Data("PGOS.ExecutionGuard.account.v1\0".utf8) + Data(recordName.utf8))
    }
    private func operationKey(_ operation: LedgerOperation) throws -> String {
        String(decoding: try ledgerEncode(operation), as: UTF8.self)
    }
    private func integrity() throws {
        guard !poisoned else { throw LedgerFailure.poisoned }
        do {
            try files.verifyBinding()
            guard try store.load() == anchorBytes else { throw LedgerFailure.anchorFailure }
            // Detect truncation/replacement/tampering, not just a valid cached head.
            try verifyAll()
        } catch { poisoned = true; throw error }
    }
    private func verifyAll() throws {
        let expected = Set((1...max(1, anchor.sequence)).filter { $0 <= anchor.sequence }.map(ExecutionLedgerFiles.recordName)).union(["guard.lock"])
        guard try files.names() == expected else { throw LedgerFailure.corrupt }
        var previous = String(repeating: "0", count: 64), state: [UUID: LedgerExecution] = [:]
        if anchor.sequence > 0 {
            for sequence in 1...anchor.sequence {
                let bytes = try files.read(sequence), record = try JSONDecoder().decode(LedgerRecord.self, from: bytes)
                guard try ledgerEncode(record) == bytes, record.body.sequence == sequence, record.body.previousMAC == previous,
                      record.mac == mac(try ledgerEncode(record.body)), record.body.wallMS <= anchor.wallHighWaterMS else { throw LedgerFailure.corrupt }
                try apply(record.body.event, permitID: record.body.permitID, to: &state)
                previous = record.mac
            }
        }
        guard previous == anchor.headMAC else { throw LedgerFailure.corrupt }; executions = state
        try files.verifyBinding()
    }
    private func fresh(_ binding: ExecutionBinding, origin: LedgerTime? = nil) throws {
        let now = clock.now()
        guard now.wallMS >= anchor.wallHighWaterMS, now.wallMS >= binding.windowStartMS, now.wallMS <= binding.windowEndMS,
              now.uptimeNS >= openedUptime, now.uptimeNS >= lastUptime else { throw LedgerFailure.expired }
        let baseline = origin ?? LedgerTime(wallMS: openedWallMS, uptimeNS: openedUptime)
        guard now.uptimeNS >= baseline.uptimeNS else { throw LedgerFailure.expired }
        let elapsedMS = Int64((now.uptimeNS - baseline.uptimeNS) / 1_000_000)
        let (predictedWall, overflow) = baseline.wallMS.addingReportingOverflow(elapsedMS)
        guard !overflow, predictedWall <= binding.windowEndMS,
              abs(now.wallMS - predictedWall) <= 5_000 else { throw LedgerFailure.expired }
        lastUptime = now.uptimeNS
    }
    private func permitID(_ permit: ExecutionPermit) throws -> UUID {
        guard permit.ledgerNonce == nonce, executions[permit.id] != nil else { throw LedgerFailure.permission }; return permit.id
    }
    private func append(_ event: LedgerEvent, id: UUID) throws {
        try integrity(); guard anchor.sequence < 2_048 else { throw LedgerFailure.capacity }
        var prospective = executions
        try apply(event, permitID: id, to: &prospective)
        let body = LedgerBody(sequence: anchor.sequence + 1, previousMAC: anchor.headMAC, permitID: id, wallMS: clock.now().wallMS, event: event)
        let digest = mac(try ledgerEncode(body)), record = LedgerRecord(body: body, mac: digest)
        var advanced = anchor; advanced.sequence += 1; advanced.headMAC = digest; advanced.wallHighWaterMS = max(anchor.wallHighWaterMS, body.wallMS)
        let next = try ledgerEncode(advanced)
        do {
            // A crash at any gap leaves extra/missing records or anchor mismatch.
            // Never repair, truncate, retry, or return a usable permit after that gap.
            try files.write(body.sequence, bytes: ledgerEncode(record))
            try store.replace(expected: anchorBytes, with: next)
            guard try store.load() == next else { throw LedgerFailure.anchorFailure }
            try files.verifyBinding()
            anchor = advanced; anchorBytes = next; executions = prospective
            try verifyAll()
        } catch { poisoned = true; throw error }
    }
    func consume(_ permission: LedgerPermission, binding: ExecutionBinding) throws -> ExecutionPermit {
        try integrity(); try binding.validate(); try fresh(binding)
        guard !hasUnresolvedExecutions else { throw LedgerFailure.poisoned }
        if permission == .developmentBatch, let qualification = executions.values.first(where: {
            $0.permission == .qualificationRead && ($0.binding.ownerWindow == binding.ownerWindow || $0.binding.approvalInputSHA256 == binding.approvalInputSHA256)
        }) { try fresh(binding, origin: qualification.consumedAt) }
        let id = UUID(); try append(.consumed(permission: permission, binding: binding, clock: clock.now()), id: id)
        return ExecutionPermit(ledgerNonce: nonce, id: id)
    }
    /// Checked read, not a cached token flag or a new authorization. The caller must
    /// still compare all fields with its independently validated Owner window.
    func binding(for permit: ExecutionPermit, requiring permission: LedgerPermission) throws -> ExecutionBinding {
        try integrity(); let id = try permitID(permit)
        guard let execution = executions[id], execution.permission == permission, execution.terminal == nil,
              !execution.failed else { throw LedgerFailure.permission }
        try fresh(execution.binding, origin: execution.consumedAt); return execution.binding
    }
    @discardableResult func intent(_ operation: LedgerOperation, permit: ExecutionPermit) throws -> UUID {
        try integrity(); let id = try permitID(permit); try fresh(executions[id]!.binding, origin: executions[id]!.consumedAt)
        let operationID = UUID(); try append(.intent(operation: operation, operationID: operationID), id: id); return operationID
    }
    /// Used immediately before an SDK invocation, not just when a session is
    /// constructed. A historic observation or a consumed permit is insufficient.
    func requirePendingIntent(_ operation: LedgerOperation, operationID: UUID, permit: ExecutionPermit) throws -> ExecutionBinding {
        try integrity(); let id = try permitID(permit)
        guard let execution = executions[id], execution.terminal == nil, !execution.failed,
              execution.operations[operationID] == operation,
              execution.position < execution.pattern.count,
              execution.pattern[execution.position] == .returned(operation) else { throw LedgerFailure.transition }
        try fresh(execution.binding, origin: execution.consumedAt); return execution.binding
    }
    func returned(_ operation: LedgerOperation, status: LedgerReturnStatus, summarySHA256: String, accountSHA256: String? = nil, permit: ExecutionPermit) throws {
        let id = try permitID(permit)
        try append(.returned(operation: operation, status: status, summarySHA256: summarySHA256, accountSHA256: accountSHA256), id: id)
    }
    func validated(_ operation: LedgerOperation, permit: ExecutionPermit) throws {
        try integrity(); let id = try permitID(permit); try fresh(executions[id]!.binding, origin: executions[id]!.consumedAt)
        try append(.validated(operation: operation), id: id)
    }
    func finishQualification(accountSHA256: String, permit: ExecutionPermit) throws {
        try integrity(); let id = try permitID(permit); try fresh(executions[id]!.binding, origin: executions[id]!.consumedAt)
        try append(.terminal(.qualificationCompleted(accountSHA256: accountSHA256)), id: id)
    }
    func finishBatch(permit: ExecutionPermit) throws {
        try integrity(); let id = try permitID(permit); try fresh(executions[id]!.binding, origin: executions[id]!.consumedAt); try append(.terminal(.batchCompleted), id: id)
    }
    func terminateUnknown(reason: LedgerStopReason, permit: ExecutionPermit) throws {
        try append(.terminal(.remoteOutcomeUnknown(reason)), id: permitID(permit))
    }
    func recordObservation(operationID: UUID, event: LedgerObservation, summarySHA256: String, permit: ExecutionPermit) throws {
        try append(.observation(operationID: operationID, event: event, summarySHA256: summarySHA256), id: permitID(permit))
    }
    private func apply(_ event: LedgerEvent, permitID: UUID, to state: inout [UUID: LedgerExecution]) throws {
        if case .consumed(let permission, let binding, let time) = event {
            try binding.validate(); guard time.wallMS >= binding.windowStartMS, time.wallMS <= binding.windowEndMS, state[permitID] == nil else { throw LedgerFailure.replay }
            let related = state.values.filter { $0.binding.ownerWindow == binding.ownerWindow || $0.binding.approvalInputSHA256 == binding.approvalInputSHA256 || $0.binding.planSHA256 == binding.planSHA256 || $0.binding.run == binding.run || $0.binding.dataset == binding.dataset }
            guard !related.contains(where: { $0.permission == permission }), !state.values.contains(where: { $0.terminal == nil }) else { throw LedgerFailure.replay }
            if permission == .qualificationRead {
                guard related.isEmpty, binding.accountSHA256 == nil else { throw LedgerFailure.permission }
            } else {
                guard let account = binding.accountSHA256, related.count == 1, let qualification = related.first,
                      qualification.permission == .qualificationRead, qualification.binding.sameApproval(as: binding),
                      case .qualificationCompleted(let established) = qualification.terminal, account == established else { throw LedgerFailure.accountMismatch }
            }
            let origin: LedgerTime
            if permission == .developmentBatch, let first = related.first { origin = first.consumedAt }
            else { origin = time }
            guard time.uptimeNS >= origin.uptimeNS else { throw LedgerFailure.expired }
            let elapsed = Int64((time.uptimeNS - origin.uptimeNS) / 1_000_000)
            let (predicted, overflow) = origin.wallMS.addingReportingOverflow(elapsed)
            guard !overflow, predicted <= binding.windowEndMS, abs(time.wallMS - predicted) <= 5_000 else { throw LedgerFailure.expired }
            state[permitID] = LedgerExecution(permission: permission, binding: binding, consumedAt: origin); return
        }
        guard var execution = state[permitID] else { throw LedgerFailure.permission }
        if case .observation(let operationID, _, let summary) = event {
            guard execution.operations[operationID] != nil, ledgerHex(summary, 64) else { throw LedgerFailure.permission }; return
        }
        guard execution.terminal == nil else { throw LedgerFailure.transition }
        if case .terminal(let terminal) = event {
            switch terminal {
            case .remoteOutcomeUnknown: break
            case .qualificationCompleted(let account):
                guard execution.permission == .qualificationRead, !execution.failed, execution.position == execution.pattern.count,
                      ledgerHex(account, 64), execution.returns[try operationKey(.userRecordID)]?.account == account else { throw LedgerFailure.transition }
            case .batchCompleted:
                guard execution.permission == .developmentBatch, !execution.failed, execution.position == execution.pattern.count else { throw LedgerFailure.transition }
            }
            execution.terminal = terminal; state[permitID] = execution; return
        }
        guard !execution.failed, execution.position < execution.pattern.count else { throw LedgerFailure.transition }
        let expected = execution.pattern[execution.position]
        switch event {
        case .intent(let operation, let operationID):
            guard expected == .intent(operation), execution.operations[operationID] == nil else { throw LedgerFailure.transition }
            execution.operations[operationID] = operation
        case .returned(let operation, let status, let summary, let account):
            guard expected == .returned(operation), ledgerHex(summary, 64), account.map({ ledgerHex($0, 64) }) ?? true else { throw LedgerFailure.transition }
            let accountOperation: Bool
            switch operation { case .userRecordID, .accountCheckBefore, .accountCheckAfter: accountOperation = true; default: accountOperation = false }
            guard accountOperation || account == nil else { throw LedgerFailure.transition }
            execution.returns[try operationKey(operation)] = LedgerReturn(status: status, account: account)
            execution.failed = status != .success
        case .validated(let operation):
            guard expected == .validated(operation), let returned = execution.returns[try operationKey(operation)], returned.status == .success else { throw LedgerFailure.transition }
            switch operation {
            case .userRecordID: guard returned.account != nil else { throw LedgerFailure.accountMismatch }
            case .accountCheckBefore, .accountCheckAfter:
                guard returned.account == execution.binding.accountSHA256, returned.account != nil else { throw LedgerFailure.accountMismatch }
            default: break
            }
        default: throw LedgerFailure.transition
        }
        execution.position += 1; state[permitID] = execution
    }
}
