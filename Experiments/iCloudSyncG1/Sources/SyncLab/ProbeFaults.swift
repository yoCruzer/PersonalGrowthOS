#if DEBUG
import Foundation
import CloudKit
import Darwin

enum ProbeProcessIdentity { static let nonce = UUID().uuidString }

public struct ProbeFaultSource: Codable {
    public var commandID: String
    public var planID: String?
    public var commandDigest: String
    public init(commandID: String, planID: String? = nil, commandDigest: String) {
        self.commandID = commandID; self.planID = planID; self.commandDigest = commandDigest
    }
    func validate() throws {
        guard validID(commandID), commandID.hasPrefix("probe-"), isHash(commandDigest),
              planID.map({ validID($0) && $0.hasPrefix("probe-") }) ?? true else { throw LabError.invalidWire }
    }
}

public struct ProbeFaultObservation: Codable {
    public var commandID: String
    public var planID: String?
    public var commandDigest: String
    public var runID: String
    public var dataset: String
    public var point: String
    public var processNonce: String
    public var provenance: String
    public var processID: Int32
    public var sourceAccountHash: String // private; strip from public evidence
    public var snapshot: LabSnapshot?
    public var snapshotError: String?
    public var unavailableImages: [String]
    public var networkStopped: Bool
    public var pendingKeys: [String]
    public var checkpointHash: String?
    public var recordDigests: [String: String]
}

enum ProbeCloudPoint: String {
    case batchPrepared, beforeACK, afterACK, beforeFetchedInstall, afterFetchedInstall, afterState
}

func isUnavailableOriginal(_ error: Error) -> Bool {
    if case LabError.missingImage = error { return true }
    let value = error as NSError
    return value.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(value.code)
}

/// Diagnostic capture permits a known incomplete asset arrival, while strict
/// backup export stays unchanged. All other corruption/limit/I/O errors fail.
@MainActor func captureProbeSnapshot(_ store: LabStore) throws -> (LabSnapshot, [String]) {
    do { return (try JSONDecoder().decode(LabSnapshot.self, from: store.exportSnapshot()), []) }
    catch { guard isUnavailableOriginal(error) else { throw error } }
    let envelopes = try store.envelopes()
    var images: [String: Data] = [:], missing: [String] = []
    for mutation in envelopes.flatMap(\.mutations) {
        guard let hash = mutation.imageHash, let count = mutation.imageBytes else { continue }
        do { images[hash] = try store.image(hash, count: count) }
        catch { guard isUnavailableOriginal(error) else { throw error }; missing.append(hash) }
    }
    guard !missing.isEmpty else { throw LabError.blocked }
    let snapshot = LabSnapshot(envelopes: envelopes, images: images)
    guard try canonical(snapshot).count <= 32_000_000 else { throw LabError.limit }
    return (snapshot, Array(Set(missing)).sorted())
}

/// Private, immutable observations survive deliberate process termination.
/// They never contain raw account IDs, state tokens, arbitrary paths or CK error text.
@MainActor final class ProbeFaultJournal {
    let directory: URL
    var provenance = "localTransactionOrFileFault"
    let source: ProbeFaultSource
    let transport: ProbeWindowTransport?
    let runID: String
    let dataset: String
    init(base: URL, dataset: String, runID: String, source: ProbeFaultSource, transport: ProbeWindowTransport? = nil) throws {
        try source.validate()
        guard validID(dataset), dataset.hasPrefix("synthetic-g1-"), validID(runID), runID.hasPrefix("probe-") else { throw LabError.invalidWire }
        self.transport = transport; self.source = source; self.runID = runID; self.dataset = dataset
        directory = base.appendingPathComponent("fault-journals").appendingPathComponent(runID)
            .appendingPathComponent(dataset).appendingPathComponent(source.planID ?? "bridge").appendingPathComponent(source.commandID)
    }
    func record(_ point: String, store: LabStore, records: [CKRecord] = [], snapshot: LabSnapshot? = nil, allowUnavailableImage: Bool = false) throws {
        guard validID(point), store.binding.dataset == dataset else { throw LabError.invalidWire }
        var captured = snapshot
        var failure: String?
        var unavailable: [String] = []
        if captured == nil {
            do { captured = try JSONDecoder().decode(LabSnapshot.self, from: store.exportSnapshot()) }
            catch {
                guard (allowUnavailableImage || provenance == "actualCloudKitCallback"), isUnavailableOriginal(error) else { throw error }
                let partial = try captureProbeSnapshot(store)
                captured = partial.0; unavailable = partial.1
                failure = "expectedOriginalUnavailable" // Partial observation, never a complete backup.
            }
        }
        var digests: [String: String] = [:]
        for record in records {
            guard record.recordID.zoneID == Wire.zone(dataset) else { throw LabError.invalidWire }
            digests[record.recordID.recordName] = try digest(Wire.payload(record, dataset: dataset))
        }
        let observation = ProbeFaultObservation(commandID: source.commandID, planID: source.planID,
            commandDigest: source.commandDigest, runID: runID, dataset: dataset, point: point, processNonce: ProbeProcessIdentity.nonce, provenance: provenance, processID: getpid(), sourceAccountHash: store.binding.accountHash,
            snapshot: captured, snapshotError: failure, unavailableImages: unavailable, networkStopped: store.stopped, pendingKeys: try store.pending().map(\.key),
            checkpointHash: try store.checkpoint().map(digest), recordDigests: digests)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // No reuse, even if bytes happen to match. Each boundary is claimed once.
        let target = directory.appendingPathComponent(point + ".json")
        guard !FileManager.default.fileExists(atPath: target.path) else { throw LabError.identityCollision }
        try publishProbeExport(canonical(observation), to: target)
        let fd = Darwin.open(directory.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { throw LabError.blocked }
        defer { Darwin.close(fd) }
        guard fsync(fd) == 0 else { throw LabError.blocked }
        try transport?.send("observation", bytes: canonical(observation))
    }
    func read(accountHash: String? = nil) throws -> [ProbeFaultObservation] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty, files.count <= 16 else { throw LabError.blocked }
        var totalBytes = 0
        return try files.map { file in
            let bytes = try readRegularProbeBytes(file, limit: 16_000_000 - totalBytes)
            totalBytes += bytes.count
            let value = try JSONDecoder().decode(ProbeFaultObservation.self, from: bytes)
            guard value.commandID == source.commandID, value.planID == source.planID,
                  value.commandDigest == source.commandDigest, value.dataset == dataset, value.runID == runID,
                  value.point + ".json" == file.lastPathComponent,
                  isHash(value.sourceAccountHash), accountHash.map({ $0 == value.sourceAccountHash }) ?? true else { throw LabError.identityCollision }
            return value
        }
    }
}

/// Slots are private aliases for previously verified bindings, never account IDs from a plan.
/// An immutable slot cannot silently move A's offline data to B.
struct ProbeCachedAccount: Codable {
    let binding: Binding
    let fingerprint: String
}
struct ProbeAccountCache {
    let base: URL
    let dataset: String
    let runID: String
    func url(_ slot: String) throws -> URL {
        guard ["A", "B"].contains(slot), validID(dataset), dataset.hasPrefix("synthetic-g1-"),
              validID(runID), runID.hasPrefix("probe-") else { throw LabError.invalidWire }
        return base.appendingPathComponent("account-slots").appendingPathComponent(runID)
            .appendingPathComponent(dataset).appendingPathComponent(slot + ".json")
    }
    func remember(_ binding: Binding, fingerprint: String, slot: String) throws {
        guard binding.dataset == dataset, isHash(fingerprint) else { throw LabError.identityCollision }
        let other = try url(slot == "A" ? "B" : "A")
        if FileManager.default.fileExists(atPath: other.path) {
            let existing = try load(slot == "A" ? "B" : "A")
            guard existing.binding.accountHash != binding.accountHash else { throw LabError.identityCollision }
        }
        try publishProbeExport(canonical(ProbeCachedAccount(binding: binding, fingerprint: fingerprint)), to: url(slot))
    }
    func load(_ slot: String) throws -> ProbeCachedAccount {
        let value = try JSONDecoder().decode(ProbeCachedAccount.self, from: readRegularProbeBytes(url(slot), limit: 4096))
        guard value.binding.dataset == dataset, isHash(value.fingerprint) else { throw LabError.identityCollision }
        _ = try Binding(accountHash: value.binding.accountHash, dataset: value.binding.dataset)
        return value
    }
}

/// Exercise only immutable, embedded synthetic originals. The held originals
/// and corrupt bytes are retained; no user photo or arbitrary path is accepted.
@MainActor func exerciseImageFaults(store: LabStore, journal: ProbeFaultJournal) throws {
    let before = try store.exportSnapshot()
    let referenced = Set(try store.envelopes().flatMap { $0.mutations.compactMap(\.imageHash) })
    let fixtures = [DevelopmentProbe.png, DevelopmentProbe.secondPNG].filter { referenced.contains(digest($0)) }
    guard !fixtures.isEmpty else { throw LabError.missingImage }
    for (index, bytes) in fixtures.enumerated() {
        let hash = digest(bytes), url = try store.imageURL(hash)
        guard try store.image(hash, count: bytes.count) == bytes else { throw LabError.missingImage }
        try journal.record("imageBaseline-\(index)", store: store)
        let held = journal.directory.appendingPathComponent("held-original-\(index)")
        guard !FileManager.default.fileExists(atPath: held.path) else { throw LabError.identityCollision }
        try FileManager.default.moveItem(at: url, to: held)
        defer { try? store.stage(bytes, hash: hash, count: bytes.count) }
        do { _ = try store.exportSnapshot(); throw LabError.blocked }
        catch LabError.blocked { throw LabError.blocked }
        catch { guard isUnavailableOriginal(error) else { throw error } }
        try journal.record("imageMissing-\(index)", store: store, allowUnavailableImage: true)
        try store.stage(bytes, hash: hash, count: bytes.count)
        try journal.record("imageMissingRepaired-\(index)", store: store)
        try Data(bytes.prefix(bytes.count / 2)).write(to: url, options: .atomic)
        do { _ = try store.exportSnapshot(); throw LabError.blocked }
        catch LabError.missingImage { }
        try journal.record("imageTruncated-\(index)", store: store, allowUnavailableImage: true)
        try store.stage(bytes, hash: hash, count: bytes.count)
        try journal.record("imageTruncatedRepaired-\(index)", store: store)
        guard try Data(contentsOf: held) == bytes else { throw LabError.identityCollision }
    }
    guard try store.exportSnapshot() == before else { throw LabError.identityCollision }
}

@MainActor final class ProbeCloudFault {
    let action: ProbeCommand.Action
    let journal: ProbeFaultJournal
    let mutation: Mutation?
    private(set) var reached = false
    private var fetched = false
    private(set) var restored: LabStore?
    private var editTask: Task<Void, Never>?
    private var edited = false
    private var acknowledged = false
    private var oldPayload: Data?
    private var taskFailed = false
    var exitProcess: (Int32) -> Void = { Darwin._exit($0) }
    init(action: ProbeCommand.Action, journal: ProbeFaultJournal, mutation: Mutation?, provenance: String = "LOCAL_CALLBACK_SEAM") {
        journal.provenance = provenance
        self.action = action; self.journal = journal; self.mutation = mutation
    }
    func cancel() { editTask?.cancel(); editTask = nil }
    func observe(_ point: ProbeCloudPoint, store: LabStore, records: [CKRecord]) throws {
        if action == .crashOnFetch, point == .afterFetchedInstall, !records.isEmpty, !reached {
            reached = true; try journal.record("afterFetchedInstall", store: store, records: records); exitProcess(75)
        }
        if action == .crashOnState {
            if point == .afterFetchedInstall, !records.isEmpty { fetched = true }
            if point == .afterState, fetched, !reached {
                reached = true; try journal.record("afterFetchedState", store: store); exitProcess(76)
            }
        }
        if action == .restoreIsolation, point == .beforeFetchedInstall, !records.isEmpty, !reached {
            guard let mutation, try store.envelopes().isEmpty else { throw LabError.blocked }
            let target = try LabStore(base: journal.directory.appendingPathComponent("restore-target"), binding: store.binding)
            var images: [String: Data] = [:]
            if let hash = mutation.imageHash, let bytes = DevelopmentProbe.fixture(hash: hash, count: mutation.imageBytes) { images[hash] = bytes }
            try target.importSnapshot(canonical(LabSnapshot(envelopes: [Envelope(object: mutation.object, mutations: [mutation])], images: images)))
            try journal.record("restoreTargetGated", store: target)
            store.fence() // Incoming real callback still holds the old ticket.
            try journal.record("oldReceiverFencedBeforeInstall", store: store, records: records)
            restored = target; reached = true
        }
        if action == .crashWithImageLease {
            let image = records.first { $0.recordType == Wire.imageType }
            if point == .batchPrepared, let image, editTask == nil {
                try journal.record("assetBatchPrepared", store: store, records: [image])
                let ticket = store.epoch
                editTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: 20_000_000)
                        guard let self, !self.acknowledged else { return }
                        try Task.checkCancellation(); try store.check(ticket)
                        guard let asset = image["original"] as? CKAsset, let url = asset.fileURL,
                              let hash = image["sha256"] as? String, let count = (image["byteCount"] as? NSNumber)?.intValue else { throw LabError.invalidWire }
                        let bytes = try Data(contentsOf: url)
                        guard bytes.count == count, digest(bytes) == hash else { throw LabError.missingImage }
                        try self.journal.record("assetLeaseBeforeACK", store: store, records: [image])
                        self.reached = true; self.exitProcess(77)
                    } catch { self?.taskFailed = true }
                }
            }
            if point == .beforeACK, image != nil { acknowledged = true }
        }
        guard action == .editDuringSend, let mutation else { return }
        let key = "object-" + mutation.object
        let target = records.first { $0.recordID.recordName == key }
        if point == .batchPrepared, let target, oldPayload == nil {
            let bytes = try Wire.payload(target, dataset: store.binding.dataset)
            guard !(try Envelope.decode(bytes)).mutations.contains(where: { $0.id == mutation.id }) else { throw LabError.blocked }
            oldPayload = bytes
            try journal.record("oldBatchPrepared", store: store, records: [target])
            let ticket = store.epoch
            // Run after handing the frozen batch back to the SDK. If ACK wins the
            // race, fail the scenario rather than claiming an in-flight edit.
            editTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 20_000_000)
                    guard let self, !self.acknowledged else { return }
                    try Task.checkCancellation(); try store.check(ticket)
                    try store.save(mutation, image: DevelopmentProbe.fixture(hash: mutation.imageHash, count: mutation.imageBytes))
                    self.edited = true
                    try self.journal.record("newEditBeforeACK", store: store)
                } catch { self?.taskFailed = true }
            }
        }
        if point == .beforeACK, let target, !acknowledged, let oldPayload {
            acknowledged = true
            guard edited, !taskFailed, try Wire.payload(target, dataset: store.binding.dataset) == oldPayload else { throw LabError.blocked }
            try journal.record("oldACKBeforeCommit", store: store, records: [target])
        }
        if point == .afterACK, target != nil, acknowledged, !reached {
            guard edited, !taskFailed, try store.pending().contains(where: { $0.key == key }) else { throw LabError.blocked }
            reached = true; try journal.record("newVersionStillPending", store: store)
        }
    }
}
#endif
