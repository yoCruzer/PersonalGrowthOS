#if DEBUG
import XCTest
import CloudKit
@testable import SyncLab

final class ProbeFaultTests: XCTestCase {
    let dataset = "synthetic-g1-fault-tests"
    let run = "probe-fault-tests"
    func root() -> URL { .temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    func binding(_ name: String = "A") throws -> Binding { try Binding(accountHash: digest(Data(("SYNTHETIC-" + name).utf8)), dataset: dataset) }
    @MainActor func journal(_ base: URL, _ name: String = "probe-fault") throws -> ProbeFaultJournal {
        try ProbeFaultJournal(base: base, dataset: dataset, runID: run,
            source: ProbeFaultSource(commandID: name, commandDigest: digest(Data(name.utf8))))
    }
    func testAllFaultStagesBindRecoveryToExactSource() throws {
        let values = try FaultBatch.stages(dataset: dataset, runID: run)
        XCTAssertEqual(values.count, 27)
        XCTAssertEqual(values.compactMap(\.expectedExit), [75,76,73,74,77])
        XCTAssertEqual(Set(values.map { $0.plan.id }).count, 27)
        for stage in values {
            XCTAssertNoThrow(try ManualProbePlan.decode(canonical(stage.plan)))
            for command in stage.plan.commands {
                if let source = command.faultSource {
                    let original = try XCTUnwrap(values.first { $0.plan.id == source.planID })
                    let crash = try XCTUnwrap(original.plan.commands.first { $0.id == source.commandID })
                    XCTAssertEqual(source.commandDigest, try digest(canonical(crash)))
                    XCTAssertEqual(original.plan.dataset, stage.plan.dataset)
                }
            }
        }
        let other = try FaultBatch.stages(dataset: dataset, runID: "probe-other-run")
        XCTAssertTrue(Set(values.map { $0.plan.id }).isDisjoint(with: other.map { $0.plan.id }))
        XCTAssertThrowsError(try FaultBatch.stages(dataset: "daily", runID: run))
    }
    @MainActor func testCloudBoundaryMissingAssetStillRetainsFactsLocalSeam() throws {
        let store = try LabStore(base: root(), binding: binding()), value = try journal(root())
        let bytes = DevelopmentProbe.png
        let mutation = Mutation(id: "probe-incoming", object: "probe-incoming", text: "SYNTHETIC incoming", imageHash: digest(bytes), imageBytes: bytes.count)
        try store.receiveEnvelope(Envelope(object: mutation.object, mutations: [mutation]).encoded(), key: "object-" + mutation.object, fields: Data(), ticket: store.epoch)
        value.provenance = "actualCloudKitCallback" // Local test of this serialization branch, not real CloudKit proof.
        try value.record("partial", store: store)
        let observation = try XCTUnwrap(value.read().first)
        XCTAssertEqual(observation.unavailableImages, [digest(bytes)])
        XCTAssertEqual(observation.snapshot?.envelopes.first?.mutations, [mutation])
        XCTAssertFalse(isUnavailableOriginal(LabError.invalidWire))
        XCTAssertFalse(isUnavailableOriginal(LabError.limit))
        XCTAssertFalse(isUnavailableOriginal(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)))
    }
    func testPhoneBundleIsBoundedValidatedAndSelectionDoesNotAuthorize() throws {
        let stages = try FaultBatch.stages(dataset: dataset, runID: run)
        var bundle = ManualProbeBundle(items: stages.filter { $0.device == "iOS" }.map { .init(title: $0.name, plan: $0.plan) })
        let loaded = try ManualProbeBundle.decode(canonical(bundle))
        XCTAssertEqual(loaded.items.count, 8)
        for item in loaded.items { XCTAssertEqual(try loaded.bytes(for: item.plan.id), try canonical(item.plan)) }
        XCTAssertThrowsError(try loaded.bytes(for: "probe-unknown"))
        XCTAssertFalse(DevelopmentAuthorization.fromEnvironment().isEnabled)
        bundle.items.append(bundle.items[0]); XCTAssertThrowsError(try ManualProbeBundle.decode(canonical(bundle)))
        bundle.items = Array(bundle.items.prefix(1)); bundle.items[0].plan.dataset = "daily"
        XCTAssertThrowsError(try ManualProbeBundle.decode(canonical(bundle)))
        XCTAssertThrowsError(try ManualProbeBundle.decode(Data(repeating: 32, count: 524289)))
    }
    func testStrictCommandOptions() throws {
        for action in [ProbeCommand.Action.openCached, .inspectFaults, .crashBeforeSave, .editDuringSend, .restoreIsolation] {
            XCTAssertThrowsError(try ProbeCommand(id: "probe-invalid", action: action).validate())
        }
        var value = ProbeCommand(id: "probe-cache", action: .openCached)
        value.accountSlot = "A"; XCTAssertNoThrow(try value.validate())
        value.accountSlot = "../A"; XCTAssertThrowsError(try value.validate())
        value.accountSlot = "B"; value.action = .save; XCTAssertThrowsError(try value.validate())
    }
    func testAccountCacheCannotRebindOrAliasPartitions() throws {
        let cache = ProbeAccountCache(base: root(), dataset: dataset, runID: run)
        let fp = digest(Data("SYNTHETIC-FINGERPRINT-A".utf8))
        try cache.remember(binding(), fingerprint: fp, slot: "A")
        XCTAssertEqual(try cache.load("A").binding, try binding())
        XCTAssertThrowsError(try cache.remember(binding("B"), fingerprint: fp, slot: "A"))
        XCTAssertThrowsError(try cache.remember(binding(), fingerprint: fp, slot: "B"))
        try cache.remember(binding("B"), fingerprint: digest(Data("SYNTHETIC-B".utf8)), slot: "B")
        XCTAssertNotEqual(try cache.load("A").binding, try cache.load("B").binding)
    }
    @MainActor func testOfflinePartitionSaveAndReopenNeverNeedsCloud() async throws {
        let base = root()
        try ProbeAccountCache(base: base, dataset: dataset, runID: run).remember(binding(), fingerprint: digest(Data("SYNTHETIC-FP".utf8)), slot: "A")
        let probe = try DevelopmentProbe(base: base, dataset: dataset, runID: run, authorization: .afterExplicitManualConsent())
        var open = ProbeCommand(id: "probe-open", action: .openCached); open.accountSlot = "A"
        let opened = await probe.perform(open)
        XCTAssertEqual(opened.status, "PASS"); XCTAssertEqual(opened.accountSource, "cachedPartitionNotCurrentAccount")
        let mutation = Mutation(id: "probe-offline", object: "probe-offline", text: "SYNTHETIC offline")
        let saved = await probe.perform(ProbeCommand(id: "probe-save", action: .save, mutation: mutation))
        let reopened = await probe.perform(ProbeCommand(id: "probe-reopen", action: .reopenLocal))
        XCTAssertEqual(saved.status, "PASS"); XCTAssertEqual(reopened.status, "PASS")
        XCTAssertEqual(reopened.pendingKeys, ["object-probe-offline"])
        XCTAssertEqual(try canonical(saved.snapshot), try canonical(reopened.snapshot))
        XCTAssertEqual(reopened.events, [])
        await probe.shutdown()
    }
    @MainActor func testPartialRecoveryCanOpenInspectAndReopenWithoutCloud() async throws {
        let base = root(), b = try binding()
        let store = try LabStore(base: base, binding: b)
        let bytes = DevelopmentProbe.png
        let mutation = Mutation(id: "probe-partial", object: "probe-partial", text: "SYNTHETIC partial", imageHash: digest(bytes), imageBytes: bytes.count)
        try store.receiveEnvelope(Envelope(object: mutation.object, mutations: [mutation]).encoded(), key: "object-" + mutation.object, fields: Data(), ticket: store.epoch)
        try ProbeAccountCache(base: base, dataset: dataset, runID: run).remember(b, fingerprint: digest(Data("SYNTHETIC-FP".utf8)), slot: "A")
        let probe = try DevelopmentProbe(base: base, dataset: dataset, runID: run, authorization: .afterExplicitManualConsent())
        var open = ProbeCommand(id: "probe-open-partial", action: .openCached); open.accountSlot = "A"
        for command in [open, ProbeCommand(id: "probe-partial-reopen", action: .reopenLocal), ProbeCommand(id: "probe-partial-snapshot", action: .snapshot)] {
            let result = await probe.perform(command)
            XCTAssertEqual(result.status, "PASS")
            XCTAssertEqual(result.snapshotComplete, false)
            XCTAssertEqual(result.unavailableImages, [digest(bytes)])
            XCTAssertEqual(result.snapshot?.envelopes.first?.mutations, [mutation])
        }
        XCTAssertThrowsError(try store.exportSnapshot()) // Diagnostic capture never relaxes backup requirements.
        await probe.shutdown()
    }
    @MainActor func testJournalIsImmutableAndIdentityBound() throws {
        let base = root(), store = try LabStore(base: root(), binding: binding()), value = try journal(base)
        try value.record("baseline", store: store)
        XCTAssertThrowsError(try value.record("baseline", store: store))
        let read = try value.read(); XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read[0].processID, ProcessInfo.processInfo.processIdentifier)
        let wrong = try ProbeFaultJournal(base: base, dataset: dataset, runID: run, source: ProbeFaultSource(commandID: "probe-fault", commandDigest: digest(Data("wrong".utf8))))
        XCTAssertThrowsError(try wrong.read())
        XCTAssertThrowsError(try value.read(accountHash: binding("B").accountHash))
    }
    @MainActor func testMissingAndTruncatedOriginalsRetainEvidenceAndRepair() throws {
        let store = try LabStore(base: root(), binding: binding()), value = try journal(root())
        for (index, bytes) in [DevelopmentProbe.png, DevelopmentProbe.secondPNG].enumerated() {
            try store.save(Mutation(id: "probe-image-\(index)", object: "probe-image-\(index)", text: "SYNTHETIC image", imageHash: digest(bytes), imageBytes: bytes.count), image: bytes)
        }
        let before = try store.exportSnapshot()
        try exerciseImageFaults(store: store, journal: value)
        XCTAssertEqual(try store.exportSnapshot(), before)
        let evidence = try value.read()
        XCTAssertEqual(evidence.count, 10)
        XCTAssertEqual(evidence.filter { $0.snapshotError == "expectedOriginalUnavailable" }.count, 4)
        XCTAssertTrue(FileManager.default.fileExists(atPath: value.directory.appendingPathComponent("held-original-0").path))
    }
    @MainActor func testRestoreFencesOldReceiverAndPersistsTargetGateLocalSeam() throws {
        let store = try LabStore(base: root(), binding: binding()), value = try journal(root())
        let source = try LabStore(base: root(), binding: binding())
        try source.save(Mutation(id: "probe-remote", object: "probe-remote", text: "SYNTHETIC remote"))
        let pending = try XCTUnwrap(source.pending().first)
        let record = try Wire.record(pending, dataset: dataset, imageURL: source.imageURL)
        let ticket = store.epoch
        let fault = ProbeCloudFault(action: .restoreIsolation, journal: value, mutation: Mutation(id: "probe-restored", object: "probe-restored", text: "SYNTHETIC restored"))
        try fault.observe(.beforeFetchedInstall, store: store, records: [record])
        XCTAssertTrue(fault.reached)
        XCTAssertThrowsError(try store.receiveEnvelope(pending.payload, key: pending.key, fields: Data(), ticket: ticket))
        XCTAssertTrue(try store.envelopes().isEmpty)
        let restored = try LabStore(base: value.directory.appendingPathComponent("restore-target"), binding: binding())
        XCTAssertTrue(restored.stopped); XCTAssertNil(try restored.checkpoint())
        XCTAssertThrowsError(try restored.check(restored.epoch))
    }
    @MainActor func testOldACKLeavesNewVersionPendingAndACKWinningFailsLocalSeam() async throws {
        for ackWins in [false, true] {
            let store = try LabStore(base: root(), binding: binding()), value = try journal(root())
            let old = Mutation(id: "probe-old", object: "probe-entry", text: "SYNTHETIC old")
            let new = Mutation(id: "probe-new", object: "probe-entry", parents: [old.id], text: "SYNTHETIC new")
            try store.save(old)
            let pending = try XCTUnwrap(store.pending().first)
            let record = try Wire.record(pending, dataset: dataset, imageURL: store.imageURL)
            let fault = ProbeCloudFault(action: .editDuringSend, journal: value, mutation: new)
            defer { fault.cancel() }
            try fault.observe(.batchPrepared, store: store, records: [record])
            if ackWins {
                XCTAssertThrowsError(try fault.observe(.beforeACK, store: store, records: [record]))
                XCTAssertFalse(fault.reached)
            } else {
                try await Task.sleep(nanoseconds: 80_000_000)
                try fault.observe(.beforeACK, store: store, records: [record])
                try store.acknowledge(pending.key, sent: pending.payload, fields: Data(), ticket: store.epoch)
                try fault.observe(.afterACK, store: store, records: [record])
                XCTAssertTrue(fault.reached)
                XCTAssertEqual(try store.pending().map(\.key), [pending.key])
                XCTAssertEqual(try value.read().count, 4)
            }
        }
    }
}
#endif
