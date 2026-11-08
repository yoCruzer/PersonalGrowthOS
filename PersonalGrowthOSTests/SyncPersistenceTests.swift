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
}
