import XCTest
import CloudKit
@testable import FormalDevelopmentSDK

private final class SpyOperation: Operation, @unchecked Sendable {
    var cancelCount = 0
    var onCancel: (() -> Void)?
    override func cancel() { cancelCount += 1; super.cancel(); onCancel?() }
}
@MainActor private final class TransportJournal {
    var events: [TransportOperationEvidence] = []
    var failures: [TransportOperationEvidence] = []
    var reject: String?
    var hook: ((TransportOperationEvidence) -> Void)?
    func emit(_ event: TransportOperationEvidence) throws {
        if event.event == reject { throw CocoaError(.fileWriteNoPermission) }
        events.append(event); hook?(event)
    }
}

@MainActor final class OperationBridgeTests: XCTestCase {
    typealias Bridge = OperationCallbackBridge<Int, String, [Int: Result<String, Error>]>
    private func bridge(_ journal: TransportJournal) -> Bridge {
        Bridge(stage: "synthetic-test", expected: [1], label: { _ in "planned" }, validValue: { $0 == 1 && $1 == "synthetic" },
            sink: { try journal.emit($0) }, onFailure: { journal.failures.append($0) }) { results, aggregate in
            try aggregate.get(); return results
        }
    }
    private func drain() async { await withCheckedContinuation { pending in DispatchQueue.main.async { pending.resume() } } }
    private func expectFailure<T>(_ task: Task<T, Error>) async {
        do { _ = try await task.value; XCTFail("unexpected success") } catch {}
    }
    func testSynchronousCallbacksAndDuplicateCompletionResumeOnlyOnce() async throws {
        let journal = TransportJournal(), operation = SpyOperation()
        let active = self.bridge(journal)
        let result = try await active.execute(operation: operation) {
            active.receive(1, .success("synthetic")); active.complete(.success(())); active.complete(.success(()))
        }
        XCTAssertEqual(try result[1]?.get(), "synthetic")
        await drain()
        XCTAssertEqual(journal.events.map(\.event), ["OPERATION_ENQUEUE_REQUESTED", "ITEM_RETURNED", "OPERATION_RETURNED", "LATE_OPERATION_RETURNED"])
        XCTAssertEqual(journal.events.map(\.sequence), [0, 1, 2, 3]); XCTAssertEqual(operation.cancelCount, 0)
        XCTAssertFalse(journal.events[2].remoteOutcomeUnknown)
    }
    func testCancelBeforeHandleNeverEnqueuesAndPersistsBeforeCancel() async {
        let journal = TransportJournal(), operation = SpyOperation()
        let active = self.bridge(journal)
        active.requestCancellation()
        operation.onCancel = { XCTAssertEqual(journal.events.last?.event, "CANCEL_REQUESTED") }
        var enqueued = false
        do { _ = try await active.execute(operation: operation) { enqueued = true }; XCTFail() } catch {}
        XCTAssertFalse(enqueued); XCTAssertEqual(operation.cancelCount, 1)
        XCTAssertFalse(journal.events[0].started); XCTAssertFalse(journal.events[0].remoteOutcomeUnknown)
    }
    func testTaskCancellationRetainsLateACKAndSynchronousCancelCallback() async {
        let journal = TransportJournal(), operation = SpyOperation(), bridge = bridge(journal)
        let started = expectation(description: "enqueued")
        operation.onCancel = {
            XCTAssertEqual(journal.events.last?.event, "CANCEL_REQUESTED")
            bridge.receive(1, .success("synthetic")); bridge.complete(.success(()))
        }
        let task = Task { try await bridge.execute(operation: operation) { started.fulfill() } }
        await fulfillment(of: [started], timeout: 2)
        task.cancel(); await expectFailure(task); await drain()
        XCTAssertEqual(operation.cancelCount, 1)
        XCTAssertTrue(journal.events.contains { $0.event == "LATE_ITEM_RETURNED" })
        XCTAssertTrue(journal.events.contains { $0.event == "LATE_OPERATION_RETURNED" })
        XCTAssertTrue(journal.events.first { $0.event == "CANCEL_REQUESTED" }!.remoteOutcomeUnknown)
        XCTAssertEqual(Set(journal.events.map(\.operationID)).count, 1)
    }
    func testTaskAlreadyCancelledBeforeExecuteNeverEnqueues() async {
        let journal = TransportJournal(), operation = SpyOperation(), bridge = bridge(journal)
        var enqueued = false
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await bridge.execute(operation: operation) { enqueued = true }
        }
        await expectFailure(task); await drain()
        XCTAssertFalse(enqueued); XCTAssertEqual(operation.cancelCount, 1)
        XCTAssertEqual(journal.events.filter { $0.event == "CANCEL_REQUESTED" }.count, 1)
    }
    func testCancellationReentrantFromEnqueueEvidencePreventsEnqueue() async {
        let journal = TransportJournal(), operation = SpyOperation(), bridge = bridge(journal)
        journal.hook = { if $0.event == "OPERATION_ENQUEUE_REQUESTED" { bridge.requestCancellation() } }
        var enqueued = false
        do { _ = try await bridge.execute(operation: operation) { enqueued = true }; XCTFail() } catch {}
        XCTAssertFalse(enqueued); XCTAssertEqual(operation.cancelCount, 1)
    }
    func testDuplicateItemAndUnknownItemStopAndDoNotOverwrite() async {
        for unknown in [false, true] {
            let journal = TransportJournal(), operation = SpyOperation(), bridge = bridge(journal)
            do {
                _ = try await bridge.execute(operation: operation) {
                    bridge.receive(1, .success("synthetic")); bridge.receive(unknown ? 99 : 1, .success("synthetic")); bridge.complete(.success(()))
                }
                XCTFail()
            } catch {}
            await drain(); XCTAssertEqual(operation.cancelCount, 1)
            XCTAssertTrue(journal.events.contains { $0.event == "UNEXPECTED_CALLBACK" })
            if unknown { XCTAssertTrue(journal.events.contains { $0.items.first?.item == "UNEXPECTED_RECORD_ID" }) }
        }
    }
    func testMissingResultAndWrongValueFailClosed() async {
        for missing in [true, false] {
            let journal = TransportJournal(), operation = SpyOperation(), bridge = bridge(journal)
            do { _ = try await bridge.execute(operation: operation) {
                if !missing { bridge.receive(1, .success("private-payload-must-not-log")) }
                bridge.complete(.success(()))
            }; XCTFail() } catch {}
            await drain()
            XCTAssertFalse(String(decoding: try! JSONEncoder().encode(journal.events), as: UTF8.self).contains("private-payload"))
        }
    }
    func testJournalFailureBeforeEnqueueNeverSendsAndNotifiesFatal() async {
        let journal = TransportJournal(), operation = SpyOperation(), bridge = bridge(journal)
        journal.reject = "OPERATION_ENQUEUE_REQUESTED"; var enqueued = false
        do { _ = try await bridge.execute(operation: operation) { enqueued = true }; XCTFail() } catch {}
        XCTAssertFalse(enqueued); XCTAssertEqual(journal.failures.count, 1); XCTAssertEqual(operation.cancelCount, 1)
        XCTAssertTrue(journal.events.isEmpty)
    }
    func testJournalFailureOnCancellationBestEffortCancelsWithoutClaimingPersistence() async {
        let journal = TransportJournal(), operation = SpyOperation(), bridge = bridge(journal)
        journal.reject = "CANCEL_REQUESTED"
        let started = expectation(description: "enqueued")
        let task = Task { try await bridge.execute(operation: operation) { started.fulfill() } }
        await fulfillment(of: [started], timeout: 2); bridge.requestCancellation(); await expectFailure(task)
        XCTAssertEqual(operation.cancelCount, 1)
        XCTAssertFalse(journal.events.contains { $0.event == "CANCEL_REQUESTED" })
        XCTAssertEqual(journal.failures.map(\.event), ["CANCEL_REQUESTED"])
    }
    func testPartialErrorsPersistOnlyNumericDetails() async {
        let journal = TransportJournal(), operation = SpyOperation(), bridge = bridge(journal)
        let privateID = CKRecord.ID(recordName: "PRIVATE_ID_MUST_NOT_APPEAR")
        let error = NSError(domain: CKErrorDomain, code: CKError.partialFailure.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "PRIVATE_DESCRIPTION", CKPartialErrorsByItemIDKey: [privateID: CKError(.permissionFailure)]])
        do { _ = try await bridge.execute(operation: operation) {
            bridge.receive(1, .failure(error)); bridge.complete(.failure(error))
        }; XCTFail() } catch {}
        let text = String(decoding: try! JSONEncoder().encode(journal.events), as: UTF8.self)
        XCTAssertFalse(text.contains("PRIVATE_")); XCTAssertTrue(journal.events.contains { !$0.items.flatMap(\.partialErrorCodes).isEmpty })
        XCTAssertTrue(journal.events.last!.remoteOutcomeUnknown)
    }
    func testLateCallbacksRemainInOriginalSinkAfterRebindingAdapter() async throws {
        let first = TransportJournal(), second = TransportJournal()
        var held: CKFetchRecordsOperation?
        let adapter = CloudKitDevelopmentAdapter(enqueueForTesting: { held = $0 as? CKFetchRecordsOperation })
        adapter.bindOperationEvidence({ try first.emit($0) }, onFailure: { first.failures.append($0) })
        let id = CKRecord.ID(recordName: "synthetic")
        let task = Task { try await adapter.fetch([id]) }
        while held == nil { await Task.yield() }
        adapter.requestCancellation(); await expectFailure(task)
        adapter.bindOperationEvidence({ try second.emit($0) }, onFailure: { second.failures.append($0) })
        held!.perRecordResultBlock?(id, .success(CKRecord(recordType: "Synthetic", recordID: id)))
        held!.fetchRecordsResultBlock?(.success(())); await drain()
        XCTAssertTrue(first.events.contains { $0.event == "LATE_ITEM_RETURNED" }); XCTAssertTrue(second.events.isEmpty)
    }
    func testAdapterExplicitOperationsPreserveExactPolicyAndIDs() async throws {
        let journal = TransportJournal(), zone = CKRecordZone.ID(zoneName: "synthetic"), id = CKRecord.ID(recordName: "synthetic")
        let record = CKRecord(recordType: "Synthetic", recordID: id)
        var kinds: [String] = []
        let adapter = CloudKitDevelopmentAdapter(enqueueForTesting: { operation in
            if let operation = operation as? CKFetchRecordZonesOperation {
                kinds.append("zone-fetch"); XCTAssertEqual(operation.recordZoneIDs, [zone])
                operation.perRecordZoneResultBlock?(zone, .success(CKRecordZone(zoneID: zone))); operation.fetchRecordZonesResultBlock?(.success(()))
            } else if let operation = operation as? CKModifyRecordZonesOperation {
                kinds.append("zone-save"); XCTAssertEqual(operation.recordZonesToSave?.map(\.zoneID), [zone]); XCTAssertEqual(operation.recordZoneIDsToDelete, [])
                operation.perRecordZoneSaveBlock?(zone, .success(CKRecordZone(zoneID: zone))); operation.modifyRecordZonesResultBlock?(.success(()))
            } else if let operation = operation as? CKModifyRecordsOperation {
                kinds.append("records-save"); XCTAssertEqual(operation.recordsToSave?.map(\.recordID), [id]); XCTAssertEqual(operation.recordIDsToDelete, [])
                XCTAssertEqual(operation.savePolicy, .ifServerRecordUnchanged); XCTAssertTrue(operation.isAtomic)
                operation.perRecordSaveBlock?(id, .success(operation.recordsToSave![0])); operation.modifyRecordsResultBlock?(.success(()))
            } else if let operation = operation as? CKFetchRecordsOperation {
                kinds.append("records-fetch"); XCTAssertEqual(operation.recordIDs, [id]); XCTAssertNil(operation.desiredKeys)
                operation.perRecordResultBlock?(id, .success(record)); operation.fetchRecordsResultBlock?(.success(()))
            } else { XCTFail("unexpected operation") }
        })
        adapter.bindOperationEvidence({ try journal.emit($0) }, onFailure: { journal.failures.append($0) })
        let exists = try await adapter.zoneExists(zone); XCTAssertTrue(exists)
        let created = try await adapter.createZone(zone); XCTAssertEqual(created, zone)
        let saved = try await adapter.save([record]); XCTAssertEqual(try saved[id]?.get().recordID, id)
        let mutation = CKRecord(recordType: "PGMutationV2", recordID: id)
        _ = try await adapter.save([mutation])
        let fetched = try await adapter.fetch([id]); XCTAssertEqual(try fetched[id]?.get().recordID, id)
        XCTAssertEqual(kinds, ["zone-fetch", "zone-save", "records-save", "records-save", "records-fetch"])
        XCTAssertEqual(Set(journal.events.map(\.operationID)).count, 5)
        XCTAssertEqual(journal.events.filter { $0.event == "OPERATION_ENQUEUE_REQUESTED" }.map(\.stage),
            ["zone-probe", "zone-save", "assets-save", "mutations-save", "exact-fetch"])
    }
    func testAdapterRequiresEvidenceAndRejectsDuplicateOrEmptyIDs() async {
        var enqueued = false
        let adapter = CloudKitDevelopmentAdapter(enqueueForTesting: { _ in enqueued = true })
        do { _ = try await adapter.zoneExists(.init(zoneName: "synthetic")); XCTFail() } catch {}
        adapter.bindOperationEvidence({ _ in }, onFailure: { _ in })
        let id = CKRecord.ID(recordName: "synthetic")
        for ids in [[], [id, id]] {
            do { _ = try await adapter.fetch(ids); XCTFail() } catch {}
        }
        XCTAssertFalse(enqueued)
    }
    func testZoneAbsenceRequiresExactPerZoneResultAndCompatibleAggregate() async throws {
        for aggregate in [CKError.Code.partialFailure, .networkFailure] {
            let journal = TransportJournal(), zone = CKRecordZone.ID(zoneName: "synthetic")
            let adapter = CloudKitDevelopmentAdapter(enqueueForTesting: { raw in
                let op = raw as! CKFetchRecordZonesOperation
                op.perRecordZoneResultBlock?(zone, .failure(CKError(.zoneNotFound)))
                op.fetchRecordZonesResultBlock?(.failure(CKError(aggregate)))
            })
            adapter.bindOperationEvidence({ try journal.emit($0) }, onFailure: { journal.failures.append($0) })
            do { let exists = try await adapter.zoneExists(zone); XCTAssertEqual(aggregate, .partialFailure); XCTAssertFalse(exists) }
            catch { XCTAssertEqual(aggregate, .networkFailure) }
        }
    }
    func testUnexpectedDeleteCallbackCannotBeAValidSave() async {
        let journal = TransportJournal(), id = CKRecord.ID(recordName: "synthetic")
        let record = CKRecord(recordType: "Synthetic", recordID: id)
        let adapter = CloudKitDevelopmentAdapter(enqueueForTesting: { raw in
            let op = raw as! CKModifyRecordsOperation
            op.perRecordDeleteBlock?(CKRecord.ID(recordName: "PRIVATE_UNEXPECTED_DELETE"), .failure(CKError(.permissionFailure)))
            op.perRecordSaveBlock?(id, .success(record)); op.modifyRecordsResultBlock?(.success(()))
        })
        adapter.bindOperationEvidence({ try journal.emit($0) }, onFailure: { journal.failures.append($0) })
        do { _ = try await adapter.save([record]); XCTFail() } catch {}
        await drain()
        XCTAssertTrue(journal.events.contains { $0.event == "UNEXPECTED_CALLBACK" && $0.items.first?.errorCode == CKError.permissionFailure.rawValue })
        XCTAssertFalse(String(decoding: try! JSONEncoder().encode(journal.events), as: UTF8.self).contains("PRIVATE_"))
    }
    func testEvidenceFailureDuringItemOrAggregateCannotSucceed() async {
        for rejected in ["ITEM_RETURNED", "OPERATION_RETURNED"] {
            let journal = TransportJournal(), operation = SpyOperation(), bridge = bridge(journal)
            journal.reject = rejected
            do { _ = try await bridge.execute(operation: operation) {
                bridge.receive(1, .success("synthetic")); bridge.complete(.success(()))
            }; XCTFail() } catch {}
            await drain()
            XCTAssertEqual(journal.failures.count, 1); XCTAssertEqual(journal.failures.first?.event, rejected)
            XCTAssertEqual(operation.cancelCount, 1)
        }
    }

}
