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

private final class ProbeLoopbackSession: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never forward the bearer token away from loopback.
    }
}

// Opt-in test transport only. It never accepts paths, container IDs, account IDs,
// arbitrary URLs, shell commands, or non-synthetic mutations from a controller.
public struct ProbeCommand: Codable {
    public enum Action: String, Codable { case connect, save, sync, snapshot, reopen, stop }
    public var id: String
    public var action: Action
    public var mutation: Mutation?
    public init(id: String, action: Action, mutation: Mutation? = nil) {
        self.id = id; self.action = action; self.mutation = mutation
    }
    public func validate() throws {
        guard validID(id), id.hasPrefix("probe-") else { throw LabError.invalidWire }
        if action == .save {
            guard let m = mutation else { throw LabError.invalidWire }
            try m.validate()
            guard m.id.hasPrefix("probe-"), m.object.hasPrefix("probe-"),
                  m.parents.allSatisfy({ $0.hasPrefix("probe-") }),
                  m.requires.allSatisfy({ $0.hasPrefix("probe-") }),
                  m.text.hasPrefix("SYNTHETIC"),
                  (m.imageHash == nil && m.imageBytes == nil) ||
                    (m.imageHash == digest(DevelopmentProbe.png) && m.imageBytes == DevelopmentProbe.png.count)
            else { throw LabError.invalidWire }
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
    public let dataset: String
    private let base: URL
    private var store: LabStore?
    private var driver: CloudDriver?
    private var runID: String
    private var connectedFingerprint: String?
    private var processLock: ProbeProcessLock?
    private let authorization: DevelopmentAuthorization
    private var manualPlanRunning = false
    public init(base: URL, dataset: String, runID: String, authorization: DevelopmentAuthorization = .fromEnvironment()) throws {
        guard validID(dataset), dataset.hasPrefix("synthetic-g1-"), validID(runID), runID.hasPrefix("probe-") else { throw LabError.invalidWire }
        self.base = base; self.dataset = dataset; self.runID = runID
        self.authorization = authorization
    }
    private func ensureExclusive() throws {
        guard authorization.isEnabled else { throw LabError.blocked }
        if processLock == nil { processLock = try ProbeProcessLock(base: base, dataset: dataset) }
    }
    public func shutdown() async {
        await driver?.stop(); driver = nil
        processLock = nil
    }
    static var reviewConnectCount = 0
    static var reviewConnectHook: (() async -> Void)?
    private func connect() async throws {
        Self.reviewConnectCount += 1
        await Self.reviewConnectHook?()
        throw LabError.blocked // REVIEW SEAM: never call CloudKit in this copy.

        guard authorization.isEnabled else { throw LabError.blocked }
        if driver != nil { return }
        let container = CKContainer(identifier: Binding.container)
        guard try await container.accountStatus() == .available else { throw LabError.blocked }
        let user = try await container.userRecordID()
        // Salt is a synthetic per-run value. No raw account identifier is exported.
        connectedFingerprint = digest(Data((runID + "|" + user.recordName).utf8))
        let binding = try Binding(accountHash: digest(Data(user.recordName.utf8)), dataset: dataset)
        if let old = store, old.binding != binding { throw LabError.staleEpoch }
        let local = try LabStore(base: base, binding: binding)
        store = local
        let cloud = CloudDriver(store: local)
        driver = cloud; try await cloud.start(authorization: authorization)
    }
    static var reviewPerformHook: ((ProbeCommand) async -> ProbeResult)?
    public func perform(_ command: ProbeCommand) async -> ProbeResult {
        if let hook = Self.reviewPerformHook { return await hook(command) } // REVIEW SEAM: deterministic command result, no cloud.

        #if os(macOS)
        let platform = "macOS"
        #else
        let platform = "iOS"
        #endif
        var result = ProbeResult(id: command.id, dataset: dataset, runID: runID, commandDigest: (try? canonical(command)).map(digest) ?? "", status: "FAIL", events: [], halted: driver?.halted ?? false, platform: platform)
        do {
            try command.validate()
            guard authorization.isEnabled else { throw LabError.blocked }
            try ensureExclusive()
            if store == nil { try await connect() }
            switch command.action {
            case .connect: try await connect()
            case .save:
                guard let store, let m = command.mutation else { throw LabError.blocked }
                try store.save(m, image: m.imageHash == nil ? nil : Self.png)
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
            result.snapshot = try JSONDecoder().decode(LabSnapshot.self, from: store.exportSnapshot())
            result.projections = try store.projections().mapValues { ProbeProjection(state: $0.state, candidates: $0.candidates, preview: $0.preview, complete: $0.complete) }
            result.pendingKeys = try store.pending().map(\.key)
            result.checkpointHash = try store.checkpoint().map(digest)
            result.status = "PASS"
        } catch let error as CKError { result.errorCode = "CK_" + String(error.errorCode) }
        catch let error as LabError { result.errorCode = "LAB_" + String(describing: error) }
        catch { result.errorCode = "LOCAL_FAILURE" }
        result.accountFingerprint = connectedFingerprint
        result.events = driver?.events ?? []
        result.halted = driver?.halted ?? false
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
        var result = await perform(command)
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
                    result = await perform(command); result.commandDigest = digest(data)
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
                        result = await perform(command); result.commandDigest = digest(commandBytes); result.planID = plan.id
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
