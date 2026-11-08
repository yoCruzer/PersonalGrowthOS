import Foundation
import CloudKit
import SyncFoundation

/// Internal seam only. Injecting CKDatabase does NOT authenticate its environment/account.
/// There is deliberately no public/live factory until the external gates are implemented.
@MainActor protocol BatchTransport {
    func zoneExists(_ id: CKRecordZone.ID) async throws -> Bool
    func createZone(_ id: CKRecordZone.ID) async throws -> CKRecordZone.ID
    func save(_ records: [CKRecord]) async throws -> [CKRecord.ID: Result<CKRecord, Error>]
    func fetch(_ ids: [CKRecord.ID]) async throws -> [CKRecord.ID: Result<CKRecord, Error>]
}

@MainActor final class CloudKitDevelopmentAdapter: OperationEvidenceTransport {
    private let enqueue: (CKDatabaseOperation) -> Void
    private var evidence: (TransportEvidenceSink, TransportEvidenceFailure)?
    private var cancelCurrent: (() -> Void)?
    // NOT a gate: internal and unreachable from the shipped locked host.
    init(unauthenticatedDatabase: CKDatabase) { enqueue = { unauthenticatedDatabase.add($0) } }
    // Offline operation/callback test seam; never constructs a database/container.
    init(enqueueForTesting: @escaping (CKDatabaseOperation) -> Void) { enqueue = enqueueForTesting }
    func bindOperationEvidence(_ sink: @escaping TransportEvidenceSink, onFailure: @escaping TransportEvidenceFailure) {
        evidence = (sink, onFailure)
    }
    func requestCancellation() { cancelCurrent?() }
    private func binding() throws -> (TransportEvidenceSink, TransportEvidenceFailure) {
        guard let evidence else { throw TransportOperationFailure.evidenceNotBound }
        guard cancelCurrent == nil else { throw BatchFailure.busy }
        return evidence
    }
    func zoneExists(_ id: CKRecordZone.ID) async throws -> Bool {
        let (sink, failed) = try binding()
        let bridge = OperationCallbackBridge<CKRecordZone.ID, CKRecordZone, Bool>(stage: "zone-probe", expected: [id], label: { _ in "zone" }, validValue: { $0 == $1.zoneID }, sink: sink, onFailure: failed) { results, aggregate in
            if case .failure(let error)? = results[id], let cloud = error as? CKError, cloud.code == .zoneNotFound {
                // A single precise absent zone may be delivered as partialFailure.
                if case .failure(let overall) = aggregate {
                    guard let ck = overall as? CKError, ck.code == .partialFailure || ck.code == .zoneNotFound else { throw overall }
                }
                return false
            }
            try aggregate.get()
            guard let result = results[id] else { throw TransportOperationFailure.invalidResults }
            _ = try result.get(); return true
        }
        let operation = CKFetchRecordZonesOperation(recordZoneIDs: [id])
        operation.perRecordZoneResultBlock = { bridge.receive($0, $1) }
        operation.fetchRecordZonesResultBlock = { bridge.complete($0) }
        cancelCurrent = { bridge.requestCancellation() }; defer { cancelCurrent = nil }
        return try await bridge.execute(operation: operation) { enqueue(operation) }
    }
    func createZone(_ id: CKRecordZone.ID) async throws -> CKRecordZone.ID {
        let (sink, failed) = try binding()
        let bridge = OperationCallbackBridge<CKRecordZone.ID, CKRecordZone, CKRecordZone.ID>(stage: "zone-save", expected: [id], label: { _ in "zone" }, validValue: { $0 == $1.zoneID }, sink: sink, onFailure: failed) { results, aggregate in
            try aggregate.get()
            guard let result = results[id] else { throw TransportOperationFailure.invalidResults }
            return try result.get().zoneID
        }
        let operation = CKModifyRecordZonesOperation(recordZonesToSave: [CKRecordZone(zoneID: id)], recordZoneIDsToDelete: [])
        operation.perRecordZoneSaveBlock = { bridge.receive($0, $1) }
        operation.perRecordZoneDeleteBlock = { _, result in bridge.unexpectedCallback(result) }
        operation.modifyRecordZonesResultBlock = { bridge.complete($0) }
        cancelCurrent = { bridge.requestCancellation() }; defer { cancelCurrent = nil }
        return try await bridge.execute(operation: operation) { enqueue(operation) }
    }
    func save(_ records: [CKRecord]) async throws -> [CKRecord.ID: Result<CKRecord, Error>] {
        let ids = records.map(\.recordID)
        guard !ids.isEmpty, Set(ids).count == ids.count else { throw TransportOperationFailure.invalidResults }
        let stage = records.allSatisfy { $0.recordType == CloudRecordCodec.mutationType } ? "mutations-save" : "assets-save"
        let (sink, failed) = try binding()
        let bridge = recordBridge(ids, stage: stage, sink: sink, failed: failed)
        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: [])
        operation.savePolicy = .ifServerRecordUnchanged; operation.isAtomic = true
        operation.perRecordSaveBlock = { bridge.receive($0, $1) }
        operation.perRecordDeleteBlock = { _, result in bridge.unexpectedCallback(result) }
        operation.modifyRecordsResultBlock = { bridge.complete($0) }
        cancelCurrent = { bridge.requestCancellation() }; defer { cancelCurrent = nil }
        return try await bridge.execute(operation: operation) { enqueue(operation) }
    }
    func fetch(_ ids: [CKRecord.ID]) async throws -> [CKRecord.ID: Result<CKRecord, Error>] {
        guard !ids.isEmpty, Set(ids).count == ids.count else { throw TransportOperationFailure.invalidResults }
        let (sink, failed) = try binding()
        let bridge = recordBridge(ids, stage: "exact-fetch", sink: sink, failed: failed)
        let operation = CKFetchRecordsOperation(recordIDs: ids)
        operation.desiredKeys = nil
        operation.perRecordResultBlock = { bridge.receive($0, $1) }
        operation.fetchRecordsResultBlock = { bridge.complete($0) }
        cancelCurrent = { bridge.requestCancellation() }; defer { cancelCurrent = nil }
        return try await bridge.execute(operation: operation) { enqueue(operation) }
    }
    private func recordBridge(_ ids: [CKRecord.ID], stage: String, sink: @escaping TransportEvidenceSink,
                              failed: @escaping TransportEvidenceFailure) -> OperationCallbackBridge<CKRecord.ID, CKRecord, [CKRecord.ID: Result<CKRecord, Error>]> {
        OperationCallbackBridge(stage: stage, expected: Set(ids), label: { $0.recordName }, validValue: { $0 == $1.recordID }, sink: sink, onFailure: failed) { results, aggregate in
            try aggregate.get(); return results
        }
    }
}
