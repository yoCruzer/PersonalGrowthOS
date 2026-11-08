import Foundation
import CloudKit

/// Internal seam only. Injecting CKDatabase does NOT authenticate its environment/account.
/// There is deliberately no public/live factory until the external gates are implemented.
@MainActor protocol BatchTransport {
    func zoneExists(_ id: CKRecordZone.ID) async throws -> Bool
    func createZone(_ id: CKRecordZone.ID) async throws -> CKRecordZone.ID
    func save(_ records: [CKRecord]) async throws -> [CKRecord.ID: Result<CKRecord, Error>]
    func fetch(_ ids: [CKRecord.ID]) async throws -> [CKRecord.ID: Result<CKRecord, Error>]
}

@MainActor final class CloudKitDevelopmentAdapter: BatchTransport {
    private let database: CKDatabase
    // NOT a gate: internal and unreachable from the shipped locked host. Future factory
    // must independently establish signing, account and Development before construction.
    init(unauthenticatedDatabase: CKDatabase) { database = unauthenticatedDatabase }
    func zoneExists(_ id: CKRecordZone.ID) async throws -> Bool {
        do {
            let zone = try await database.recordZone(for: id)
            guard zone.zoneID == id else { throw BatchFailure.wrongZone }
            return true
        }
        catch let error as CKError where error.code == .zoneNotFound { return false }
    }
    func createZone(_ id: CKRecordZone.ID) async throws -> CKRecordZone.ID {
        try await database.save(CKRecordZone(zoneID: id)).zoneID
    }
    func save(_ records: [CKRecord]) async throws -> [CKRecord.ID: Result<CKRecord, Error>] {
        // No delete, overwrite policy or retry. Preserve every per-record outcome.
        let result = try await database.modifyRecords(saving: records, deleting: [],
            savePolicy: .ifServerRecordUnchanged, atomically: true)
        guard result.deleteResults.isEmpty else { throw BatchFailure.unexpectedResults }
        return result.saveResults
    }
    func fetch(_ ids: [CKRecord.ID]) async throws -> [CKRecord.ID: Result<CKRecord, Error>] {
        try await database.records(for: ids, desiredKeys: nil)
    }
}
