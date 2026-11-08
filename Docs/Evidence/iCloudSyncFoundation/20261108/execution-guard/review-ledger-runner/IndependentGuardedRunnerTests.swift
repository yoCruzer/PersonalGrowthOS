import XCTest
import Foundation
import CloudKit
import FormalProbeCore
import SyncFoundation
@testable import FormalDevelopmentSDK

@MainActor private final class IndependentGuardedAnchor: ExecutionAnchorStore {
    private var bytes: Data?
    func load() throws -> Data? { bytes }
    func create(_ value: Data) throws { guard bytes == nil else { throw LedgerFailure.anchorFailure }; bytes = value }
    func replace(expected: Data, with value: Data) throws { guard bytes == expected else { throw LedgerFailure.anchorFailure }; bytes = value }
}

@MainActor private final class IndependentGuardedFakeAccount: BatchAccountProvider {
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
@MainActor private final class IndependentGuardedFakeCloud {
    var records: [CKRecord.ID: CKRecord] = [:]
    var calls: [String] = []
    var fault: String?
    var hook: ((String) -> Void)?
    var heldFetch: CKFetchRecordsOperation?
    var holdZoneProbe = false
    lazy var adapter = CloudKitDevelopmentAdapter(enqueueForTesting: { [unowned self] in enqueue($0) })
    func enqueue(_ operation: CKDatabaseOperation) {
        if let op = operation as? CKFetchRecordZonesOperation {
            calls.append("zoneProbe"); hook?("zoneProbe")
            if holdZoneProbe { return }
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
@MainActor final class IndependentGuardedRunnerTests: XCTestCase {
    private let digest = String(repeating: "a", count: 64)
    @MainActor private struct Context {
        let root: URL, output: URL
        let window: ValidatedOwnerWindow
        let ledger: ExecutionLedger
        let permit: ExecutionPermit
        let binding: ExecutionBinding
        let account: IndependentGuardedFakeAccount
        let cloud: IndependentGuardedFakeCloud
        let runner = GuardedBatchRunner()
    }
    private func context(expiresAfter: Int64 = 300, reusing existingLedger: ExecutionLedger? = nil) throws -> Context {
        let root = URL(fileURLWithPath: "/private/tmp/pgos-guarded-runner-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let fixture = try ProbeFixture.make(run: UUID(), dataset: UUID()), now = Int64(Date().timeIntervalSince1970)
        let receipt = Data("SYNTHETIC NOT A QUALIFIED RECEIPT".utf8), pins = Data("SYNTHETIC NOT RUNTIME PINS".utf8)
        let approval = OwnerExecutionApproval(version: 1, disposition: "OWNER_APPROVED_DEVELOPMENT_WINDOW", purpose: "FIXED_SYNTHETIC_DEVELOPMENT_BATCH",
            ownerDecisionSHA256: digest, ownerSessionSHA256: digest, window: UUID(), startsAt: now - 1, expiresAt: now + expiresAfter,
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
        let ledger = try existingLedger ?? ExecutionLedger.enrollForTesting(root: root.appendingPathComponent("ledger"), anchorStore: IndependentGuardedAnchor(),
            clock: SystemLedgerClock(), ownerDecisionSHA256: digest)
        let permit = try ledger.consume(.qualificationRead, binding: binding)
        return Context(root: root, output: root.appendingPathComponent("output"), window: window, ledger: ledger, permit: permit,
            binding: binding, account: IndependentGuardedFakeAccount(ledger), cloud: IndependentGuardedFakeCloud())
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

    func testIndependentPriorEvidenceTamperMustNotCommitSuccess() async throws {
        let c = try context()
        c.account.hook = { count in if count == 3 {
            try! Data("SYNTHETIC_MUTATED_EVIDENCE".utf8).write(to: c.output.appendingPathComponent("000000-callback.json"))
        }}
        do { _ = try await run(c); XCTFail("Changed raw evidence must prevent successful commit") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: c.output.appendingPathComponent("verified-report.json").path))
        XCTAssertTrue(c.cloud.calls.isEmpty)
    }
    func testIndependentPriorReturnTamperPreventsNextWriteStage() async throws {
        let c = try context()
        c.account.hook = { count in if count == 5 {
            let names = try! FileManager.default.contentsOfDirectory(atPath: c.output.path)
            let name = names.filter { $0.hasSuffix("-returned.json") }.sorted().first!
            try! Data("SYNTHETIC_CHANGED_RETURN".utf8).write(to: c.output.appendingPathComponent(name))
        }}
        do { _ = try await run(c); XCTFail("Changed return evidence must prevent next write") } catch {}
        XCTAssertEqual(c.cloud.calls, ["zoneProbe"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: c.output.appendingPathComponent("verified-report.json").path))
    }
    func testIndependentMissingEvidenceFailsClosed() async throws {
        let c = try context()
        c.account.hook = { count in if count == 3 {
            try! FileManager.default.removeItem(at: c.output.appendingPathComponent("000000-callback.json"))
        }}
        do { _ = try await run(c); XCTFail("Removed evidence must prevent commit") } catch {}
        XCTAssertTrue(c.cloud.calls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: c.output.appendingPathComponent("verified-report.json").path))
    }
    func testIndependentEvidenceSymlinkIsNotReadOrOverwritten() async throws {
        let c = try context(), target = c.root.appendingPathComponent("synthetic-sentinel")
        let sentinel = Data("SYNTHETIC_SENTINEL_DO_NOT_REPORT".utf8); try sentinel.write(to: target)
        c.account.hook = { count in if count == 3 {
            let file = c.output.appendingPathComponent("000000-callback.json")
            try! FileManager.default.removeItem(at: file)
            try! FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        }}
        do { _ = try await run(c); XCTFail("Symlinked prior evidence must not pass") } catch {}
        XCTAssertEqual(try Data(contentsOf: target), sentinel)
        XCTAssertTrue(c.cloud.calls.isEmpty)
        for name in ["failed-report.json", "fatal-unknown.json"] {
            let file = c.output.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: file.path) {
                XCTAssertFalse(String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("SYNTHETIC_SENTINEL_DO_NOT_REPORT"))
            }
        }
    }
    func testIndependentLateCallbackDiscoversTamperWithoutRewritingSuccess() async throws {
        let c = try context(); var fatalCount = 0
        _ = try await run(c, fatal: { fatalCount += 1 })
        let success = try Data(contentsOf: c.output.appendingPathComponent("verified-report.json"))
        try Data("SYNTHETIC_POST_TERMINAL_TAMPER".utf8).write(to: c.output.appendingPathComponent("000000-callback.json"))
        c.cloud.heldFetch?.fetchRecordsResultBlock?(.success(())); await drain()
        XCTAssertTrue(c.runner.evidenceFatal); XCTAssertEqual(fatalCount, 1)
        XCTAssertEqual(try Data(contentsOf: c.output.appendingPathComponent("verified-report.json")), success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: c.output.appendingPathComponent("fatal-unknown.json").path))
        XCTAssertTrue(try outputText(c).contains("LATE_OPERATION_RETURNED"))
    }
    func testIndependentSuccessfulOutputMatchesEveryJournalSummaryHash() async throws {
        let c = try context(); let result = try await run(c)
        XCTAssertEqual(result.status, "GUARDED_STEPS_VERIFIED"); XCTAssertEqual(c.account.calls, 12)
        XCTAssertEqual(c.cloud.calls, ["zoneProbe", "zoneSave", "assetsSave", "mutationsSave", "exactFetch"])
        let files = try FileManager.default.contentsOfDirectory(at: c.output, includingPropertiesForKeys: nil)
        let hashes = Set(try files.map { syncDigest(try Data(contentsOf: $0)) })
        var summaries: [String] = []
        func collect(_ object: Any) {
            if let dictionary = object as? [String: Any] {
                for (key, value) in dictionary { if key == "summarySHA256", let hash = value as? String { summaries.append(hash) }; collect(value) }
            } else if let array = object as? [Any] { array.forEach(collect) }
        }
        for file in try FileManager.default.contentsOfDirectory(at: c.root.appendingPathComponent("ledger"), includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            collect(try JSONSerialization.jsonObject(with: Data(contentsOf: file)))
        }
        XCTAssertGreaterThan(summaries.count, 50)
        XCTAssertTrue(summaries.allSatisfy(hashes.contains), "Every HMAC-journal summary must match an actual retained output file")
        XCTAssertFalse(result.p0Passed); XCTAssertFalse(result.realNetworkQualificationClaimed)
    }

    func testIndependentExpiredWindowCancelsSuspendedAccountWithoutCallback() async throws {
        let c = try context(expiresAfter: 2)
        c.account.holdAt = 1
        let completed = expectation(description: "window expiry must actively unblock suspended account")
        var finished = false, returnedSuccess = false
        let task = Task { do { _ = try await run(c); returnedSuccess = true } catch {} ; finished = true; completed.fulfill() }
        await fulfillment(of: [completed], timeout: 4)
        let finishedBeforeCleanup = finished
        if !finished { task.cancel() }
        await task.value
        XCTAssertTrue(finishedBeforeCleanup); XCTAssertFalse(returnedSuccess)
        XCTAssertEqual(c.account.calls, 1); XCTAssertTrue(c.cloud.calls.isEmpty)
        XCTAssertGreaterThan(c.account.cancellations, 0)
        XCTAssertTrue(try outputText(c).contains("CANCEL_REQUESTED"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: c.output.appendingPathComponent("verified-report.json").path))
    }
    func testIndependentExpiredWindowCancelsSuspendedCloudWithoutCallback() async throws {
        let c = try context(expiresAfter: 2)
        c.cloud.holdZoneProbe = true
        let completed = expectation(description: "window expiry must actively unblock suspended transport")
        var finished = false, returnedSuccess = false
        let task = Task { do { _ = try await run(c); returnedSuccess = true } catch {} ; finished = true; completed.fulfill() }
        await fulfillment(of: [completed], timeout: 4)
        let finishedBeforeCleanup = finished
        if !finished { task.cancel() }
        await task.value
        XCTAssertTrue(finishedBeforeCleanup); XCTAssertFalse(returnedSuccess)
        XCTAssertEqual(c.cloud.calls, ["zoneProbe"])
        XCTAssertTrue(try outputText(c).contains("CANCEL_REQUESTED"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: c.output.appendingPathComponent("verified-report.json").path))
    }

    func testIndependentOldRunLateFatalCancelsNewWindowOnSameRunnerAndLedger() async throws {
        let first = try context(); _ = try await run(first)
        let second = try context(reusing: first.ledger)
        XCTAssertNotEqual(first.window.approval.window, second.window.approval.window)
        XCTAssertNotEqual(first.window.approval.run, second.window.approval.run)
        second.account.holdAt = 1
        let entered = expectation(description: "second legitimate window started")
        second.account.hook = { count in if count == 1 { entered.fulfill() } }
        let completed = expectation(description: "old run fatal must cancel current run")
        var finished = false, returnedSuccess = false
        let current = Task {
            do { _ = try await run(second, runner: first.runner); returnedSuccess = true } catch {}
            finished = true; completed.fulfill()
        }
        await fulfillment(of: [entered], timeout: 3)
        let files = try FileManager.default.contentsOfDirectory(atPath: first.output.path)
        let next = files.compactMap { Int($0.prefix(6)) }.max()! + 1
        try Data("SYNTHETIC_OLD_RUN_EVIDENCE_COLLISION".utf8).write(to: first.output.appendingPathComponent(String(format: "%06d-callback.json", next)))
        first.account.retained.first?.complete(.success(()))
        await fulfillment(of: [completed], timeout: 2)
        let finishedBeforeCleanup = finished
        if !finished { current.cancel() }
        await current.value
        XCTAssertTrue(finishedBeforeCleanup, "Late failure must reach the new active context without another callback")
        XCTAssertFalse(returnedSuccess); XCTAssertTrue(first.runner.evidenceFatal)
        XCTAssertGreaterThan(second.account.cancellations, 0); XCTAssertTrue(second.cloud.calls.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.output.appendingPathComponent("fatal-unknown.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.output.appendingPathComponent("verified-report.json").path))
        do { _ = try await run(second, runner: first.runner); XCTFail("Poisoned shared runner must reject later starts") }
        catch GuardedBatchFailure.poisoned {}
    }

}
