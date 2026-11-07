import Foundation
import CloudKit

public enum Wire {
    public static let objectType = "G1ObjectV1"
    public static let imageType = "G1ImageV1"
    public static func zone(_ dataset: String) -> CKRecordZone.ID { CKRecordZone.ID(zoneName: "G1-" + dataset, ownerName: CKCurrentUserDefaultName) }
    public static func fields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder); coder.finishEncoding(); return coder.encodedData
    }
    public static func record(_ item: Pending, dataset: String, imageURL: (String) throws -> URL) throws -> CKRecord {
        let id = CKRecord.ID(recordName: item.key, zoneID: zone(dataset))
        let isImage = item.key.hasPrefix("image-")
        let type = isImage ? imageType : objectType
        let record: CKRecord
        if let data = item.systemFields {
            let coder = try NSKeyedUnarchiver(forReadingFrom: data); coder.requiresSecureCoding = true
            defer { coder.finishDecoding() }
            guard let decoded = CKRecord(coder: coder), decoded.recordID == id, decoded.recordType == type else { throw LabError.invalidWire }
            record = decoded
        } else { record = CKRecord(recordType: type, recordID: id) }
        record["wireVersion"] = 1 as CKRecordValue
        if isImage {
            let hash = String(item.key.dropFirst(6)); let count = try JSONDecoder().decode(Int.self, from: item.payload)
            guard isHash(hash), (1...8_388_608).contains(count) else { throw LabError.invalidWire }
            let url = try imageURL(hash)
            let bytes = try Data(contentsOf: url)
            guard bytes.count == count, digest(bytes) == hash else { throw LabError.missingImage }
            record["sha256"] = hash as CKRecordValue
            record["byteCount"] = count as CKRecordValue
            record["original"] = CKAsset(fileURL: url)
        } else {
            let e = try Envelope.decode(item.payload)
            guard item.key == "object-" + e.object else { throw LabError.invalidWire }
            record["objectID"] = e.object as CKRecordValue
            record["payload"] = item.payload as CKRecordValue
            record["sha256"] = digest(item.payload) as CKRecordValue
        }
        return record
    }
    public static func payload(_ record: CKRecord, dataset: String) throws -> Data {
        guard record.recordID.zoneID == zone(dataset), (record["wireVersion"] as? NSNumber)?.intValue == 1 else { throw LabError.invalidWire }
        if record.recordType == objectType {
            guard let bytes = record["payload"] as? Data, record["sha256"] as? String == digest(bytes) else { throw LabError.invalidWire }
            let e = try Envelope.decode(bytes)
            guard record["objectID"] as? String == e.object, record.recordID.recordName == "object-" + e.object else { throw LabError.invalidWire }
            return bytes
        }
        guard record.recordType == imageType, let hash = record["sha256"] as? String, isHash(hash), record.recordID.recordName == "image-" + hash,
              let count = (record["byteCount"] as? NSNumber)?.intValue, (1...8_388_608).contains(count) else { throw LabError.invalidWire }
        return try canonical(count)
    }
}

// Manual sync only. Automatic/background scheduling is a separate NOT_RUN gate.
// Each instance owns ONE immutable account/dataset partition. Never rebind an engine.
@MainActor public final class CloudDriver: CKSyncEngineDelegate {
    public let store: LabStore
    private let ticket: UUID
    private var engine: CKSyncEngine?
    public private(set) var events: [String] = [] // fixed codes only; no cloud errors containing account IDs
    public private(set) var halted = false
    #if DEBUG
    var probeHook: ((ProbeCloudPoint, LabStore, [CKRecord]) throws -> Void)?
    #endif
    public init(store: LabStore) { self.store = store; ticket = store.epoch }
    public func start(authorization: DevelopmentAuthorization = .fromEnvironment()) async throws {
        #if !DEBUG
        throw LabError.blocked
        #else
        guard authorization.isEnabled, !halted, engine == nil else { throw LabError.blocked }
        // The runbook requires signed entitlement/profile verification BEFORE opt-in.
        let container = CKContainer(identifier: Binding.container)
        guard try await container.accountStatus() == .available else { throw LabError.blocked }
        let account = try await container.userRecordID()
        try store.check(ticket)
        guard digest(Data(account.recordName.utf8)) == store.binding.accountHash else { throw LabError.staleEpoch }
        let state = try store.checkpoint().map { try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        var config = CKSyncEngine.Configuration(database: container.privateCloudDatabase, stateSerialization: state, delegate: self)
        config.automaticallySync = false
        let new = CKSyncEngine(config); engine = new
        new.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Wire.zone(store.binding.dataset)))])
        try schedule(new)
        events.append("ENGINE_STARTED_DEVELOPMENT_OPT_IN")
        #endif
    }
    public func sync() async throws {
        try store.check(ticket); guard !halted, let engine else { throw LabError.blocked }
        try schedule(engine)
        try await engine.sendChanges()
        try store.check(ticket)
        try await engine.fetchChanges(.init(scope: .zoneIDs([Wire.zone(store.binding.dataset)])))
        try store.check(ticket)
        try schedule(engine) // fetched merge or old ACK may have left durable work
    }
    public func stop() async {
        // Fence first; cancel is async and callbacks may arrive while awaiting it.
        halted = true; store.fence()
        await engine?.cancelOperations(); engine = nil
    }
    func schedule(_ engine: CKSyncEngine) throws {
        try store.check(ticket)
        let pending = try store.pending().map { CKSyncEngine.PendingRecordZoneChange.saveRecord(CKRecord.ID(recordName: $0.key, zoneID: Wire.zone(store.binding.dataset))) }
        engine.state.add(pendingRecordZoneChanges: pending)
    }
    func accept(_ record: CKRecord) throws {
        // Retain opaque fields BEFORE any codec validation, including future wire versions.
        try store.retainInbound(NSKeyedArchiver.archivedData(withRootObject: record, requiringSecureCoding: true), ticket: ticket)
        if let asset = record["original"] as? CKAsset, let url = asset.fileURL {
            try store.retainFile(Data(contentsOf: url))
        }
        let bytes = try Wire.payload(record, dataset: store.binding.dataset)
        if record.recordType == Wire.objectType {
            try store.receiveEnvelope(bytes, key: record.recordID.recordName, fields: Wire.fields(record), ticket: ticket)
        } else {
            guard let asset = record["original"] as? CKAsset, let url = asset.fileURL, let hash = record["sha256"] as? String else { throw LabError.missingImage }
            let count = try JSONDecoder().decode(Int.self, from: bytes)
            // Copy system temporary CKAsset bytes into the retained lease before checkpoint.
            try store.receiveImage(Data(contentsOf: url), hash: hash, count: count, fields: Wire.fields(record), ticket: ticket)
        }
    }
    func processSaveFailure(_ error: CKError) throws {
        try store.check(ticket)
        if error.code == .serverRecordChanged, let server = error.serverRecord {
            try accept(server)
            events.append("SERVER_RECORD_CHANGED_MERGED")
        } else { events.append("SEND_RETAINED_ERROR_" + String(error.errorCode)) }
    }
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard engine === syncEngine, !halted else { return }
        do {
            try store.check(ticket)
            switch event {
            case .accountChange(let change):
                switch change.changeType {
                case .signIn(let currentUser) where digest(Data(currentUser.recordName.utf8)) == store.binding.accountHash:
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Wire.zone(store.binding.dataset)))])
                    try schedule(syncEngine)
                    events.append("SAME_ACCOUNT_QUEUE_REBUILT")
                default:
                    events.append("ACCOUNT_CHANGED_REOPEN_REQUIRED"); halted = true; store.fence()
                    Task { await syncEngine.cancelOperations() }
                }
            case .fetchedRecordZoneChanges(let change):
                // Physical deletion is NOT a logical tombstone. Keep local evidence and stop.
                guard change.deletions.isEmpty else { throw LabError.blocked }
                #if DEBUG
                try probeHook?(.beforeFetchedInstall, store, change.modifications.map(\.record))
                #endif
                for modified in change.modifications { try accept(modified.record) }
                #if DEBUG
                try probeHook?(.afterFetchedInstall, store, change.modifications.map(\.record))
                #endif
                events.append("FETCH_CONTENT_DURABLE")
            case .stateUpdate(let update):
                // Delegate is serialized on MainActor. No await between content commit and state commit.
                try store.saveCheckpoint(try canonical(update.stateSerialization), ticket: ticket)
                events.append("STATE_DURABLE")
                #if DEBUG
                try probeHook?(.afterState, store, [])
                #endif
            case .sentRecordZoneChanges(let change):
                #if DEBUG
                try probeHook?(.beforeACK, store, change.savedRecords)
                #endif
                for record in change.savedRecords {
                    try store.acknowledge(record.recordID.recordName, sent: Wire.payload(record, dataset: store.binding.dataset), fields: Wire.fields(record), ticket: ticket)
                }
                #if DEBUG
                try probeHook?(.afterACK, store, change.savedRecords)
                #endif
                for failure in change.failedRecordSaves {
                    try processSaveFailure(failure.error)
                }
                try schedule(syncEngine)
                events.append("ACK_EXACT_AND_RESCHEDULED")
            case .didSendChanges:
                // Re-add after the engine has removed successfully sent record IDs.
                try schedule(syncEngine)
            case .fetchedDatabaseChanges(let change):
                guard !change.deletions.contains(where: { $0.zoneID == Wire.zone(store.binding.dataset) }) else { throw LabError.blocked }
            case .sentDatabaseChanges(let change):
                if !change.failedZoneSaves.isEmpty { events.append("ZONE_SAVE_FAILED_RETAINED") }
            default: break
            }
        } catch {
            // Never let a failed content/asset commit advance a later checkpoint.
            halted = true; store.fence(); events.append("HALTED_RETAINED_REPLAY_REQUIRED")
        }
    }
    public func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        .init(scope: .zoneIDs([Wire.zone(store.binding.dataset)]))
    }
    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard engine === syncEngine, !halted else { return nil }
        do {
            try store.check(ticket)
            let rows = try store.pending().filter { context.options.scope.contains(CKRecord.ID(recordName: $0.key, zoneID: Wire.zone(store.binding.dataset))) }.prefix(32)
            let records = try rows.map { try Wire.record($0, dataset: store.binding.dataset, imageURL: store.imageURL) }
            #if DEBUG
            try probeHook?(.batchPrepared, store, records)
            #endif
            return records.isEmpty ? nil : CKSyncEngine.RecordZoneChangeBatch(recordsToSave: records, atomicByZone: false)
        } catch {
            halted = true; store.fence(); events.append("BATCH_FAILED_RETAINED"); return nil
        }
    }
}
