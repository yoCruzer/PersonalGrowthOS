import Foundation
import CloudKit
import CoreFoundation
import SyncFoundation

enum SyncCloudPauseReason: Equatable, Sendable {
    case accountChanged, accountUnavailable, identityMismatch, environmentMismatch
    case zoneMissing, remoteDeletion, conflict, invalidRecord, persistenceFailure
    case cloudFailure(Int)
}

enum SyncCloudTransportError: Error, Equatable {
    case staleSession, alreadyStarted, notStarted, paused(SyncCloudPauseReason)
}

/// A capability for one activation, not merely the reusable persisted generation UUID.
/// Every persistence implementation must check this after suspension and immediately before
/// its atomic commit. Checking only in this transport cannot fence a suspended store callback.
@MainActor final class SyncCloudSession {
    let binding: SyncBinding
    private(set) var active = true
    private(set) var firstPauseReason: SyncCloudPauseReason?
    private(set) var secondaryCloudErrorCode: Int?
    init(binding: SyncBinding) { self.binding = binding }
    func check() throws { guard active else { throw SyncCloudTransportError.staleSession } }
    func invalidate() { active = false }
    func pause(_ reason: SyncCloudPauseReason) {
        guard active else { return }
        if firstPauseReason == nil { firstPauseReason = reason }
        active = false
    }
    /// Preserve a recorded failure when SDK cancellation follows our fail-closed stop.
    /// A cancellation without an earlier pause remains an error, never synthetic success.
    func observeFailure(_ error: Error) -> Error {
        guard let firstPauseReason else { return error }
        if let cloud = error as? CKError, secondaryCloudErrorCode == nil,
           firstPauseReason != .cloudFailure(cloud.code.rawValue) {
            secondaryCloudErrorCode = cloud.code.rawValue
        }
        return SyncCloudTransportError.paused(firstPauseReason)
    }
}

enum SyncCloudDownloaded: Equatable, Sendable {
    case mutation(MutationManifest)
    case payloadChunk(AssetDescriptor, Data)
    case original(AssetDescriptor, Data)
}

enum SyncCloudAcknowledgement: Equatable, Sendable {
    case mutation(id: UUID, manifestSHA256: String)
    case payloadChunk(AssetDescriptor)
    case original(AssetDescriptor)
}

/// The store owns immutable staging files. It must retain them across cancellation and late SDK
/// callbacks; cancelOperations is explicitly not proof that all in-progress operations finished.
enum SyncCloudUpload {
    case mutation(MutationManifest)
    case payloadChunk(AssetDescriptor, URL)
    case original(AssetDescriptor, URL)

    func makeRecord(dataset: UUID) throws -> CKRecord {
        switch self {
        case .mutation(let manifest):
            guard manifest.dataset == dataset else { throw SyncValidationError.invalidIdentity }
            return try CloudRecordCodec.encode(manifest)
        case .payloadChunk(let descriptor, let url):
            return try CloudRecordCodec.encodeChunk(descriptor, dataset: dataset, url: url)
        case .original(let descriptor, let url):
            return try CloudRecordCodec.encodeOriginal(descriptor, dataset: dataset, url: url)
        }
    }
    func acknowledgement() throws -> SyncCloudAcknowledgement {
        switch self {
        case .mutation(let manifest): return .mutation(id: manifest.mutation, manifestSHA256: syncDigest(try manifest.encoded()))
        case .payloadChunk(let descriptor, _): return .payloadChunk(descriptor)
        case .original(let descriptor, _): return .original(descriptor)
        }
    }
}

@MainActor protocol SyncCloudPersistence: AnyObject {
    func loadEngineState(binding: SyncBinding) throws -> Data?
    /// Return only this binding's immutable records, including every still-unacknowledged asset.
    func pendingRecordIDs(session: SyncCloudSession) throws -> [CKRecord.ID]
    /// Recheck the complete binding and durable initial-creation intent. A lost/established
    /// zone or a missing explicit intent never grants fresh creation permission.
    func permitsPendingZoneCreation(session: SyncCloudSession) throws -> Bool
    func uploadRecord(id: CKRecord.ID, session: SyncCloudSession) async throws -> SyncCloudUpload?
    /// Persist bytes before returning; never retain SDK temporary asset URLs as durable content.
    func durableInbox(_ records: [SyncCloudDownloaded], session: SyncCloudSession) async throws
    /// A manifest ACK alone must not finish a mutation whose assets remain unacknowledged.
    func acknowledge(_ records: [SyncCloudAcknowledgement], session: SyncCloudSession) async throws
    func didSaveZone(session: SyncCloudSession) async throws
    func saveEngineState(_ bytes: Data, session: SyncCloudSession) async throws
    func didPause(_ reason: SyncCloudPauseReason, binding: SyncBinding)
}

/// Cloud-independent ordered commit seam. The SDK delivers events serially; this additional
/// FIFO also preserves order when the store suspends, and is exercised without a CKContainer.
@MainActor final class SyncCloudDurableEvents {
    enum Event {
        case downloaded([SyncCloudDownloaded])
        case acknowledged([SyncCloudAcknowledgement])
        case state(Data)
        case zoneSaved
        case pause(SyncCloudPauseReason)
    }
    let session: SyncCloudSession
    private let persistence: any SyncCloudPersistence
    private var tail: Task<Void, Error>?
    init(session: SyncCloudSession, persistence: any SyncCloudPersistence) {
        self.session = session; self.persistence = persistence
    }
    func accept(_ event: Event) async throws {
        let previous = tail
        let task = Task { @MainActor [self] in
            if let previous { try await previous.value }
            try session.check()
            do {
                switch event {
                case .downloaded(let records): try await persistence.durableInbox(records, session: session)
                case .acknowledged(let records): try await persistence.acknowledge(records, session: session)
                case .state(let bytes): try await persistence.saveEngineState(bytes, session: session)
                case .zoneSaved: try await persistence.didSaveZone(session: session)
                case .pause(let reason):
                    session.pause(reason); persistence.didPause(reason, binding: session.binding)
                    throw SyncCloudTransportError.paused(reason)
                }
                try session.check()
            } catch {
                if session.active {
                    session.pause(.persistenceFailure); persistence.didPause(.persistenceFailure, binding: session.binding)
                }
                throw error
            }
        }
        tail = task
        try await task.value
    }
}

/// Opt-in iOS 17 driver. Initialization performs no account request and creates no container.
/// CloudKit's environment comes from signing; it is NOT selected by CKContainer(identifier:).
@MainActor final class SyncCloudTransport: CKSyncEngineDelegate {
    private let persistence: any SyncCloudPersistence
    private(set) var session: SyncCloudSession?
    private var events: SyncCloudDurableEvents?
    private var engine: CKSyncEngine?
    private var cloudContainer: CKContainer?
    private var admitted: [CKRecord.ID: (SyncCloudUpload, CKRecord)] = [:]
    private var synchronizingSession: SyncCloudSession?
    private var allowsInitialZoneCreation = false

    init(persistence: any SyncCloudPersistence) { self.persistence = persistence }

    static func accountFingerprint(recordID: CKRecord.ID) -> String {
        syncDigest(Data(recordID.recordName.utf8))
    }

    /// Only call after explicit user activation. `signedEnvironment` must come from verified
    /// app signing configuration. `createZone` is reserved for a persisted fresh-dataset intent;
    /// a lost zone is never recreated by this driver.
    func start(binding: SyncBinding, signedEnvironment: CloudEnvironment, createZone: Bool = false) async throws {
        guard session == nil else { throw SyncCloudTransportError.alreadyStarted }
        guard binding.environment == signedEnvironment else {
            throw SyncCloudTransportError.paused(.environmentMismatch)
        }
        let active = SyncCloudSession(binding: binding)
        allowsInitialZoneCreation = createZone
        session = active; events = SyncCloudDurableEvents(session: active, persistence: persistence)
        do {
            let stateBytes = try persistence.loadEngineState(binding: binding)
            let state = try stateBytes.map { try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
            let container = CKContainer(identifier: binding.container)
            let status = try await container.accountStatus()
            try active.check()
            guard status == .available else { throw SyncCloudTransportError.paused(.accountUnavailable) }
            let user = try await container.userRecordID()
            try active.check()
            guard Self.accountFingerprint(recordID: user) == binding.accountHash else {
                throw SyncCloudTransportError.paused(.identityMismatch)
            }
            var configuration = CKSyncEngine.Configuration(database: container.privateCloudDatabase,
                                                           stateSerialization: state, delegate: self)
            configuration.automaticallySync = false
            let created = CKSyncEngine(configuration)
            engine = created; cloudContainer = container
            let obsoleteZoneSaves = try Self.restoredZoneSavesToRemove(
                recordChanges: created.state.pendingRecordZoneChanges,
                databaseChanges: created.state.pendingDatabaseChanges,
                dataset: binding.dataset, createZone: createZone)
            if !obsoleteZoneSaves.isEmpty { created.state.remove(pendingDatabaseChanges: obsoleteZoneSaves) }
            try Self.validatePending(recordChanges: created.state.pendingRecordZoneChanges,
                databaseChanges: created.state.pendingDatabaseChanges, dataset: binding.dataset, createZone: createZone)
            if createZone { created.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudRecordCodec.zone(dataset: binding.dataset)))]) }
            try refreshOutbox(engine: created, session: active)
        } catch {
            if active.active { pause(reason(for: error), session: active) }
            throw active.observeFailure(error)
        }
    }

    func stop() async {
        session?.invalidate()
        let previous = engine
        engine = nil; cloudContainer = nil; session = nil; events = nil; admitted = [:]; synchronizingSession = nil
        // Do not delete staging or durable state. SDK cancellation can still deliver late events.
        if let previous { await previous.cancelOperations() }
    }

    func synchronize() async throws {
        guard let engine, let session else { throw SyncCloudTransportError.notStarted }
        try session.check()
        guard synchronizingSession !== session else { return }
        synchronizingSession = session
        defer { if synchronizingSession === session { synchronizingSession = nil } }
        do {
            try refreshOutbox(engine: engine, session: session)
            let zone = CloudRecordCodec.zone(dataset: session.binding.dataset)
            try await engine.sendChanges(.init(scope: .zoneIDs([zone])))
            try session.check()
            // Old ACKs may have coincided with newer local edits. Re-read durable outbox.
            try refreshOutbox(engine: engine, session: session)
            try await engine.fetchChanges(.init(scope: .zoneIDs([zone])))
            try session.check()
        } catch {
            if session.active { pause(reason(for: error), session: session) }
            throw session.observeFailure(error)
        }
    }

    private func refreshOutbox(engine: CKSyncEngine, session: SyncCloudSession) throws {
        try session.check()
        let ids = try persistence.pendingRecordIDs(session: session)
        let zone = CloudRecordCodec.zone(dataset: session.binding.dataset)
        guard ids.allSatisfy({ $0.zoneID == zone }) else { throw SyncValidationError.invalidIdentity }
        try session.check()
        try Self.validatePending(recordChanges: engine.state.pendingRecordZoneChanges,
                                 databaseChanges: engine.state.pendingDatabaseChanges,
                                 dataset: session.binding.dataset, createZone: allowsInitialZoneCreation)
        engine.state.add(pendingRecordZoneChanges: ids.map { .saveRecord($0) })
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard engine === syncEngine, let session, session.active, let events else { return }
        let zone = CloudRecordCodec.zone(dataset: session.binding.dataset)
        do {
            switch event {
            case .stateUpdate(let update):
                try await events.accept(.state(try JSONEncoder().encode(update.stateSerialization)))
            case .accountChange(let change):
                let plan = try Self.accountChangePlan(change.changeType, session: session,
                    allowsInitialZoneCreation: allowsInitialZoneCreation, persistence: persistence)
                // CKSyncEngine clears its pending changes when establishing an account.
                // Restore durable work only for this already-verified account; never ACK it.
                if plan.createZone {
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zone))])
                }
                syncEngine.state.add(pendingRecordZoneChanges: plan.records.map { .saveRecord($0) })
            case .fetchedDatabaseChanges(let changes):
                if changes.deletions.contains(where: { $0.zoneID == zone }) { pause(.zoneMissing, session: session) }
            case .fetchedRecordZoneChanges(let changes):
                guard changes.deletions.isEmpty else { pause(.remoteDeletion, session: session); return }
                // Decode/copy each temporary asset while the callback still owns it.
                for modification in changes.modifications {
                    try session.check()
                    let value = try Self.download(modification.record, dataset: session.binding.dataset)
                    try await events.accept(.downloaded([value]))
                }
            case .sentRecordZoneChanges(let changes):
                guard changes.deletedRecordIDs.isEmpty, changes.failedRecordDeletes.isEmpty else {
                    pause(.remoteDeletion, session: session); return
                }
                var acknowledgements: [SyncCloudAcknowledgement] = []
                for saved in changes.savedRecords {
                    guard let (upload, expected) = admitted[saved.recordID], Self.matches(saved, expected) else {
                        throw SyncValidationError.invalidRecord
                    }
                    acknowledgements.append(try upload.acknowledgement())
                }
                // Store precise successes even if other records in this batch failed.
                try await events.accept(.acknowledged(acknowledgements))
                try session.check()
                for saved in changes.savedRecords { admitted.removeValue(forKey: saved.recordID) }
                var unresolved: CKError?
                for failed in changes.failedRecordSaves {
                    try session.check()
                    if failed.error.code == .serverRecordChanged, let server = failed.error.serverRecord {
                        guard let (upload, _) = admitted[failed.record.recordID],
                              server.recordID == failed.record.recordID else { throw SyncValidationError.invalidRecord }
                        // A crash after server save but before our ACK must converge. The
                        // immutable server bytes are verified and durably received first.
                        guard let container = cloudContainer else { throw SyncCloudTransportError.staleSession }
                        try await Self.acceptServerReplay(server, upload: upload, events: events) { id in
                            try await Self.fetchReplayRecord(id: id, session: session,
                                currentAccount: { Self.accountFingerprint(recordID: try await container.userRecordID()) },
                                fetch: { try await syncEngine.database.record(for: $0) })
                        }
                        try session.check()
                        admitted.removeValue(forKey: failed.record.recordID)
                        syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(failed.record.recordID)])
                    } else if unresolved == nil { unresolved = failed.error }
                }
                if let unresolved { pause(reason(for: unresolved), session: session) }
            case .sentDatabaseChanges(let changes):
                if changes.savedZones.contains(where: { $0.zoneID == zone }) {
                    try await events.accept(.zoneSaved)
                    try session.check()
                    allowsInitialZoneCreation = false
                }
                if !changes.deletedZoneIDs.isEmpty || !changes.failedZoneDeletes.isEmpty {
                    pause(.zoneMissing, session: session)
                } else if let failure = changes.failedZoneSaves.first { pause(reason(for: failure.error), session: session) }
            case .didFetchRecordZoneChanges(let fetched):
                if let error = fetched.error { pause(reason(for: error), session: session) }
            default: break
            }
        } catch {
            if session.active { pause(reason(for: error), session: session) }
            else { cancelLater(syncEngine) }
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard engine === syncEngine, let session, session.active else { return nil }
        let zone = CloudRecordCodec.zone(dataset: session.binding.dataset)
        let pending = syncEngine.state.pendingRecordZoneChanges.filter {
            if case .saveRecord(let id) = $0 { return id.zoneID == zone && context.options.scope.contains($0) }
            return false // Physical deletes are never part of this immutable protocol.
        }
        let batch = await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] id in
            await self?.provideRecord(id: id, session: session)
        }
        guard session.active, engine === syncEngine else { return nil }
        return batch
    }

    func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext,
                                 syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        guard engine === syncEngine, let session, session.active else { return .init(scope: .zoneIDs([])) }
        let zone = CloudRecordCodec.zone(dataset: session.binding.dataset)
        return .init(scope: .zoneIDs(context.options.scope.contains(zone) ? [zone] : []))
    }

    private func provideRecord(id: CKRecord.ID, session: SyncCloudSession) async -> CKRecord? {
        do {
            try session.check()
            guard let upload = try await persistence.uploadRecord(id: id, session: session) else { return nil }
            try session.check()
            let record = try upload.makeRecord(dataset: session.binding.dataset)
            guard record.recordID == id else { throw SyncValidationError.invalidIdentity }
            if let (_, previous) = admitted[id], !Self.matches(record, previous) { throw SyncValidationError.identityCollision }
            admitted[id] = (upload, record)
            return record
        } catch {
            if session.active { pause(reason(for: error), session: session) }
            return nil
        }
    }

    /// The first engine account event may be a sign-in to the account independently
    /// verified during start. It is not permission to adopt a different account or to
    /// recreate an established/lost zone. All other account transitions fail closed.
    static func accountChangePlan(_ change: CKSyncEngine.Event.AccountChange.ChangeType,
                                  session: SyncCloudSession, allowsInitialZoneCreation: Bool,
                                  persistence: any SyncCloudPersistence) throws -> (records: [CKRecord.ID], createZone: Bool) {
        try session.check()
        guard case .signIn(let user) = change,
              accountFingerprint(recordID: user) == session.binding.accountHash else {
            throw SyncCloudTransportError.paused(.accountChanged)
        }
        let durableZonePermission = try persistence.permitsPendingZoneCreation(session: session)
        let records = try persistence.pendingRecordIDs(session: session)
        try session.check()
        let zone = CloudRecordCodec.zone(dataset: session.binding.dataset)
        guard records.allSatisfy({ $0.zoneID == zone }) else { throw SyncValidationError.invalidIdentity }
        return (records, allowsInitialZoneCreation && durableZonePermission)
    }

    /// A prior initial-zone save may survive in serialized engine state even after
    /// independent metadata verification confirms the exact zone already exists. Validate
    /// the ENTIRE restored scope first; then retire only those same-zone save intents when
    /// this activation has no creation permission. Record work and all other state survive.
    static func restoredZoneSavesToRemove(recordChanges: [CKSyncEngine.PendingRecordZoneChange],
                                         databaseChanges: [CKSyncEngine.PendingDatabaseChange],
                                         dataset: UUID, createZone: Bool) throws -> [CKSyncEngine.PendingDatabaseChange] {
        try validatePending(recordChanges: recordChanges, databaseChanges: databaseChanges,
                            dataset: dataset, createZone: true)
        return createZone ? [] : databaseChanges
    }

    /// Treat restored engine state as scoped input, not authority to delete or recreate data.
    static func validatePending(recordChanges: [CKSyncEngine.PendingRecordZoneChange],
                                databaseChanges: [CKSyncEngine.PendingDatabaseChange],
                                dataset: UUID, createZone: Bool) throws {
        let zone = CloudRecordCodec.zone(dataset: dataset)
        for change in recordChanges {
            guard case .saveRecord(let id) = change, id.zoneID == zone else {
                throw SyncValidationError.invalidRecord
            }
        }
        for change in databaseChanges {
            guard case .saveZone(let value) = change, createZone, value.zoneID == zone else {
                throw SyncValidationError.invalidRecord
            }
        }
    }

    static func download(_ record: CKRecord, dataset: UUID) throws -> SyncCloudDownloaded {
        switch record.recordType {
        case CloudRecordCodec.mutationType: return .mutation(try CloudRecordCodec.decode(record, dataset: dataset))
        case CloudRecordCodec.chunkType:
            let (descriptor, bytes) = try CloudRecordCodec.decodeChunk(record, dataset: dataset)
            return .payloadChunk(descriptor, bytes)
        case CloudRecordCodec.originalType:
            let (descriptor, bytes) = try CloudRecordCodec.decodeOriginal(record, dataset: dataset)
            return .original(descriptor, bytes)
        default: throw SyncValidationError.invalidRecord
        }
    }

    /// A direct record fetch runs outside the sync engine's account-change event delivery.
    /// Recheck the SAME container's observed account on both sides before admitting bytes.
    /// This detects observable switches; equal samples do not prove absence of an A→B→A
    /// transition. Exact content hashes and the durable session fence remain required.
    static func fetchReplayRecord(id: CKRecord.ID, session: SyncCloudSession,
                                  currentAccount: () async throws -> String,
                                  fetch: (CKRecord.ID) async throws -> CKRecord) async throws -> CKRecord {
        try session.check()
        guard id.zoneID == CloudRecordCodec.zone(dataset: session.binding.dataset) else {
            throw SyncValidationError.invalidIdentity
        }
        let before = try await currentAccount()
        try session.check()
        guard before == session.binding.accountHash else { throw SyncCloudTransportError.paused(.accountChanged) }
        let record = try await fetch(id)
        try session.check()
        guard record.recordID == id else { throw SyncValidationError.invalidIdentity }
        let after = try await currentAccount()
        try session.check()
        guard after == session.binding.accountHash else { throw SyncCloudTransportError.paused(.accountChanged) }
        return record
    }

    /// Exact replay is success only after independently validating downloaded asset
    /// bytes and retaining the inbox. Comparing CKAsset presence alone cannot prove it.
    static func acceptServerReplay(_ server: CKRecord, upload: SyncCloudUpload,
                                   events: SyncCloudDurableEvents,
                                   fetchRecord: ((CKRecord.ID) async throws -> CKRecord)? = nil) async throws {
        try events.session.check()
        let dataset = events.session.binding.dataset
        let expected = try upload.makeRecord(dataset: dataset)
        guard server.recordID == expected.recordID, server.recordType == expected.recordType else {
            throw SyncValidationError.invalidIdentity
        }
        let complete: CKRecord
        switch upload {
        case .mutation: complete = server
        case .payloadChunk, .original:
            // Apple's serverRecordChanged error omits all asset file URLs. Fetch
            // exactly this immutable record on the SAME private database before ACK.
            // https://developer.apple.com/documentation/cloudkit/ckasset/fileurl
            if let fetchRecord { complete = try await fetchRecord(server.recordID) }
            else { complete = server } // Already fetched bytes in cloud-free tests.
        }
        try events.session.check()
        guard complete.recordID == expected.recordID else { throw SyncValidationError.invalidIdentity }
        let downloaded = try download(complete, dataset: dataset)
        try await events.accept(.downloaded([downloaded]))
        guard matches(complete, expected) else {
            try await events.accept(.pause(.conflict))
            throw SyncValidationError.identityCollision
        }
        try await events.accept(.acknowledged([try upload.acknowledgement()]))
    }

    /// Compare every declared immutable field. The acknowledged asset bytes are the immutable
    /// staged lease admitted above; SDK-returned temporary asset paths are not their identity.
    static func matches(_ received: CKRecord, _ expected: CKRecord) -> Bool {
        guard received.recordID == expected.recordID, received.recordType == expected.recordType,
              Set(received.allKeys()) == Set(expected.allKeys()) else { return false }
        for key in expected.allKeys() {
            if expected[key] is CKAsset { guard received[key] is CKAsset else { return false }; continue }
            switch expected[key] {
            case let value as Data: guard received[key] as? Data == value else { return false }
            case let value as String: guard received[key] as? String == value else { return false }
            case let value as NSNumber:
                guard let number = received[key] as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID(),
                      ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"].contains(String(cString: number.objCType)),
                      number == value else { return false }
            default: return false
            }
        }
        return true
    }

    private func reason(for error: Error) -> SyncCloudPauseReason {
        if case SyncCloudTransportError.paused(let reason) = error { return reason }
        if error is SyncValidationError { return .invalidRecord }
        guard let cloud = error as? CKError else { return .persistenceFailure }
        switch cloud.code {
        case .serverRecordChanged: return .conflict
        case .zoneNotFound, .userDeletedZone: return .zoneMissing
        case .unknownItem: return .remoteDeletion
        case .notAuthenticated: return .accountChanged
        default: return .cloudFailure(cloud.code.rawValue)
        }
    }
    private func pause(_ reason: SyncCloudPauseReason, session: SyncCloudSession) {
        guard session.active else { return }
        session.pause(reason); persistence.didPause(reason, binding: session.binding)
        if let engine { cancelLater(engine) }
    }
    private func cancelLater(_ engine: CKSyncEngine) {
        // Never await SDK cancellation inside its serial event callback.
        Task { await engine.cancelOperations() }
    }
}
