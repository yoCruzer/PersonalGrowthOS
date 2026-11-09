import Foundation
import SwiftData
import CloudKit
import Combine
import Network
import UIKit
import SyncFoundation

enum SyncInitialZoneSetupError: Error { case confirmationRequired, ineligible }

extension Notification.Name { static let productSyncLocalCommit = Notification.Name("ProductSyncLocalCommit") }

/// One coordinator per open store. It owns no CloudKit object until explicit opt-in.
@MainActor final class SyncProductCoordinator: ObservableObject, SyncCloudPersistence {
    static let containerID = "iCloud.com.yocruzer.PersonalGrowthOS"
    // CloudKit private databases already isolate accounts. A stable default workspace identity
    // lets a second installation join without an extra mutable root record/schema type.
    static let defaultDatasetID = UUID(uuidString: "EAB541A0-45A1-43E4-9009-4E6F316EA001")!
    let container: ModelContainer
    let mediaRoot: URL
    @Published private(set) var status = String(localized: "iCloud sync is off")
    @Published private(set) var activity: SyncCloudActivity?
    #if DEBUG
    private(set) var projectionPassCount = 0
    #endif
    var displayedStatus: String {
        switch activity {
        case .checking: return String(localized: "Checking iCloud account…")
        case .uploading: return String(localized: "Uploading to iCloud…")
        case .downloading: return String(localized: "Downloading from iCloud…")
        case .applying: return String(localized: "Applying downloaded changes…")
        case nil: return status
        }
    }
    static func localizedStoredStatus(_ value: String) -> String {
        let prefix = "Sync paused (", suffix = "); local data and pending revisions are kept."
        if value.hasPrefix(prefix), value.hasSuffix(suffix) {
            let reason = String(value.dropFirst(prefix.count).dropLast(suffix.count))
            return String.localizedStringWithFormat(String(localized: "Sync paused (%@); local data and pending revisions are kept."), reason)
        }
        let capacityPrefix = "Local changes saved; synchronization requires reconciliation ("
        if value.hasPrefix(capacityPrefix), value.hasSuffix(").") {
            return String.localizedStringWithFormat(String(localized: "Local changes saved; synchronization requires reconciliation (%@)."), String(value.dropFirst(capacityPrefix.count).dropLast(2)))
        }
        return String(localized: String.LocalizationValue(value))
    }
    @Published private(set) var metadataRealm: CloudEnvironment?
    @Published private(set) var hasRetainedOtherRealm = false
    var environmentLabel: String {
        switch metadataRealm {
        case .production: return String(localized: "Production")
        case .development: return String(localized: "Development")
        case nil: return String(localized: "Unavailable")
        }
    }
    @Published private(set) var enabled = false
    @Published private(set) var busy = false
    @Published private(set) var requiresAttention = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var conflicts: [SyncConflictSummary] = []
    @Published private(set) var canConfirmInitialZoneCreation = false
    private var initialZoneConsent: SyncBinding?
    private var activation = UUID()
    private var driver: (any SyncCloudDriving)?
    private let accountReader: (() async throws -> String)?
    private let transportFactory: @MainActor (any SyncCloudPersistence) -> any SyncCloudDriving
    private var pendingWake = false
    private var retryAttempt = 0
    private var retryNotBefore: Date?
    private var pathMonitor: NWPathMonitor?
    private var previouslyConnected: Bool?
    private static let retryPrefix = "Sync retry scheduled|"
    private static let waitingReason = "Sync is waiting for missing versions or photos. Local data is kept."
    private static let editingReason = "Downloaded changes are not yet applied. Finish the current edit, then sync again."
    private static let legacyWaitingReason = "Sync is incomplete: some versions or photos have not arrived or cannot be read. Local data is kept."
    private static func isWaiting(_ reason: String) -> Bool {
        reason.hasPrefix(retryPrefix) || [waitingReason, editingReason, legacyWaitingReason].contains(reason)
    }
    private static func retryDate(_ reason: String?) -> Date? {
        guard let reason, reason.hasPrefix(retryPrefix),
              let seconds = Double(reason.dropFirst(retryPrefix.count)), seconds.isFinite else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
    private var wakeTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private let environment: CloudEnvironment?
    private let automaticSync: Bool

    init(container: ModelContainer, mediaRoot: URL, environment: CloudEnvironment? = nil, automaticSync: Bool = true,
         accountReader: (() async throws -> String)? = nil,
         transportFactory: (@MainActor (any SyncCloudPersistence) -> any SyncCloudDriving)? = nil) {
        self.container = container; self.mediaRoot = mediaRoot; self.automaticSync = automaticSync
        self.accountReader = accountReader; self.transportFactory = transportFactory ?? { SyncCloudTransport(persistence: $0) }
        self.environment = environment ?? SyncBuildConfiguration.environment()
        refreshStatus()
        observer = NotificationCenter.default.addObserver(forName: .productSyncLocalCommit, object: nil, queue: .main) { [weak self] notification in
            let path = notification.userInfo?["root"] as? String
            Task { @MainActor [weak self] in
                guard let self, path == StorePublication.key(for: self.mediaRoot) else { return }
                self.refreshStatus(); self.scheduleSync()
            }
        }
        if automaticSync {
            let monitor = NWPathMonitor(); pathMonitor = monitor
            monitor.pathUpdateHandler = { [weak self] path in
                let connected = path.status == .satisfied
                Task { @MainActor [weak self] in self?.networkChanged(connected: connected) }
            }
            monitor.start(queue: DispatchQueue(label: "ProductSyncReachability"))
        }
    }
    deinit { pathMonitor?.cancel(); if let observer { NotificationCenter.default.removeObserver(observer) }; wakeTask?.cancel() }

    private func dataset(in context: ModelContext) throws -> ProductSyncDataset? {
        try ProductSyncStoreSelection.selectedDataset(in: context)
    }
    func refreshStatus() {
        do {
            let context = ModelContext(container)
            metadataRealm = try ProductSyncStoreSelection.selectedEnvironment(in: context) ?? environment
            hasRetainedOtherRealm = try context.fetch(FetchDescriptor<ProductSyncDataset>()).contains {
                $0.initialized && $0.environment != metadataRealm?.rawValue
            }
            guard let dataset = try dataset(in: context) else {
                enabled = false; pendingCount = 0; requiresAttention = false; conflicts = []
                status = String(localized: "iCloud sync is off"); return
            }
            enabled = dataset.enabled
            requiresAttention = dataset.needsReconciliation || (dataset.blockedReason.map { !Self.isWaiting($0) } ?? false)
            retryNotBefore = Self.retryDate(dataset.blockedReason)
            let id = dataset.id
            conflicts = try context.fetch(FetchDescriptor<ProductSyncObjectState>(predicate: #Predicate { $0.dataset == id }))
                .filter { $0.projectionState == "conflict" }.compactMap { state in
                    guard let kind = SyncDomainKind(rawValue: state.kind), let heads = try? JSONDecoder().decode([UUID].self, from: state.heads) else { return nil }
                    return SyncConflictSummary(key: .init(kind: kind, id: state.businessID), heads: heads)
                }
            pendingCount = try context.fetch(FetchDescriptor<ProductSyncOutbox>(predicate: #Predicate { $0.dataset == id && !$0.completed })).count
            if !enabled { status = String(localized: "iCloud sync is off") }
            else if let reason = dataset.blockedReason {
                status = reason.hasPrefix(Self.retryPrefix) ? String(localized: "Sync will retry automatically. Local data is kept.") : Self.localizedStoredStatus(reason)
            }
            else if pendingCount > 0 {
                status = String.localizedStringWithFormat(String(localized: "%lld local revisions waiting"), Int64(pendingCount))
            } else if let completed = dataset.lastSuccess {
                status = String.localizedStringWithFormat(String(localized: "Last sync completed at %@"), completed.formatted(date: .abbreviated, time: .standard))
            } else { status = String(localized: "Waiting to check iCloud") }
        } catch { status = String(localized: "Sync metadata needs attention; local data is preserved.") }
    }

    /// UI consent explicitly covers uploading existing local data to this account's private database.
    func enable() async { await activate(initialZoneConsent: nil) }
    func confirmInitialZoneCreation() async {
        guard let consent = takeInitialZoneConsent() else { return }
        await activate(initialZoneConsent: consent)
    }
    func takeInitialZoneConsent() -> SyncBinding? {
        let consent = initialZoneConsent
        initialZoneConsent = nil; canConfirmInitialZoneCreation = false
        return consent
    }
    private func activate(initialZoneConsent consent: SyncBinding?) async {
        guard !busy else { return }; busy = true; activity = .checking
        defer { finishCycle() }
        wakeTask?.cancel(); wakeTask = nil; pendingWake = false
        let attempt = UUID(); activation = attempt
        _ = takeInitialZoneConsent()
        var consentAccepted = false
        var failureBinding: SyncBinding?
        var transportStarted = false
        do {
            guard let environment else { throw SyncCloudTransportError.paused(.environmentMismatch) }
            let account = try await readAccount()
            guard activation == attempt else { throw SyncCloudTransportError.staleSession }
            let context = ModelContext(container); context.autosaveEnabled = false
            let binding = try StorePublication.perform(at: mediaRoot) {
                guard !container.mainContext.hasChanges else { throw StorePublicationFailure.busy }
                let selected = try ProductSyncStoreSelection.selectedEnvironment(in: context)
                guard selected == nil || selected == environment else { throw SyncCloudTransportError.paused(.environmentMismatch) }
                try ProductSyncStoreSelection.prepare(context: context, environment: environment)
                let value: ProductSyncDataset
                if let existing = try dataset(in: context) { value = existing }
                else {
                    value = ProductSyncDataset(id: ProductSyncStoreSelection.defaultDatasetID(for: environment))
                    value.environment = environment.rawValue
                    try ProductSyncStoreSelection.activate(value, in: context)
                }
                if let prior = value.accountHash {
                    guard prior == account, value.environment == environment.rawValue else { throw ProductSyncFailure.accountChanged }
                }
                guard !value.needsReconciliation, !value.zoneLost else { throw ProductSyncFailure.corruptState }
                if let consent {
                    guard try initialZoneRecoveryEligible(consent, context: context) else { throw SyncInitialZoneSetupError.ineligible }
                    consentAccepted = true
                }
                value.accountHash = account; value.environment = environment.rawValue
                value.generation = UUID(); value.enabled = true; value.blockedReason = nil
                try ProductSyncCommit.initialize(context, dataset: value)
                try context.save()
                return try SyncBinding(container: Self.containerID, environment: environment, accountHash: account, dataset: value.id, generation: value.generation)
            }
            failureBinding = binding
            if let driver { await driver.stop() }
            guard activation == attempt else { throw SyncCloudTransportError.staleSession }
            let transport = transportFactory(self); driver = transport
            var value = try requireDataset(binding)
            if !value.zoneEstablished && value.zoneCreationAttempted {
                // A prior attempted creation is not permission to recreate a deleted zone.
                // Read only the known zone metadata; absent/unknown stays paused.
                let exists = try await Self.initialZoneExists(binding: binding,
                    check: { [self] in
                        guard activation == attempt else { throw SyncCloudTransportError.staleSession }
                        _ = try requireDataset(binding)
                    }, account: { [self] in try await readAccount() },
                    fetch: { try await CKContainer(identifier: Self.containerID).privateCloudDatabase.recordZone(for: $0) })
                guard activation == attempt else { throw SyncCloudTransportError.staleSession }
                if exists {
                    try StorePublication.perform(at: mediaRoot) {
                        let write = ModelContext(container); let current = try requireDataset(binding, context: write)
                        current.zoneEstablished = true; try write.save()
                    }
                } else if !consentAccepted {
                    try offerInitialZoneConsent(binding)
                    throw SyncInitialZoneSetupError.confirmationRequired
                } else {
                    guard try initialZoneRecoveryEligible(binding) else { throw SyncInitialZoneSetupError.ineligible }
                }
                value = try requireDataset(binding)
            }
            let createZone = !value.zoneEstablished
            if createZone {
                try StorePublication.perform(at: mediaRoot) {
                    let write = ModelContext(container); let current = try requireDataset(binding, context: write)
                    guard !current.zoneLost, !current.zoneEstablished else { throw ProductSyncFailure.corruptState }
                    if current.zoneCreationAttempted {
                        guard consentAccepted, try initialZoneRecoveryEligible(binding, context: write) else { throw SyncInitialZoneSetupError.ineligible }
                    }
                    current.zoneCreationAttempted = true; try write.save()
                }
            }
            try await transport.start(binding: binding, signedEnvironment: environment, createZone: createZone)
            transportStarted = true
            guard activation == attempt else { throw SyncCloudTransportError.staleSession }
            enabled = true
            if automaticSync { UIApplication.shared.registerForRemoteNotifications() }
            try await transport.synchronize()
            guard let session = transport.session else { throw SyncCloudTransportError.staleSession }
            try await applyDurableInbox(session: session)
            try markSuccessful(binding)
        } catch {
            guard activation == attempt else { return }
            if SyncCloudRetry.delay(for: error, attempt: 0) != nil {
                if !transportStarted { if let driver { await driver.stop() }; driver = nil }
                if failureBinding == nil, let prior = try? dataset(in: ModelContext(container)), prior.enabled,
                   let account = prior.accountHash, let realm = CloudEnvironment(rawValue: prior.environment) {
                    failureBinding = try? SyncBinding(container: Self.containerID, environment: realm,
                        accountHash: account, dataset: prior.id, generation: prior.generation)
                }
            }
            guard activation == attempt else { return }
            presentFailure(error, binding: failureBinding)
        }
    }
    func disable() async {
        activity = nil
        _ = takeInitialZoneConsent()
        activation = UUID(); wakeTask?.cancel(); wakeTask = nil; pendingWake = false; retryNotBefore = nil; retryAttempt = 0
        driver?.session?.invalidate()
        do {
            try StorePublication.perform(at: mediaRoot) {
                let context = ModelContext(container)
                if let value = try dataset(in: context) { value.enabled = false; value.generation = UUID(); try context.save() }
            }
        } catch { status = message(error); return }
        if let driver { await driver.stop() }; driver = nil
        enabled = false; requiresAttention = false; status = String(localized: "iCloud sync is off. Local data and pending revisions are kept.")
    }
    func synchronize() async {
        guard enabled else { return }
        if busy { pendingWake = true; return }
        if let retryNotBefore, retryNotBefore > Date() { scheduleSync(); return }
        guard let driver, let session = driver.session, session.active else { await enable(); return }
        let attempt = activation
        busy = true; pendingWake = false; defer { finishCycle() }
        do {
            try await applyDurableInbox(session: session)
            try await driver.synchronize()
            try await applyDurableInbox(session: session)
            try markSuccessful(session.binding)
        }
        catch {
            guard activation == attempt else { return }
            presentFailure(error, binding: session.binding)
        }
    }
    /// Only an exact zoneNotFound is evidence for offering initial setup consent.
    /// This read-only seam never creates a zone and fences every account/metadata await.
    static func initialZoneExists(binding: SyncBinding, check: () throws -> Void,
                                  account: () async throws -> String,
                                  fetch: (CKRecordZone.ID) async throws -> CKRecordZone) async throws -> Bool {
        try check()
        let before = try await account(); try check()
        guard before == binding.accountHash else { throw SyncCloudTransportError.paused(.accountChanged) }
        let expected = CloudRecordCodec.zone(dataset: binding.dataset)
        let result: CKRecordZone?
        do { result = try await fetch(expected) }
        catch {
            try check()
            guard let cloud = error as? CKError, cloud.code == .zoneNotFound else { throw error }
            result = nil
        }
        try check()
        let after = try await account(); try check()
        guard after == binding.accountHash else { throw SyncCloudTransportError.paused(.accountChanged) }
        if let result, result.zoneID != expected { throw SyncValidationError.invalidIdentity }
        return result != nil
    }
    func initialZoneRecoveryEligible(_ binding: SyncBinding, context: ModelContext? = nil) throws -> Bool {
        let context = context ?? ModelContext(container), value = try requireDataset(binding, context: context)
        guard value.initialized, value.zoneCreationAttempted, !value.zoneEstablished, !value.zoneLost,
              value.lastSuccess == nil else { return false }
        let id = binding.dataset
        guard try context.fetchCount(FetchDescriptor<ProductSyncInbox>(predicate: #Predicate { $0.dataset == id })) == 0 else { return false }
        guard try context.fetch(FetchDescriptor<ProductSyncMutation>(predicate: #Predicate { $0.dataset == id })).allSatisfy({ $0.local }) else { return false }
        for row in try context.fetch(FetchDescriptor<ProductSyncOutbox>(predicate: #Predicate { $0.dataset == id })) {
            guard !row.completed, try JSONDecoder().decode([String].self, from: row.acknowledgedRecords).isEmpty else { return false }
        }
        return true
    }
    /// Called only after the read-only metadata seam returned an exact missing zone.
    func offerInitialZoneConsent(_ binding: SyncBinding) throws {
        try StorePublication.perform(at: mediaRoot) {
            let context = ModelContext(container)
            guard try initialZoneRecoveryEligible(binding, context: context) else { throw SyncInitialZoneSetupError.ineligible }
            let value = try requireDataset(binding, context: context)
            value.blockedReason = "Initial iCloud setup was not confirmed. Review setup before continuing; local data and pending revisions are kept."
            try context.save()
        }
        initialZoneConsent = binding; canConfirmInitialZoneCreation = true
    }
    /// A callback can pause durably, then SDK cancellation throws a secondary error.
    /// Keep the matching activation's first persisted reason; stale callbacks must not
    /// overwrite a newer activation or a user-requested stop.
    func presentFailure(_ error: Error, binding: SyncBinding?) {
        if let binding {
            do {
                guard binding.container == Self.containerID, let value = try dataset(in: ModelContext(container)),
                      value.id == binding.dataset, value.generation == binding.generation,
                      value.accountHash == binding.accountHash, value.environment == binding.environment.rawValue else { return }
                recordDiagnostic(.init(phase: activity.map { String(describing: $0) } ?? "cycle", failed: 1, error: error), binding: binding)
                if value.blockedReason == nil || Self.isWaiting(value.blockedReason!) {
                    if let delay = SyncCloudRetry.delay(for: error, attempt: retryAttempt) {
                        retryAttempt += 1
                        let deadline = Date().addingTimeInterval(delay)
                        try StorePublication.perform(at: mediaRoot) {
                            let write = ModelContext(container); let current = try requireDataset(binding, context: write)
                            current.blockedReason = Self.retryPrefix + String(deadline.timeIntervalSince1970)
                            try write.save()
                        }
                        activity = nil; refreshStatus(); pendingWake = true; scheduleSync(); return
                    }
                }
                activity = nil; refreshStatus(); requiresAttention = true
                if let first = value.blockedReason { status = Self.localizedStoredStatus(first); return }
            } catch { status = String(localized: "Sync metadata needs attention; local data is preserved."); requiresAttention = true; return }
        } else { activity = nil; refreshStatus(); requiresAttention = true }
        status = message(error)
    }
    var canAutomaticallySync: Bool { automaticSync && enabled && !requiresAttention }
    func resumeIfEnabled() async {
        refreshStatus()
        if canAutomaticallySync { await synchronize() }
    }
    func networkChanged(connected: Bool) {
        defer { previouslyConnected = connected }
        if previouslyConnected == false && connected { scheduleSync() }
    }
    private func readAccount() async throws -> String {
        if let accountReader { return try await accountReader() }
        let cloud = CKContainer(identifier: Self.containerID)
        try SyncCloudTransport.validateAccountStatus(try await cloud.accountStatus())
        return SyncCloudTransport.accountFingerprint(recordID: try await cloud.userRecordID())
    }
    private func finishCycle() {
        busy = false; activity = nil
        guard canAutomaticallySync else { pendingWake = false; return }
        let reason = try? dataset(in: ModelContext(container))?.blockedReason
        let waiting = reason.map(Self.isWaiting) ?? false
        let waitingForPieces = waiting && Self.retryDate(reason) == nil
        if waitingForPieces { retryAttempt += 1 }
        if pendingWake || waiting || pendingCount > 0 {
            let delay = waitingForPieces ? min(300, 2 * pow(2, Double(min(retryAttempt, 7)))) : (waiting ? 0 : 1)
            scheduleSync(after: delay)
        }
    }
    private func scheduleSync(after delay: TimeInterval = 1) {
        guard canAutomaticallySync else { return }
        pendingWake = true
        guard !busy else { return }
        // Coalesce requests without moving an existing deadline later.
        guard wakeTask == nil else { return }
        let wait = max(delay, retryNotBefore?.timeIntervalSinceNow ?? 0)
        let attempt = activation
        wakeTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(min(max(0, wait), 86_400) * 1_000_000_000)); try Task.checkCancellation() }
            catch { return }
            guard let self, self.activation == attempt else { return }
            self.wakeTask = nil
            await self.synchronize()
        }
    }
    private func message(_ error: Error) -> String {
        if case SyncCloudTransportError.paused(let reason) = error {
            return Self.localizedStoredStatus("Sync paused (\(reason)); local data and pending revisions are kept.")
        }
        if error is StorePublicationFailure { return String(localized: "Save or close the current edit, then sync again.") }
        if case ProductSyncFailure.accountChanged = error { return String(localized: "This workspace belongs to a different iCloud account. Sync is paused; local data is kept.") }
        return String.localizedStringWithFormat(String(localized: "Sync paused (%@). Local data and pending changes are kept."), String(describing: error))
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
        // Receipt only: projection is deliberately deferred until the operation boundary.
        // Bytes/assets are durable before any following engine checkpoint can be accepted.
    }
    func didChangeActivity(_ activity: SyncCloudActivity, session: SyncCloudSession) throws {
        _ = try checked(session, context: ModelContext(container))
        self.activity = activity
    }
    func applyDurableInbox(session: SyncCloudSession) async throws {
        try didChangeActivity(.applying, session: session)
        let applying = activity
        defer { if activity == applying { activity = nil } }
        await Task.yield()
        try session.check()
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
    func permitsPendingZoneCreation(session: SyncCloudSession) throws -> Bool {
        let value = try checked(session, context: ModelContext(container))
        return value.initialized && value.zoneCreationAttempted && !value.zoneEstablished && !value.zoneLost
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
        if accepted { activity = nil; requiresAttention = true; status = Self.localizedStoredStatus("Sync paused (\(reason)); local data and pending revisions are kept.") }
    }
    func markSuccessful(_ binding: SyncBinding, completedAt: Date = Date()) throws {
        try StorePublication.perform(at: mediaRoot) {
            let context = ModelContext(container); let value = try requireDataset(binding, context: context)
            let id = binding.dataset
            guard value.blockedReason == nil,
                  try context.fetchCount(FetchDescriptor<ProductSyncOutbox>(predicate: #Predicate { $0.dataset == id && !$0.completed })) == 0 else { return }
            value.lastSuccess = completedAt; try context.save()
            retryAttempt = 0
            var history = diagnosticHistory(); history.episodeOpen = false; saveDiagnosticHistory(history)
        }
        refreshStatus()
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
            #if DEBUG
            projectionPassCount += 1
            #endif
            guard !container.mainContext.hasChanges else {
                value.blockedReason = Self.editingReason
                try context.save(); status = Self.localizedStoredStatus(value.blockedReason!)
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
            var invalidContent = false
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
                    // Missing pieces can arrive later. Corrupt/unsupported bytes need review.
                    if case SyncValidationError.missingAsset = error {} else { invalidContent = true }
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
                let invalidGraph = result.contains { item in item.pendingReasons.contains { reason in
                    switch reason {
                    case .crossObjectParent, .causalCycle, .unsupportedPayload, .dependencyCycle: return true
                    default: return false
                    }
                } }
                if !conflicts.isEmpty {
                    value.blockedReason = "Concurrent versions need review. Local data is kept; no version was silently overwritten."
                } else if invalidContent || invalidGraph || inbox.contains(where: { $0.quarantinedReason != nil }) {
                    value.blockedReason = "Downloaded sync data needs review. Local data and pending revisions are kept."
                } else { value.blockedReason = Self.waitingReason }
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
              let coordinator, coordinator.acceptsPush(notification), coordinator.canAutomaticallySync else { return .noData }
        await coordinator.resumeIfEnabled()
        return coordinator.requiresAttention ? .failed : .newData
    }
}

extension SyncProductCoordinator {
    func acceptsPush(_ notification: CKNotification) -> Bool {
        guard notification.containerIdentifier == Self.containerID,
              let value = try? dataset(in: ModelContext(container)), value.enabled,
              value.environment == environment?.rawValue else { return false }
        if let database = notification as? CKDatabaseNotification {
            return database.databaseScope == .private
        }
        if let zone = notification as? CKRecordZoneNotification {
            return zone.databaseScope == .private && zone.recordZoneID == CloudRecordCodec.zone(dataset: value.id)
        }
        return false
    }
}

extension SyncProductCoordinator {
    private var diagnosticURL: URL? {
        guard let value = try? dataset(in: ModelContext(container)) else { return nil }
        let scope = [value.environment, value.id.uuidString, value.accountHash ?? "unbound"].joined(separator: "/")
        return mediaRoot.appendingPathComponent("Sync/Diagnostics-" + syncDigest(Data(scope.utf8)) + ".json")
    }
    private func diagnosticHistory() -> SyncDiagnosticHistory {
        guard let url = diagnosticURL, let bytes = try? Data(contentsOf: url), bytes.count <= 32_768,
              let history = try? JSONDecoder().decode(SyncDiagnosticHistory.self, from: bytes) else { return .init() }
        return history
    }
    private func saveDiagnosticHistory(_ history: SyncDiagnosticHistory) {
        guard let url = diagnosticURL else { return }
        var bounded = history
        while let bytes = try? JSONEncoder().encode(bounded), bytes.count > 24_576, !bounded.events.isEmpty {
            bounded.events.removeFirst()
        }
        guard let bytes = try? JSONEncoder().encode(bounded), bytes.count <= 24_576 else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: url, options: .atomic)
        } catch { /* Diagnostics never alter business persistence or synchronization ACKs. */ }
    }
    func recordDiagnostic(_ event: SyncDiagnosticEvent, binding: SyncBinding) {
        guard binding.container == Self.containerID, let value = try? dataset(in: ModelContext(container)),
              value.enabled, value.id == binding.dataset, value.generation == binding.generation,
              value.accountHash == binding.accountHash, value.environment == binding.environment.rawValue else { return }
        var history = diagnosticHistory(); history.append(event); saveDiagnosticHistory(history)
    }
    func diagnosticText() -> String {
        struct Snapshot: Encodable {
            let format: Int, time: Date, build: String, appVersion: String, appBuild: String, source: String, dirty: Bool, environment: String
            let enabled: Bool, busy: Bool, requiresAttention: Bool
            let pendingUploads: Int, pendingApplications: Int, historyRevisions: Int, historyLimit: Int
            let historyNearLimit: Bool, retryNotBefore: Date?
            let firstFailure: SyncDiagnosticEvent?, events: [SyncDiagnosticEvent]
        }
        let context = ModelContext(container), value = try? dataset(in: context), provenance = BuildProvenance()
        let id = value?.id ?? UUID()
        let historyCount = (try? context.fetchCount(FetchDescriptor<ProductSyncMutation>(predicate: #Predicate { $0.dataset == id }))) ?? 0
        let pending = (try? context.fetch(FetchDescriptor<ProductSyncObjectState>(predicate: #Predicate { $0.dataset == id })).filter { !["ready", "deleted"].contains($0.projectionState) }.count) ?? 0
        let history = diagnosticHistory()
        let version = AppVersionInformation()
        let uploads = (try? context.fetchCount(FetchDescriptor<ProductSyncOutbox>(predicate: #Predicate { $0.dataset == id && !$0.completed }))) ?? 0
        let snapshot = Snapshot(format: 1, time: Date(), build: provenance.commit ?? "unknown", appVersion: version.version, appBuild: version.build, source: provenance.source,
            dirty: provenance.isDirty, environment: value?.environment ?? environment?.rawValue ?? "unavailable",
            enabled: enabled, busy: busy, requiresAttention: requiresAttention,
            pendingUploads: uploads, pendingApplications: pending, historyRevisions: historyCount, historyLimit: 10_000,
            historyNearLimit: historyCount >= 8_000, retryNotBefore: retryNotBefore,
            firstFailure: history.firstFailure, events: history.events)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        guard let bytes = try? encoder.encode(snapshot), bytes.count <= 32_768,
              let text = String(data: bytes, encoding: .utf8) else { return "Sync diagnostics unavailable" }
        return text
    }
}
