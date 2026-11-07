#if DEBUG
import Foundation

/// Independent-process harness for the exact Debug command path. No CKContainer
/// is constructed: only openCached/save/reopenLocal/inspectFaults are permitted.
public enum OfflineFaultReplay {
    @MainActor public static func run(mode: String, base: URL) async throws {
        let dataset = "synthetic-g1-process-fault", run = "probe-process-fault"
        let binding = try Binding(accountHash: digest(Data("SYNTHETIC-OFFLINE-ONLY".utf8)), dataset: dataset)
        let cache = ProbeAccountCache(base: base, dataset: dataset, runID: run)
        let old = Mutation(id: "probe-old", object: "probe-entry", text: "SYNTHETIC committed baseline")
        let new = Mutation(id: "probe-new", object: "probe-entry", parents: [old.id], text: "SYNTHETIC next transaction")
        if mode == "seed" {
            guard !FileManager.default.fileExists(atPath: base.path) else { throw LabError.blocked }
            try cache.remember(binding, fingerprint: digest(Data("SYNTHETIC-LOCAL-FINGERPRINT".utf8)), slot: "A")
            try LabStore(base: base, binding: binding).save(old)
            print("PASS LOCAL_ONLY seed")
            return
        }
        guard ["before", "after", "verify-before", "verify-after"].contains(mode) else { throw LabError.invalidWire }
        let probe = try DevelopmentProbe(base: base, dataset: dataset, runID: run, authorization: .afterExplicitManualConsent())
        var open = ProbeCommand(id: "probe-open", action: .openCached); open.accountSlot = "A"
        let opened = await probe.perform(open)
        guard opened.status == "PASS" else { throw LabError.blocked }
        let before = mode.hasSuffix("before")
        let crash = ProbeCommand(id: before ? "probe-crash-before" : "probe-crash-after", action: before ? .crashBeforeSave : .crashAfterSave, mutation: new)
        if !mode.hasPrefix("verify-") {
            _ = await probe.perform(crash)
            throw LabError.blocked // Deliberate exit must prevent this return.
        }
        var inspect = ProbeCommand(id: "probe-inspect", action: .inspectFaults)
        inspect.faultSource = ProbeFaultSource(commandID: crash.id, commandDigest: try digest(canonical(crash)))
        let evidence = await probe.perform(inspect)
        guard evidence.status == "PASS", let observations = evidence.faultObservations,
              observations.allSatisfy({ $0.processNonce != evidence.processNonce && $0.processID != ProcessInfo.processInfo.processIdentifier }),
              observations.contains(where: { $0.point == (before ? "beforeSaveCommit" : "afterSaveCommit") }),
              evidence.snapshot?.envelopes.first?.mutations == (before ? [old] : [new, old]),
              evidence.pendingKeys == ["object-probe-entry"], evidence.accountSource == "cachedPartitionNotCurrentAccount"
        else { throw LabError.blocked }
        print("PASS LOCAL_ONLY independent process " + mode + "; durable facts and outbox verified")
        await probe.shutdown()
    }
}
#endif
