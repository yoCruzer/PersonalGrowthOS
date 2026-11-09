import XCTest
import SwiftData
import CloudKit
import SyncFoundation
@testable import PersonalGrowthOS

@MainActor final class SyncCoordinatorTests: XCTestCase {
    private var roots: [URL] = []
    override func tearDownWithError() throws {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots = []
    }
    private func root() throws -> URL {
        let result = FileManager.default.temporaryDirectory.appendingPathComponent("PGOS-Synthetic-Coordinator-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: false)
        roots.append(result); return result
    }
    private func fixture() throws -> (ModelContainer, SyncProductCoordinator, SyncCloudSession) {
        let container = try PersistenceContainerFactory.makeInMemory()
        container.mainContext.autosaveEnabled = false
        let dataset = ProductSyncDataset()
        dataset.accountHash = String(repeating: "a", count: 64)
        dataset.initialized = true; dataset.enabled = true
        container.mainContext.insert(dataset); try container.mainContext.save()
        let binding = try SyncBinding(container: SyncProductCoordinator.containerID, environment: .development,
            accountHash: dataset.accountHash!, dataset: dataset.id, generation: dataset.generation)
        return (container, SyncProductCoordinator(container: container, mediaRoot: try root(), environment: .development, automaticSync: false),
                SyncCloudSession(binding: binding))
    }
    private func mutation(dataset: UUID, object: UUID, parent: UUID? = nil, content: String,
                          originals: [OriginalReference] = []) throws -> ProductSyncMutation {
        let bytes = Data(content.utf8)
        let manifest = try MutationManifest(dataset: dataset, mutation: UUID(),
            object: SyncObject(kind: "entry", id: object), parents: parent.map { [$0] } ?? [],
            payload: PayloadManifest(bytes: bytes), originals: originals)
        return try ProductSyncMutation(manifest, payload: bytes, transactionID: UUID(), local: true)
    }
    private func queue(_ mutations: [ProductSyncMutation], in container: ModelContainer) throws {
        let context = container.mainContext
        for mutation in mutations { context.insert(mutation); context.insert(ProductSyncOutbox(mutation)) }
        try context.save()
    }
    private func completed(_ id: UUID, in container: ModelContainer) throws -> Bool {
        try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<ProductSyncOutbox>(predicate: #Predicate { $0.mutationID == id })).first).completed
    }
    private func cloned(_ binding: SyncBinding, container: String? = nil, account: String? = nil,
                        generation: UUID? = nil) throws -> SyncCloudSession {
        SyncCloudSession(binding: try SyncBinding(container: container ?? binding.container, environment: binding.environment,
            accountHash: account ?? binding.accountHash, dataset: binding.dataset, generation: generation ?? binding.generation))
    }

    func testPrimaryDurablePauseSurvivesSecondaryCancellationAndReconciliationFlags() throws {
        for reason in [SyncCloudPauseReason.accountChanged, .zoneMissing, .invalidRecord, .persistenceFailure] {
            let (container, coordinator, session) = try fixture()
            coordinator.didPause(reason, binding: session.binding)
            let first = coordinator.status
            coordinator.presentFailure(CKError(.operationCancelled), binding: session.binding)
            XCTAssertEqual(coordinator.status, first)
            XCTAssertTrue(coordinator.requiresAttention)
            XCTAssertFalse(coordinator.canAutomaticallySync)
            let canonical = "Sync paused (\(reason)); local data and pending revisions are kept."
            XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<ProductSyncDataset>()).first?.blockedReason, canonical)
            XCTAssertEqual(SyncProductCoordinator.localizedStoredStatus(canonical), first)
        }
    }
    func testOldGenerationCancellationCannotOverwriteCurrentStatus() throws {
        let (container, coordinator, session) = try fixture()
        let context = ModelContext(container), value = try XCTUnwrap(context.fetch(FetchDescriptor<ProductSyncDataset>()).first)
        value.generation = UUID(); value.enabled = false; try context.save()
        coordinator.refreshStatus(); let status = coordinator.status
        coordinator.presentFailure(CKError(.operationCancelled), binding: session.binding)
        XCTAssertEqual(coordinator.status, status); XCTAssertFalse(coordinator.requiresAttention); XCTAssertFalse(coordinator.enabled)
    }
    func testPreBindingFailureDoesNotPresentAnEarlierPersistedReason() throws {
        let (_, coordinator, session) = try fixture()
        coordinator.didPause(.accountChanged, binding: session.binding)
        coordinator.presentFailure(SyncCloudTransportError.paused(.environmentMismatch), binding: nil)
        XCTAssertTrue(coordinator.status.contains("environmentMismatch")); XCTAssertFalse(coordinator.status.contains("accountChanged"))
    }
    func testZoneCreationAdmissionRequiresExactBindingAndUnconsumedPersistentIntent() throws {
        let (container, coordinator, session) = try fixture()
        let context = ModelContext(container), value = try XCTUnwrap(context.fetch(FetchDescriptor<ProductSyncDataset>()).first)
        XCTAssertFalse(try coordinator.permitsPendingZoneCreation(session: session))
        value.zoneCreationAttempted = true; try context.save()
        XCTAssertTrue(try coordinator.permitsPendingZoneCreation(session: session))
        value.zoneEstablished = true; try context.save()
        XCTAssertFalse(try coordinator.permitsPendingZoneCreation(session: session))
        value.zoneEstablished = false; value.zoneLost = true; try context.save()
        XCTAssertFalse(try coordinator.permitsPendingZoneCreation(session: session))
        XCTAssertThrowsError(try coordinator.permitsPendingZoneCreation(session: cloned(session.binding, generation: UUID())))
        session.invalidate()
        XCTAssertThrowsError(try coordinator.permitsPendingZoneCreation(session: session))
    }
    func testInitialZoneProbeOnlyAcceptsExactMissingAndFencesAccountChanges() async throws {
        let (_, _, session) = try fixture(), binding = session.binding
        let zone = CloudRecordCodec.zone(dataset: binding.dataset)
        var requests = 0
        let existing = try await SyncProductCoordinator.initialZoneExists(binding: binding, check: { try session.check() },
            account: { binding.accountHash }, fetch: { id in requests += 1; XCTAssertEqual(id, zone); return CKRecordZone(zoneID: id) })
        XCTAssertTrue(existing); XCTAssertEqual(requests, 1)
        let missing = try await SyncProductCoordinator.initialZoneExists(binding: binding, check: { try session.check() },
            account: { binding.accountHash }, fetch: { _ in throw CKError(.zoneNotFound) })
        XCTAssertFalse(missing)
        for code in [CKError.Code.networkUnavailable, .unknownItem, .partialFailure, .userDeletedZone] {
            do {
                _ = try await SyncProductCoordinator.initialZoneExists(binding: binding, check: { try session.check() },
                    account: { binding.accountHash }, fetch: { _ in throw CKError(code) })
                XCTFail("Only exact zoneNotFound may offer setup")
            } catch { XCTAssertEqual((error as? CKError)?.code, code) }
        }
        var samples = 0
        do {
            _ = try await SyncProductCoordinator.initialZoneExists(binding: binding, check: { try session.check() },
                account: { samples += 1; return samples == 1 ? binding.accountHash : String(repeating: "b", count: 64) },
                fetch: { _ in throw CKError(.zoneNotFound) })
            XCTFail("A changed account cannot authorize setup")
        } catch { XCTAssertEqual(error as? SyncCloudTransportError, .paused(.accountChanged)) }
        do {
            _ = try await SyncProductCoordinator.initialZoneExists(binding: binding, check: { try session.check() },
                account: { binding.accountHash }, fetch: { _ in session.invalidate(); throw CKError(.zoneNotFound) })
            XCTFail("A stop during metadata lookup must fence setup")
        } catch { XCTAssertEqual(error as? SyncCloudTransportError, .staleSession) }
    }
    func testInitialZoneConsentIsSingleUseAndPreservesExistingLocalQueue() throws {
        let (container, coordinator, session) = try fixture(), context = ModelContext(container)
        let value = try XCTUnwrap(context.fetch(FetchDescriptor<ProductSyncDataset>()).first)
        value.zoneCreationAttempted = true; try context.save()
        let change = try mutation(dataset: session.binding.dataset, object: UUID(), content: "retained original")
        try queue([change], in: container)
        XCTAssertTrue(try coordinator.initialZoneRecoveryEligible(session.binding))
        try coordinator.offerInitialZoneConsent(session.binding)
        XCTAssertTrue(coordinator.canConfirmInitialZoneCreation)
        XCTAssertEqual(coordinator.takeInitialZoneConsent(), session.binding)
        XCTAssertNil(coordinator.takeInitialZoneConsent()); XCTAssertFalse(coordinator.canConfirmInitialZoneCreation)
        let read = ModelContext(container)
        XCTAssertEqual(try read.fetch(FetchDescriptor<ProductSyncMutation>()).map(\.id), [change.id])
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<ProductSyncOutbox>()), 1)
        XCTAssertTrue(try XCTUnwrap(read.fetch(FetchDescriptor<ProductSyncDataset>()).first).zoneCreationAttempted)
        XCTAssertThrowsError(try coordinator.offerInitialZoneConsent(cloned(session.binding, generation: UUID()).binding))
    }
    func testInitialZoneConsentRejectsAnySuccessRemoteEvidenceOrCorruptAcknowledgements() throws {
        for scenario in 0..<9 {
            let (container, coordinator, session) = try fixture(), context = container.mainContext
            let value = try XCTUnwrap(context.fetch(FetchDescriptor<ProductSyncDataset>()).first)
            value.zoneCreationAttempted = true
            switch scenario {
            case 0: value.zoneEstablished = true
            case 1: value.zoneLost = true
            case 2: value.needsReconciliation = true
            case 3: value.lastSuccess = Date()
            case 4: context.insert(ProductSyncInbox(dataset: value.id, recordName: "synthetic", recordType: "synthetic", bytes: Data()))
            default:
                let change = try mutation(dataset: value.id, object: UUID(), content: "synthetic")
                change.local = scenario != 5
                context.insert(change)
                let outbox = ProductSyncOutbox(change)
                if scenario == 6 { outbox.acknowledgedRecords = Data("[\"synthetic-ack\"]".utf8) }
                if scenario == 7 { outbox.completed = true }
                if scenario == 8 { outbox.acknowledgedRecords = Data("invalid JSON".utf8) }
                context.insert(outbox)
            }
            try context.save()
            XCTAssertThrowsError(try coordinator.offerInitialZoneConsent(session.binding), "scenario \(scenario)")
            XCTAssertFalse(coordinator.canConfirmInitialZoneCreation)
            XCTAssertNil(coordinator.takeInitialZoneConsent())
        }
    }
    func testRefreshRetainsHistoricalCompletionAndDoesNotOverwriteActiveDownloadPhase() throws {
        let (container, coordinator, session) = try fixture(), context = ModelContext(container)
        let value = try XCTUnwrap(context.fetch(FetchDescriptor<ProductSyncDataset>()).first)
        let completed = Date(timeIntervalSince1970: 1_700_000_000)
        value.lastSuccess = completed; try context.save()
        coordinator.refreshStatus()
        let expected = String.localizedStringWithFormat(String(localized: "Last sync completed at %@"), completed.formatted(date: .abbreviated, time: .standard))
        XCTAssertEqual(coordinator.displayedStatus, expected)
        let reopened = SyncProductCoordinator(container: container, mediaRoot: try root(), environment: .development, automaticSync: false)
        XCTAssertEqual(reopened.displayedStatus, expected)
        try coordinator.didChangeActivity(.downloading, session: session)
        coordinator.refreshStatus()
        XCTAssertEqual(coordinator.pendingCount, 0)
        XCTAssertEqual(coordinator.displayedStatus, String(localized: "Downloading from iCloud…"))
        coordinator.didPause(.accountChanged, binding: session.binding)
        XCTAssertNil(coordinator.activity); XCTAssertTrue(coordinator.displayedStatus.contains("accountChanged"))
        session.invalidate()
        XCTAssertThrowsError(try coordinator.didChangeActivity(.uploading, session: session))
        XCTAssertTrue(coordinator.displayedStatus.contains("accountChanged"))
    }
    func testOnlyCompleteAppliedAndAcknowledgedCycleAdvancesCompletionTime() async throws {
        let (container, coordinator, session) = try fixture(), context = ModelContext(container)
        let value = try XCTUnwrap(context.fetch(FetchDescriptor<ProductSyncDataset>()).first)
        let old = Date(timeIntervalSince1970: 1_600_000_000), next = Date(timeIntervalSince1970: 1_700_000_000)
        value.lastSuccess = old; value.blockedReason = "Synthetic missing asset"; try context.save()
        try coordinator.markSuccessful(session.binding, completedAt: next)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<ProductSyncDataset>()).first?.lastSuccess, old)
        value.blockedReason = nil; try context.save()
        container.mainContext.insert(Entry(body: "unsaved synthetic", createdAt: next))
        try await coordinator.applyDurableInbox(session: session)
        try coordinator.markSuccessful(session.binding, completedAt: next)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<ProductSyncDataset>()).first?.lastSuccess, old)
        container.mainContext.rollback()
        try await coordinator.applyDurableInbox(session: session)
        let pending = try mutation(dataset: session.binding.dataset, object: UUID(), content: "pending synthetic")
        try queue([pending], in: container)
        try coordinator.markSuccessful(session.binding, completedAt: next)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<ProductSyncDataset>()).first?.lastSuccess, old)
        let write = ModelContext(container)
        try XCTUnwrap(write.fetch(FetchDescriptor<ProductSyncOutbox>()).first).completed = true
        try write.save()
        try coordinator.markSuccessful(session.binding, completedAt: next)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<ProductSyncDataset>()).first?.lastSuccess, next)
    }
    func testDefaultInitializationHasNoImplicitDatasetOrCloudActivation() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let coordinator = SyncProductCoordinator(container: container, mediaRoot: try root(), environment: .development, automaticSync: false)
        XCTAssertFalse(coordinator.enabled); XCTAssertFalse(coordinator.busy)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<ProductSyncDataset>()), 0)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<ProductSyncEngineState>()), 0)
    }
    func testExactRevisionAndCompleteAssetClosureAreRequiredForAck() async throws {
        let (container, coordinator, session) = try fixture(), object = UUID()
        let media = AssetDescriptor(bytes: Data([1,2,3]))
        let first = try mutation(dataset: session.binding.dataset, object: object, content: "first",
                                 originals: [OriginalReference(id: UUID(), asset: media)])
        let second = try mutation(dataset: session.binding.dataset, object: object, parent: first.id, content: "second")
        try queue([first,second], in: container)
        let firstManifest = try MutationManifest.decode(first.manifest), secondManifest = try MutationManifest.decode(second.manifest)
        try await coordinator.acknowledge([.mutation(id: first.id, manifestSHA256: String(repeating: "0", count: 64))], session: session)
        XCTAssertFalse(try completed(first.id, in: container))
        try await coordinator.acknowledge([.mutation(id: first.id, manifestSHA256: first.manifestHash),
            .payloadChunk(firstManifest.payload!.chunks[0])], session: session)
        XCTAssertFalse(try completed(first.id, in: container)); XCTAssertFalse(try completed(second.id, in: container))
        try await coordinator.acknowledge([.original(media)], session: session)
        XCTAssertTrue(try completed(first.id, in: container)); XCTAssertFalse(try completed(second.id, in: container))
        let pending = try coordinator.pendingRecordIDs(session: session)
        XCTAssertEqual(Set(pending), Set([CloudRecordCodec.mutationID(second.id, dataset: session.binding.dataset),
            CloudRecordCodec.chunkID(secondManifest.payload!.chunks[0].sha256, dataset: session.binding.dataset)]))
        try await coordinator.acknowledge([.mutation(id: first.id, manifestSHA256: first.manifestHash)], session: session)
        XCTAssertFalse(try completed(second.id, in: container))
        try await coordinator.acknowledge([.mutation(id: second.id, manifestSHA256: second.manifestHash),
            .payloadChunk(secondManifest.payload!.chunks[0])], session: session)
        XCTAssertTrue(try completed(second.id, in: container))
    }
    func testWrongContainerAccountAndGenerationCannotReadOrAcknowledge() async throws {
        let (container, coordinator, session) = try fixture()
        let value = try mutation(dataset: session.binding.dataset, object: UUID(), content: "retained")
        try queue([value], in: container)
        for stale in [try cloned(session.binding, container: "iCloud.com.synthetic.other"),
                      try cloned(session.binding, account: String(repeating: "b", count: 64)),
                      try cloned(session.binding, generation: UUID())] {
            XCTAssertThrowsError(try coordinator.pendingRecordIDs(session: stale))
            do {
                try await coordinator.acknowledge([.mutation(id: value.id, manifestSHA256: value.manifestHash)], session: stale)
                XCTFail("Mismatched binding must not ACK")
            } catch {}
            do { try await coordinator.saveEngineState(Data([1]), session: stale); XCTFail("Mismatched checkpoint must fail") } catch {}
            coordinator.didPause(.zoneMissing, binding: stale.binding)
            let dataset = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<ProductSyncDataset>()).first)
            XCTAssertFalse(dataset.zoneLost)
            XCTAssertNil(dataset.blockedReason)
        }
        XCTAssertFalse(try completed(value.id, in: container))
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<ProductSyncEngineState>()), 0)
    }
    func testPersistedDisableRejectsSessionEvenBeforeTransportCallbackStops() async throws {
        let (container, coordinator, session) = try fixture()
        let context = ModelContext(container)
        let dataset = try XCTUnwrap(context.fetch(FetchDescriptor<ProductSyncDataset>()).first)
        dataset.enabled = false; dataset.generation = UUID(); try context.save()
        XCTAssertTrue(session.active)
        XCTAssertThrowsError(try coordinator.pendingRecordIDs(session: session))
        do { try await coordinator.saveEngineState(Data([1]), session: session); XCTFail("Disabled checkpoint must fail") } catch {}
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<ProductSyncEngineState>()), 0)
    }
    func testInboxOriginalIsDurableAndImmutableBeforeAnyCheckpoint() async throws {
        let (container, coordinator, session) = try fixture()
        let bytes = Data("synthetic original".utf8), descriptor = AssetDescriptor(bytes: Data("synthetic original".utf8))
        try await coordinator.durableInbox([.original(descriptor,bytes)], session: session)
        let independent = ModelContext(container)
        let inbox = try XCTUnwrap(independent.fetch(FetchDescriptor<ProductSyncInbox>()).first)
        XCTAssertEqual(inbox.bytes, bytes); XCTAssertEqual(inbox.sha256, syncDigest(bytes))
        XCTAssertEqual(try independent.fetchCount(FetchDescriptor<ProductSyncEngineState>()), 0)
        try await coordinator.durableInbox([.original(descriptor,bytes)], session: session)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<ProductSyncInbox>()), 1)
        do { try await coordinator.durableInbox([.original(descriptor,Data("wrong".utf8))], session: session); XCTFail("Corrupt bytes must fail") } catch {}
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<ProductSyncInbox>()).first?.bytes, bytes)
    }
    func testManifestIdentityCollisionRetainsFirstDurableInbox() async throws {
        let (container, coordinator, session) = try fixture()
        // Unsupported domain/version is intentionally retained pending, never installed as business data.
        let id = UUID(), object = try SyncObject(kind: "FutureAggregate", id: UUID())
        let first = try MutationManifest(dataset: session.binding.dataset, mutation: id, object: object,
                                        payloadVersion: 99, payload: PayloadManifest(bytes: Data([1])))
        let other = try MutationManifest(dataset: session.binding.dataset, mutation: id, object: object,
                                        payloadVersion: 99, payload: PayloadManifest(bytes: Data([2])))
        // Domain publication may remain pending; incoming bytes must already be durable either way.
        do { try await coordinator.durableInbox([.mutation(first)], session: session) } catch {}
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<ProductSyncInbox>()).first?.bytes, try first.encoded())
        do { try await coordinator.durableInbox([.mutation(other)], session: session); XCTFail("Equivocation must fail") } catch {}
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<ProductSyncInbox>()).first?.bytes, try first.encoded())
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Entry>()), 0)
    }
    func testAutomaticWakeGateHonorsOptInPauseAndExplicitTestDisable() async throws {
        let (container, _, _) = try fixture()
        let media = try root()
        let allowed = SyncProductCoordinator(container: container, mediaRoot: media, automaticSync: true)
        // A positive gate is inspected only. Never activate a real transport in this test.
        XCTAssertTrue(allowed.canAutomaticallySync)
        let disabledAutomation = SyncProductCoordinator(container: container, mediaRoot: media, automaticSync: false)
        XCTAssertFalse(disabledAutomation.canAutomaticallySync)
        let unchanged = disabledAutomation.status
        await disabledAutomation.resumeIfEnabled()
        XCTAssertEqual(disabledAutomation.status, unchanged)
        XCTAssertFalse(disabledAutomation.busy)

        let context = ModelContext(container)
        let dataset = try XCTUnwrap(context.fetch(FetchDescriptor<ProductSyncDataset>()).first)
        dataset.blockedReason = "Synthetic pause requiring attention"; try context.save()
        allowed.refreshStatus()
        XCTAssertFalse(allowed.canAutomaticallySync)
        let paused = allowed.status
        await allowed.resumeIfEnabled()
        XCTAssertEqual(allowed.status, paused)
        XCTAssertFalse(allowed.busy)

        dataset.blockedReason = nil; dataset.enabled = false; try context.save()
        allowed.refreshStatus()
        XCTAssertFalse(allowed.canAutomaticallySync)
        let off = allowed.status
        await allowed.resumeIfEnabled()
        XCTAssertEqual(allowed.status, off)
        XCTAssertFalse(allowed.busy)
    }
    private func schedulingFixture() throws -> (ModelContainer, SyncProductCoordinator, SyntheticSyncDriver) {
        let media = try root()
        try FileManager.default.createDirectory(at: media.appendingPathComponent("Store"), withIntermediateDirectories: true)
        let container = try PersistenceContainerFactory.makeOnDisk(at: media.appendingPathComponent("Store/synthetic.sqlite"))
        container.mainContext.autosaveEnabled = false
        let dataset = ProductSyncDataset()
        dataset.accountHash = String(repeating: "a", count: 64); dataset.enabled = true; dataset.zoneEstablished = true
        container.mainContext.insert(dataset); try ProductSyncCommit.initialize(container.mainContext, dataset: dataset)
        let driver = SyntheticSyncDriver(); driver.acknowledgeUploads = true
        let coordinator = SyncProductCoordinator(container: container, mediaRoot: media, environment: .development, automaticSync: true,
            accountReader: { String(repeating: "a", count: 64) }, transportFactory: { persistence in driver.persistence = persistence; return driver })
        return (container, coordinator, driver)
    }
    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Synthetic scheduler did not make progress within 10 seconds")
        throw SyncCloudTransportError.notStarted
    }
    private func push(scope: Int = 1, container: String = SyncProductCoordinator.containerID,
                      zone: CKRecordZone.ID? = nil) -> [AnyHashable: Any] {
        var details: [String: Any] = ["dbs": scope, "sid": "synthetic-subscription"]
        if let zone { details["zid"] = zone.zoneName; details["zoid"] = zone.ownerName }
        return ["ck": ["ce": 2, "cid": container, zone == nil ? "met" : "fet": details]]
    }
    func testBusyLocalCommitAloneTriggersNextUploadWithoutOverlappingDrivers() async throws {
        let (container, coordinator, driver) = try schedulingFixture()
        let seed = Entry(body: "sent before fetch", createdAt: Date())
        container.mainContext.insert(seed); try ProductSyncCommit.save(container.mainContext)
        var gate: CheckedContinuation<Void, Never>?
        driver.onFetch = { value in
            if value.cycles == 1 { await withCheckedContinuation { gate = $0 } }
        }
        let start = Task { await coordinator.enable() }
        try await eventually { gate != nil }
        let write = ModelContext(container)
        try XCTUnwrap(write.fetch(FetchDescriptor<Entry>()).first { $0.id == seed.id }).body = "changed during fetch"
        write.insert(Entry(body: "created during fetch", createdAt: Date()))
        try ProductSyncCommit.save(write)
        // Local commit notification is the only new wake; no foreground/manual/push help.
        await Task.yield()
        XCTAssertEqual(driver.cycles, 1)
        XCTAssertEqual(try coordinator.pendingRecordIDs(session: XCTUnwrap(driver.session)).count, 4)
        gate?.resume(); gate = nil
        await start.value
        try await eventually { driver.cycles >= 2 && coordinator.pendingCount == 0 && !coordinator.busy }
        XCTAssertEqual(driver.starts, 1); XCTAssertEqual(driver.cycles, 2); XCTAssertEqual(driver.maxActiveCycles, 1)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<ProductSyncMutation>()), 3)
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<ProductSyncOutbox>()).allSatisfy(\.completed))
        XCTAssertNotNil(try ModelContext(container).fetch(FetchDescriptor<ProductSyncDataset>()).first?.lastSuccess)
        await coordinator.disable()
    }
    func testRetryAfterSurvivesForegroundNetworkWakeAndNewCommitsThenCompletesAutomatically() async throws {
        let (container, coordinator, driver) = try schedulingFixture()
        var failedAt: Date?, retriedAt: Date?
        driver.onFetch = { value in
            if value.cycles == 1 {
                failedAt = Date()
                throw CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 2.4])
            }
            retriedAt = Date()
        }
        await coordinator.enable()
        XCTAssertFalse(coordinator.requiresAttention); XCTAssertTrue(coordinator.canAutomaticallySync)
        let write = ModelContext(container)
        let entry = Entry(body: "offline saved", createdAt: Date()); write.insert(entry); try ProductSyncCommit.save(write)
        await coordinator.resumeIfEnabled()
        coordinator.networkChanged(connected: false); coordinator.networkChanged(connected: true)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(driver.cycles, 1)
        try await eventually { driver.cycles >= 2 && coordinator.pendingCount == 0 && !coordinator.busy }
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(retriedAt).timeIntervalSince(XCTUnwrap(failedAt)), 2.4)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Entry>()).map(\.id), [entry.id])
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<ProductSyncOutbox>()).allSatisfy(\.completed))
        XCTAssertFalse(coordinator.requiresAttention)
        await coordinator.disable()
    }
    func testPushScopeAndDisablePreventUnrelatedOrLateWakes() async throws {
        let (_, coordinator, driver) = try schedulingFixture()
        await coordinator.enable()
        let binding = try XCTUnwrap(driver.session).binding
        let zone = CloudRecordCodec.zone(dataset: binding.dataset)
        XCTAssertTrue(coordinator.acceptsPush(try XCTUnwrap(CKNotification(fromRemoteNotificationDictionary: push()))))
        XCTAssertTrue(coordinator.acceptsPush(try XCTUnwrap(CKNotification(fromRemoteNotificationDictionary: push(zone: zone)))))
        SyncPushBridge.coordinator = coordinator
        defer { SyncPushBridge.coordinator = nil }
        for notification in [push(scope: 2), push(scope: 3), push(container: "iCloud.com.synthetic.other"),
                             push(zone: CKRecordZone.ID(zoneName: "unrelated")), [:]] {
            let result = await SyncPushBridge.receive(notification)
            XCTAssertEqual(result, .noData)
        }
        XCTAssertEqual(driver.cycles, 1)
        let old = try XCTUnwrap(driver.session)
        await coordinator.disable()
        coordinator.didPause(.zoneMissing, binding: old.binding)
        coordinator.networkChanged(connected: false); coordinator.networkChanged(connected: true)
        let result = await SyncPushBridge.receive(push())
        XCTAssertEqual(result, .noData)
        await coordinator.resumeIfEnabled()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(driver.cycles, 1); XCTAssertFalse(old.active); XCTAssertFalse(coordinator.enabled)
    }
    func testRetryPolicyKeepsIntegrityAccountAndMixedPartialErrorsProtected() {
        for code in [CKError.Code.networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy, .serverResponseLost] {
            XCTAssertEqual(SyncCloudRetry.delay(for: CKError(code), attempt: 0), 2)
            XCTAssertEqual(SyncCloudRetry.delay(for: CKError(code), attempt: 99), 300)
        }
        for code in [CKError.Code.notAuthenticated, .permissionFailure, .zoneNotFound, .userDeletedZone, .unknownItem, .serverRecordChanged, .invalidArguments, .operationCancelled] {
            XCTAssertNil(SyncCloudRetry.delay(for: CKError(code), attempt: 0))
        }
        let limited = CKError(.serviceUnavailable, userInfo: [CKErrorRetryAfterKey: 600])
        XCTAssertEqual(SyncCloudRetry.delay(for: limited, attempt: 99), 600)
        XCTAssertEqual(SyncCloudRetry.delay(for: CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: ["a": limited, "b": CKError(.networkFailure)]]), attempt: 0), 600)
        XCTAssertNil(SyncCloudRetry.delay(for: CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: ["a": limited, "b": CKError(.permissionFailure)]]), attempt: 0))
    }
    func testDiagnosticSnapshotIsBoundedRedactedAndKeepsFirstCauseAcrossReopenAndPartialAck() async throws {
        let (container, coordinator, session) = try fixture()
        let mutation = try mutation(dataset: session.binding.dataset, object: UUID(), content: "PRIVATE_BODY_SENTINEL")
        try queue([mutation], in: container)
        try await coordinator.acknowledge([.mutation(id: mutation.id, manifestSHA256: mutation.manifestHash)], session: session)
        let privateText = "PRIVATE_ACCOUNT_PATH_RECORD_SENTINEL"
        let nested = NSError(domain: NSURLErrorDomain, code: -1009, userInfo: [NSLocalizedDescriptionKey: privateText])
        let first = CKError(.partialFailure, userInfo: [
            NSLocalizedDescriptionKey: privateText,
            NSUnderlyingErrorKey: nested,
            CKPartialErrorsByItemIDKey: [privateText: CKError(.permissionFailure, userInfo: [NSLocalizedDescriptionKey: privateText])]])
        coordinator.recordDiagnostic(.init(phase: "uploading", recordTypes: [CloudRecordCodec.mutationType, privateText],
            succeeded: 1, failed: 1, error: first), binding: session.binding)
        for _ in 0..<24 {
            coordinator.recordDiagnostic(.init(phase: "cycle", error: CKError(.operationCancelled)), binding: session.binding)
        }
        let media = coordinator.mediaRoot
        let reopened = SyncProductCoordinator(container: container, mediaRoot: media, environment: .development, automaticSync: false)
        let text = reopened.diagnosticText()
        XCTAssertLessThanOrEqual(text.utf8.count, 32_768)
        for secret in [privateText, "PRIVATE_BODY_SENTINEL", mutation.id.uuidString, session.binding.accountHash, session.binding.dataset.uuidString] {
            XCTAssertFalse(text.contains(secret), secret)
        }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let firstSaved = try XCTUnwrap(object["firstFailure"] as? [String: Any])
        XCTAssertEqual(firstSaved["succeeded"] as? Int, 1); XCTAssertEqual(firstSaved["failed"] as? Int, 1)
        XCTAssertEqual(firstSaved["recordTypes"] as? [String], [CloudRecordCodec.mutationType])
        let failure = try XCTUnwrap(firstSaved["failure"] as? [String: Any])
        XCTAssertEqual(failure["domain"] as? String, CKErrorDomain)
        XCTAssertEqual(failure["code"] as? Int, CKError.Code.partialFailure.rawValue)
        XCTAssertEqual((failure["children"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual((object["events"] as? [Any])?.count, 8)
        let row = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<ProductSyncOutbox>()).first)
        XCTAssertFalse(row.completed)
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: row.acknowledgedRecords).count, 1)
        let before = (object["events"] as? [Any])?.count
        coordinator.recordDiagnostic(.init(phase: "cycle", error: first), binding: try cloned(session.binding, generation: UUID()).binding)
        let after = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(coordinator.diagnosticText().utf8)) as? [String: Any])
        XCTAssertEqual((after["events"] as? [Any])?.count, before)
    }
    func testUnsupportedDownloadedHistoryRemainsProtectivelyPaused() async throws {
        let (_, coordinator, session) = try fixture()
        let manifest = try MutationManifest(dataset: session.binding.dataset, mutation: UUID(),
            object: SyncObject(kind: "FutureAggregate", id: UUID()), payloadVersion: 99, payload: PayloadManifest(bytes: Data([1])))
        try await coordinator.durableInbox([.mutation(manifest)], session: session)
        try await coordinator.applyDurableInbox(session: session)
        XCTAssertTrue(coordinator.requiresAttention); XCTAssertFalse(coordinator.canAutomaticallySync)
    }

    func testColdStartAccountNetworkFailureRetriesBeforeTransportCreationAndKeepsIdentity() async throws {
        let (container, initial, _) = try schedulingFixture()
        let original = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<ProductSyncDataset>()).first)
        let originalID = original.id, originalAccount = original.accountHash
        var reads = 0
        let driver = SyntheticSyncDriver(); driver.acknowledgeUploads = true
        let replay = SyncProductCoordinator(container: container, mediaRoot: initial.mediaRoot, environment: .development, automaticSync: true,
            accountReader: {
                reads += 1
                if reads == 1 { throw CKError(.networkUnavailable) }
                return String(repeating: "a", count: 64)
            }, transportFactory: { persistence in driver.persistence = persistence; return driver })
        await replay.resumeIfEnabled()
        XCTAssertEqual(driver.starts, 0); XCTAssertFalse(replay.requiresAttention)
        try await eventually { driver.cycles == 1 && !replay.busy }
        XCTAssertEqual(reads, 2); XCTAssertEqual(driver.starts, 1)
        let final = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<ProductSyncDataset>()).first)
        XCTAssertEqual(final.id, originalID); XCTAssertEqual(final.accountHash, originalAccount)
        XCTAssertNotNil(final.lastSuccess)
        await replay.disable()
    }
    func testTemporaryAccountStatusCanRetryButUnavailableAccountStaysProtected() throws {
        XCTAssertNoThrow(try SyncCloudTransport.validateAccountStatus(.available))
        for status in [CKAccountStatus.temporarilyUnavailable, .couldNotDetermine] {
            XCTAssertThrowsError(try SyncCloudTransport.validateAccountStatus(status)) {
                XCTAssertNotNil(SyncCloudRetry.delay(for: $0, attempt: 0))
            }
        }
        for status in [CKAccountStatus.noAccount, .restricted] {
            XCTAssertThrowsError(try SyncCloudTransport.validateAccountStatus(status)) {
                XCTAssertEqual($0 as? SyncCloudTransportError, .paused(.accountUnavailable))
                XCTAssertNil(SyncCloudRetry.delay(for: $0, attempt: 0))
            }
        }
    }

    func testDatabasePushDuringBusyCycleSchedulesExactlyOneFollowingFetch() async throws {
        let (_, coordinator, driver) = try schedulingFixture()
        var gate: CheckedContinuation<Void, Never>?
        driver.onFetch = { value in if value.cycles == 1 { await withCheckedContinuation { gate = $0 } } }
        let start = Task { await coordinator.enable() }
        try await eventually { gate != nil }
        SyncPushBridge.coordinator = coordinator
        defer { SyncPushBridge.coordinator = nil }
        for _ in 0..<3 {
            let result = await SyncPushBridge.receive(push())
            XCTAssertEqual(result, .newData)
        }
        XCTAssertEqual(driver.cycles, 1)
        gate?.resume(); gate = nil; await start.value
        XCTAssertNil(try ModelContext(coordinator.container).fetch(FetchDescriptor<ProductSyncDataset>()).first?.lastSuccess,
            "A queued remote wake must be fetched before advancing completion")
        try await eventually { driver.cycles == 2 && !coordinator.busy }
        XCTAssertEqual(driver.maxActiveCycles, 1); XCTAssertEqual(driver.starts, 1)
        await coordinator.disable()
    }
    func testDisableCancelsAnAlreadyScheduledNetworkRetry() async throws {
        let (_, coordinator, driver) = try schedulingFixture()
        driver.onFetch = { _ in throw CKError(.networkUnavailable) }
        await coordinator.enable()
        XCTAssertTrue(coordinator.canAutomaticallySync)
        await coordinator.disable()
        coordinator.networkChanged(connected: false); coordinator.networkChanged(connected: true)
        try await Task.sleep(nanoseconds: 2_200_000_000)
        XCTAssertEqual(driver.cycles, 1); XCTAssertFalse(coordinator.enabled)
    }

    func testNonretryableApplicationFailureStaysPausedAfterRefreshAndReopen() throws {
        let (container, coordinator, session) = try fixture()
        coordinator.presentFailure(SyncValidationError.invalidManifest, binding: session.binding)
        coordinator.refreshStatus()
        XCTAssertTrue(coordinator.requiresAttention)
        let reopened = SyncProductCoordinator(container: container, mediaRoot: coordinator.mediaRoot, environment: .development, automaticSync: true,
            accountReader: { XCTFail("Protective pause must not activate CloudKit"); return session.binding.accountHash })
        XCTAssertTrue(reopened.requiresAttention); XCTAssertFalse(reopened.canAutomaticallySync)
        XCTAssertTrue(reopened.diagnosticText().contains("invalidManifest"))
    }

}
