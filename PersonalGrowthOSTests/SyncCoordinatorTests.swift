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
}
