import Foundation
import SwiftData
import CloudKit
import Combine
import UIKit
import SyncFoundation

extension Notification.Name { static let productSyncLocalCommit = Notification.Name("ProductSyncLocalCommit") }

/// One coordinator per open store. It owns no CloudKit object until explicit opt-in.
@MainActor final class SyncProductCoordinator: ObservableObject, SyncCloudPersistence {
    static let containerID = "iCloud.com.yocruzer.PersonalGrowthOS"
    // CloudKit private databases already isolate accounts. A stable default workspace identity
    // lets a second installation join without an extra mutable root record/schema type.
    static let defaultDatasetID = UUID(uuidString: "EAB541A0-45A1-43E4-9009-4E6F316EA001")!
    let container: ModelContainer
    let mediaRoot: URL
    @Published private(set) var status = "iCloud sync is off"
    @Published private(set) var enabled = false
    @Published private(set) var busy = false
    @Published private(set) var requiresAttention = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var conflicts: [SyncConflictSummary] = []
    private var activation = UUID()
    private var driver: SyncCloudTransport?
    private var wakeTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private let environment: CloudEnvironment?
    private let automaticSync: Bool

    init(container: ModelContainer, mediaRoot: URL, environment: CloudEnvironment? = nil, automaticSync: Bool = true) {
        self.container = container; self.mediaRoot = mediaRoot; self.automaticSync = automaticSync
        self.environment = environment ?? SyncBuildConfiguration.environment()
        refreshStatus()
        observer = NotificationCenter.default.addObserver(forName: .productSyncLocalCommit, object: nil, queue: .main) { [weak self] notification in
            let path = notification.userInfo?["root"] as? String
            Task { @MainActor [weak self] in
                guard let self, path == StorePublication.key(for: self.mediaRoot) else { return }
                self.refreshStatus(); self.scheduleSync()
            }
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) }; wakeTask?.cancel() }

    private func dataset(in context: ModelContext) throws -> ProductSyncDataset? {
        let rows = try context.fetch(FetchDescriptor<ProductSyncDataset>())
        guard rows.count <= 1 else { throw ProductSyncFailure.corruptState }
        return rows.first
    }
    func refreshStatus() {
        do {
            let context = ModelContext(container)
            guard let dataset = try dataset(in: context) else { enabled = false; pendingCount = 0; return }
            enabled = dataset.enabled
            requiresAttention = dataset.needsReconciliation || dataset.blockedReason != nil
            let id = dataset.id
            conflicts = try context.fetch(FetchDescriptor<ProductSyncObjectState>(predicate: #Predicate { $0.dataset == id }))
                .filter { $0.projectionState == "conflict" }.compactMap { state in
                    guard let kind = SyncDomainKind(rawValue: state.kind), let heads = try? JSONDecoder().decode([UUID].self, from: state.heads) else { return nil }
                    return SyncConflictSummary(key: .init(kind: kind, id: state.businessID), heads: heads)
                }
            pendingCount = try context.fetch(FetchDescriptor<ProductSyncOutbox>(predicate: #Predicate { $0.dataset == id && !$0.completed })).count
            if let reason = dataset.blockedReason { status = reason }
            else if !enabled { status = "iCloud sync is off" }
            else { status = pendingCount == 0 ? "Waiting to check iCloud" : "\(pendingCount) local revisions waiting" }
        } catch { status = "Sync metadata needs attention; local data is preserved." }
    }

    /// UI consent explicitly covers uploading existing local data to this account's private database.
    func enable() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let attempt = UUID(); activation = attempt
        do {
            guard let environment else { throw SyncCloudTransportError.paused(.environmentMismatch) }
            let cloud = CKContainer(identifier: Self.containerID)
            let accountStatus = try await cloud.accountStatus()
            guard activation == attempt else { throw SyncCloudTransportError.staleSession }
            guard accountStatus == .available else { throw SyncCloudTransportError.paused(.accountUnavailable) }
            let account = SyncCloudTransport.accountFingerprint(recordID: try await cloud.userRecordID())
            guard activation == attempt else { throw SyncCloudTransportError.staleSession }
            let context = ModelContext(container); context.autosaveEnabled = false
            let binding = try StorePublication.perform(at: mediaRoot) {
                guard !container.mainContext.hasChanges else { throw StorePublicationFailure.busy }
                let value: ProductSyncDataset
                if let existing = try dataset(in: context) { value = existing }
                else { value = ProductSyncDataset(id: Self.defaultDatasetID); context.insert(value) }
                if let prior = value.accountHash {
                    guard prior == account, value.environment == environment.rawValue else { throw ProductSyncFailure.accountChanged }
                }
                guard !value.needsReconciliation, !value.zoneLost else { throw ProductSyncFailure.corruptState }
                value.accountHash = account; value.environment = environment.rawValue
                value.generation = UUID(); value.enabled = true; value.blockedReason = nil
                try ProductSyncCommit.initialize(context, dataset: value)
                try context.save()
                return try SyncBinding(container: Self.containerID, environment: environment, accountHash: account, dataset: value.id, generation: value.generation)
            }
            if let driver { await driver.stop() }
            guard activation == attempt else { throw SyncCloudTransportError.staleSession }
            let transport = SyncCloudTransport(persistence: self); driver = transport
            var value = try requireDataset(binding)
            if !value.zoneEstablished && value.zoneCreationAttempted {
                // A prior attempted creation is not permission to recreate a deleted zone.
                // Read only the known zone metadata; absent/unknown stays paused.
                _ = try await cloud.privateCloudDatabase.recordZone(for: CloudRecordCodec.zone(dataset: binding.dataset))
                guard activation == attempt else { throw SyncCloudTransportError.staleSession }
                try StorePublication.perform(at: mediaRoot) {
                    let write = ModelContext(container); let current = try requireDataset(binding, context: write)
                    current.zoneEstablished = true; try write.save()
                }
                value = try requireDataset(binding)
            }
            let createZone = !value.zoneEstablished
            if createZone {
                try StorePublication.perform(at: mediaRoot) {
                    let write = ModelContext(container); let current = try requireDataset(binding, context: write)
                    guard !current.zoneCreationAttempted, !current.zoneLost else { throw ProductSyncFailure.corruptState }
                    current.zoneCreationAttempted = true; try write.save()
                }
            }
            try await transport.start(binding: binding, signedEnvironment: environment, createZone: createZone)
            guard activation == attempt else { throw SyncCloudTransportError.staleSession }
            enabled = true
            if automaticSync { UIApplication.shared.registerForRemoteNotifications() }
            try await transport.synchronize()
            guard let session = transport.session else { throw SyncCloudTransportError.staleSession }
            try project(session)
            try markSuccessful(binding)
        } catch { refreshStatus(); requiresAttention = true; status = message(error) }
    }
    func disable() async {
        activation = UUID(); wakeTask?.cancel(); wakeTask = nil
        driver?.session?.invalidate()
        do {
            try StorePublication.perform(at: mediaRoot) {
                let context = ModelContext(container)
                if let value = try dataset(in: context) { value.enabled = false; value.generation = UUID(); try context.save() }
            }
        } catch { status = message(error); return }
        if let driver { await driver.stop() }; driver = nil
        enabled = false; requiresAttention = false; status = "iCloud sync is off. Local data and pending revisions are kept."
    }
    func synchronize() async {
        guard !busy, enabled else { return }
        guard let driver, let session = driver.session, session.active else { await enable(); return }
        busy = true; defer { busy = false }
        do { try project(session); try await driver.synchronize(); try project(session); try markSuccessful(session.binding) }
        catch { refreshStatus(); requiresAttention = true; status = message(error) }
    }
    var canAutomaticallySync: Bool { automaticSync && enabled && !requiresAttention && !busy }
    func resumeIfEnabled() async { if canAutomaticallySync { await synchronize() } }
    private func scheduleSync() {
        guard canAutomaticallySync else { return }; wakeTask?.cancel()
        wakeTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 1_000_000_000); try Task.checkCancellation() }
            catch { return }
            await self?.synchronize()
        }
    }
    private func message(_ error: Error) -> String {
        if error is StorePublicationFailure { return "Save or close the current edit, then sync again." }
        if case ProductSyncFailure.accountChanged = error { return "This workspace belongs to a different iCloud account. Sync is paused; local data is kept." }
        return "Sync paused (\(String(describing: error))). Local data and pending changes are kept."
    }
    private func requireDataset(_ binding: SyncBinding, context: ModelContext? = nil) throws -> ProductSyncDataset {
        let context = context ?? ModelContext(container)
        guard binding.container == Self.containerID, let value = try dataset(in: context), value.id == binding.dataset,
              value.accountHash == binding.accountHash, value.environment == binding.environment.rawValue,
              value.generation == binding.generation, value.enabled, !value.needsReconciliation else { throw SyncCloudTransportError.staleSession }
        return value
    }
    private func checked(_ session: SyncCloudSession, context: ModelContext) throws -> ProductSyncDataset {
        try session.check(); return try requireDataset(session.binding, context: context)
    }
    private func stateKey(_ binding: SyncBinding) -> String {
        [binding.container, binding.environment.rawValue, binding.accountHash, binding.dataset.uuidString.lowercased()].joined(separator: "/")
    }
    func loadEngineState(binding: SyncBinding) throws -> Data? {
        let context = ModelContext(container); _ = try requireDataset(binding, context: context)
        let key = stateKey(binding)
        return try context.fetch(FetchDescriptor<ProductSyncEngineState>(predicate: #Predicate { $0.key == key })).first?.bytes
    }
    func pendingRecordIDs(session: SyncCloudSession) throws -> [CKRecord.ID] {
        let context = ModelContext(container); _ = try checked(session, context: context)
        let dataset = session.binding.dataset
        let queue = try context.fetch(FetchDescriptor<ProductSyncOutbox>(predicate: #Predicate { $0.dataset == dataset && !$0.completed }))
        let mutations = try context.fetch(FetchDescriptor<ProductSyncMutation>(predicate: #Predicate { $0.dataset == dataset }))
        let byID = Dictionary(uniqueKeysWithValues: mutations.map { ($0.id, $0) })
        var pending = Set<String>()
        for item in queue {
            guard let mutation = byID[item.mutationID], mutation.manifestHash == item.manifestHash else { throw ProductSyncFailure.corruptState }
            let manifest = try MutationManifest.decode(mutation.manifest)
            let ack = Set(try JSONDecoder().decode([String].self, from: item.acknowledgedRecords))
            pending.formUnion(recordNames(manifest).subtracting(ack))
        }
        return pending.sorted().map { CKRecord.ID(recordName: $0, zoneID: CloudRecordCodec.zone(dataset: dataset)) }
    }
    private func recordNames(_ manifest: MutationManifest) -> Set<String> {
        var names: Set<String> = [CloudRecordCodec.mutationID(manifest.mutation, dataset: manifest.dataset).recordName]
        names.formUnion(manifest.payload?.chunks.map { "chunk-" + $0.sha256 } ?? [])
        names.formUnion(manifest.originals.map { "original-" + $0.asset.sha256 }); return names
    }
    func uploadRecord(id: CKRecord.ID, session: SyncCloudSession) async throws -> SyncCloudUpload? {
        let context = ModelContext(container); _ = try checked(session, context: context)
        guard id.zoneID == CloudRecordCodec.zone(dataset: session.binding.dataset) else { throw SyncValidationError.invalidIdentity }
        let dataset = session.binding.dataset
        let mutations = try context.fetch(FetchDescriptor<ProductSyncMutation>(predicate: #Predicate { $0.dataset == dataset }))
        let assets = SyncAssetStore(root: mediaRoot)
        for mutation in mutations {
            let manifest = try MutationManifest.decode(mutation.manifest)
            if id == CloudRecordCodec.mutationID(mutation.id, dataset: dataset) { return .mutation(manifest) }
            for (index, chunk) in (manifest.payload?.chunks ?? []).enumerated() where id.recordName == "chunk-" + chunk.sha256 {
                guard let payload = mutation.payload else { throw SyncValidationError.missingAsset }
                try manifest.payload?.verify(bytes: payload)
                let start = index * SyncLimits.chunkBytes
                let bytes = payload.subdata(in: start..<min(start + chunk.byteCount, payload.count))
                return .payloadChunk(chunk, try assets.retain(bytes, as: chunk))
            }
            for original in manifest.originals where id.recordName == "original-" + original.asset.sha256 {
                _ = try assets.read(original.asset)
                return .original(original.asset, try assets.url(for: original.asset))
            }
        }
        return nil
    }
    func durableInbox(_ records: [SyncCloudDownloaded], session: SyncCloudSession) async throws {
        try StorePublication.perform(at: mediaRoot) {
            let context = ModelContext(container); context.autosaveEnabled = false
            _ = try checked(session, context: context)
            do {
                for record in records {
                    let name: String, type: String, bytes: Data
                    switch record {
                    case .mutation(let manifest):
                        guard manifest.dataset == session.binding.dataset else { throw SyncValidationError.invalidIdentity }
                        name = "mutation-" + manifest.mutation.uuidString.lowercased(); type = CloudRecordCodec.mutationType; bytes = try manifest.encoded()
                        let id = manifest.mutation
                        if let old = try context.fetch(FetchDescriptor<ProductSyncMutation>(predicate: #Predicate { $0.id == id })).first {
                            try manifest.verifyReplay(of: old.manifest)
                        }
                    case .payloadChunk(let descriptor, let content):
                        _ = try SyncAssetStore(root: mediaRoot).retain(content, as: descriptor)
                        name = "chunk-" + descriptor.sha256; type = CloudRecordCodec.chunkType; bytes = content
                    case .original(let descriptor, let content):
                        _ = try SyncAssetStore(root: mediaRoot).retain(content, as: descriptor)
                        name = "original-" + descriptor.sha256; type = CloudRecordCodec.originalType; bytes = content
                    }
                    let key = session.binding.dataset.uuidString.lowercased() + "/" + name
                    if let previous = try context.fetch(FetchDescriptor<ProductSyncInbox>(predicate: #Predicate { $0.key == key })).first {
                        guard previous.recordType == type, previous.bytes == bytes else { throw SyncValidationError.identityCollision }
                    } else { context.insert(ProductSyncInbox(dataset: session.binding.dataset, recordName: name, recordType: type, bytes: bytes)) }
                }
                _ = try checked(session, context: context)
                try context.save()
            } catch { context.rollback(); throw error }
        }
        try project(session)
    }
    func acknowledge(_ records: [SyncCloudAcknowledgement], session: SyncCloudSession) async throws {
        try StorePublication.perform(at: mediaRoot) {
            let context = ModelContext(container); _ = try checked(session, context: context)
            let dataset = session.binding.dataset
            let queue = try context.fetch(FetchDescriptor<ProductSyncOutbox>(predicate: #Predicate { $0.dataset == dataset && !$0.completed }))
            for item in queue {
                let id = item.mutationID
                guard let mutation = try context.fetch(FetchDescriptor<ProductSyncMutation>(predicate: #Predicate { $0.id == id })).first,
                      mutation.manifestHash == item.manifestHash else { throw ProductSyncFailure.corruptState }
                let manifest = try MutationManifest.decode(mutation.manifest)
                var ack = Set(try JSONDecoder().decode([String].self, from: item.acknowledgedRecords))
                for record in records {
                    switch record {
                    case .mutation(let acknowledged, let hash):
                        if acknowledged == id && hash == item.manifestHash { ack.insert("mutation-" + id.uuidString.lowercased()) }
                    case .payloadChunk(let chunk):
                        if manifest.payload?.chunks.contains(chunk) == true { ack.insert("chunk-" + chunk.sha256) }
                    case .original(let original):
                        if manifest.originals.contains(where: { $0.asset == original }) { ack.insert("original-" + original.sha256) }
                    }
                }
                item.acknowledgedRecords = try JSONEncoder().encode(ack.sorted())
                item.completed = recordNames(manifest).isSubset(of: ack)
            }
            _ = try checked(session, context: context); try context.save()
        }
        refreshStatus()
    }
    func saveEngineState(_ bytes: Data, session: SyncCloudSession) async throws {
        try StorePublication.perform(at: mediaRoot) {
            let context = ModelContext(container); _ = try checked(session, context: context)
            let key = stateKey(session.binding)
            if let row = try context.fetch(FetchDescriptor<ProductSyncEngineState>(predicate: #Predicate { $0.key == key })).first { row.bytes = bytes }
            else { context.insert(ProductSyncEngineState(key: key, bytes: bytes)) }
            _ = try checked(session, context: context); try context.save()
        }
    }
    func didSaveZone(session: SyncCloudSession) async throws {
        try StorePublication.perform(at: mediaRoot) {
            let context = ModelContext(container); let value = try checked(session, context: context)
            value.zoneEstablished = true; try session.check(); try context.save()
        }
    }
    func didPause(_ reason: SyncCloudPauseReason, binding: SyncBinding) {
        var accepted = false
        do {
            try StorePublication.perform(at: mediaRoot) {
                let context = ModelContext(container)
                guard binding.container == Self.containerID, let value = try dataset(in: context), value.id == binding.dataset,
                      value.generation == binding.generation, value.accountHash == binding.accountHash,
                      value.environment == binding.environment.rawValue else { return }
                accepted = true
                if reason == .zoneMissing { value.zoneLost = true }
                if [.zoneMissing, .remoteDeletion, .invalidRecord, .conflict].contains(reason) { value.needsReconciliation = true }
                value.blockedReason = "Sync paused (\(reason)); local data and pending revisions are kept."
                try context.save()
            }
        } catch { /* A matching session's failure remains visible even when disk is unavailable. */ }
        if accepted { requiresAttention = true; status = "Sync paused (\(reason)); local data and pending revisions are kept." }
    }
    private func markSuccessful(_ binding: SyncBinding) throws {
        try StorePublication.perform(at: mediaRoot) {
            let context = ModelContext(container); let value = try requireDataset(binding, context: context)
            value.lastSuccess = Date(); try context.save()
        }
        refreshStatus()
        if conflicts.isEmpty, try dataset(in: ModelContext(container))?.blockedReason == nil { status = pendingCount == 0 ? "Latest sync completed" : "\(pendingCount) revisions still waiting" }
    }
}

struct SyncConflictSummary: Identifiable {
    let key: SyncDomainKey
    let heads: [UUID]
    var id: String { key.kind.rawValue + "/" + key.id.uuidString }
}

extension SyncProductCoordinator {
    private func project(_ session: SyncCloudSession) throws {
        try StorePublication.perform(at: mediaRoot) {
            let context = ModelContext(container); context.autosaveEnabled = false
            let value = try checked(session, context: context)
            guard !container.mainContext.hasChanges else {
                value.blockedReason = "Downloaded changes are not yet applied. Finish the current edit, then sync again."
                try context.save(); status = value.blockedReason!
                return
            }
            let datasetID = value.id
            let inbox = try context.fetch(FetchDescriptor<ProductSyncInbox>(predicate: #Predicate { $0.dataset == datasetID }))
            let persisted = try context.fetch(FetchDescriptor<ProductSyncMutation>(predicate: #Predicate { $0.dataset == datasetID }))
            var records = Dictionary(uniqueKeysWithValues: persisted.map { ($0.id, $0) })
            var manifests: [UUID: MutationManifest] = [:]
            for row in persisted { manifests[row.id] = try MutationManifest.decode(row.manifest) }
            for row in inbox where row.recordType == CloudRecordCodec.mutationType && row.quarantinedReason == nil {
                do {
                    let manifest = try MutationManifest.decode(row.bytes)
                    guard manifest.dataset == datasetID else { throw SyncValidationError.invalidIdentity }
                    if let previous = manifests[manifest.mutation] { try manifest.verifyReplay(of: previous.encoded()) }
                    manifests[manifest.mutation] = manifest
                } catch { row.quarantinedReason = "Invalid immutable manifest" }
            }
            let assets = SyncAssetStore(root: mediaRoot)
            var verified = Set<UUID>()
            var documents: [UUID: SyncDomainDocument] = [:]
            for (id, manifest) in manifests {
                do {
                    var payload = records[id]?.payload
                    if !manifest.deleted && payload == nil, let descriptor = manifest.payload {
                        var collected = Data(); collected.reserveCapacity(descriptor.total.byteCount)
                        for chunk in descriptor.chunks { collected.append(try assets.read(chunk)) }
                        payload = collected
                    }
                    try manifest.verifyAssetsComplete(payload: payload, originalBytes: { try assets.read($0.asset) })
                    if let payload {
                        let document = try SyncDomainCodec.decode(payload)
                        guard document.key.kind.rawValue == manifest.object.kind, document.key.id == manifest.object.id,
                              document.dependencies.map({ try? SyncObject(kind: $0.kind.rawValue, id: $0.id) }).compactMap({$0}) == manifest.dependencies,
                              document.media.map({ OriginalReference(id: $0.id, asset: AssetDescriptor(sha256: $0.sha256, byteCount: Int($0.byteCount))) }).sorted(by: {$0.id.uuidString < $1.id.uuidString}) == manifest.originals else { throw SyncValidationError.invalidManifest }
                        documents[id] = document
                    }
                    verified.insert(id)
                    if records[id] == nil {
                        let row = try ProductSyncMutation(manifest, payload: payload, transactionID: UUID(), local: false)
                        context.insert(row); records[id] = row
                    }
                } catch {
                    // Missing chunks/originals and unsupported domain data remain durable but
                    // unpublishable. They never release dependencies or an older live revision.
                }
            }
            let result = try CausalProjection.project(manifestBytes: manifests.values.map { try $0.encoded() }, dataset: datasetID,
                supportedPayloadVersions: Dictionary(uniqueKeysWithValues: SyncDomainKind.allCases.map { ($0.rawValue, Set([1])) }),
                verifiedMutationAssets: verified)
            conflicts = result.filter { $0.state == .conflict }.compactMap {
                guard let kind = SyncDomainKind(rawValue: $0.object.kind) else { return nil }
                return SyncConflictSummary(key: .init(kind: kind, id: $0.object.id), heads: $0.heads)
            }
            let complete = result.allSatisfy(\.complete) && !inbox.contains(where: { $0.quarantinedReason != nil })
            let priorStates = try context.fetch(FetchDescriptor<ProductSyncObjectState>(predicate: #Predicate { $0.dataset == datasetID }))
            var states = Dictionary(uniqueKeysWithValues: priorStates.map { ($0.key, $0) })
            var affected = Set<SyncDomainKey>()
            var projected: [SyncDomainDocument] = []
            for item in result {
                guard let kind = SyncDomainKind(rawValue: item.object.kind) else { continue }
                let key = SyncDomainKey(kind: kind, id: item.object.id)
                let stateKey = ProductSyncObjectState.key(dataset: datasetID, object: key)
                let old = states[stateKey]
                let document = item.selectedMutation.flatMap { documents[$0] }
                let fingerprint = try document.map { syncDigest(try SyncDomainCodec.encode($0)) } ?? "deleted"
                if complete {
                    if let document { projected.append(document) }
                    if old?.fingerprint != fingerprint || old?.deleted != (item.state == .deleted) { affected.insert(key) }
                }
                let state: ProductSyncObjectState
                if let old { state = old }
                else {
                    state = try ProductSyncObjectState(dataset: datasetID, object: key, heads: [], fingerprint: "unpublished", deleted: false)
                    context.insert(state); states[stateKey] = state
                }
                state.heads = try JSONEncoder().encode(item.heads)
                if complete {
                    state.fingerprint = fingerprint; state.deleted = item.state == .deleted; state.projectionState = item.state.rawValue
                } else if item.state == .conflict { state.projectionState = "conflict" }
                else if item.complete && old?.fingerprint == fingerprint && old?.deleted == (item.state == .deleted) {
                    state.projectionState = item.state.rawValue
                } else { state.projectionState = "pending" }
            }
            if complete {
                let projection = try SyncDomainCodec.reconstruct(completeDocuments: projected)
                // Immutable bytes are installed before DB publication; leftovers on rollback are
                // retained, never treated as successful records and never overwrite other bytes.
                let mediaStore = MediaStore(rootURL: mediaRoot)
                for document in projected where affected.contains(document.key) {
                    for media in document.media {
                        let descriptor = AssetDescriptor(sha256: media.sha256, byteCount: Int(media.byteCount))
                        let url = try assets.url(for: descriptor)
                        let destination = try mediaStore.fileURL(for: mediaStore.originalRelativePath(id: media.id, contentType: media.contentType))
                        if FileManager.default.fileExists(atPath: destination.path) {
                            guard AssetDescriptor(bytes: try Data(contentsOf: destination)) == descriptor else { throw SyncValidationError.identityCollision }
                        } else {
                            let stored = try mediaStore.storeOriginal(.init(url: url, originalFilename: media.id.uuidString, contentType: media.contentType), id: media.id)
                            guard stored.checksum == descriptor.sha256, stored.byteCount == descriptor.byteCount else { throw SyncValidationError.corruptAsset }
                        }
                    }
                }
                try SyncDomainInstaller.install(projection, affectedKeys: affected, in: context)
                value.blockedReason = nil
            } else {
                value.blockedReason = conflicts.isEmpty ? "Sync is incomplete: some versions or photos have not arrived or cannot be read. Local data is kept." : "Concurrent versions need review. Local data is kept; no version was silently overwritten."
            }
            do {
                _ = try checked(session, context: context)
                try ProductSyncCommit.save(context, origin: .remoteProjection)
            } catch { context.rollback(); throw error }
            refreshStatus()
        }
    }

    func conflictVersions(_ conflict: SyncConflictSummary) throws -> [SyncConflictVersion] {
        let context = ModelContext(container)
        guard let value = try dataset(in: context) else { return [] }
        let datasetID = value.id
        return try context.fetch(FetchDescriptor<ProductSyncMutation>(predicate: #Predicate { $0.dataset == datasetID }))
            .filter { conflict.heads.contains($0.id) }.map { row in
                let manifest = try MutationManifest.decode(row.manifest)
                return SyncConflictVersion(id: row.id, deleted: manifest.deleted,
                    payload: row.payload.flatMap { try? SyncDomainCodec.decode($0) }.flatMap { try? SyncDomainCodec.conflictPreview($0) } ?? (manifest.deleted ? "Deletion" : "Version content is not ready"),
                    receivedAt: row.createdAt)
            }.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// Choosing a version is an explicit merge whose parents are ALL current heads.
    /// It never changes an existing immutable revision or fabricates a last-writer timestamp.
    func resolve(_ conflict: SyncConflictSummary, choosing selected: UUID) throws {
        guard !busy else { throw StorePublicationFailure.busy }
        try StorePublication.perform(at: mediaRoot) {
            let context = ModelContext(container)
            guard !container.mainContext.hasChanges, let value = try dataset(in: context), value.enabled else { throw StorePublicationFailure.busy }
            let key = ProductSyncObjectState.key(dataset: value.id, object: conflict.key)
            guard let state = try context.fetch(FetchDescriptor<ProductSyncObjectState>(predicate: #Predicate { $0.key == key })).first else { throw ProductSyncFailure.corruptState }
            let heads = try JSONDecoder().decode([UUID].self, from: state.heads)
            guard Set(heads) == Set(conflict.heads), heads.contains(selected) else { throw SyncCloudTransportError.staleSession }
            let id = selected
            guard let row = try context.fetch(FetchDescriptor<ProductSyncMutation>(predicate: #Predicate { $0.id == id })).first,
                  row.dataset == value.id else { throw SyncValidationError.missingAsset }
            let chosen = try MutationManifest.decode(row.manifest)
            guard chosen.mutation == selected, chosen.object.kind == conflict.key.kind.rawValue, chosen.object.id == conflict.key.id else { throw ProductSyncFailure.corruptState }
            try chosen.verifyAssetsComplete(payload: row.payload, originalBytes: { try SyncAssetStore(root: mediaRoot).read($0.asset) })
            let merged = try MutationManifest(dataset: value.id, mutation: UUID(), object: chosen.object, parents: heads,
                dependencies: chosen.dependencies, deleted: chosen.deleted, payloadVersion: chosen.payloadVersion,
                payload: chosen.payload, originals: chosen.originals)
            let revision = try ProductSyncMutation(merged, payload: row.payload, transactionID: UUID(), local: true)
            context.insert(revision); context.insert(ProductSyncOutbox(revision))
            state.heads = try JSONEncoder().encode([revision.id]); state.projectionState = "pending"
            try context.save()
        }
        if let session = driver?.session, session.active { try project(session) }
        refreshStatus(); scheduleSync()
    }
}

struct SyncConflictVersion: Identifiable {
    let id: UUID
    let deleted: Bool
    let payload: String
    let receivedAt: Date
}


@MainActor enum SyncPushBridge {
    static weak var coordinator: SyncProductCoordinator?
    static func receive(_ userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              notification.containerIdentifier == SyncProductCoordinator.containerID,
              notification.notificationType == .recordZone,
              let coordinator, coordinator.canAutomaticallySync else { return .noData }
        await coordinator.synchronize()
        return coordinator.requiresAttention ? .failed : .newData
    }
}
