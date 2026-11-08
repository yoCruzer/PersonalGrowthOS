import XCTest
import Foundation
import CloudKit
import FormalProbeCore
import SyncFoundation
@testable import FormalDevelopmentSDK

@MainActor private final class GuardedFakeAccount: BatchAccountProvider {
    typealias Bridge = OperationCallbackBridge<String, String, String>
    let ledger: ExecutionLedger
    private var pending: (LedgerOperation, UUID, ExecutionPermit)?
    private var evidence: (TransportEvidenceSink, TransportEvidenceFailure)?
    private var cancel: (() -> Void)?
    var calls = 0
    var epochValid = true
    var identity = "SYNTHETIC_OPAQUE_ACCOUNT_DO_NOT_LOG"
    var hook: ((Int) -> Void)?
    var holdAt: Int?
    var retained: [Bridge] = []
    var cancellations = 0
    init(_ ledger: ExecutionLedger) { self.ledger = ledger }
    func authorizeRead(_ operation: LedgerOperation, operationID: UUID, permit: ExecutionPermit) throws {
        guard pending == nil else { throw GuardedAccountError.busy }
        _ = try ledger.requirePendingIntent(operation, operationID: operationID, permit: permit)
        pending = (operation, operationID, permit)
    }
    func bindOperationEvidence(_ sink: @escaping TransportEvidenceSink, onFailure: @escaping TransportEvidenceFailure) throws { evidence = (sink, onFailure) }
    func checkEpoch() throws { guard epochValid else { throw GuardedAccountError.changed } }
    func requestCancellation() { cancellations += 1; cancel?() }
    func available() async throws { _ = try await read(status: true) }
    func userRecordName() async throws -> String { try await read(status: false) }
    private func read(status: Bool) async throws -> String {
        guard let pending, let evidence else { throw GuardedAccountError.wrongPermission }
        guard (pending.0 == .accountStatus) == status else { throw GuardedAccountError.wrongPermission }
        self.pending = nil; defer { cancel = nil }
        let stage = status ? "account-status" : "account-record-id"
        let bridge = Bridge(stage: stage, expected: [stage], label: { $0 }, validValue: { _, _ in true },
            sink: evidence.0, onFailure: evidence.1, cancellationScope: .localWaitOnly) { result, aggregate in
                try aggregate.get(); return try result[stage]!.get()
            }
        retained.append(bridge); cancel = { bridge.requestCancellation() }
        return try await bridge.execute(operation: Operation()) {
            do { _ = try ledger.requirePendingIntent(pending.0, operationID: pending.1, permit: pending.2) }
            catch { bridge.complete(.failure(error)); return }
            calls += 1; hook?(calls)
            if calls != holdAt {
                bridge.receive(stage, .success(status ? "available" : identity)); bridge.complete(.success(()))
            }
        }
    }
}
@MainActor private final class GuardedFakeCloud {
    var records: [CKRecord.ID: CKRecord] = [:]
    var calls: [String] = []
    var fault: String?
    var hook: ((String) -> Void)?
    var heldFetch: CKFetchRecordsOperation?
    var heldZone: CKFetchRecordZonesOperation?
    var holdStage: String?
    lazy var adapter = CloudKitDevelopmentAdapter(enqueueForTesting: { [unowned self] in enqueue($0) })
    func enqueue(_ operation: CKDatabaseOperation) {
        if let op = operation as? CKFetchRecordZonesOperation {
            calls.append("zoneProbe"); hook?("zoneProbe"); heldZone = op
            if holdStage == "zoneProbe" { return }
            let id = op.recordZoneIDs![0]
            if fault == "existingZone" { op.perRecordZoneResultBlock?(id, .success(CKRecordZone(zoneID: id))); op.fetchRecordZonesResultBlock?(.success(())) }
            else { op.perRecordZoneResultBlock?(id, .failure(CKError(.zoneNotFound))); op.fetchRecordZonesResultBlock?(.failure(CKError(.zoneNotFound))) }
        } else if let op = operation as? CKModifyRecordZonesOperation {
            calls.append("zoneSave"); hook?("zoneSave")
            let zone = op.recordZonesToSave![0]
            op.perRecordZoneSaveBlock?(zone.zoneID, .success(zone)); op.modifyRecordZonesResultBlock?(.success(()))
        } else if let op = operation as? CKModifyRecordsOperation {
            let mutation = op.recordsToSave![0].recordType == CloudRecordCodec.mutationType
            let label = mutation ? "mutationsSave" : "assetsSave"; calls.append(label); hook?(label)
            XCTAssertEqual(op.savePolicy, .ifServerRecordUnchanged); XCTAssertTrue(op.isAtomic); XCTAssertTrue(op.recordIDsToDelete?.isEmpty ?? true)
            for (index, record) in op.recordsToSave!.enumerated() {
                records[record.recordID] = record
                if fault == "partial" && !mutation && index == 0 { op.perRecordSaveBlock?(record.recordID, .failure(CKError(.quotaExceeded))) }
                else { op.perRecordSaveBlock?(record.recordID, .success(record)) }
            }
            if fault == "partial" && !mutation { op.modifyRecordsResultBlock?(.failure(CKError(.partialFailure))) }
            else { op.modifyRecordsResultBlock?(.success(())) }
        } else if let op = operation as? CKFetchRecordsOperation {
            calls.append("exactFetch"); hook?("exactFetch"); heldFetch = op
            for (index, id) in op.recordIDs!.enumerated() {
                if fault == "missingFetch" && index == 0 { continue }
                let record = records[id]!
                if fault == "badBytes" && record.recordType == CloudRecordCodec.originalType { record["sha256"] = String(repeating: "0", count: 64) as CKRecordValue }
                op.perRecordResultBlock?(id, .success(record))
            }
            op.fetchRecordsResultBlock?(.success(()))
        } else { XCTFail("unexpected operation") }
    }
}
@MainActor final class GuardedBatchRunnerTests: XCTestCase {
    private let digest = String(repeating: "a", count: 64)
    @MainActor private struct Context {
        let root: URL, output: URL
        let window: ValidatedOwnerWindow
        let ledger: ExecutionLedger
        let permit: ExecutionPermit
        let binding: ExecutionBinding
        let account: GuardedFakeAccount
        let cloud: GuardedFakeCloud
        let runner = GuardedBatchRunner()
    }
    private func context(windowSeconds: Int64 = 300, existingLedger: ExecutionLedger? = nil) throws -> Context {
        let root = URL(fileURLWithPath: "/private/tmp/pgos-guarded-runner-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let fixture = try ProbeFixture.make(run: UUID(), dataset: UUID()), now = Int64(Date().timeIntervalSince1970)
        let receipt = Data("SYNTHETIC NOT A QUALIFIED RECEIPT".utf8), pins = Data("SYNTHETIC NOT RUNTIME PINS".utf8)
        let approval = OwnerExecutionApproval(version: 1, disposition: "OWNER_APPROVED_DEVELOPMENT_WINDOW", purpose: "FIXED_SYNTHETIC_DEVELOPMENT_BATCH",
            ownerDecisionSHA256: digest, ownerSessionSHA256: digest, window: UUID(), startsAt: now - 1, expiresAt: now + windowSeconds,
            osUserID: getuid(), run: fixture.plan.run, dataset: fixture.plan.dataset, planSHA256: try fixture.plan.digest,
            schemaSHA256: FormalProbeIdentity.schemaSHA256, runtime: ApprovedRuntimeBinding(signedBinarySHA256: digest,
                codeDirectoryHash: String(repeating: "b", count: 40), profileSHA256: digest,
                packagingReceiptSHA256: syncDigest(receipt), sourcePinsSHA256: syncDigest(pins)), packagingReceipt: receipt, sourcePins: pins)
        let bytes = try approval.encoded(), window = try OwnerExecutionApproval.validate(bytes, expectedSHA256: syncDigest(bytes))
        let binding = ExecutionBinding(ownerWindow: approval.window, approvalInputSHA256: window.inputSHA256, ownerDecisionSHA256: digest,
            windowStartMS: approval.startsAt * 1_000, windowEndMS: approval.expiresAt * 1_000, planSHA256: approval.planSHA256,
            run: approval.run, dataset: approval.dataset, schemaSHA256: approval.schemaSHA256, binarySHA256: digest,
            codeDirectoryHash: approval.runtime.codeDirectoryHash, profileSHA256: digest,
            packagingReceiptSHA256: approval.runtime.packagingReceiptSHA256, sourcePinsSHA256: approval.runtime.sourcePinsSHA256,
            osUserID: getuid(), osSessionSHA256: digest, ownerConfirmedAccountSessionSHA256: digest, accountSHA256: nil)
        let ledger = try existingLedger ?? ExecutionLedger.enrollForTesting(root: root.appendingPathComponent("ledger"), anchorStore: FakeExecutionAnchor(),
            clock: SystemLedgerClock(), ownerDecisionSHA256: digest)
        let permit = try ledger.consume(.qualificationRead, binding: binding)
        return Context(root: root, output: root.appendingPathComponent("output"), window: window, ledger: ledger, permit: permit,
            binding: binding, account: GuardedFakeAccount(ledger), cloud: GuardedFakeCloud())
    }
    @discardableResult private func run(_ c: Context, runner: GuardedBatchRunner? = nil, runtime: @escaping () throws -> Void = {}, fatal: @escaping () -> Void = {}) async throws -> GuardedBatchReport {
        try await (runner ?? c.runner).run(window: c.window, ledger: c.ledger, qualificationPermit: c.permit, binding: c.binding,
            output: c.output, accountProvider: c.account, transportFactory: { permit, binding in
                XCTAssertEqual(try c.ledger.binding(for: permit, requiring: .developmentBatch), binding)
                return c.cloud.adapter
            }, runtimeRecheck: runtime, onEvidenceFatal: fatal)
    }
    private func failure(_ c: Context, runtime: @escaping () throws -> Void = {}) async {
        do { _ = try await run(c, runtime: runtime); XCTFail("unexpected success") } catch {}
    }
    private func drain() async { await withCheckedContinuation { pending in DispatchQueue.main.async { pending.resume() } } }
    private func outputText(_ c: Context) throws -> String {
        try FileManager.default.contentsOfDirectory(at: c.output, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.map { try String(contentsOf: $0) }.joined(separator: "\n")
    }
    func testTwelveAccountReadsFiveTransportStagesAndNoRealAuthorityClaim() async throws {
        let c = try context(); var runtimeChecks = 0
        let result = try await run(c, runtime: { runtimeChecks += 1 })
        XCTAssertEqual(result.status, "GUARDED_STEPS_VERIFIED"); XCTAssertEqual(result.mode, "INJECTED_OR_EXTERNAL_FACTORY")
        XCTAssertEqual(result.providerMethodInvocations, 12); XCTAssertEqual(c.account.calls, 12)
        XCTAssertEqual(result.transportMethodInvocations, 5); XCTAssertEqual(c.cloud.records.count, 6)
        XCTAssertEqual(result.completedStages, LedgerStage.allCases.map(\.rawValue)); XCTAssertGreaterThan(runtimeChecks, 50)
        XCTAssertFalse(result.realNetworkQualificationClaimed); XCTAssertFalse(result.p0Passed); XCTAssertFalse(c.ledger.hasUnresolvedExecutions)
        let text = try outputText(c); XCTAssertFalse(text.contains(c.account.identity))
        XCTAssertFalse(text.contains(try c.ledger.accountDigest(c.account.identity)))
        XCTAssertTrue(text.contains("ledgerOperationID")); XCTAssertTrue(text.contains("localWaitOnly"))
    }
    func testIdentitySwitchAfterProbeStopsBeforeZoneWrite() async throws {
        let c = try context(); c.account.hook = { count in if count == 4 { c.account.identity = "OTHER_SYNTHETIC_ACCOUNT" } }
        await failure(c)
        XCTAssertEqual(c.cloud.calls, ["zoneProbe"]); XCTAssertEqual(c.account.calls, 4)
        XCTAssertFalse(FileManager.default.fileExists(atPath: c.output.appendingPathComponent("verified-report.json").path))
    }
    func testEpochInvalidationAtEachTransportSuspensionStopsNextStage() async throws {
        for stage in LedgerStage.allCases {
            let c = try context(); c.cloud.hook = { if $0 == stage.rawValue { c.account.epochValid = false } }
            await failure(c); XCTAssertEqual(c.cloud.calls.last, stage.rawValue)
            XCTAssertFalse(FileManager.default.fileExists(atPath: c.output.appendingPathComponent("verified-report.json").path))
        }
    }
    func testLeaseAndPlanMutationDuringLookupStopsBeforeWrites() async throws {
        for name in ["plan.json", "lease-original.png"] {
            let c = try context(); c.account.hook = { count in
                if count == 3 { try! Data("mutated synthetic fixture".utf8).write(to: c.output.appendingPathComponent(name)) }
            }
            await failure(c); XCTAssertEqual(c.cloud.calls.count, 0)
        }
    }
    func testRuntimeRecheckAtEnqueueCanPreventFirstProviderInvocation() async throws {
        let c = try context(); var checks = 0
        await failure(c, runtime: {
            checks += 1
            if checks == 4 { throw GuardedBatchFailure.binding }
        })
        XCTAssertEqual(c.account.calls, 0); XCTAssertEqual(c.cloud.calls.count, 0)
    }
    func testPartialAndMissingOrCorruptFetchNeverFinishBatch() async throws {
        for fault in ["partial", "missingFetch", "badBytes", "existingZone"] {
            let c = try context(); c.cloud.fault = fault
            await failure(c)
            XCTAssertFalse(FileManager.default.fileExists(atPath: c.output.appendingPathComponent("verified-report.json").path))
            let text = try outputText(c); XCTAssertTrue(text.contains("REMOTE_OUTCOME_UNKNOWN"))
            if fault == "partial" { XCTAssertEqual(c.cloud.calls.last, "assetsSave"); XCTAssertTrue(text.contains("RETURNED_FAILURE")) }
        }
    }
    func testSingleFlightCancellationAndLateACKRemainOriginalPermit() async throws {
        let c = try context(), entered = expectation(description: "lookup enqueued")
        c.account.holdAt = 1; c.account.hook = { if $0 == 1 { entered.fulfill() } }
        let task = Task { try await run(c) }
        await fulfillment(of: [entered], timeout: 3)
        do { _ = try await run(c); XCTFail() } catch GuardedBatchFailure.busy {}
        task.cancel(); do { _ = try await task.value; XCTFail() } catch {}
        let bridge = try XCTUnwrap(c.account.retained.first)
        bridge.receive("account-status", .success("available")); bridge.complete(.success(())); await drain()
        XCTAssertEqual(c.cloud.calls.count, 0)
        let text = try outputText(c); XCTAssertTrue(text.contains("LATE_ITEM_RETURNED")); XCTAssertTrue(text.contains("REMOTE_OUTCOME_UNKNOWN"))
        XCTAssertFalse(text.contains("GUARDED_STEPS_VERIFIED"))
    }
    func testExpiredWindowDuringLookupStopsAndKeepsRawResponse() async throws {
        let c = try context(); c.account.hook = { count in
            if count == 3 { try? c.window.check(now: Date(timeIntervalSince1970: Double(c.window.approval.expiresAt + 1))) }
        }
        await failure(c); XCTAssertEqual(c.cloud.calls.count, 0)
        XCTAssertTrue(try outputText(c).contains("OPERATION_RETURNED"))
    }
    func testOutputCollisionPreservesOriginalAndConsumesNoLookup() async throws {
        let c = try context(); try FileManager.default.createDirectory(at: c.output, withIntermediateDirectories: false)
        try Data("preserve".utf8).write(to: c.output.appendingPathComponent("sentinel"))
        await failure(c); XCTAssertEqual(c.account.calls, 0)
        XCTAssertEqual(try String(contentsOf: c.output.appendingPathComponent("sentinel")), "preserve")
        XCTAssertThrowsError(try c.ledger.binding(for: c.permit, requiring: .qualificationRead))
    }
    func testEvidenceFailurePoisonsRunnerAndCannotReturnSuccess() async throws {
        let c = try context(); c.account.hook = { count in
            if count == 1 {
                // Enqueue callback is 000000. Refuse the next raw callback's exclusive write.
                try! Data("preserve-existing".utf8).write(to: c.output.appendingPathComponent("000001-callback.json"))
            }
        }
        await failure(c); XCTAssertTrue(c.runner.evidenceFatal); XCTAssertEqual(c.cloud.calls.count, 0)
        XCTAssertEqual(try String(contentsOf: c.output.appendingPathComponent("000001-callback.json")), "preserve-existing")
        XCTAssertFalse(FileManager.default.fileExists(atPath: c.output.appendingPathComponent("verified-report.json").path))
        do { _ = try await run(c); XCTFail() } catch GuardedBatchFailure.poisoned {}
    }
    func testLateEvidenceWriteFailureAddsMarkerAndNotifiesAfterTerminal() async throws {
        let c = try context(); var fatalCalls = 0
        _ = try await run(c, fatal: { fatalCalls += 1 })
        let before = try Data(contentsOf: c.output.appendingPathComponent("verified-report.json"))
        let callbackFiles = try FileManager.default.contentsOfDirectory(atPath: c.output.path).filter { $0.first?.isNumber == true }
        let next = callbackFiles.compactMap { Int($0.prefix(6)) }.max()! + 1
        try Data("collision".utf8).write(to: c.output.appendingPathComponent(String(format: "%06d-callback.json", next)))
        c.cloud.heldFetch?.fetchRecordsResultBlock?(.success(())); await drain()
        XCTAssertTrue(c.runner.evidenceFatal); XCTAssertEqual(fatalCalls, 1)
        XCTAssertEqual(try Data(contentsOf: c.output.appendingPathComponent("verified-report.json")), before)
        XCTAssertTrue(try String(contentsOf: c.output.appendingPathComponent("fatal-unknown.json")).contains("postTerminal"))
    }
    func testFinalReportCollisionNeverReturnsSuccessOrOverwrites() async throws {
        let c = try context(); c.cloud.hook = { stage in
            if stage == "exactFetch" { try! Data("sentinel".utf8).write(to: c.output.appendingPathComponent("verified-report.json")) }
        }
        await failure(c); XCTAssertTrue(c.runner.evidenceFatal)
        XCTAssertEqual(try String(contentsOf: c.output.appendingPathComponent("verified-report.json")), "sentinel")
        XCTAssertTrue(FileManager.default.fileExists(atPath: c.output.appendingPathComponent("fatal-unknown.json").path))
    }
    func testOutputDirectoryReplacementStopsAndWritesOnlyHeldOriginal() async throws {
        let c = try context(), original = c.root.appendingPathComponent("original-output")
        c.account.hook = { count in
            if count == 3 {
                try! FileManager.default.moveItem(at: c.output, to: original)
                try! FileManager.default.createDirectory(at: c.output, withIntermediateDirectories: false)
                try! Data("preserve".utf8).write(to: c.output.appendingPathComponent("sentinel"))
            }
        }
        await failure(c); XCTAssertEqual(c.cloud.calls.count, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: c.output.path), ["sentinel"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.appendingPathComponent("failed-report.json").path))
    }
    func testLateQualificationFatalMarkerAnchorsOriginalQualificationOperation() async throws {
        let c = try context(); _ = try await run(c)
        let files = try FileManager.default.contentsOfDirectory(atPath: c.output.path)
        let next = files.compactMap { Int($0.prefix(6)) }.max()! + 1
        try Data("collision".utf8).write(to: c.output.appendingPathComponent(String(format: "%06d-callback.json", next)))
        c.account.retained.first?.complete(.success(())); await drain()
        let marker = try Data(contentsOf: c.output.appendingPathComponent("fatal-unknown.json"))
        XCTAssertTrue(String(decoding: marker, as: UTF8.self).contains("accountStatus"))
        let journal = try FileManager.default.contentsOfDirectory(at: c.root.appendingPathComponent("ledger"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.map { try String(contentsOf: $0) }.joined()
        XCTAssertTrue(journal.contains(syncDigest(marker)), "Fatal marker must be HMAC-journal linked under the original qualification permit")
    }

    func testPreviouslyWrittenCallbackReturnedAndValidatedEvidenceCannotBeChanged() async throws {
        for suffix in ["-callback.json", "-returned.json", "-validated.json"] {
            let c = try context()
            c.account.hook = { count in
                if count == (suffix == "-validated.json" ? 5 : 3) {
                    let file = try! FileManager.default.contentsOfDirectory(atPath: c.output.path).sorted().first { $0.hasSuffix(suffix) }!
                    try! Data("tampered prior evidence".utf8).write(to: c.output.appendingPathComponent(file))
                }
            }
            await failure(c); XCTAssertTrue(c.runner.evidenceFatal)
            XCTAssertFalse(FileManager.default.fileExists(atPath: c.output.appendingPathComponent("verified-report.json").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: c.output.appendingPathComponent("fatal-unknown.json").path))
        }
    }
    func testPostTerminalReportTamperDetectedByLateCallbackAndRawEventPreserved() async throws {
        let c = try context(); _ = try await run(c)
        try Data("tampered success report".utf8).write(to: c.output.appendingPathComponent("verified-report.json"))
        c.cloud.heldFetch?.fetchRecordsResultBlock?(.success(())); await drain()
        XCTAssertTrue(c.runner.evidenceFatal)
        XCTAssertEqual(try String(contentsOf: c.output.appendingPathComponent("verified-report.json")), "tampered success report")
        let raw = try outputText(c); XCTAssertTrue(raw.contains("LATE_OPERATION_RETURNED")); XCTAssertTrue(raw.contains("FATAL_EXECUTION_OR_EVIDENCE_UNKNOWN"))
    }

    func testEveryPublishedSuccessEvidenceFileIsLinkedByLedgerDigest() async throws {
        let c = try context(); _ = try await run(c)
        var linked = Set<String>()
        func visit(_ value: Any) {
            if let dict = value as? [String: Any] {
                for (key, item) in dict {
                    if key == "summarySHA256", let text = item as? String { linked.insert(text) }
                    visit(item)
                }
            } else if let array = value as? [Any] { array.forEach(visit) }
        }
        for file in try FileManager.default.contentsOfDirectory(at: c.root.appendingPathComponent("ledger"), includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            visit(try JSONSerialization.jsonObject(with: Data(contentsOf: file)))
        }
        let output = try FileManager.default.contentsOfDirectory(at: c.output, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "plan.json" }
        let digests = try Set(output.map { syncDigest(try Data(contentsOf: $0)) })
        XCTAssertEqual(digests, linked, "Every callback, return, validation and prepared/final report must be durably linked")
    }

    func testHangingAccountReadIsCancelledAtOwnerDeadlineWithoutRetry() async throws {
        let c = try context(windowSeconds: 2)
        c.account.holdAt = 1
        let start = Date()
        await failure(c)
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
        XCTAssertEqual(c.account.calls, 1); XCTAssertEqual(c.cloud.calls.count, 0)
        XCTAssertThrowsError(try c.ledger.binding(for: c.permit, requiring: .qualificationRead))
        let raw = try outputText(c); XCTAssertTrue(raw.contains("OWNER_WINDOW_EXPIRED")); XCTAssertTrue(raw.contains("CANCEL_REQUESTED"))
        XCTAssertFalse(raw.contains("GUARDED_STEPS_VERIFIED"))
        c.account.retained.first?.receive("account-status", .success("available"))
        c.account.retained.first?.complete(.success(())); await drain()
        XCTAssertTrue(try outputText(c).contains("LATE_OPERATION_RETURNED"))
    }
    func testHangingTransportIsCancelledAtOwnerDeadlineAndLateACKRetained() async throws {
        let c = try context(windowSeconds: 2); c.cloud.holdStage = "zoneProbe"
        let start = Date(); await failure(c)
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
        XCTAssertEqual(c.account.calls, 3); XCTAssertEqual(c.cloud.calls, ["zoneProbe"])
        let op = try XCTUnwrap(c.cloud.heldZone), id = op.recordZoneIDs![0]
        XCTAssertTrue(op.isCancelled)
        op.perRecordZoneResultBlock?(id, .failure(CKError(.zoneNotFound)))
        op.fetchRecordZonesResultBlock?(.failure(CKError(.zoneNotFound))); await drain()
        let raw = try outputText(c); XCTAssertTrue(raw.contains("OWNER_WINDOW_EXPIRED")); XCTAssertTrue(raw.contains("LATE_OPERATION_RETURNED"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: c.output.appendingPathComponent("verified-report.json").path))
    }

    func testOldScopeFatalStopsNewActiveRunOnSameRunnerAndLedger() async throws {
        let first = try context(); _ = try await run(first)
        let second = try context(existingLedger: first.ledger)
        let entered = expectation(description: "second window lookup pending")
        second.account.holdAt = 1; second.account.hook = { if $0 == 1 { entered.fulfill() } }
        let active = Task { try await run(second, runner: first.runner) }
        await fulfillment(of: [entered], timeout: 3)
        let names = try FileManager.default.contentsOfDirectory(atPath: first.output.path)
        let next = names.compactMap { Int($0.prefix(6)) }.max()! + 1
        try Data("collision on old callback".utf8).write(to: first.output.appendingPathComponent(String(format: "%06d-callback.json", next)))
        first.account.retained.first?.complete(.success(())); await drain()
        XCTAssertTrue(first.runner.evidenceFatal)
        XCTAssertGreaterThan(second.account.cancellations, 0, "An old-scope fatal must actively cancel the current run")
        // Bounded cleanup of the historical red version; this is not counted as
        // the runner's cancellation and occurs after the assertion above.
        if second.account.cancellations == 0 { second.account.requestCancellation() }
        do { _ = try await active.value; XCTFail("new window resumed after global fatal") } catch {}
        XCTAssertEqual(second.cloud.calls.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.output.appendingPathComponent("verified-report.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.output.appendingPathComponent("fatal-unknown.json").path))
    }

    func testValidOldLateCallbackKeepsNewWindowAndItsEvidenceIsolated() async throws {
        let first = try context(); _ = try await run(first)
        let second = try context(existingLedger: first.ledger)
        let entered = expectation(description: "second window pending")
        second.account.holdAt = 1; second.account.hook = { if $0 == 1 { entered.fulfill() } }
        let active = Task { try await run(second, runner: first.runner) }
        await fulfillment(of: [entered], timeout: 3)
        first.account.retained.first?.complete(.success(())); await drain()
        XCTAssertFalse(first.runner.evidenceFatal); XCTAssertEqual(second.account.cancellations, 0)
        let oldFiles = try FileManager.default.contentsOfDirectory(at: first.output, includingPropertiesForKeys: nil)
        let oldLate = try oldFiles.filter { $0.lastPathComponent.hasSuffix("-callback.json") }.compactMap { url -> [String: Any]? in
            let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            return (value["callback"] as? [String: Any])?["event"] as? String == "LATE_OPERATION_RETURNED" ? value : nil
        }
        XCTAssertEqual(oldLate.count, 1)
        XCTAssertEqual(oldLate.first?["run"] as? String, first.window.approval.run.uuidString)
        second.account.retained.first?.receive("account-status", .success("available"))
        second.account.retained.first?.complete(.success(()))
        let result = try await active.value
        XCTAssertEqual(result.run, second.window.approval.run); XCTAssertEqual(result.status, "GUARDED_STEPS_VERIFIED")
        XCTAssertEqual(second.account.calls, 12); XCTAssertEqual(second.cloud.calls.count, 5)
        XCTAssertFalse(try outputText(second).contains("LATE_OPERATION_RETURNED"))
    }

}
