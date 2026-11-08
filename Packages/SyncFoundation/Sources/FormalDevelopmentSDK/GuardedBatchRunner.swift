import Foundation
import CloudKit
import FormalProbeCore
import SyncFoundation

enum GuardedBatchFailure: String, Error { case busy, poisoned, binding, callbackProtocol, evidence, accountChanged, invalidResults, existingZone, bytesChanged }
struct GuardedBatchReport: Encodable {
    let mode = "INJECTED_OR_EXTERNAL_FACTORY"
    let status: String
    let planSHA256: String
    let run: UUID
    let dataset: UUID
    let ownerWindow: UUID
    let p0Passed = false
    let realNetworkQualificationClaimed = false
    let providerMethodInvocations: Int
    let transportMethodInvocations: Int
    let completedStages: [String]
    let failure: String?
    let remoteOutcomeUnknown: Bool
    let failureStage: String?
    let operationEnqueuePrevented: Bool
    // Admission is not an assertion that the provider reached its SDK call.
    let sdkEnqueuesAdmitted: Int
}
private struct GuardedFatalMarker: Encodable {
    let status = "FATAL_EXECUTION_OR_EVIDENCE_UNKNOWN"
    let run: UUID
    let dataset: UUID
    let planSHA256: String
    let ledgerOperationID: UUID?
    let operation: LedgerOperation?
    let postTerminal: Bool
    let failureStage: String
    let failureCode: String
    let operationEnqueuePrevented: Bool
    let sdkEnqueuesAdmitted: Int
}
func guardedCode(_ error: Error) -> String {
    if let value = error as? GuardedBatchFailure { return "GUARDED_" + value.rawValue }
    if let value = error as? GuardedAccountError { return "ACCOUNT_" + value.rawValue }
    if let value = error as? OwnerWindowError { return "WINDOW_" + value.rawValue }
    if let value = error as? RuntimeSigningDiagnosticFailure { return "RUNTIME_" + value.stage.rawValue + "_" + String(value.status) }
    if let value = error as? RuntimeSigningError { return "RUNTIME_" + value.rawValue }
    if let value = error as? GuardedEntryError { return "ENTRY_" + value.rawValue }
    if let value = error as? LedgerFailure { return "LEDGER_" + String(describing: value) }
    return code(error)
}
private struct GuardedSummary: Encodable {
    let operation: LedgerOperation
    let status: String
    let detail: String
    let items: [Outcome]
}
private struct GuardedCallbackRecord: Encodable {
    let run: UUID
    let ledgerOperation: LedgerOperation
    let ledgerOperationID: UUID
    let callback: TransportOperationEvidence
    let originalItemCount: Int
    let truncatedPartialErrorItems: Int
    let originalStageMatched: Bool
}
@MainActor private final class GuardedTransportBox {
    let value: OperationEvidenceTransport
    init(_ value: OperationEvidenceTransport) { self.value = value }
}
@MainActor private final class GuardedRunEvidence {
    let directory: ProbeDirectory
    let fixture: ProbeFixture
    let ledger: ExecutionLedger
    var permit: ExecutionPermit
    weak var provider: BatchAccountProvider?
    weak var transport: GuardedTransportBox?
    var sequence = 0
    private var written: [String: (digest: String, count: Int)] = [:]
    var fatal = false
    var terminal = false
    var deadlineExpired = false
    var activeOperation: LedgerOperation?
    var activeScope: GuardedCallbackScope?
    var lastOperationID: UUID?
    var lastOperation: LedgerOperation?
    var lastOperationPermit: ExecutionPermit?
    var accountCalls = 0
    var transportCalls = 0
    var completed: [String] = []
    var primaryFailure: Error?
    var failureStage: String?
    var operationEnqueuePrevented = false
    var sdkEnqueuesAdmitted = 0
    let onFatal: () -> Void
    init(directory: ProbeDirectory, fixture: ProbeFixture, ledger: ExecutionLedger, permit: ExecutionPermit,
         provider: BatchAccountProvider, onFatal: @escaping () -> Void) {
        self.directory = directory; self.fixture = fixture; self.ledger = ledger; self.permit = permit
        self.provider = provider; self.onFatal = onFatal
    }
    func checkFiles() throws {
        try directory.requirePathBinding()
        guard try directory.read("plan.json") == fixture.plan.encoded() else { throw GuardedBatchFailure.bytesChanged }
        for (name, bytes) in fixture.files {
            guard try directory.read("lease-" + name) == bytes else { throw GuardedBatchFailure.bytesChanged }
        }
        try checkEvidence()
    }
    func checkEvidence(operationID: UUID? = nil, operation: LedgerOperation? = nil, originalPermit: ExecutionPermit? = nil) throws {
        do {
            for (name, expected) in written {
                let actual = try directory.read(name)
                guard actual.count == expected.count, syncDigest(actual) == expected.digest else { throw GuardedBatchFailure.evidence }
            }
        } catch { failEvidence(operationID: operationID, operation: operation, originalPermit: originalPermit); throw GuardedBatchFailure.evidence }
    }
    @discardableResult func writeNamed(_ name: String, bytes: Data) throws -> String {
        guard bytes.count <= 65_536, written.count < 4_096, written[name] == nil else { throw GuardedBatchFailure.evidence }
        try directory.write(name, bytes: bytes)
        let digest = syncDigest(bytes); written[name] = (digest, bytes.count)
        guard try directory.read(name) == bytes else { throw GuardedBatchFailure.evidence }
        return digest
    }
    @discardableResult func write<T: Encodable>(_ name: String, _ value: T) throws -> String {
        let bytes = try json(value)
        guard bytes.count <= 65_536 else { throw GuardedBatchFailure.evidence }
        let file = String(format: "%06d-%@.json", sequence, name); sequence += 1
        return try writeNamed(file, bytes: bytes)
    }
    func expireWindow(ownerWindow: UUID) {
        guard !terminal, !deadlineExpired else { return }; deadlineExpired = true
        do {
            let bytes = try json(["status": "OWNER_WINDOW_EXPIRED", "run": fixture.plan.run.uuidString,
                "dataset": fixture.plan.dataset.uuidString, "planSHA256": try fixture.plan.digest,
                "ownerWindow": ownerWindow.uuidString, "ledgerOperationID": lastOperationID?.uuidString ?? "NO_OPERATION_ISSUED"])
            let digest = try writeNamed("deadline-expired.json", bytes: bytes)
            if let id = lastOperationID, let permit = lastOperationPermit {
                try ledger.recordObservation(operationID: id, event: .cancellationRequested, summarySHA256: digest, permit: permit)
            }
        } catch { failEvidence() }
        // Both production interfaces cancel their local bridge wait immediately;
        // CloudKit may still finish remotely. Late callbacks keep the original sink.
        provider?.requestCancellation(); transport?.value.requestCancellation()
    }
    func failEvidence(operationID: UUID? = nil, operation: LedgerOperation? = nil, originalPermit: ExecutionPermit? = nil,
                      error: Error = GuardedBatchFailure.evidence, stage: String = "evidence", enqueuePrevented: Bool = false) {
        guard !fatal else { return }; fatal = true
        // Capture the first cause before cancellation can resume an awaiting bridge.
        primaryFailure = error; failureStage = stage; operationEnqueuePrevented = enqueuePrevented
        // Never rewrite an already returned report. A durable sidecar, when storage
        // permits, records post-terminal failure; the caller also receives onFatal.
        do {
            let bytes = try json(GuardedFatalMarker(run: fixture.plan.run, dataset: fixture.plan.dataset,
                planSHA256: try fixture.plan.digest, ledgerOperationID: operationID ?? lastOperationID,
                operation: operation ?? lastOperation, postTerminal: terminal,
                failureStage: stage, failureCode: guardedCode(error), operationEnqueuePrevented: enqueuePrevented,
                sdkEnqueuesAdmitted: sdkEnqueuesAdmitted))
            try writeNamed("fatal-unknown.json", bytes: bytes)
            if let id = operationID ?? lastOperationID {
                try ledger.recordObservation(operationID: id, event: .callbackRejected,
                    summarySHA256: syncDigest(bytes), permit: originalPermit ?? lastOperationPermit ?? permit)
            }
        } catch { /* Cannot claim unavailable evidence was persisted. onFatal is still mandatory. */ }
        onFatal(); provider?.requestCancellation(); transport?.value.requestCancellation()
    }
}
@MainActor private final class GuardedCallbackScope {
    let context: GuardedRunEvidence
    let operation: LedgerOperation
    let ledgerID: UUID
    let permit: ExecutionPermit
    let beforeEnqueue: () throws -> Void
    private var bridgeID: UUID?
    private var nextSequence = 0
    private(set) var enqueued = false
    private(set) var completed = false
    init(context: GuardedRunEvidence, operation: LedgerOperation, ledgerID: UUID, permit: ExecutionPermit,
         beforeEnqueue: @escaping () throws -> Void) {
        self.context = context; self.operation = operation; self.ledgerID = ledgerID; self.permit = permit
        self.beforeEnqueue = beforeEnqueue
    }
    private var stage: String {
        switch operation {
        case .accountStatus: return "account-status"
        case .userRecordID, .accountCheckBefore, .accountCheckAfter: return "account-record-id"
        case .transport(let stage):
            switch stage { case .zoneProbe: return "zone-probe"; case .zoneSave: return "zone-save"
            case .assetsSave: return "assets-save"; case .mutationsSave: return "mutations-save"; case .exactFetch: return "exact-fetch" }
        }
    }
    func receive(_ incoming: TransportOperationEvidence) throws {
        do {
            let allowed = Set(context.fixture.plan.records.map(\.recordName)).union(["zone", "operation", "account-status", "account-record-id", "UNEXPECTED_RECORD_ID"])
            // Public callback records never contain opaque account values or unknown IDs.
            let safeItems = incoming.items.prefix(8).map { item in
                TransportItemEvidence(item: allowed.contains(item.item) ? item.item : "UNEXPECTED_RECORD_ID",
                    status: item.status == "RETURNED_SUCCESS_UNVERIFIED" ? item.status : "RETURNED_FAILURE",
                    errorDomain: item.errorDomain == nil ? nil : (item.errorDomain == CKErrorDomain ? CKErrorDomain : "OTHER"),
                    errorCode: item.errorCode, partialErrorCodes: Array(item.partialErrorCodes.prefix(16)))
            }
            let callback = TransportOperationEvidence(operationID: incoming.operationID, stage: stage, sequence: incoming.sequence,
                event: knownEvent(incoming.event) ? incoming.event : "UNEXPECTED_CALLBACK", started: incoming.started,
                cancellationRequested: incoming.cancellationRequested, remoteOutcomeUnknown: incoming.remoteOutcomeUnknown,
                cancellationScope: incoming.cancellationScope, items: safeItems)
            let digest = try context.write("callback", GuardedCallbackRecord(run: context.fixture.plan.run,
                ledgerOperation: operation, ledgerOperationID: ledgerID, callback: callback,
                originalItemCount: incoming.items.count, truncatedPartialErrorItems: incoming.items.filter { $0.partialErrorCodes.count > 16 }.count,
                originalStageMatched: incoming.stage == stage))
            guard incoming.stage == stage, incoming.sequence == nextSequence,
                  incoming.items.count <= 8, incoming.items.allSatisfy({ $0.partialErrorCodes.count <= 16 }),
                  incoming.items.allSatisfy({ allowed.contains($0.item) && $0.item != "UNEXPECTED_RECORD_ID" &&
                      ["RETURNED_SUCCESS_UNVERIFIED", "RETURNED_FAILURE"].contains($0.status) }),
                  knownEvent(incoming.event), bridgeID == nil || bridgeID == incoming.operationID else {
                try context.ledger.recordObservation(operationID: ledgerID, event: .callbackRejected, summarySHA256: digest, permit: permit)
                throw GuardedBatchFailure.callbackProtocol
            }
            if bridgeID == nil {
                guard ["OPERATION_ENQUEUE_REQUESTED", "CANCEL_REQUESTED"].contains(incoming.event), incoming.sequence == 0 else {
                    try context.ledger.recordObservation(operationID: ledgerID, event: .callbackRejected, summarySHA256: digest, permit: permit)
                    throw GuardedBatchFailure.callbackProtocol
                }
                bridgeID = incoming.operationID
            }
            nextSequence += 1
            let event: LedgerObservation
            switch incoming.event {
            case "OPERATION_ENQUEUE_REQUESTED": event = .enqueueRequested
            case "CANCEL_REQUESTED": event = .cancellationRequested
            case "ITEM_RETURNED": event = .recordReturned
            case "OPERATION_RETURNED": event = .operationReturned
            case "UNEXPECTED_CALLBACK": event = .callbackRejected
            default: event = .lateCallback
            }
            try context.ledger.recordObservation(operationID: ledgerID, event: event, summarySHA256: digest, permit: permit)
            // Preserve the new raw callback first, then reject an earlier evidence
            // mutation even if this is a late callback after the original return.
            try context.checkEvidence(operationID: ledgerID, operation: operation, originalPermit: permit)
            if incoming.event == "OPERATION_ENQUEUE_REQUESTED" {
                // A provider claiming it already started cannot also establish a
                // pre-SDK rejection. Preserve that contradiction as unknown.
                guard !enqueued, !incoming.started, !incoming.cancellationRequested,
                      !incoming.remoteOutcomeUnknown else { throw GuardedBatchFailure.callbackProtocol }
                do { try beforeEnqueue() } // Bridge cannot enqueue unless this synchronous check returns.
                catch {
                    context.failEvidence(operationID: ledgerID, operation: operation, originalPermit: permit,
                        error: error, stage: "pre-enqueue-gate", enqueuePrevented: true)
                    throw error
                }
                enqueued = true; context.sdkEnqueuesAdmitted += 1
            }
            if incoming.event == "OPERATION_RETURNED" { completed = true }
        } catch {
            context.failEvidence(operationID: ledgerID, operation: operation, originalPermit: permit,
                error: error, stage: "callback-evidence")
            throw error
        }
    }
    private func knownEvent(_ event: String) -> Bool {
        ["OPERATION_ENQUEUE_REQUESTED", "CANCEL_REQUESTED", "ITEM_RETURNED", "OPERATION_RETURNED", "UNEXPECTED_CALLBACK",
         "LATE_ITEM_RETURNED", "LATE_OPERATION_RETURNED", "LATE_UNEXPECTED_CALLBACK"].contains(event)
    }
    func requireComplete() throws {
        guard enqueued, completed, !context.fatal else { throw GuardedBatchFailure.callbackProtocol }
    }
}

@MainActor final class GuardedBatchRunner {
    private var busy = false
    private weak var activeEvidence: GuardedRunEvidence?
    private(set) var evidenceFatal = false
    private func poisonActiveRun() {
        guard !evidenceFatal else { return }
        evidenceFatal = true
        // An old immutable callback scope may fail while a later window is
        // waiting. Preserve both runs' own evidence and stop the current wait.
        // Set the latch before calling back into a context to bound recursion.
        activeEvidence?.failEvidence()
    }
    /// Internal orchestration only. A supplied factory/runtime closure is not, by
    /// itself, proof of real signing, account qualification or external permission.
    func run(window: ValidatedOwnerWindow, ledger: ExecutionLedger, qualificationPermit: ExecutionPermit,
             binding: ExecutionBinding, output: URL, accountProvider: BatchAccountProvider,
             transportFactory: (ExecutionPermit, ExecutionBinding) throws -> OperationEvidenceTransport,
             runtimeRecheck: @escaping () throws -> Void, onEvidenceFatal: @escaping () -> Void = {}) async throws -> GuardedBatchReport {
        guard !busy else { throw GuardedBatchFailure.busy }; guard !evidenceFatal else { throw GuardedBatchFailure.poisoned }
        busy = true; defer { busy = false; activeEvidence = nil }
        var context: GuardedRunEvidence?
        var watchdog: Task<Void, Never>?
        defer { watchdog?.cancel() }
        var currentPermit = qualificationPermit
        do {
            try window.check(); try runtimeRecheck(); try accountProvider.checkEpoch(); try Task.checkCancellation()
            guard try ledger.binding(for: qualificationPermit, requiring: .qualificationRead) == binding else { throw GuardedBatchFailure.binding }
            try match(binding, window: window)
            let fixture = try ProbeFixture.make(run: window.approval.run, dataset: window.approval.dataset)
            guard try fixture.plan.digest == binding.planSHA256 else { throw GuardedBatchFailure.binding }
            let directory = try ProbeDirectory(output, create: true)
            let state = GuardedRunEvidence(directory: directory, fixture: fixture, ledger: ledger, permit: qualificationPermit,
                provider: accountProvider) { [weak self] in self?.poisonActiveRun(); onEvidenceFatal() }
            context = state; activeEvidence = state
            try directory.write("plan.json", bytes: fixture.plan.encoded())
            for (name, bytes) in fixture.files { try directory.write("lease-" + name, bytes: bytes) }
            let remaining = try window.remainingDuration()
            guard remaining.isFinite, remaining > 0, remaining <= 900 else { throw OwnerWindowError.outsideWindow }
            watchdog = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: UInt64((remaining * 1_000_000_000).rounded(.up))) }
                catch { return }
                guard !Task.isCancelled else { return }
                _ = try? window.check()
                state.expireWindow(ownerWindow: window.approval.window)
            }
            func check() throws {
                guard !self.evidenceFatal else { throw GuardedBatchFailure.poisoned }
                guard !state.fatal else { throw GuardedBatchFailure.evidence }
                guard !state.deadlineExpired else { throw OwnerWindowError.outsideWindow }
                try Task.checkCancellation(); try window.check(); try runtimeRecheck()
                guard let provider = state.provider else { throw GuardedBatchFailure.binding }
                try provider.checkEpoch(); try state.checkFiles(); try window.check()
            }
            func scope(_ operation: LedgerOperation, permit: ExecutionPermit) throws -> GuardedCallbackScope {
                try check()
                let id = try ledger.intent(operation, permit: permit)
                let value = GuardedCallbackScope(context: state, operation: operation, ledgerID: id, permit: permit) {
                    try check(); _ = try ledger.requirePendingIntent(operation, operationID: id, permit: permit)
                }
                state.activeOperation = operation; state.activeScope = value
                state.lastOperationID = id; state.lastOperation = operation; state.lastOperationPermit = permit
                return value
            }
            func returned(_ operation: LedgerOperation, detail: String, items: [Outcome] = [], account: String? = nil) throws {
                try state.activeScope?.requireComplete()
                let digest = try state.write("returned", GuardedSummary(operation: operation, status: "RETURNED_UNVERIFIED", detail: detail, items: items))
                try ledger.returned(operation, status: .success, summarySHA256: digest, accountSHA256: account, permit: currentPermit)
                state.activeOperation = nil; state.activeScope = nil
            }
            func accountRead(_ operation: LedgerOperation, expected: String? = nil) async throws -> String? {
                let evidence = try scope(operation, permit: currentPermit)
                try accountProvider.authorizeRead(operation, operationID: evidence.ledgerID, permit: currentPermit)
                try accountProvider.bindOperationEvidence({ try evidence.receive($0) }, onFailure: { _ in state.failEvidence(operationID: evidence.ledgerID, operation: operation, originalPermit: evidence.permit) })
                try check(); guard state.accountCalls < 12 else { throw GuardedBatchFailure.invalidResults }; state.accountCalls += 1
                let identity: String?
                if operation == .accountStatus {
                    try await accountProvider.available(); identity = nil
                } else {
                    let opaque = try await accountProvider.userRecordName()
                    identity = try ledger.accountDigest(opaque) // Never serialize opaque value or HMAC in run output.
                }
                try returned(operation, detail: operation == .accountStatus ? "AVAILABLE" : "IDENTITY_OBSERVED", account: identity)
                try check()
                if let expected { guard identity == expected else { throw GuardedBatchFailure.accountChanged } }
                try ledger.validated(operation, permit: currentPermit)
                return identity
            }
            _ = try await accountRead(.accountStatus)
            guard let account = try await accountRead(.userRecordID) else { throw GuardedBatchFailure.accountChanged }
            try check(); try ledger.finishQualification(accountSHA256: account, permit: currentPermit)
            let batchBinding = bound(binding, account: account)
            currentPermit = try ledger.consume(.developmentBatch, binding: batchBinding); state.permit = currentPermit
            try check()
            let transport = GuardedTransportBox(try transportFactory(currentPermit, batchBinding)); state.transport = transport
            let zone = CloudRecordCodec.zone(dataset: fixture.plan.dataset)
            let records = try encode(fixture, directory: directory)
            let allowed = Set(records.map(\.recordID))
            for stage in LedgerStage.allCases {
                _ = try await accountRead(.accountCheckBefore(stage), expected: account)
                let operation = LedgerOperation.transport(stage), evidence = try scope(operation, permit: currentPermit)
                transport.value.bindOperationEvidence({ try evidence.receive($0) }, onFailure: { _ in state.failEvidence(operationID: evidence.ledgerID, operation: operation, originalPermit: evidence.permit) })
                try check(); guard state.transportCalls < 5 else { throw GuardedBatchFailure.invalidResults }; state.transportCalls += 1
                var exists: Bool?, savedZone: CKRecordZone.ID?, results: [CKRecord.ID: Result<CKRecord, Error>]?
                var expected: [CKRecord] = []
                switch stage {
                case .zoneProbe: exists = try await transport.value.zoneExists(zone)
                case .zoneSave: savedZone = try await transport.value.createZone(zone)
                case .assetsSave:
                    expected = records.filter { $0.recordType != CloudRecordCodec.mutationType }
                    results = try await transport.value.save(expected)
                case .mutationsSave:
                    expected = records.filter { $0.recordType == CloudRecordCodec.mutationType }
                    results = try await transport.value.save(expected)
                case .exactFetch: expected = records; results = try await transport.value.fetch(records.map(\.recordID))
                }
                let items = results?.keys.sorted { $0.recordName < $1.recordName }.map { outcome($0.recordName, results![$0]!, id: $0, allowed: allowed) } ?? []
                let detail = exists.map { $0 ? "ZONE_EXISTS" : "ZONE_ABSENT" } ?? (savedZone.map { $0 == zone ? "ZONE_ID_MATCH" : "ZONE_ID_MISMATCH" } ?? "RECORD_RESULTS")
                try returned(operation, detail: detail, items: items)
                try check()
                _ = try await accountRead(.accountCheckAfter(stage), expected: account)
                try check()
                if let exists { guard !exists else { throw GuardedBatchFailure.existingZone } }
                if let savedZone { guard savedZone == zone else { throw GuardedBatchFailure.invalidResults } }
                if let results { try validate(results, expected: expected, fixture: fixture) }
                let validationDigest = try state.write("validated", GuardedSummary(operation: operation, status: "EXACT_RESULT_VALIDATED", detail: detail, items: []))
                try ledger.recordObservation(operationID: evidence.ledgerID, event: .validationEvidence,
                    summarySHA256: validationDigest, permit: evidence.permit)
                try ledger.validated(operation, permit: currentPermit); state.completed.append(stage.rawValue)
            }
            try check()
            // A precommit marker never claims success. A failure between the
            // ledger commit and final report is fatal/unknown and cannot be retried.
            let preparedDigest = try state.writeNamed("prepared-report.json", bytes: json(["status": "AWAITING_LEDGER_COMMIT", "planSHA256": binding.planSHA256]))
            guard let finalOperationID = state.lastOperationID else { throw GuardedBatchFailure.invalidResults }
            try ledger.recordObservation(operationID: finalOperationID, event: .reportPrepared, summarySHA256: preparedDigest, permit: currentPermit)
            try state.checkFiles(); try ledger.finishBatch(permit: currentPermit)
            state.terminal = true
            let success = report(window: window, context: state, failure: nil)
            let reportDigest = try state.writeNamed("verified-report.json", bytes: json(success))
            try ledger.recordObservation(operationID: finalOperationID, event: .reportPublished, summarySHA256: reportDigest, permit: currentPermit)
            try check()
            return success
        } catch {
            let error: Error = context?.primaryFailure ?? (context?.deadlineExpired == true ? OwnerWindowError.outsideWindow : error)
            if let state = context {
                if let active = state.activeOperation {
                    do {
                        let digest = try state.write("failed-return", GuardedSummary(operation: active, status: "REMOTE_OUTCOME_UNKNOWN", detail: guardedCode(error), items: []))
                        try ledger.returned(active, status: .unknown, summarySHA256: digest, permit: currentPermit)
                    } catch { state.failEvidence() }
                }
                state.activeScope = nil
                if !state.terminal {
                    do { try ledger.terminateUnknown(reason: stopReason(error), permit: currentPermit) }
                    catch { state.failEvidence() }
                } else { state.failEvidence() }
                state.terminal = true
                do {
                    let failedDigest = try state.writeNamed("failed-report.json", bytes: json(report(window: window, context: state, failure: guardedCode(error))))
                    if let id = state.lastOperationID, let permit = state.lastOperationPermit {
                        try ledger.recordObservation(operationID: id, event: .reportPublished, summarySHA256: failedDigest, permit: permit)
                    }
                } catch { state.failEvidence() }
                accountProvider.requestCancellation(); state.transport?.value.requestCancellation()
            } else {
                // Caller already consumed this qualification. No existing output is
                // touched and no failed setup silently restores that permission.
                try? ledger.terminateUnknown(reason: .validationFailed, permit: currentPermit)
                accountProvider.requestCancellation()
            }
            throw error
        }
    }
    private func match(_ b: ExecutionBinding, window: ValidatedOwnerWindow) throws {
        let w = window.approval
        guard w.purpose == "FIXED_SYNTHETIC_DEVELOPMENT_BATCH", b.accountSHA256 == nil,
              b.ownerWindow == w.window, b.approvalInputSHA256 == window.inputSHA256, b.ownerDecisionSHA256 == w.ownerDecisionSHA256,
              b.ownerConfirmedAccountSessionSHA256 == w.ownerSessionSHA256, b.osUserID == w.osUserID,
              b.windowStartMS == w.startsAt * 1_000, b.windowEndMS == w.expiresAt * 1_000,
              b.run == w.run, b.dataset == w.dataset, b.planSHA256 == w.planSHA256, b.schemaSHA256 == w.schemaSHA256,
              b.binarySHA256 == w.runtime.signedBinarySHA256, b.codeDirectoryHash == w.runtime.codeDirectoryHash,
              b.profileSHA256 == w.runtime.profileSHA256, b.packagingReceiptSHA256 == w.runtime.packagingReceiptSHA256,
              b.sourcePinsSHA256 == w.runtime.sourcePinsSHA256 else { throw GuardedBatchFailure.binding }
    }
    private func bound(_ b: ExecutionBinding, account: String) -> ExecutionBinding {
        ExecutionBinding(ownerWindow: b.ownerWindow, approvalInputSHA256: b.approvalInputSHA256, ownerDecisionSHA256: b.ownerDecisionSHA256,
            windowStartMS: b.windowStartMS, windowEndMS: b.windowEndMS, planSHA256: b.planSHA256, run: b.run, dataset: b.dataset,
            schemaSHA256: b.schemaSHA256, binarySHA256: b.binarySHA256, codeDirectoryHash: b.codeDirectoryHash,
            profileSHA256: b.profileSHA256, packagingReceiptSHA256: b.packagingReceiptSHA256, sourcePinsSHA256: b.sourcePinsSHA256,
            osUserID: b.osUserID, osSessionSHA256: b.osSessionSHA256, ownerConfirmedAccountSessionSHA256: b.ownerConfirmedAccountSessionSHA256,
            accountSHA256: account)
    }
    private func encode(_ fixture: ProbeFixture, directory: ProbeDirectory) throws -> [CKRecord] {
        try fixture.plan.records.map { item in
            let bytes = fixture.files[item.file]!, url = try directory.assetURL("lease-" + item.file)
            if item.recordType == CloudRecordCodec.originalType { return try CloudRecordCodec.encodeOriginal(AssetDescriptor(bytes: bytes), dataset: fixture.plan.dataset, url: url) }
            if item.recordType == CloudRecordCodec.chunkType { return try CloudRecordCodec.encodeChunk(AssetDescriptor(bytes: bytes), dataset: fixture.plan.dataset, url: url) }
            return try CloudRecordCodec.encode(MutationManifest.decode(bytes))
        }
    }
    private func validate(_ results: [CKRecord.ID: Result<CKRecord, Error>], expected: [CKRecord], fixture: ProbeFixture) throws {
        guard Set(results.keys) == Set(expected.map(\.recordID)) else { throw GuardedBatchFailure.invalidResults }
        for request in expected {
            guard case .success(let record) = results[request.recordID]!, record.recordID == request.recordID,
                  record.recordType == request.recordType,
                  let item = fixture.plan.records.first(where: { $0.recordName == record.recordID.recordName }) else { throw GuardedBatchFailure.invalidResults }
            let bytes: Data
            if record.recordType == CloudRecordCodec.originalType { bytes = try CloudRecordCodec.decodeOriginal(record, dataset: fixture.plan.dataset).1 }
            else if record.recordType == CloudRecordCodec.chunkType { bytes = try CloudRecordCodec.decodeChunk(record, dataset: fixture.plan.dataset).1 }
            else { bytes = try CloudRecordCodec.decode(record, dataset: fixture.plan.dataset).encoded() }
            guard bytes == fixture.files[item.file] else { throw GuardedBatchFailure.bytesChanged }
        }
    }
    private func report(window: ValidatedOwnerWindow, context: GuardedRunEvidence, failure: String?) -> GuardedBatchReport {
        // Gate/admission fields describe local events only. They cannot guarantee
        // global remote effects or evidence integrity, including after late callbacks.
        return GuardedBatchReport(status: failure == nil ? "GUARDED_STEPS_VERIFIED" : "REMOTE_OUTCOME_UNKNOWN", planSHA256: window.approval.planSHA256,
            run: window.approval.run, dataset: window.approval.dataset, ownerWindow: window.approval.window,
            providerMethodInvocations: context.accountCalls, transportMethodInvocations: context.transportCalls,
            completedStages: context.completed, failure: failure, remoteOutcomeUnknown: failure != nil,
            failureStage: context.failureStage, operationEnqueuePrevented: context.operationEnqueuePrevented,
            sdkEnqueuesAdmitted: context.sdkEnqueuesAdmitted)
    }
    private func stopReason(_ error: Error) -> LedgerStopReason {
        if error is CancellationError { return .cancelled }
        if error is OwnerWindowError { return .expired }
        if error is GuardedAccountError { return .accountChanged }
        if let failure = error as? GuardedBatchFailure {
            if failure == .accountChanged { return .accountChanged }
            if failure == .evidence { return .evidenceFailed }
        }
        if case LedgerFailure.expired = error { return .expired }
        return .validationFailed
    }
}
