import Foundation
import SwiftData
import SyncFoundation

// These rows share the business store. They are deliberately absent from backup v12.
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
                    for dataset in try context.fetch(FetchDescriptor<ProductSyncDataset>()) {
                        dataset.enabled = false; dataset.generation = UUID()
                    }
                    // A restored workspace never inherits old account/token/ack state.
                    for row in try context.fetch(FetchDescriptor<ProductSyncDataset>()) { context.delete(row) }
                    context.insert(ProductSyncDataset())
                } else if origin == .local {
                    let kinds = try dirtyKinds(context)
                    if !kinds.isEmpty {
                        let datasets = try context.fetch(FetchDescriptor<ProductSyncDataset>())
                        guard datasets.count <= 1 else { throw ProductSyncFailure.corruptState }
                        if let dataset = datasets.first, dataset.initialized {
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
                guard !dataset.initialized else { return }
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
        for (key, prior) in states where !prior.deleted {
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
            case is TodoReminderDeviceRecord, is ProductSyncDataset, is ProductSyncObjectState, is ProductSyncMutation,
                 is ProductSyncOutbox, is ProductSyncInbox, is ProductSyncEngineState, is ProductSyncMediaLease: break
            default: throw ProductSyncFailure.unknownModel(String(describing: type(of: model)))
            }
        }
        return kinds
    }
}
