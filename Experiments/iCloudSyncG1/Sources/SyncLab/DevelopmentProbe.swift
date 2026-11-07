#if DEBUG
import Foundation
import CloudKit
import Darwin

final class ProbeProcessLock {
    private let descriptor: Int32
    init(base: URL, dataset: String) throws {
        guard validID(dataset), dataset.hasPrefix("synthetic-g1-") else { throw LabError.invalidWire }
        let directory = base.appendingPathComponent("probe-locks", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(dataset + ".lock").path
        let opened = Darwin.open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard opened >= 0 else { throw LabError.blocked }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(opened); throw LabError.blocked }
        descriptor = opened
    }
    deinit { Darwin.close(descriptor) } // OS also releases the lock on process exit.
}

final class ProbeLoopbackSession: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never forward the bearer token away from loopback.
    }
}

// Opt-in test transport only. It never accepts paths, container IDs, account IDs,
// arbitrary URLs, shell commands, or non-synthetic mutations from a controller.
public struct ProbeCommand: Codable {
    public enum Action: String, Codable { case connect, save, sync, snapshot, reopen, stop, openCached, reopenLocal, crashBeforeSave, crashAfterSave, crashOnFetch, crashOnState, editDuringSend, inspectFaults, imageFaults, restoreIsolation, waitForAccountChange, closePartition, crashWithImageLease }
    public var id: String
    public var action: Action
    public var mutation: Mutation?
    public var accountSlot: String? = nil
    public var faultSource: ProbeFaultSource? = nil
    public init(id: String, action: Action, mutation: Mutation? = nil) {
        self.id = id; self.action = action; self.mutation = mutation
    }
    public func validate() throws {
        guard validID(id), id.hasPrefix("probe-") else { throw LabError.invalidWire }
        guard accountSlot == nil || (["A", "B"].contains(accountSlot!) && [.connect, .openCached].contains(action)),
              action != .openCached || accountSlot != nil,
              (action == .inspectFaults) == (faultSource != nil) else { throw LabError.invalidWire }
        try faultSource?.validate()
        if [.save, .crashBeforeSave, .crashAfterSave, .editDuringSend, .restoreIsolation].contains(action) {
            guard let m = mutation else { throw LabError.invalidWire }
            try m.validate()
            guard m.id.hasPrefix("probe-"), m.object.hasPrefix("probe-"),
                  m.parents.allSatisfy({ $0.hasPrefix("probe-") }),
                  m.requires.allSatisfy({ $0.hasPrefix("probe-") }),
                  m.text.hasPrefix("SYNTHETIC"),
                  (m.imageHash == nil && m.imageBytes == nil) ||
                    (DevelopmentProbe.fixture(hash: m.imageHash, count: m.imageBytes) != nil)
            else { throw LabError.invalidWire }
            if action == .restoreIsolation { guard m.parents.isEmpty, m.requires.isEmpty, !m.deleted else { throw LabError.invalidWire } }
        } else { guard mutation == nil else { throw LabError.invalidWire } }
    }
}

public struct ProbeProjection: Codable {
    public var state: String
    public var candidates: [String]
    public var preview: Mutation?
    public var complete: Bool
}

public struct ProbeResult: Codable {
    public var scope = "Command execution only; not a cloud convergence or G1 acceptance verdict"
    public var planID: String? = nil
    public var id: String
    public var dataset: String
    public var runID: String
    public var commandDigest: String
    public var status: String
    public var errorCode: String?
    // Private local coordination only; strip before committing any evidence.
    public var accountFingerprint: String?
    public var snapshot: LabSnapshot?
    public var projections: [String: ProbeProjection]?
    public var pendingKeys: [String]?
    public var checkpointHash: String?
    public var events: [String]
    public var halted: Bool
    public var platform: String
    public var processNonce: String? = nil
    public var processID: Int32? = nil
    public var snapshotComplete: Bool? = nil
    public var unavailableImages: [String]? = nil
    public var accountSource: String? = nil
    public var faultObservations: [ProbeFaultObservation]? = nil
}

// A request is journaled before execution. If a process dies before its result,
// the same ID is left explicitly indeterminate instead of silently replayed.
final class ProbeJournal {
    let directory: URL
    let dataset: String
    let runID: String
    let contextID: String?
    init(root: URL, dataset: String, runID: String, contextID: String? = nil) throws {
        guard validID(dataset), dataset.hasPrefix("synthetic-g1-"), validID(runID), runID.hasPrefix("probe-") else { throw LabError.invalidWire }
        if let contextID { guard validID(contextID), contextID.hasPrefix("probe-") else { throw LabError.invalidWire } }
        self.dataset = dataset; self.runID = runID
        self.contextID = contextID
        let partition = root.appendingPathComponent(runID).appendingPathComponent(dataset)
        directory = contextID.map { partition.appendingPathComponent("plans").appendingPathComponent($0) } ?? partition
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    private func publish(_ bytes: Data, to target: URL) throws {
        let temporary = directory.appendingPathComponent(UUID().uuidString + ".tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try bytes.write(to: temporary, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: temporary); try handle.synchronize(); try handle.close()
        try FileManager.default.linkItem(at: temporary, to: target)
    }
    func claim(_ command: ProbeCommand, bytes: Data) throws -> ProbeResult? {
        try command.validate()
        let request = directory.appendingPathComponent(command.id + ".request.json")
        let result = directory.appendingPathComponent(command.id + ".json")
        if FileManager.default.fileExists(atPath: request.path) {
            guard try Data(contentsOf: request) == bytes else { throw LabError.identityCollision }
            guard FileManager.default.fileExists(atPath: result.path) else { throw LabError.blocked }
            let old = try JSONDecoder().decode(ProbeResult.self, from: Data(contentsOf: result))
            guard old.id == command.id, old.dataset == dataset, old.runID == runID, old.commandDigest == digest(bytes), old.planID == contextID else { throw LabError.identityCollision }
            return old
        }
        guard !FileManager.default.fileExists(atPath: result.path) else { throw LabError.identityCollision }
        try publish(bytes, to: request)
        return nil
    }
    func complete(_ result: ProbeResult) throws {
        guard validID(result.id), result.id.hasPrefix("probe-"), result.dataset == dataset, result.runID == runID, result.planID == contextID else { throw LabError.identityCollision }
        let request = directory.appendingPathComponent(result.id + ".request.json")
        guard try digest(Data(contentsOf: request)) == result.commandDigest else { throw LabError.identityCollision }
        try publish(canonical(result), to: directory.appendingPathComponent(result.id + ".json"))
    }
}

@MainActor public final class DevelopmentProbe {
    public nonisolated static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
    // A second, distinct fixed original permits testing a genuinely new iOS CKAsset.
    public nonisolated static let secondPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMQT7z8HwAEKQJLn6egIAAAAABJRU5ErkJggg==")!
    public nonisolated static func fixture(hash: String?, count: Int?) -> Data? {
        [png, secondPNG].first { digest($0) == hash && $0.count == count }
    }
    public let dataset: String
    private let base: URL
    private var store: LabStore?
    private var driver: CloudDriver?
    private var runID: String
    private var connectedFingerprint: String?
    private var accountSource: String?
    private var processLock: ProbeProcessLock?
    private let authorization: DevelopmentAuthorization
    private let windowTransport: ProbeWindowTransport?
    private var manualPlanRunning = false
    public init(base: URL, dataset: String, runID: String, authorization: DevelopmentAuthorization = .fromEnvironment(), windowTransport: ProbeWindowTransport? = nil) throws {
        guard validID(dataset), dataset.hasPrefix("synthetic-g1-"), validID(runID), runID.hasPrefix("probe-") else { throw LabError.invalidWire }
        self.base = base; self.dataset = dataset; self.runID = runID
        self.authorization = authorization; self.windowTransport = windowTransport
    }
    private func ensureExclusive() throws {
        guard authorization.isEnabled else { throw LabError.blocked }
        if processLock == nil { processLock = try ProbeProcessLock(base: base, dataset: dataset) }
    }
    public func shutdown() async {
        await driver?.stop(); driver = nil
        processLock = nil
    }
    private func connect(slot: String? = nil) async throws {
        guard authorization.isEnabled else { throw LabError.blocked }
        if let driver {
            guard !driver.halted else { throw LabError.staleEpoch }
            if let slot, let store, let connectedFingerprint {
                try accountCache.remember(store.binding, fingerprint: connectedFingerprint, slot: slot)
            }
            return
        }
        let container = CKContainer(identifier: Binding.container)
        guard try await container.accountStatus() == .available else { throw LabError.blocked }
        let user = try await container.userRecordID()
        // Salt is a synthetic per-run value. No raw account identifier is exported.
        let fingerprint = digest(Data((runID + "|" + user.recordName).utf8))
        let binding = try Binding(accountHash: digest(Data(user.recordName.utf8)), dataset: dataset)
        if let old = store, old.binding != binding { throw LabError.staleEpoch }
        if let slot { try accountCache.remember(binding, fingerprint: fingerprint, slot: slot) }
        connectedFingerprint = fingerprint; accountSource = "liveCloudKit"
        let local = try LabStore(base: base, binding: binding)
        store = local
        let cloud = CloudDriver(store: local)
        driver = cloud; try await cloud.start(authorization: authorization)
    }
    private var accountCache: ProbeAccountCache { ProbeAccountCache(base: base, dataset: dataset, runID: runID) }
    public func perform(_ command: ProbeCommand, planID: String? = nil, requestDigest: String? = nil) async -> ProbeResult {
        #if os(macOS)
        let platform = "macOS"
        #else
        let platform = "iOS"
        #endif
        var result = ProbeResult(planID: planID, id: command.id, dataset: dataset, runID: runID, commandDigest: requestDigest ?? (try? canonical(command)).map(digest) ?? "", status: "FAIL", events: [], halted: driver?.halted ?? false, platform: platform)
        do {
            try command.validate()
            guard isHash(result.commandDigest) else { throw LabError.invalidWire }
            guard authorization.isEnabled else { throw LabError.blocked }
            try ensureExclusive()
            if command.action == .openCached {
                guard driver == nil, store == nil, let slot = command.accountSlot else { throw LabError.blocked }
                let cached = try accountCache.load(slot)
                store = try LabStore(base: base, binding: cached.binding)
                connectedFingerprint = cached.fingerprint; accountSource = "cachedPartitionNotCurrentAccount"
            } else if store == nil { try await connect(slot: command.accountSlot) }
            let journal = try ProbeFaultJournal(base: base, dataset: dataset, runID: runID,
                source: ProbeFaultSource(commandID: command.id, planID: planID, commandDigest: result.commandDigest), transport: windowTransport)
            switch command.action {
            case .connect: try await connect(slot: command.accountSlot)
            case .openCached: break
            case .reopenLocal:
                await driver?.stop(); driver = nil
                guard let binding = store?.binding else { throw LabError.blocked }
                store = try LabStore(base: base, binding: binding)
                accountSource = "cachedPartitionNotCurrentAccount"
            case .inspectFaults:
                guard let source = command.faultSource else { throw LabError.invalidWire }
                result.faultObservations = try ProbeFaultJournal(base: base, dataset: dataset, runID: runID, source: source).read(accountHash: store?.binding.accountHash)
            case .crashBeforeSave, .crashAfterSave:
                guard let store, let mutation = command.mutation else { throw LabError.blocked }
                if command.action == .crashBeforeSave {
                    let baseline = try JSONDecoder().decode(LabSnapshot.self, from: store.exportSnapshot())
                    try journal.record("beforeSaveBaseline", store: store)
                    store.beforeCommit = {
                        // Snapshot is the committed baseline; pendingKeys may reflect the uncommitted transaction.
                        try journal.record("beforeSaveCommit", store: store, snapshot: baseline)
                        Darwin._exit(73)
                    }
                }
                defer { store.beforeCommit = nil }
                try store.save(mutation, image: Self.fixture(hash: mutation.imageHash, count: mutation.imageBytes))
                try journal.record("afterSaveCommit", store: store); Darwin._exit(74)
            case .crashOnFetch, .crashOnState, .editDuringSend, .crashWithImageLease:
                guard let driver else { throw LabError.blocked }
                let fault = ProbeCloudFault(action: command.action, journal: journal, mutation: command.mutation, provenance: "actualCloudKitCallback")
                driver.probeHook = { point, store, records in try fault.observe(point, store: store, records: records) }
                defer { fault.cancel(); driver.probeHook = nil }
                try await driver.sync()
                guard fault.reached else { throw LabError.blocked }
                result.faultObservations = try journal.read()
            case .imageFaults:
                guard let old = store else { throw LabError.blocked }
                await driver?.stop(); driver = nil
                let local = try LabStore(base: base, binding: old.binding); store = local
                try exerciseImageFaults(store: local, journal: journal)
                result.faultObservations = try journal.read()
                accountSource = "cachedPartitionNotCurrentAccount"
            case .restoreIsolation:
                guard let driver, let store else { throw LabError.blocked }
                let fault = ProbeCloudFault(action: command.action, journal: journal, mutation: command.mutation, provenance: "actualCloudKitCallback")
                driver.probeHook = { point, store, records in try fault.observe(point, store: store, records: records) }
                defer { fault.cancel(); driver.probeHook = nil }
                do { try await driver.sync() } catch { guard fault.reached, driver.halted else { throw error } }
                guard fault.reached, driver.halted, try store.envelopes().isEmpty, let restored = fault.restored else { throw LabError.blocked }
                let reopened = try LabStore(base: journal.directory.appendingPathComponent("restore-target"), binding: restored.binding)
                guard reopened.stopped, try reopened.checkpoint() == nil else { throw LabError.blocked }
                do { try reopened.check(reopened.epoch); throw LabError.blocked } catch LabError.staleEpoch { }
                try journal.record("restoreGateSurvivedReopen", store: reopened)
                result.events = driver.events + ["EXPECTED_RESTORE_FENCE_OBSERVED"]
                await driver.stop(); self.driver = nil
                result.faultObservations = try journal.read()
            case .waitForAccountChange:
                guard let driver, let store else { throw LabError.blocked }
                try journal.record("beforeAccountChange", store: store)
                let deadline = Date().addingTimeInterval(600)
                while !driver.halted, Date() < deadline {
                    try Task.checkCancellation(); try await Task.sleep(nanoseconds: 500_000_000)
                }
                guard driver.halted, driver.events.contains("ACCOUNT_CHANGED_REOPEN_REQUIRED") else { throw LabError.blocked }
                try journal.record("accountChangeFenced", store: store)
                result.events = driver.events + ["EXPECTED_ACCOUNT_FENCE_OBSERVED"]
                await driver.stop(); self.driver = nil
                accountSource = "cachedPartitionNotCurrentAccount"
                result.faultObservations = try journal.read()
            case .closePartition:
                await driver?.stop(); driver = nil
            case .save:
                guard let store, let m = command.mutation else { throw LabError.blocked }
                try store.save(m, image: Self.fixture(hash: m.imageHash, count: m.imageBytes))
            case .sync:
                guard let driver else { throw LabError.blocked }
                try await driver.sync()
                guard !driver.halted else { throw LabError.blocked }
            case .snapshot: break
            case .reopen:
                await driver?.stop(); driver = nil
                if let binding = store?.binding { store = try LabStore(base: base, binding: binding) }
                try await connect()
            case .stop:
                await driver?.stop(); driver = nil
            }
            guard let store else { throw LabError.blocked }
            let captured = try captureProbeSnapshot(store)
            result.snapshot = captured.0; result.unavailableImages = captured.1
            result.snapshotComplete = captured.1.isEmpty
            result.projections = try store.projections().mapValues { ProbeProjection(state: $0.state, candidates: $0.candidates, preview: $0.preview, complete: $0.complete) }
            result.pendingKeys = try store.pending().map(\.key)
            result.checkpointHash = try store.checkpoint().map(digest)
            result.status = "PASS"
        } catch let error as CKError { result.errorCode = "CK_" + String(error.errorCode) }
        catch let error as LabError { result.errorCode = "LAB_" + String(describing: error) }
        catch { result.errorCode = "LOCAL_FAILURE" }
        result.processNonce = ProbeProcessIdentity.nonce; result.processID = getpid()
        result.accountFingerprint = connectedFingerprint
        result.accountSource = accountSource
        result.events = driver?.events ?? result.events
        result.halted = driver?.halted ?? false
        if command.action == .closePartition, result.status == "PASS" {
            store = nil; connectedFingerprint = nil; accountSource = nil
        }
        return result
    }

    // iPhone commands run once per actual process launch. Results live only in
    // this app's Documents directory and are copied with devicectl by bundle ID.
    public func runOnce(_ encoded: String) async throws -> ProbeResult {
        guard let data = Data(base64Encoded: encoded), data.count <= 65_536 else { throw LabError.limit }
        let command = try JSONDecoder().decode(ProbeCommand.self, from: data)
        try command.validate()
        try ensureExclusive()
        try rejectLegacySharedJournal(command)
        let journal = try ProbeJournal(root: base.appendingPathComponent("probe-journals"), dataset: dataset, runID: runID)
        if let existing = try journal.claim(command, bytes: data) {
            try exportCommand(existing); return existing
        }
        var result = await perform(command, requestDigest: digest(data))
        result.commandDigest = digest(data)
        try journal.complete(result)
        try exportCommand(result)
        return result
    }

    private func rejectLegacySharedJournal(_ command: ProbeCommand) throws {
        let legacy = URL.documentsDirectory.appendingPathComponent("SyncLab-Probe").appendingPathComponent(runID)
            .appendingPathComponent(dataset).appendingPathComponent(command.id + ".request.json")
        // Do not promote formerly shared files to trusted evidence or silently replay them.
        guard !FileManager.default.fileExists(atPath: legacy.path) else { throw LabError.blocked }
    }
    private func exportCommand(_ result: ProbeResult) throws {
        try publishProbeExport(canonical(result), to: URL.documentsDirectory.appendingPathComponent("SyncLab-" + runID + "-" + result.id + ".json"))
    }

    // A fixed loopback bridge lets the original Mac user coordinate a signed
    // app the Owner explicitly launches in the isolated GUI user. Network
    // client entitlement is already present; no sandbox bypass or remote shell.
    public static func loopbackURL(_ value: String) throws -> URL {
        guard let parts = URLComponents(string: value), parts.scheme == "http", parts.host == "127.0.0.1",
              let port = parts.port, (1024...65535).contains(port), parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.path.isEmpty || parts.path == "/",
              let url = parts.url else { throw LabError.invalidWire }
        return url
    }
    public func runBridge(_ address: String, token: String, report: (String) -> Void) async throws {
        guard authorization.isEnabled, isHash(token) else { throw LabError.blocked }
        let endpoint = try Self.loopbackURL(address)
        try ensureExclusive()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
        config.connectionProxyDictionary = [:]
        let session = URLSession(configuration: config, delegate: ProbeLoopbackSession(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        // Bounded session, no persistent helper/login item. Close the app to stop.
        let deadline = Date().addingTimeInterval(3600)
        while Date() < deadline, !Task.isCancelled {
            var get = URLRequest(url: endpoint.appendingPathComponent("next"))
            get.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: get)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 65_536 else { throw LabError.blocked }
            if !data.isEmpty {
                let command = try JSONDecoder().decode(ProbeCommand.self, from: data)
                try command.validate()
                try rejectLegacySharedJournal(command)
                let journal = try ProbeJournal(root: base.appendingPathComponent("probe-journals"), dataset: dataset, runID: runID)
                var result: ProbeResult
                if let existing = try journal.claim(command, bytes: data) { result = existing }
                else {
                    result = await perform(command, requestDigest: digest(data)); result.commandDigest = digest(data)
                    try journal.complete(result)
                }
                var post = URLRequest(url: endpoint.appendingPathComponent("result"))
                post.httpMethod = "POST"; post.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
                post.setValue("application/json", forHTTPHeaderField: "Content-Type")
                post.httpBody = try canonical(result)
                let (_, reply) = try await session.data(for: post)
                guard (reply as? HTTPURLResponse)?.statusCode == 200 else { throw LabError.blocked }
                report(command.id + ": " + result.status + " " + (result.errorCode ?? ""))
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    // Fixed local-document transport for devices whose developer image is unavailable.
    // Loading a document never starts this method; the Owner must tap the Debug button.
    public func runManualPlan(_ bytes: Data, documents: URL) async throws -> ManualProbeExecution {
        guard !manualPlanRunning else { throw LabError.blocked }
        try Task.checkCancellation()
        guard authorization.isEnabled else { throw LabError.blocked }
        manualPlanRunning = true
        defer { manualPlanRunning = false }
        let plan = try ManualProbePlan.decode(bytes)
        guard plan.dataset == dataset, plan.runID == runID else { throw LabError.identityCollision }
        try ensureExclusive()
        do {
            let journal = try ManualProbeJournal(root: base.appendingPathComponent("manual-plan-journals"), plan: plan)
            let output = documents.appendingPathComponent("SyncLab-Manual-" + plan.id + ".json")
            if let cached = try journal.claim(bytes) {
                try publishProbeExport(Data(contentsOf: journal.resultURL), to: output)
                await shutdown(); return ManualProbeExecution(report: cached, exportURL: output, reusedOriginal: true)
            }
            let commands = try ProbeJournal(root: base.appendingPathComponent("probe-journals"), dataset: dataset, runID: runID, contextID: plan.id)
            var report = ManualProbeReport(planID: plan.id, dataset: dataset, runID: runID,
                                           planDigest: digest(bytes), results: [])
            for command in plan.commands {
                do {
                    try Task.checkCancellation()
                    let commandBytes = try canonical(command)
                    var result: ProbeResult
                    if let cached = try commands.claim(command, bytes: commandBytes) { result = cached }
                    else {
                        result = await perform(command, planID: plan.id); result.commandDigest = digest(commandBytes); result.planID = plan.id
                        try commands.complete(result)
                    }
                    report.results.append(result)
                    if result.status != "PASS" || result.halted || result.errorCode != nil {
                        report.errorCode = result.errorCode ?? (result.halted ? "ENGINE_HALTED" : "COMMAND_FAILED"); break
                    }
                } catch is CancellationError { report.errorCode = "CANCELLED"; break }
                catch let error as LabError {
                    report.errorCode = "LAB_" + String(describing: error); break
                } catch { report.errorCode = "LOCAL_FAILURE"; break }
            }
            report.completedAllCommands = report.results.count == plan.commands.count && report.results.allSatisfy { $0.status == "PASS" && !$0.halted && $0.errorCode == nil }
            await driver?.stop(); driver = nil // Keep the process lock through report publication.
            try journal.complete(report)
            try publishProbeExport(Data(contentsOf: journal.resultURL), to: output)
            await shutdown()
            return ManualProbeExecution(report: report, exportURL: output, reusedOriginal: false)
        } catch { await shutdown(); throw error }
    }
}
#endif
