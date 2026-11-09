import Foundation
import SwiftData
import SyncFoundation

// These rows share the business store. They are deliberately absent from backup v12.
/// Added only in V18. The V17 entities below retain their original schema unchanged.
/// This singleton routes local capture and cloud callbacks; archived datasets remain intact.
@Model final class ProductSyncSelection {
    @Attribute(.unique) var key: String
    var developmentDatasetID: UUID?
    var productionDatasetID: UUID?
    var environment: String
    var activeDatasetID: UUID? {
        switch CloudEnvironment(rawValue: environment) {
        case .development: return developmentDatasetID
        case .production: return productionDatasetID
        case nil: return nil
        }
    }
    init(environment: CloudEnvironment, activeDatasetID: UUID? = nil) {
        key = "active"; self.environment = environment.rawValue
        developmentDatasetID = environment == .development ? activeDatasetID : nil
        productionDatasetID = environment == .production ? activeDatasetID : nil
    }
    fileprivate func select(_ id: UUID, for environment: CloudEnvironment) {
        switch environment {
        case .development: developmentDatasetID = id
        case .production: productionDatasetID = id
        }
    }
}

/// Call mutations inside the caller's StorePublication lease and save them together with
/// the owning transaction. These methods never save, contact CloudKit or erase old metadata.
enum ProductSyncStoreSelection {
    static func defaultDatasetID(for environment: CloudEnvironment) -> UUID {
        switch environment {
        case .development: return UUID(uuidString: "EAB541A0-45A1-43E4-9009-4E6F316EA001")!
        case .production: return UUID(uuidString: "EAB541A0-45A1-43E4-9009-4E6F316EA002")!
        }
    }
    private static func selection(in context: ModelContext) throws -> ProductSyncSelection? {
        let rows = try context.fetch(FetchDescriptor<ProductSyncSelection>())
        guard rows.count <= 1 else { throw ProductSyncFailure.corruptState }
        if let row = rows.first {
            guard row.key == "active", CloudEnvironment(rawValue: row.environment) != nil else { throw ProductSyncFailure.corruptState }
            let datasets = try context.fetch(FetchDescriptor<ProductSyncDataset>())
            // Validate both realms, including the inactive pointer. Never infer a replacement
            // from retained headers: restore deliberately leaves older identities archived.
            for (id, environment) in [(row.developmentDatasetID, CloudEnvironment.development),
                                      (row.productionDatasetID, CloudEnvironment.production)] {
                guard let id else { continue }
                let matches = datasets.filter { $0.id == id }
                guard matches.count == 1, matches[0].environment == environment.rawValue else {
                    throw ProductSyncFailure.corruptState
                }
            }
        }
        return rows.first
    }
    static func selectedDataset(in context: ModelContext) throws -> ProductSyncDataset? {
        if let selector = try selection(in: context) {
            // Explicitly unselected (e.g. first Production launch) must not fall back to Development.
            guard let id = selector.activeDatasetID else { return nil }
            let rows = try context.fetch(FetchDescriptor<ProductSyncDataset>(predicate: #Predicate { $0.id == id }))
            guard rows.count == 1, rows[0].environment == selector.environment else { throw ProductSyncFailure.corruptState }
            return rows[0]
        }
        let legacy = try context.fetch(FetchDescriptor<ProductSyncDataset>())
        guard legacy.count <= 1 else { throw ProductSyncFailure.corruptState }
        if let row = legacy.first, CloudEnvironment(rawValue: row.environment) == nil { throw ProductSyncFailure.corruptState }
        return legacy.first
    }
    static func selectedEnvironment(in context: ModelContext) throws -> CloudEnvironment? {
        if let selector = try selection(in: context) { return CloudEnvironment(rawValue: selector.environment) }
        return try selectedDataset(in: context).flatMap { CloudEnvironment(rawValue: $0.environment) }
    }
    static func prepare(context: ModelContext, environment: CloudEnvironment) throws {
        let existing = try selection(in: context)
        let current = try selectedDataset(in: context) // Validate before changing any row.
        let rows = try context.fetch(FetchDescriptor<ProductSyncDataset>())
        let changesEnvironment = (existing?.environment ?? current?.environment).map { $0 != environment.rawValue } ?? false
        if let existing {
            if changesEnvironment {
                for row in rows { row.enabled = false; row.generation = UUID() }
                existing.environment = environment.rawValue
            } else {
                for row in rows where row.id != existing.activeDatasetID && row.enabled {
                    row.enabled = false; row.generation = UUID()
                }
            }
        } else {
            if changesEnvironment {
                for row in rows { row.enabled = false; row.generation = UUID() }
            }
            let selector = ProductSyncSelection(environment: environment)
            if let current, let oldEnvironment = CloudEnvironment(rawValue: current.environment) {
                selector.select(current.id, for: oldEnvironment)
            }
            context.insert(selector)
        }
    }
    static func activate(_ newDataset: ProductSyncDataset, in context: ModelContext) throws {
        guard let selector = try selection(in: context),
              newDataset.environment == selector.environment else { throw ProductSyncFailure.corruptState }
        let rows = try context.fetch(FetchDescriptor<ProductSyncDataset>())
        // Do not let SwiftData uniqueness upsert silently replace a retained dataset header.
        guard !rows.contains(where: { $0.id == newDataset.id }) else { throw ProductSyncFailure.corruptState }
        for row in rows where row.enabled { row.enabled = false; row.generation = UUID() }
        context.insert(newDataset)
        selector.select(newDataset.id, for: CloudEnvironment(rawValue: selector.environment)!)
    }
    static func isolateRestoredWorkspace(in context: ModelContext) throws {
        let environment = try selectedEnvironment(in: context) ?? .development
        try prepare(context: context, environment: environment)
        for row in try context.fetch(FetchDescriptor<ProductSyncDataset>()) {
            row.enabled = false; row.generation = UUID()
        }
        let fresh = ProductSyncDataset(); fresh.environment = environment.rawValue
        try activate(fresh, in: context)
    }
}

@Model final class ProductSyncDataset {
    @Attribute(.unique) var id: UUID
    var accountHash: String?
    var environment: String
    var generation: UUID
    var enabled: Bool
    var initialized: Bool
    var zoneEstablished: Bool
    var zoneCreationAttempted: Bool
    var zoneLost: Bool
    var needsReconciliation: Bool
    var blockedReason: String?
    var lastSuccess: Date?
    init(id: UUID = UUID()) {
        self.id = id; environment = "development"; generation = UUID()
        enabled = false; initialized = false; zoneEstablished = false; zoneCreationAttempted = false; zoneLost = false; needsReconciliation = false
    }
}
@Model final class ProductSyncObjectState {
    @Attribute(.unique) var key: String
    var dataset: UUID
    var kind: String
    var businessID: UUID
    var heads: Data
    var fingerprint: String
    var deleted: Bool
    var projectionState: String
    init(dataset: UUID, object: SyncDomainKey, heads: [UUID], fingerprint: String, deleted: Bool) throws {
        self.dataset = dataset; kind = object.kind.rawValue; businessID = object.id
        key = Self.key(dataset: dataset, object: object)
        self.heads = try JSONEncoder().encode(heads); self.fingerprint = fingerprint; self.deleted = deleted
        projectionState = deleted ? "deleted" : "ready"
    }
    static func key(dataset: UUID, object: SyncDomainKey) -> String {
        dataset.uuidString.lowercased() + "/" + object.kind.rawValue + "/" + object.id.uuidString.lowercased()
    }
}
@Model final class ProductSyncMutation {
    @Attribute(.unique) var id: UUID
    var dataset: UUID
    var transactionID: UUID
    var manifest: Data
    var payload: Data?
    var manifestHash: String
    var createdAt: Date
    var local: Bool
    init(_ manifest: MutationManifest, payload: Data?, transactionID: UUID, local: Bool) throws {
        let bytes = try manifest.encoded()
        id = manifest.mutation; dataset = manifest.dataset; self.manifest = bytes
        self.payload = payload; manifestHash = syncDigest(bytes)
        self.transactionID = transactionID; self.local = local; createdAt = Date()
    }
}
@Model final class ProductSyncOutbox {
    @Attribute(.unique) var mutationID: UUID
    var dataset: UUID
    var manifestHash: String
    var acknowledgedRecords: Data
    var completed: Bool
    init(_ mutation: ProductSyncMutation) {
        mutationID = mutation.id; dataset = mutation.dataset; manifestHash = mutation.manifestHash
        acknowledgedRecords = Data("[]".utf8); completed = false
    }
}
@Model final class ProductSyncInbox {
    @Attribute(.unique) var key: String
    var dataset: UUID
    var recordName: String
    var recordType: String
    var bytes: Data
    var sha256: String
    var quarantinedReason: String?
    init(dataset: UUID, recordName: String, recordType: String, bytes: Data) {
        self.dataset = dataset; self.recordName = recordName; self.recordType = recordType; self.bytes = bytes
        sha256 = syncDigest(bytes); key = dataset.uuidString.lowercased() + "/" + recordName
    }
}
@Model final class ProductSyncEngineState {
    @Attribute(.unique) var key: String
    var bytes: Data
    init(key: String, bytes: Data) { self.key = key; self.bytes = bytes }
}
@Model final class ProductSyncMediaLease {
    @Attribute(.unique) var key: String
    var dataset: UUID
    var mutationID: UUID
    var originalID: UUID
    var sha256: String
    var byteCount: Int64
    var contentType: String
    // Never wire this path. It is rooted at this installation's media root.
    var relativePath: String
    init(dataset: UUID, mutationID: UUID, media: SyncOriginalDescriptor, relativePath: String) {
        self.dataset = dataset; self.mutationID = mutationID; originalID = media.id
        sha256 = media.sha256; byteCount = media.byteCount; contentType = media.contentType
        self.relativePath = relativePath
        key = dataset.uuidString.lowercased() + "/" + mutationID.uuidString.lowercased() + "/" + media.id.uuidString.lowercased()
    }
}

enum ProductSyncFailure: Error { case corruptState, unknownModel(String), unresolvedConflict, accountChanged, disabled }
enum ProductSyncSaveOrigin { case local, remoteProjection, migrationBaseline, restoreNewDataset }

/// Synchronous on the caller's context executor, inside the existing store publication lease.
/// The only save publishes business edits, immutable revisions and their outbox atomically.
enum ProductSyncCommit {
    static func save(_ context: ModelContext, origin: ProductSyncSaveOrigin = .local,
                     persist: (ModelContext) throws -> Void = { try $0.save() }) throws {
        try StorePublication.performCommit(at: StorePublication.root(for: context.container)) {
            do {
                context.autosaveEnabled = false
                if origin == .restoreNewDataset {
                    // Retain old headers, account binding, immutable history and acknowledgements.
                    // Only the active pointer moves to a new unbound, disabled random dataset.
                    try ProductSyncStoreSelection.isolateRestoredWorkspace(in: context)
                } else if origin == .local {
                    let kinds = try dirtyKinds(context)
                    if !kinds.isEmpty {
                        if let dataset = try ProductSyncStoreSelection.selectedDataset(in: context), dataset.initialized {
                            do { try stage(context, dataset: dataset, kinds: kinds) }
                            catch ProductSyncFailure.unresolvedConflict { throw ProductSyncFailure.unresolvedConflict }
                            catch {
                                // Domain validation has already accepted the local edit. A wire/asset
                                // limit must not destroy it. Pause the whole sender until a full diff
                                // can atomically reconcile the durable local facts with known heads.
                                dataset.needsReconciliation = true
                                dataset.blockedReason = "Local changes saved; synchronization requires reconciliation (" + String(describing: type(of: error)) + ")."
                            }
                        }
                    }
                }
                try persist(context)
                if origin == .local {
                    NotificationCenter.default.post(name: .productSyncLocalCommit, object: nil,
                        userInfo: ["root": StorePublication.key(for: StorePublication.root(for: context.container))])
                }
            } catch { context.rollback(); throw error }
        }
    }

    /// Called only by explicit product enable, before any transport is started.
    static func initialize(_ context: ModelContext, dataset: ProductSyncDataset) throws {
        try StorePublication.performCommit(at: StorePublication.root(for: context.container)) {
            do {
                // Explicit Enable also reconciles facts changed while another environment
                // was selected. Stable fingerprints add nothing; changed facts descend from
                // this dataset's retained heads without rewriting its acknowledgements.
                try stage(context, dataset: dataset, kinds: Set(SyncDomainKind.allCases))
                dataset.initialized = true
                try context.save()
            } catch { context.rollback(); throw error }
        }
    }

    private static func stage(_ context: ModelContext, dataset: ProductSyncDataset, kinds: Set<SyncDomainKind>) throws {
        let documents = try SyncDomainCodec.capture(context: context, kinds: kinds)
        let datasetID = dataset.id
        let old = try context.fetch(FetchDescriptor<ProductSyncObjectState>(predicate: #Predicate { $0.dataset == datasetID }))
            .filter { kinds.contains(SyncDomainKind(rawValue: $0.kind) ?? .entry) }
        var states = [SyncDomainKey: ProductSyncObjectState]()
        for state in old {
            guard let kind = SyncDomainKind(rawValue: state.kind) else { throw ProductSyncFailure.corruptState }
            let key = SyncDomainKey(kind: kind, id: state.businessID)
            guard states.updateValue(state, forKey: key) == nil else { throw ProductSyncFailure.corruptState }
        }
        let transaction = UUID()
        var actions: [() -> Void] = []
        for document in documents {
            let bytes = try SyncDomainCodec.encode(document)
            let hash = syncDigest(bytes)
            let prior = states.removeValue(forKey: document.key)
            if prior?.fingerprint == hash && prior?.deleted == false { continue }
            actions.append(try prepare(context, dataset: dataset, key: document.key, bytes: bytes, document: document,
                       prior: prior, transaction: transaction))
        }
        // Only a fingerprint installed in the business store is a deletion baseline.
        // Remote pending/conflict heads can exist before this device has ever published
        // the object. Its absence is not a user deletion (including while sync is off).
        for (key, prior) in states where !prior.deleted && prior.fingerprint != "unpublished" {
            actions.append(try prepare(context, dataset: dataset, key: key, bytes: nil, document: nil, prior: prior, transaction: transaction))
        }
        // No metadata changes occur until the entire transaction is representable.
        actions.forEach { $0() }
    }

    private static func prepare(_ context: ModelContext, dataset: ProductSyncDataset, key: SyncDomainKey,
                               bytes: Data?, document: SyncDomainDocument?, prior: ProductSyncObjectState?, transaction: UUID) throws -> () -> Void {
        let parents = try prior.map { try JSONDecoder().decode([UUID].self, from: $0.heads) } ?? []
        // Normal editing must not implicitly resolve a concurrent conflict.
        guard parents.count <= 1, prior == nil || ["ready", "deleted"].contains(prior!.projectionState) else { throw ProductSyncFailure.unresolvedConflict }
        let payload = try bytes.map { try PayloadManifest(bytes: $0) }
        let manifest = try MutationManifest(dataset: dataset.id, mutation: UUID(),
            object: SyncObject(kind: key.kind.rawValue, id: key.id), parents: parents,
            dependencies: try document?.dependencies.map { try SyncObject(kind: $0.kind.rawValue, id: $0.id) } ?? [],
            deleted: bytes == nil, payload: payload,
            originals: document?.media.map { OriginalReference(id: $0.id, asset: AssetDescriptor(sha256: $0.sha256, byteCount: Int($0.byteCount))) } ?? [])
        let mutation = try ProductSyncMutation(manifest, payload: bytes, transactionID: transaction, local: true)
        let outbox = ProductSyncOutbox(mutation)
        let hash = bytes.map(syncDigest) ?? "deleted"
        let newHeads = try JSONEncoder().encode([mutation.id])
        let newState = try ProductSyncObjectState(dataset: dataset.id, object: key, heads: [mutation.id], fingerprint: hash, deleted: bytes == nil)
        let root = StorePublication.root(for: context.container)
        let assets = SyncAssetStore(root: root)
        let mediaStore = MediaStore(rootURL: root)
        let leases = try (document?.media ?? []).map { media in
            _ = try assets.retainOriginal(media, mediaStore: mediaStore)
            return ProductSyncMediaLease(dataset: dataset.id, mutationID: mutation.id, media: media,
                relativePath: "Sync/Assets/" + media.sha256)
        }
        return {
            context.insert(mutation); context.insert(outbox)
            if let prior {
                prior.heads = newHeads; prior.fingerprint = hash; prior.deleted = bytes == nil
            } else { context.insert(newState) }
            leases.forEach { context.insert($0) }
        }
    }

    static func dirtyKinds(_ context: ModelContext) throws -> Set<SyncDomainKind> {
        var kinds = Set<SyncDomainKind>()
        for model in context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray {
            switch model {
            case is Entry, is ImageMetadata, is EntryExternalSource, is EntryPin, is EntryFollowUp: kinds.insert(.entry)
            case is Tag: kinds.insert(.tag)
            case is ObjectLink: kinds.insert(.objectLink)
            case is Habit, is HabitConfiguration, is HabitPlanRevision, is HabitLifecycleEvent: kinds.insert(.habit)
            case is HabitLog, is HabitLogDayMetadata: kinds.insert(.habitLog)
            case is Goal, is GoalLifecycleEvent: kinds.insert(.goal)
            case is WeightRecord: kinds.insert(.weight)
            case is WeeklyReview: kinds.insert(.weeklyReview)
            case is TodoList: kinds.insert(.todoList)
            case is TodoTask, is TodoTaskEvent, is TodoTaskSource, is TodoSeries, is TodoSeriesPreferences, is TodoReminderIntent:
                kinds.formUnion([.todoTask, .todoSeries, .importantDayTodoLink])
            case is ImportantDay, is ImportantDayCover: kinds.insert(.importantDay)
            case is ImportantDayEntryLink: kinds.insert(.importantDayEntryLink)
            case is ImportantDayTodoLink: kinds.insert(.importantDayTodoLink)
            case is SleepRecord: kinds.insert(.sleepRecord)
            case is SleepGoalRule: kinds.insert(.sleepGoal)
            case is CaptureImportReceipt: kinds.insert(.captureReceipt)
            case is InvestmentParticipant: kinds.insert(.investmentParticipant)
            case is InvestmentActivity: kinds.insert(.investmentActivity)
            case is InvestmentSession, is InvestmentOperation: kinds.insert(.investmentRecord)
            case is BodyReferenceSettings: kinds.insert(.bodyReference)
            case is NetWorthItem: kinds.insert(.netWorthItem)
            case is NetWorthSnapshot: kinds.insert(.netWorthSnapshot)
            case is TodoReminderDeviceRecord, is ProductSyncSelection, is ProductSyncDataset, is ProductSyncObjectState, is ProductSyncMutation,
                 is ProductSyncOutbox, is ProductSyncInbox, is ProductSyncEngineState, is ProductSyncMediaLease: break
            default: throw ProductSyncFailure.unknownModel(String(describing: type(of: model)))
            }
        }
        return kinds
    }
}
