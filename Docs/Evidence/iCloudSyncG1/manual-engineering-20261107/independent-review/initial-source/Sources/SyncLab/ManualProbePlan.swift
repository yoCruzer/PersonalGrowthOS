#if DEBUG
import Foundation
import Darwin

public struct ManualProbePlan: Codable {
    public var version = 1
    public var id: String
    public var dataset: String
    public var runID: String
    public var commands: [ProbeCommand]
    public func validate() throws {
        guard version == 1, validID(id), id.hasPrefix("probe-"),
              validID(runID), runID.hasPrefix("probe-"), validID(dataset), dataset.hasPrefix("synthetic-g1-"),
              (1...16).contains(commands.count), Set(commands.map(\.id)).count == commands.count
        else { throw LabError.invalidWire }
        for command in commands { try command.validate() }
    }
    public static func decode(_ bytes: Data) throws -> Self {
        guard bytes.count <= 262_144 else { throw LabError.limit }
        let plan = try JSONDecoder().decode(Self.self, from: bytes)
        try plan.validate(); return plan
    }
    public static func readImportedPlan(documents: URL) throws -> Data {
        let url = documents.appendingPathComponent("SyncLab-Probe-Plan.json")
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw LabError.invalidWire }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true); defer { try? file.close() }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG else { throw LabError.invalidWire }
        let bytes = try file.read(upToCount: 262_145) ?? Data()
        _ = try decode(bytes); return bytes
    }
}

public struct ManualProbeReport: Codable {
    public var scope = "Command execution only; not cloud convergence or G1 acceptance"
    public var planID: String
    public var dataset: String
    public var runID: String
    public var planDigest: String
    public var results: [ProbeResult]
    public var completedAllCommands = false
    public var errorCode: String?
    func validate(plan: ManualProbePlan, bytes: Data) throws {
        guard planID == plan.id, dataset == plan.dataset, runID == plan.runID,
              planDigest == digest(bytes), results.count <= plan.commands.count else { throw LabError.identityCollision }
        for (index, result) in results.enumerated() {
            let command = plan.commands[index]
            guard result.id == command.id, result.dataset == dataset, result.runID == runID,
                  result.commandDigest == (try digest(canonical(command))), ["PASS", "FAIL"].contains(result.status),
                  (result.status == "PASS" && !result.halted && result.errorCode == nil) || index == results.count - 1 else { throw LabError.identityCollision }
        }
        let complete = results.count == plan.commands.count && results.allSatisfy { $0.status == "PASS" && !$0.halted && $0.errorCode == nil }
        guard completedAllCommands == complete, !complete || errorCode == nil,
              complete || errorCode != nil else { throw LabError.identityCollision }
    }
}

// Plan identity and raw bytes are immutable. An interrupted plan remains blocked;
// individual command journals retain completed/indeterminate steps for inspection.
final class ManualProbeJournal {
    let directory: URL
    let resultURL: URL
    private let requestURL: URL
    private let plan: ManualProbePlan
    init(root: URL, plan: ManualProbePlan) throws {
        try plan.validate(); self.plan = plan
        directory = root.appendingPathComponent("SyncLab-Manual-Results").appendingPathComponent(plan.runID).appendingPathComponent(plan.dataset)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        requestURL = directory.appendingPathComponent(plan.id + ".request.json")
        resultURL = directory.appendingPathComponent(plan.id + ".json")
    }
    private func publish(_ bytes: Data, to target: URL) throws {
        let temporary = directory.appendingPathComponent(UUID().uuidString + ".tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try bytes.write(to: temporary, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: temporary); try handle.synchronize(); try handle.close()
        try FileManager.default.linkItem(at: temporary, to: target)
    }
    func claim(_ bytes: Data) throws -> ManualProbeReport? {
        let decoded = try ManualProbePlan.decode(bytes)
        guard try canonical(decoded) == canonical(plan) else { throw LabError.identityCollision }
        if FileManager.default.fileExists(atPath: requestURL.path) {
            guard try Data(contentsOf: requestURL) == bytes else { throw LabError.identityCollision }
            guard FileManager.default.fileExists(atPath: resultURL.path) else { throw LabError.blocked }
            let report = try JSONDecoder().decode(ManualProbeReport.self, from: Data(contentsOf: resultURL))
            try report.validate(plan: plan, bytes: bytes); return report
        }
        guard !FileManager.default.fileExists(atPath: resultURL.path) else { throw LabError.identityCollision }
        try publish(bytes, to: requestURL); return nil
    }
    func complete(_ report: ManualProbeReport) throws {
        let bytes = try Data(contentsOf: requestURL)
        try report.validate(plan: plan, bytes: bytes)
        try publish(canonical(report), to: resultURL)
    }
}
#endif
