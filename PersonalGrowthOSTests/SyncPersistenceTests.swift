import Foundation
import SwiftData
import XCTest
import SyncFoundation
@testable import PersonalGrowthOS

@MainActor final class SyncPersistenceTests: XCTestCase {
    private enum Injected: Error { case failure }
    private func fixture() throws -> (ModelContainer, ProductSyncDataset) {
        let container = try PersistenceContainerFactory.makeInMemory()
        container.mainContext.autosaveEnabled = false
        let dataset = ProductSyncDataset()
        container.mainContext.insert(dataset)
        try ProductSyncCommit.initialize(container.mainContext, dataset: dataset)
        return (container, dataset)
    }
    func testDisabledStoreDoesNotInitializeOrQueueImplicitly() throws {
        let container = try PersistenceContainerFactory.makeInMemory()
        let context = container.mainContext
        context.insert(Entry(body: "synthetic local", createdAt: Date()))
        try ProductSyncCommit.save(context)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Entry>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProductSyncDataset>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProductSyncOutbox>()), 0)
    }
    func testOnceDailyInitializationAndRepeatedCallsDoNotDuplicateRevisions() throws {
        let container = try PersistenceContainerFactory.makeInMemory(), c = container.mainContext
        c.autosaveEnabled = false
        let habit = try HabitService(context: c).create(name: "Once daily initial", plan: .legacy(mode: .oncePerDay, target: nil))
        let original = try SyncDomainSupplement.capture(context: c)
        let dataset = ProductSyncDataset(); c.insert(dataset)
        try ProductSyncCommit.initialize(c, dataset: dataset)
        let first = try c.fetch(FetchDescriptor<ProductSyncMutation>()).map(\.id).sorted { $0.uuidString < $1.uuidString }
        XCTAssertFalse(first.isEmpty)
        for _ in 0..<2 { try ProductSyncCommit.initialize(c, dataset: dataset) }
        let read = ModelContext(container)
        XCTAssertTrue(try XCTUnwrap(read.fetch(FetchDescriptor<ProductSyncDataset>()).first).initialized)
        XCTAssertEqual(try read.fetch(FetchDescriptor<ProductSyncMutation>()).map(\.id).sorted { $0.uuidString < $1.uuidString }, first)
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<ProductSyncOutbox>()), first.count)
        XCTAssertEqual(try SyncDomainSupplement.capture(context: read), original)
        XCTAssertEqual(try read.fetch(FetchDescriptor<Habit>()).map(\.id), [habit.id])
    }
    func testFactsMutationAndOutboxCommitTogether() throws {
        let (container, dataset) = try fixture(); let context = container.mainContext
        let entry = Entry(body: "synthetic revision", createdAt: Date()); context.insert(entry)
        try ProductSyncCommit.save(context)
        let independent = ModelContext(container)
        let revisions = try independent.fetch(FetchDescriptor<ProductSyncMutation>())
        XCTAssertEqual(revisions.count, 1)
        let manifest = try MutationManifest.decode(XCTUnwrap(revisions.first).manifest)
        XCTAssertEqual(manifest.dataset, dataset.id); XCTAssertEqual(manifest.object.id, entry.id)
        XCTAssertEqual(manifest.parents, []); XCTAssertFalse(manifest.deleted)
        XCTAssertEqual(try independent.fetchCount(FetchDescriptor<ProductSyncOutbox>()), 1)
        XCTAssertEqual(try independent.fetch(FetchDescriptor<Entry>()).first?.body, "synthetic revision")
    }
    func testInjectedSaveFailureRollsBackFactsAndQueue() throws {
        let (container, _) = try fixture(); let context = container.mainContext
        context.insert(Entry(body: "must rollback", createdAt: Date()))
        XCTAssertThrowsError(try ProductSyncCommit.save(context, persist: { _ in throw Injected.failure }))
        let independent = ModelContext(container)
        XCTAssertEqual(try independent.fetchCount(FetchDescriptor<Entry>()), 0)
        XCTAssertEqual(try independent.fetchCount(FetchDescriptor<ProductSyncMutation>()), 0)
        XCTAssertEqual(try independent.fetchCount(FetchDescriptor<ProductSyncOutbox>()), 0)
        XCTAssertFalse(context.hasChanges)
    }
    func testEditParentsExactRevisionAndDeleteCreatesTombstone() throws {
        let (container, _) = try fixture(); let context = container.mainContext
        let entry = Entry(body: "first", createdAt: Date()); context.insert(entry); try ProductSyncCommit.save(context)
        let first = try XCTUnwrap(context.fetch(FetchDescriptor<ProductSyncMutation>()).first)
        entry.body = "second"; try ProductSyncCommit.save(context)
        let second = try XCTUnwrap(context.fetch(FetchDescriptor<ProductSyncMutation>()).first { $0.id != first.id })
        XCTAssertEqual(try MutationManifest.decode(second.manifest).parents, [first.id])
        context.delete(entry); try ProductSyncCommit.save(context)
        let tombstone = try XCTUnwrap(context.fetch(FetchDescriptor<ProductSyncMutation>()).map { try MutationManifest.decode($0.manifest) }.first { $0.deleted })
        XCTAssertEqual(tombstone.parents, [second.id]); XCTAssertTrue(tombstone.dependencies.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProductSyncOutbox>()), 3)
    }
    func testNoOpSaveDoesNotCreateDuplicateRevision() throws {
        let (container, _) = try fixture(); let context = container.mainContext
        context.insert(Entry(body: "stable", createdAt: Date())); try ProductSyncCommit.save(context)
        try ProductSyncCommit.save(context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProductSyncMutation>()), 1)
    }
    func testRemotePublicationDoesNotEchoIntoOutbox() throws {
        let (container, _) = try fixture(); let context = container.mainContext
        context.insert(Entry(body: "remote", createdAt: Date()))
        try ProductSyncCommit.save(context, origin: .remoteProjection)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProductSyncOutbox>()), 0)
    }
    func testCommitJoinsExistingLeaseWithoutReenteringPublicOperation() throws {
        let (container, _) = try fixture(); let context = container.mainContext
        let root = StorePublication.root(for: container)
        try StorePublication.perform(at: root) {
            context.insert(Entry(body: "leased", createdAt: Date()))
            try ProductSyncCommit.save(context)
            XCTAssertThrowsError(try StorePublication.perform(at: root) {})
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProductSyncOutbox>()), 1)
    }
    func testV16DiskMigrationPreservesBusinessIdentityAndAddsEmptySyncTables() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PGOS-Synthetic-V16-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("synthetic.sqlite"); let id = UUID()
        try autoreleasepool {
            let schema = Schema(versionedSchema: PersonalGrowthSchemaV16.self)
            let config = ModelConfiguration("SyntheticV16", schema: schema, url: url, cloudKitDatabase: .none)
            let old = try ModelContainer(for: schema, configurations: [config])
            let entry = Entry(body: "retained V16", createdAt: Date()); entry.id = id
            old.mainContext.insert(entry); try old.mainContext.save()
        }
        let migrated = try PersistenceContainerFactory.makeOnDisk(at: url)
        let entries = try migrated.mainContext.fetch(FetchDescriptor<Entry>())
        XCTAssertEqual(entries.map(\.id), [id]); XCTAssertEqual(entries.first?.body, "retained V16")
        XCTAssertEqual(try migrated.mainContext.fetchCount(FetchDescriptor<ProductSyncDataset>()), 0)
        XCTAssertEqual(try migrated.mainContext.fetchCount(FetchDescriptor<ProductSyncMutation>()), 0)
        XCTAssertTrue(StartupStoreProtection.isCurrentStore(at: url))
    }
    func testProductionSelectionRetainsDevelopmentHistoryAndRequiresNewBaseline() throws {
        let (container, development) = try fixture(), context = container.mainContext
        let entry = Entry(body: "development fact", createdAt: Date()); context.insert(entry)
        try ProductSyncCommit.save(context)
        development.accountHash = String(repeating: "a", count: 64); development.enabled = true
        let state = ProductSyncEngineState(key: "retained-development-state", bytes: Data([10,20,30])); context.insert(state)
        try context.save()
        let oldGeneration = development.generation
        let original = try XCTUnwrap(context.fetch(FetchDescriptor<ProductSyncMutation>()).first)
        let manifestBytes = original.manifest, oldID = original.id
        let oldAck = try XCTUnwrap(context.fetch(FetchDescriptor<ProductSyncOutbox>()).first).acknowledgedRecords
        try ProductSyncStoreSelection.prepare(context: context, environment: .production); try context.save()
        XCTAssertNil(try ProductSyncStoreSelection.selectedDataset(in: ModelContext(container)))
        XCTAssertEqual(development.environment, "development"); XCTAssertFalse(development.enabled)
        XCTAssertNotEqual(development.generation, oldGeneration)
        XCTAssertEqual(development.accountHash, String(repeating: "a", count: 64))
        entry.body = "local edit before Production consent"
        try ProductSyncCommit.save(context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProductSyncMutation>()), 1)

        let production = ProductSyncDataset(id: ProductSyncStoreSelection.defaultDatasetID(for: .production))
        production.environment = "production"
        try ProductSyncStoreSelection.activate(production, in: context)
        try ProductSyncCommit.initialize(context, dataset: production)
        XCTAssertEqual(try ProductSyncStoreSelection.selectedDataset(in: ModelContext(container))?.id, production.id)
        let revisions = try context.fetch(FetchDescriptor<ProductSyncMutation>())
        XCTAssertEqual(revisions.count, 2)
        let fresh = try XCTUnwrap(revisions.first { $0.dataset == production.id })
        XCTAssertEqual(try MutationManifest.decode(fresh.manifest).parents, [])
        XCTAssertNotEqual(fresh.id, oldID)
        XCTAssertEqual(revisions.first { $0.id == oldID }?.manifest, manifestBytes)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProductSyncOutbox>()).first { $0.mutationID == oldID }?.acknowledgedRecords, oldAck)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProductSyncEngineState>()).first?.bytes, Data([10,20,30]))
        // Turning sync off preserves capture for the selected dataset, not retired Development.
        XCTAssertFalse(production.enabled)
        entry.body = "offline Production edit"; try ProductSyncCommit.save(context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProductSyncMutation>()).filter { $0.dataset == development.id }.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProductSyncMutation>()).filter { $0.dataset == production.id }.count, 2)
    }
    func testSameEnvironmentAdoptsLegacySelectionWithoutChangingAuthorizationOrEpoch() throws {
        let (container, dataset) = try fixture(), context = container.mainContext
        dataset.enabled = true; try context.save(); let generation = dataset.generation
        try ProductSyncStoreSelection.prepare(context: context, environment: .development); try context.save()
        XCTAssertEqual(try ProductSyncStoreSelection.selectedDataset(in: ModelContext(container))?.id, dataset.id)
        XCTAssertTrue(dataset.enabled); XCTAssertEqual(dataset.generation, generation)
        try ProductSyncStoreSelection.prepare(context: context, environment: .development); try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProductSyncSelection>()), 1)
        XCTAssertEqual(dataset.generation, generation)
        XCTAssertNotEqual(ProductSyncStoreSelection.defaultDatasetID(for: .development), ProductSyncStoreSelection.defaultDatasetID(for: .production))
        XCTAssertEqual(ProductSyncStoreSelection.defaultDatasetID(for: .development).uuidString, "EAB541A0-45A1-43E4-9009-4E6F316EA001")
    }
    func testSelectionRejectsAmbiguousLegacyDanglingPointerAndDuplicateDatasetIdentity() throws {
        let (container, old) = try fixture(), context = container.mainContext
        try ProductSyncStoreSelection.prepare(context: context, environment: .development); try context.save()
        let duplicate = ProductSyncDataset(id: old.id)
        XCTAssertThrowsError(try ProductSyncStoreSelection.activate(duplicate, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProductSyncDataset>()), 1)
        let selector = try XCTUnwrap(context.fetch(FetchDescriptor<ProductSyncSelection>()).first)
        selector.developmentDatasetID = UUID()
        XCTAssertThrowsError(try ProductSyncStoreSelection.selectedDataset(in: context))
        context.rollback()
        let other = ProductSyncDataset(); other.environment = "production"
        XCTAssertThrowsError(try ProductSyncStoreSelection.activate(other, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProductSyncDataset>()), 1)
        let isolated = try PersistenceContainerFactory.makeInMemory()
        isolated.mainContext.insert(ProductSyncDataset()); isolated.mainContext.insert(ProductSyncDataset())
        try isolated.mainContext.save()
        XCTAssertThrowsError(try ProductSyncStoreSelection.selectedDataset(in: isolated.mainContext))
        XCTAssertThrowsError(try ProductSyncStoreSelection.prepare(context: isolated.mainContext, environment: .production))
    }
    func testRestoreRetainsAllHeadersAndSelectsNewUnboundIdentityInCurrentEnvironment() throws {
        let (container, old) = try fixture(), context = container.mainContext
        old.enabled = true; old.accountHash = String(repeating: "a", count: 64)
        let entry = Entry(body: "retained revision", createdAt: Date()); context.insert(entry)
        try ProductSyncCommit.save(context)
        let originalBytes = try XCTUnwrap(context.fetch(FetchDescriptor<ProductSyncMutation>()).first).manifest
        try ProductSyncStoreSelection.prepare(context: context, environment: .production)
        let production = ProductSyncDataset(id: ProductSyncStoreSelection.defaultDatasetID(for: .production))
        production.environment = "production"; production.enabled = true; production.accountHash = String(repeating: "a", count: 64)
        try ProductSyncStoreSelection.activate(production, in: context)
        try ProductSyncCommit.initialize(context, dataset: production)
        let before = try context.fetchCount(FetchDescriptor<ProductSyncOutbox>())
        let generation = production.generation
        try ProductSyncCommit.save(context, origin: .restoreNewDataset)
        let read = ModelContext(container), fresh = try XCTUnwrap(ProductSyncStoreSelection.selectedDataset(in: read))
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<ProductSyncDataset>()), 3)
        XCTAssertNotEqual(fresh.id, old.id); XCTAssertNotEqual(fresh.id, production.id)
        XCTAssertEqual(fresh.environment, "production"); XCTAssertNil(fresh.accountHash)
        XCTAssertFalse(fresh.enabled); XCTAssertFalse(fresh.initialized); XCTAssertFalse(fresh.zoneEstablished)
        XCTAssertFalse(production.enabled); XCTAssertNotEqual(production.generation, generation)
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<ProductSyncOutbox>()), before)
        XCTAssertTrue(try read.fetch(FetchDescriptor<ProductSyncMutation>()).contains { $0.manifest == originalBytes })
        XCTAssertEqual(old.accountHash, String(repeating: "a", count: 64))
    }
    func testEnvironmentRoundTripRetainsEachIdentityAndRequiresExplicitReenable() throws {
        let (container, development) = try fixture(), context = container.mainContext
        development.enabled = true
        context.insert(Entry(body: "before realm switch", createdAt: Date()))
        try ProductSyncCommit.save(context)
        let oldMutation = try XCTUnwrap(context.fetch(FetchDescriptor<ProductSyncMutation>()).first)
        let immutable = oldMutation.manifest
        try ProductSyncStoreSelection.prepare(context: context, environment: .production)
        let production = ProductSyncDataset(id: ProductSyncStoreSelection.defaultDatasetID(for: .production))
        production.environment = "production"
        try ProductSyncStoreSelection.activate(production, in: context)
        try ProductSyncCommit.initialize(context, dataset: production)
        production.enabled = true; try context.save()
        let productionEpoch = production.generation
        try ProductSyncStoreSelection.prepare(context: context, environment: .development); try context.save()
        XCTAssertEqual(try ProductSyncStoreSelection.selectedDataset(in: ModelContext(container))?.id, development.id)
        XCTAssertFalse(development.enabled); XCTAssertFalse(production.enabled)
        XCTAssertFalse(development.needsReconciliation)
        XCTAssertNotEqual(production.generation, productionEpoch)
        let developmentEpoch = development.generation
        development.enabled = true; try context.save()
        try ProductSyncStoreSelection.prepare(context: context, environment: .production); try context.save()
        XCTAssertEqual(try ProductSyncStoreSelection.selectedDataset(in: ModelContext(container))?.id, production.id)
        XCTAssertFalse(development.enabled); XCTAssertFalse(production.enabled)
        XCTAssertFalse(production.needsReconciliation)
        XCTAssertNotEqual(development.generation, developmentEpoch)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProductSyncDataset>()), 2)
        XCTAssertEqual(oldMutation.manifest, immutable)
        let selector = try XCTUnwrap(context.fetch(FetchDescriptor<ProductSyncSelection>()).first)
        XCTAssertEqual(selector.developmentDatasetID, development.id)
        XCTAssertEqual(selector.productionDatasetID, production.id)
    }
    func testExplicitReenableDiffsCrossEnvironmentEditsFromRetainedHeadsAndIsIdempotent() throws {
        let (container, development) = try fixture(), context = container.mainContext
        let entry = Entry(body: "original development fact", createdAt: Date())
        context.insert(entry); try ProductSyncCommit.save(context)
        let original = try XCTUnwrap(context.fetch(FetchDescriptor<ProductSyncMutation>()).first)
        let originalBytes = original.manifest
        let oldAck = try XCTUnwrap(context.fetch(FetchDescriptor<ProductSyncOutbox>()).first)
        oldAck.completed = true; oldAck.acknowledgedRecords = try JSONEncoder().encode(["retained-ack"])
        let ackBytes = oldAck.acknowledgedRecords
        try ProductSyncStoreSelection.prepare(context: context, environment: .production)
        let production = ProductSyncDataset(id: ProductSyncStoreSelection.defaultDatasetID(for: .production))
        production.environment = "production"
        try ProductSyncStoreSelection.activate(production, in: context)
        try ProductSyncCommit.initialize(context, dataset: production)
        entry.body = "changed while Production selected"; try ProductSyncCommit.save(context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProductSyncMutation>()).filter { $0.dataset == development.id }.count, 1)
        try ProductSyncStoreSelection.prepare(context: context, environment: .development); try context.save()
        XCTAssertFalse(development.enabled)
        try ProductSyncCommit.initialize(context, dataset: development)
        let revisions = try context.fetch(FetchDescriptor<ProductSyncMutation>()).filter { $0.dataset == development.id }
        XCTAssertEqual(revisions.count, 2)
        let fresh = try XCTUnwrap(revisions.first { $0.id != original.id })
        XCTAssertEqual(try MutationManifest.decode(fresh.manifest).parents, [original.id])
        XCTAssertEqual(original.manifest, originalBytes)
        XCTAssertTrue(oldAck.completed); XCTAssertEqual(oldAck.acknowledgedRecords, ackBytes)
        try ProductSyncCommit.initialize(context, dataset: development)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProductSyncMutation>()).filter { $0.dataset == development.id }.count, 2)
        // The diff must not erase a separately persisted error/reconciliation condition.
        development.needsReconciliation = true; development.blockedReason = "synthetic retained error"
        try ProductSyncCommit.initialize(context, dataset: development)
        XCTAssertTrue(development.needsReconciliation)
        XCTAssertEqual(development.blockedReason, "synthetic retained error")
    }
    func testRestoreChangesOnlyCurrentRealmPointerAndRoundTripRejectsInvalidInactivePointer() throws {
        let (container, development) = try fixture(), context = container.mainContext
        try ProductSyncStoreSelection.prepare(context: context, environment: .production)
        let production = ProductSyncDataset(id: ProductSyncStoreSelection.defaultDatasetID(for: .production))
        production.environment = "production"
        try ProductSyncStoreSelection.activate(production, in: context); try context.save()
        try ProductSyncCommit.save(context, origin: .restoreNewDataset)
        let restoredID = try XCTUnwrap(ProductSyncStoreSelection.selectedDataset(in: context)).id
        XCTAssertNotEqual(restoredID, production.id)
        try ProductSyncStoreSelection.prepare(context: context, environment: .development); try context.save()
        XCTAssertEqual(try ProductSyncStoreSelection.selectedDataset(in: context)?.id, development.id)
        try ProductSyncStoreSelection.prepare(context: context, environment: .production); try context.save()
        XCTAssertEqual(try ProductSyncStoreSelection.selectedDataset(in: ModelContext(container))?.id, restoredID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProductSyncDataset>()), 3)
        let selector = try XCTUnwrap(context.fetch(FetchDescriptor<ProductSyncSelection>()).first)
        let generation = try XCTUnwrap(ProductSyncStoreSelection.selectedDataset(in: context)).generation
        selector.developmentDatasetID = UUID() // Even the inactive realm must resolve exactly.
        XCTAssertThrowsError(try ProductSyncStoreSelection.selectedDataset(in: context))
        XCTAssertThrowsError(try ProductSyncStoreSelection.prepare(context: context, environment: .development))
        XCTAssertEqual(selector.environment, "production")
        context.rollback()
        XCTAssertEqual(try ProductSyncStoreSelection.selectedDataset(in: context)?.generation, generation)
        selector.developmentDatasetID = restoredID // Existing ID in the wrong realm is also invalid.
        XCTAssertThrowsError(try ProductSyncStoreSelection.selectedDataset(in: context))
        XCTAssertThrowsError(try ProductSyncStoreSelection.prepare(context: context, environment: .development))
        context.rollback()
    }
    func testEnvironmentSelectionAndFactsRollbackTogetherOnSaveFailure() throws {
        let (container, old) = try fixture(), context = container.mainContext
        old.enabled = true
        try ProductSyncStoreSelection.prepare(context: context, environment: .development); try context.save()
        let generation = old.generation
        try ProductSyncStoreSelection.prepare(context: context, environment: .production)
        let fresh = ProductSyncDataset(id: ProductSyncStoreSelection.defaultDatasetID(for: .production)); fresh.environment = "production"
        try ProductSyncStoreSelection.activate(fresh, in: context)
        context.insert(Entry(body: "must roll back", createdAt: Date()))
        XCTAssertThrowsError(try ProductSyncCommit.save(context, origin: .remoteProjection, persist: { _ in throw Injected.failure }))
        let read = ModelContext(container), selected = try XCTUnwrap(ProductSyncStoreSelection.selectedDataset(in: read))
        XCTAssertEqual(selected.id, old.id); XCTAssertEqual(selected.generation, generation); XCTAssertTrue(selected.enabled)
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<ProductSyncDataset>()), 1)
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<Entry>()), 0)
    }
    func testV17DiskMigrationAddsOnlySelectionAndPreservesOriginalSyncBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PGOS-Synthetic-V17-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("synthetic.sqlite"), datasetID = UUID(), mutationID = UUID(), objectID = UUID()
        let payload = Data("synthetic retained payload".utf8)
        let manifest = try MutationManifest(dataset: datasetID, mutation: mutationID,
            object: SyncObject(kind: "entry", id: objectID), payload: PayloadManifest(bytes: payload))
        let originalBytes = try manifest.encoded(), token = Data([1,3,5,7]), ack = try JSONEncoder().encode(["synthetic-ack"])
        try autoreleasepool {
            let schema = Schema(versionedSchema: PersonalGrowthSchemaV17.self)
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration("SyntheticV17", schema: schema, url: url, cloudKitDatabase: .none)])
            old.mainContext.autosaveEnabled = false
            let dataset = ProductSyncDataset(id: datasetID); dataset.accountHash = String(repeating: "a", count: 64)
            dataset.initialized = true; dataset.enabled = true
            let revision = try ProductSyncMutation(manifest, payload: payload, transactionID: UUID(), local: true)
            let outbox = ProductSyncOutbox(revision); outbox.acknowledgedRecords = ack
            old.mainContext.insert(dataset); old.mainContext.insert(revision); old.mainContext.insert(outbox)
            old.mainContext.insert(ProductSyncEngineState(key: "synthetic-v17-state", bytes: token))
            old.mainContext.insert(ProductSyncInbox(dataset: datasetID, recordName: "synthetic-record", recordType: "synthetic-type", bytes: payload))
            try old.mainContext.save()
        }
        let migrated = try PersistenceContainerFactory.makeOnDisk(at: url), read = migrated.mainContext
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<ProductSyncSelection>()), 0)
        XCTAssertEqual(try read.fetch(FetchDescriptor<ProductSyncMutation>()).first?.manifest, originalBytes)
        XCTAssertEqual(try read.fetch(FetchDescriptor<ProductSyncOutbox>()).first?.acknowledgedRecords, ack)
        XCTAssertEqual(try read.fetch(FetchDescriptor<ProductSyncEngineState>()).first?.bytes, token)
        XCTAssertEqual(try read.fetch(FetchDescriptor<ProductSyncInbox>()).first?.bytes, payload)
        XCTAssertEqual(try ProductSyncStoreSelection.selectedDataset(in: read)?.id, datasetID)
        XCTAssertTrue(try XCTUnwrap(read.fetch(FetchDescriptor<ProductSyncDataset>()).first).enabled)
        XCTAssertFalse(PersonalGrowthSchemaV17.models.contains { $0 == ProductSyncSelection.self })
        XCTAssertTrue(PersonalGrowthSchemaV18.models.contains { $0 == ProductSyncSelection.self })
    }

}
