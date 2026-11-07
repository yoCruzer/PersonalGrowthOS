#if DEBUG
import Foundation
import Darwin

/// Offline plan preparation only. Generation grants no Development authorization.
/// Execute stages in order, with evidence inspection between devices.
public enum RemainingBatch {
    public static func plans(dataset: String, runID: String) throws -> [ManualProbePlan] {
        func mutation(_ id: String, _ object: String, parents: [String] = [], requires: [String] = [], deleted: Bool = false) -> Mutation {
            Mutation(id: "probe-batch-" + id, object: "probe-batch-" + object,
                     parents: parents.map { "probe-batch-" + $0 }, requires: requires.map { "probe-batch-" + $0 },
                     text: "SYNTHETIC batch " + id, deleted: deleted)
        }
        func plan(_ stage: String, _ mutations: [Mutation], observeFirst: Bool = false) -> ManualProbePlan {
            var commands = [ProbeCommand(id: "probe-" + stage + "-connect", action: .connect)]
            if observeFirst {
                commands += [ProbeCommand(id: "probe-" + stage + "-fetch", action: .sync),
                             ProbeCommand(id: "probe-" + stage + "-before", action: .snapshot)]
            }
            commands += mutations.enumerated().map { ProbeCommand(id: "probe-" + stage + "-save-" + String($0.offset), action: .save, mutation: $0.element) }
            commands += [ProbeCommand(id: "probe-" + stage + "-sync", action: .sync),
                         ProbeCommand(id: "probe-" + stage + "-drain", action: .sync),
                         ProbeCommand(id: "probe-" + stage + "-after", action: .snapshot)]
            // Full digest binds the export name as well as the private journal to this run.
            let identity = digest(Data((dataset + "|" + runID + "|" + stage).utf8))
            return ManualProbePlan(id: "probe-" + String(stage.prefix(2)) + "-" + identity, dataset: dataset, runID: runID, commands: commands)
        }
        let seed = plan("01-mac-seed", [
            mutation("deleted-live", "deleted"),
            mutation("deleted-tombstone", "deleted", parents: ["deleted-live"], deleted: true),
            mutation("deleted-child", "deleted-child", requires: ["deleted"]),
            mutation("missing-new", "missing", parents: ["missing-parent"]),
            mutation("trans-mid", "trans-mid", requires: ["trans-leaf"]),
            mutation("trans-root", "trans-root", requires: ["trans-mid"]),
            mutation("dep-a", "dep-a", requires: ["dep-b"]),
            mutation("dep-b", "dep-b", requires: ["dep-a"]),
            mutation("head-old", "head"),
            mutation("head-new", "head", parents: ["head-old"], requires: ["head-dependency"]),
            mutation("cause-a", "cause", parents: ["cause-b"]),
            mutation("cause-b", "cause", parents: ["cause-a"])
        ])
        var image = mutation("new-image", "new-image")
        image.imageHash = digest(DevelopmentProbe.secondPNG); image.imageBytes = DevelopmentProbe.secondPNG.count
        let repair = plan("02-ios-repair", [
            mutation("missing-parent", "missing"), mutation("trans-leaf", "trans-leaf"),
            mutation("head-dependency", "head-dependency"), image
        ], observeFirst: true)
        let verify = plan("03-mac-fetch", [])
        for value in [seed, repair, verify] { try value.validate() }
        return [seed, repair, verify]
    }
    /// Refuse existing destinations, including symlinks. Never replaces prior inputs.
    public static func write(to directory: URL, dataset: String, runID: String) throws {
        let values = try plans(dataset: dataset, runID: runID)
        guard mkdir(directory.path, 0o700) == 0 else { throw LabError.blocked }
        for plan in values {
            let stage = directory.appendingPathComponent(plan.id)
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
            try canonical(plan).write(to: stage.appendingPathComponent("SyncLab-Probe-Plan.json"), options: .withoutOverwriting)
        }
    }
}
#endif
