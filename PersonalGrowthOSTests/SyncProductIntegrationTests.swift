import Foundation
import SwiftData
import CloudKit
import UIKit
import XCTest
import SyncFoundation
@testable import PersonalGrowthOS

/// Two isolated on-disk stores. Transport is a value-array handoff: no enable/start/CloudKit calls.
@MainActor final class SyncProductIntegrationTests: XCTestCase {
    private let instant=Date(timeIntervalSince1970:1_700_000_000)
    private let datasetID=UUID(uuidString:"B84EF799-215F-4E52-BAE4-9BC45B312659")!
    private struct Device {
        let root:URL
        let container:ModelContainer
        let coordinator:SyncProductCoordinator
        let session:SyncCloudSession
    }
    private struct Revision {
        let manifest:MutationManifest
        let payload:Data?
    }
    private func device() throws -> Device {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("PGOS-Synthetic-Integration-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root.appendingPathComponent("Store"),withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:root)}
        let container=try PersistenceContainerFactory.makeOnDisk(at:root.appendingPathComponent("Store/PersonalGrowthOS.sqlite"))
        container.mainContext.autosaveEnabled=false
        let context=ModelContext(container);context.autosaveEnabled=false
        let dataset=ProductSyncDataset(id:datasetID)
        dataset.accountHash=String(repeating:"a",count:64);dataset.enabled=true;dataset.zoneEstablished=true
        context.insert(dataset);try ProductSyncCommit.initialize(context,dataset:dataset)
        let binding=try SyncBinding(container:SyncProductCoordinator.containerID,environment:.development,
            accountHash:try XCTUnwrap(dataset.accountHash),dataset:dataset.id,generation:dataset.generation)
        return Device(root:root,container:container,
            coordinator:SyncProductCoordinator(container:container,mediaRoot:root,environment:.development,automaticSync:false),
            session:SyncCloudSession(binding:binding))
    }
    private func write(_ device:Device,_ body:(ModelContext)throws->Void) throws {
        let context=ModelContext(device.container);context.autosaveEnabled=false
        try body(context);try ProductSyncCommit.save(context)
    }
    private func createEntry(_ device:Device,id:UUID=UUID(),body:String) throws -> UUID {
        try write(device){$0.insert(Entry(id:id,body:body,createdAt:instant))};return id
    }
    private func edit(_ device:Device,id:UUID,body:String) throws {
        try write(device){context in
            let row=try XCTUnwrap(context.fetch(FetchDescriptor<Entry>()).first{$0.id==id})
            row.body=body;row.updatedAt=row.updatedAt.addingTimeInterval(1)
        }
    }
    private func body(_ device:Device,id:UUID) throws -> String? {
        try ModelContext(device.container).fetch(FetchDescriptor<Entry>()).first{$0.id==id}?.body
    }
    private func revisions(_ device:Device) throws -> [Revision] {
        let context=ModelContext(device.container)
        return try context.fetch(FetchDescriptor<ProductSyncMutation>()).map {
            Revision(manifest:try MutationManifest.decode($0.manifest),payload:$0.payload)
        }
    }
    private func headIDs(_ device:Device,kind:SyncDomainKind = .entry,id:UUID) throws -> Set<UUID> {
        let context=ModelContext(device.container)
        let row=try XCTUnwrap(context.fetch(FetchDescriptor<ProductSyncObjectState>()).first{$0.kind==kind.rawValue && $0.businessID==id})
        return Set(try JSONDecoder().decode([UUID].self,from:row.heads))
    }
    private func head(_ device:Device,kind:SyncDomainKind = .entry,id:UUID) throws -> Revision {
        let ids=try headIDs(device,kind:kind,id:id);XCTAssertEqual(ids.count,1)
        return try XCTUnwrap(revisions(device).first{ids.contains($0.manifest.mutation)})
    }
    private func packets(_ revision:Revision,from device:Device) throws -> [SyncCloudDownloaded] {
        var result:[SyncCloudDownloaded]=[.mutation(revision.manifest)]
        if let descriptor=revision.manifest.payload {
            let payload=try XCTUnwrap(revision.payload);try descriptor.verify(bytes:payload)
            for (index,chunk) in descriptor.chunks.enumerated() {
                let start=index*SyncLimits.chunkBytes
                let bytes=payload.subdata(in:start..<(start+chunk.byteCount))
                XCTAssertEqual(AssetDescriptor(bytes:bytes),chunk);result.append(.payloadChunk(chunk,bytes))
            }
        }
        for original in revision.manifest.originals {
            result.append(.original(original.asset,try SyncAssetStore(root:device.root).read(original.asset)))
        }
        return result
    }
    private func allPackets(_ device:Device) throws -> [SyncCloudDownloaded] {
        try revisions(device).flatMap{try packets($0,from:device)}
    }
    private func deliver(_ records:[SyncCloudDownloaded],to device:Device) async throws {
        try await device.coordinator.durableInbox(records,session:device.session)
        try await device.coordinator.applyDurableInbox(session: device.session)
    }
    private func outboxCount(_ device:Device) throws -> Int {
        try ModelContext(device.container).fetchCount(FetchDescriptor<ProductSyncOutbox>())
    }

    func testOverTenThousandRevisionsReplayFromDiskVerifyOnlyHeadAndContinueLocalUpload() async throws {
        let a = try device(), b = try device()
        let id = try createEntry(a, body: "immutable input")
        let first = try head(a, id: id)
        var manifests = [first.manifest]
        for _ in 1...10_000 {
            manifests.append(try MutationManifest(dataset: datasetID, mutation: UUID(), object: first.manifest.object,
                parents: [manifests.last!.mutation], payload: first.manifest.payload))
        }
        let before = Date()
        let payloadPackets = try packets(first, from: a).filter { if case .mutation = $0 { return false }; return true }
        try await b.coordinator.durableInbox(manifests.reversed().map { .mutation($0) } + payloadPackets, session: b.session)
        // Reopen before projection: exercise durable inbox replay, not only the pure graph.
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: b.root.appendingPathComponent("Store/PersonalGrowthOS.sqlite"))
        reopened.mainContext.autosaveEnabled = false
        let coordinator = SyncProductCoordinator(container: reopened, mediaRoot: b.root, environment: .development, automaticSync: false)
        let replay = Device(root: b.root, container: reopened, coordinator: coordinator, session: b.session)
        try await coordinator.applyDurableInbox(session: b.session)
        XCTAssertEqual(try body(replay, id: id), "immutable input")
        XCTAssertEqual(coordinator.verifiedAssetMutationCount, 1)
        let reader = ModelContext(reopened)
        let rows = try reader.fetch(FetchDescriptor<ProductSyncMutation>())
        XCTAssertEqual(rows.count, 10_001)
        XCTAssertEqual(Set(rows.map(\.manifestHash)), Set(try manifests.map { syncDigest(try $0.encoded()) }))
        XCTAssertEqual(rows.filter { $0.payload != nil }.count, 1)
        XCTAssertEqual(try outboxCount(replay), 0)
        try edit(replay, id: id, body: "edit after 10001 revisions")
        let local = try head(replay, id: id)
        XCTAssertEqual(local.manifest.parents, [manifests.last!.mutation])
        XCTAssertFalse(try coordinator.pendingRecordIDs(session: b.session).isEmpty)
        try await coordinator.applyDurableInbox(session: b.session)
        XCTAssertEqual(coordinator.verifiedAssetMutationCount, 1)
        XCTAssertEqual(try body(replay, id: id), "edit after 10001 revisions")
        XCTAssertFalse(coordinator.requiresAttention)
        XCTAssertEqual(try ModelContext(reopened).fetchCount(FetchDescriptor<ProductSyncMutation>()), 10_002)
        // Reuse an old payload hash whose historical metadata has no inline payload.
        // The sender must select a durable local outbox source, never the first old revision.
        try edit(replay, id: id, body: "immutable input")
        let uploads = try coordinator.pendingRecordIDs(session: b.session)
        for recordID in uploads {
            let upload = try await coordinator.uploadRecord(id: recordID, session: b.session)
            let acknowledgement = try XCTUnwrap(upload).acknowledgement()
            try await coordinator.acknowledge([acknowledgement], session: b.session)
        }
        XCTAssertTrue(try coordinator.pendingRecordIDs(session: b.session).isEmpty)
        XCTAssertEqual(try ModelContext(reopened).fetchCount(FetchDescriptor<ProductSyncMutation>()), 10_003)
        print("SYNC_HISTORY_10001_SECONDS=\(Date().timeIntervalSince(before))")
    }

    func testObsoleteMissingOriginalDoesNotBlockNewFullHeadAndLateBytesRemainIntact() async throws {
        let a = try device(), b = try device(), id = UUID(), imageID = UUID()
        let original = UIGraphicsImageRenderer(size: .init(width: 8, height: 8)).pngData { canvas in
            UIColor.blue.setFill(); canvas.fill(.init(x: 0, y: 0, width: 8, height: 8))
        }
        let input = a.root.appendingPathComponent("history.png"); try original.write(to: input)
        let stored = try MediaStore(rootURL: a.root).storeOriginal(.init(url: input, originalFilename: "history.png", contentType: "image/png"), id: imageID)
        try write(a) { context in
            let entry = Entry(id: id, body: "historical photo", createdAt: instant)
            let image = ImageMetadata(id: imageID, relativePath: stored.relativePath, originalFilename: "history.png", contentType: "image/png",
                byteCount: stored.byteCount, pixelWidth: stored.pixelWidth, pixelHeight: stored.pixelHeight, checksum: stored.checksum, createdAt: instant)
            image.entry = entry; context.insert(entry); context.insert(image)
        }
        let historical = try head(a, id: id), oldPackets = try allPackets(a)
        try write(a) { context in
            for image in try context.fetch(FetchDescriptor<ImageMetadata>()) { context.delete(image) }
            try XCTUnwrap(context.fetch(FetchDescriptor<Entry>()).first).body = "latest complete content"
        }
        let next = try head(a, id: id)
        let oldWithoutOriginal = oldPackets.filter { if case .original = $0 { return false }; return true }
        try await deliver(packets(next, from: a) + oldWithoutOriginal, to: b)
        XCTAssertEqual(try body(b, id: id), "latest complete content")
        XCTAssertEqual(b.coordinator.verifiedAssetMutationCount, 1)
        XCTAssertEqual(try ModelContext(b.container).fetchCount(FetchDescriptor<ImageMetadata>()), 0)
        XCTAssertEqual(try revisions(b).first { $0.manifest.mutation == historical.manifest.mutation }?.manifest.encoded(), try historical.manifest.encoded())
        let descriptor = try XCTUnwrap(historical.manifest.originals.first).asset
        XCTAssertThrowsError(try SyncAssetStore(root: b.root).read(descriptor))
        try await deliver([.original(descriptor, original)], to: b)
        XCTAssertEqual(try SyncAssetStore(root: b.root).read(descriptor), original)
        XCTAssertEqual(try body(b, id: id), "latest complete content")
    }

    func testRestoredWorkspaceDiscoveryDownloadsOriginalContentAndPhotoWithoutEcho() async throws {
        let source = try device(), entryID = UUID(), imageID = UUID()
        let original = UIGraphicsImageRenderer(size: .init(width: 8, height: 8)).pngData { canvas in
            UIColor.green.setFill(); canvas.fill(.init(x: 0, y: 0, width: 8, height: 8))
        }
        let input = source.root.appendingPathComponent("restored.png"); try original.write(to: input)
        let stored = try MediaStore(rootURL: source.root).storeOriginal(.init(url: input, originalFilename: "restored.png", contentType: "image/png"), id: imageID)
        try write(source) { context in
            let entry = Entry(id: entryID, body: "restored original", createdAt: instant)
            let image = ImageMetadata(id: imageID, relativePath: stored.relativePath, originalFilename: "restored.png", contentType: "image/png",
                byteCount: stored.byteCount, pixelWidth: stored.pixelWidth, pixelHeight: stored.pixelHeight, checksum: stored.checksum, createdAt: instant)
            image.entry = entry; context.insert(entry); context.insert(image)
        }
        // The real restore commit boundary selects a fresh random dataset and retains old history.
        let restoredContext = ModelContext(source.container); restoredContext.autosaveEnabled = false
        try ProductSyncCommit.save(restoredContext, origin: .restoreNewDataset)
        let restored = try XCTUnwrap(ProductSyncStoreSelection.selectedDataset(in: restoredContext))
        XCTAssertNotEqual(restored.id, datasetID)
        try ProductSyncCommit.initialize(restoredContext, dataset: restored)
        let cloud = try revisions(source).filter { $0.manifest.dataset == restored.id }.flatMap { try packets($0, from: source) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PGOS-Synthetic-Rediscovery-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Store"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let container = try PersistenceContainerFactory.makeOnDisk(at: root.appendingPathComponent("Store/PersonalGrowthOS.sqlite"))
        container.mainContext.autosaveEnabled = false
        let driver = SyntheticSyncDriver()
        driver.onFetch = { driver in
            try await driver.persistence!.durableInbox(cloud, session: XCTUnwrap(driver.session))
        }
        let coordinator = SyncProductCoordinator(container: container, mediaRoot: root, environment: .development, automaticSync: false,
            accountReader: { String(repeating: "a", count: 64) },
            zoneReader: { [CKRecordZone(zoneID: CloudRecordCodec.zone(dataset: restored.id))] },
            transportFactory: { persistence in driver.persistence = persistence; return driver })
        await coordinator.discoverWorkspaces()
        try await coordinator.connectDiscoveredWorkspace(XCTUnwrap(coordinator.discoveredWorkspaces.first))
        await coordinator.enable()
        XCTAssertEqual(driver.requestedZoneCreation, [false]); XCTAssertEqual(driver.session?.binding.dataset, restored.id)
        let reader = ModelContext(container)
        XCTAssertEqual(try reader.fetch(FetchDescriptor<Entry>()).map(\.body), ["restored original"])
        let image = try XCTUnwrap(reader.fetch(FetchDescriptor<ImageMetadata>()).first)
        XCTAssertEqual(image.id, imageID)
        XCTAssertEqual(try Data(contentsOf: MediaStore(rootURL: root).fileURL(for: image.relativePath)), original)
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<ProductSyncOutbox>()), 0)
        XCTAssertFalse(coordinator.requiresAttention)
        XCTAssertEqual(try ModelContext(source.container).fetchCount(FetchDescriptor<ProductSyncDataset>()), 2)
        XCTAssertEqual(try Data(contentsOf: MediaStore(rootURL: source.root).fileURL(for: stored.relativePath)), original)
    }

    func testCrossUUIDTagConflictSurvivesReopenAndRenamePreservesRelationships() async throws {
        let a = try device(), b = try device()
        var tags: [UUID] = []
        for device in [a, b] {
            let entry = try createEntry(device, body: "linked original")
            let tag = Tag(displayName: "Shared", normalizedName: "shared", createdAt: instant)
            tags.append(tag.id)
            try write(device) { context in
                context.insert(tag)
                context.insert(ObjectLink(sourceType: .entry, sourceID: entry, targetType: .tag, targetID: tag.id, kind: .entryUsesTag, createdAt: instant))
            }
        }
        let originalPackets = try allPackets(a)
        try await deliver(originalPackets, to: b)
        let conflict = try XCTUnwrap(b.coordinator.identityConflicts.first)
        XCTAssertEqual(conflict.candidates.count, 2)
        XCTAssertEqual(try ModelContext(b.container).fetchCount(FetchDescriptor<Tag>()), 1)
        let reopened = SyncProductCoordinator(container: b.container, mediaRoot: b.root, environment: .development, automaticSync: false)
        XCTAssertEqual(reopened.identityConflicts, [conflict])
        XCTAssertThrowsError(try reopened.resolveIdentity(conflict, keeping: .init(kind: .tag, id: tags[0]), tagName: "SHARED"))
        try reopened.resolveIdentity(conflict, keeping: .init(kind: .tag, id: tags[0]), tagName: "Shared from device A")
        XCTAssertThrowsError(try reopened.resolveIdentity(conflict, keeping: .init(kind: .tag, id: tags[0]), tagName: "stale"))
        try await b.coordinator.applyDurableInbox(session: b.session)
        try await deliver(allPackets(b), to: a)
        for device in [a, b] {
            let context = ModelContext(device.container)
            XCTAssertEqual(Set(try context.fetch(FetchDescriptor<Tag>()).map(\.id)), Set(tags))
            XCTAssertEqual(Set(try context.fetch(FetchDescriptor<ObjectLink>()).map(\.targetID)), Set(tags))
            XCTAssertTrue(device.coordinator.identityConflicts.isEmpty)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()), 2)
        }
        try await deliver(originalPackets, to: b)
        XCTAssertEqual(try ModelContext(b.container).fetchCount(FetchDescriptor<Tag>()), 2)
    }

    func testThreeSameNameTagsCanBeRenamedOneAtATime() async throws {
        let peers = try [device(), device(), device()]
        let receiver = peers[0]
        var ids = Set<UUID>()
        for peer in peers {
            let tag = Tag(displayName: "Shared", normalizedName: "shared", createdAt: instant)
            ids.insert(tag.id)
            try write(peer) { $0.insert(tag) }
        }
        for peer in peers.dropFirst() { try await deliver(allPackets(peer), to: receiver) }
        for count in [3, 2] {
            let group = try XCTUnwrap(receiver.coordinator.identityConflicts.first)
            XCTAssertEqual(group.candidates.count, count)
            try receiver.coordinator.resolveIdentity(group, keeping: group.candidates[0].key, tagName: "Renamed \(count)")
        }
        XCTAssertTrue(receiver.coordinator.identityConflicts.isEmpty)
        let tags = try ModelContext(receiver.container).fetch(FetchDescriptor<Tag>())
        XCTAssertEqual(Set(tags.map(\.id)), ids)
        XCTAssertEqual(Set(tags.map(\.normalizedName)), ["shared", "renamed 3", "renamed 2"])
    }

    func testIdentityChoicesSurviveColdActivationWhileAnotherGroupIsUnresolved() async throws {
        let a = try device(), b = try device(), week = try WeeklyReviewPeriod(containing: instant)
        var sleepIDs: [UUID] = [], reviewIDs: [UUID] = []
        for (index, device) in [a, b].enumerated() {
            let sleep = try SleepRecord(wakeDay: "2023-11-14", timeZoneID: "UTC", values: .init(note: "sleep \(index)"), createdAt: instant)
            let review = WeeklyReview(weekIdentifier: week.identifier, periodStart: week.start, periodEnd: week.end,
                rememberedText: "remembered \(index)", focusText: "focus \(index)", createdAt: instant)
            sleepIDs.append(sleep.id); reviewIDs.append(review.id)
            try write(device) { $0.insert(sleep); $0.insert(review) }
        }
        try await deliver(allPackets(a), to: b)
        XCTAssertEqual(b.coordinator.identityConflicts.count, 2)
        let sleepConflict = try XCTUnwrap(b.coordinator.identityConflicts.first { $0.kind == .sleepRecord })
        try b.coordinator.resolveIdentity(sleepConflict, keeping: .init(kind: .sleepRecord, id: sleepIDs[0]))
        let queued = try outboxCount(b)
        await b.coordinator.disable()
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: b.root.appendingPathComponent("Store/PersonalGrowthOS.sqlite"))
        reopened.mainContext.autosaveEnabled = false
        let driver = SyntheticSyncDriver()
        let coordinator = SyncProductCoordinator(container: reopened, mediaRoot: b.root, environment: .development, automaticSync: false,
            accountReader: { String(repeating: "a", count: 64) }, transportFactory: { persistence in driver.persistence = persistence; return driver })
        await coordinator.enable()
        XCTAssertEqual(driver.starts, 1)
        XCTAssertEqual(try ModelContext(reopened).fetchCount(FetchDescriptor<ProductSyncOutbox>()), queued)
        XCTAssertEqual(coordinator.identityConflicts.count, 1)
        let reviewConflict = try XCTUnwrap(coordinator.identityConflicts.first)
        try coordinator.resolveIdentity(reviewConflict, keeping: .init(kind: .weeklyReview, id: reviewIDs[0]))
        let reader = ModelContext(reopened)
        XCTAssertEqual(try reader.fetch(FetchDescriptor<SleepRecord>()).map(\.id), [sleepIDs[0]])
        XCTAssertEqual(try reader.fetch(FetchDescriptor<WeeklyReview>()).map(\.id), [reviewIDs[0]])
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<ProductSyncMutation>()), 8)
        XCTAssertTrue(coordinator.identityConflicts.isEmpty)
        XCTAssertFalse(coordinator.requiresAttention)
    }

    func testIdentityChoiceCannotOrphanNetWorthEditingDraftAndKeepsOriginalHistory() async throws {
        let a = try device(), b = try device()
        var ids: [UUID] = []
        for (index, device) in [a, b].enumerated() {
            var snapshot = NetWorthSnapshotValue(day: "2023-11-14", timeZoneID: "UTC", confirmed: true,
                note: "history \(index)", createdAt: instant, updatedAt: instant, completedAt: instant)
            snapshot.assetsConfirmed = true; snapshot.liabilitiesConfirmed = true
            ids.append(snapshot.id)
            try write(device) { context in
                context.insert(try NetWorthSnapshot(snapshot))
                if index == 0 {
                    let draft = NetWorthSnapshotValue(day: "2023-11-14", timeZoneID: "UTC", note: "retained editing draft",
                        editingID: snapshot.id, editingRevision: snapshot.revision, createdAt: instant, updatedAt: instant)
                    context.insert(try NetWorthSnapshot(draft))
                }
            }
        }
        let originalA = try allPackets(a), originalB = try revisions(b)
        try await deliver(originalA, to: b)
        let conflict = try XCTUnwrap(b.coordinator.identityConflicts.first)
        // A competing root for the editing draft removes it from the single-head
        // document list. Its reference still forbids deleting the edited snapshot.
        let forkPeer = try device()
        try await deliver(originalA + (try allPackets(b)), to: forkPeer)
        let draft = try XCTUnwrap(revisions(a).first { !$0.manifest.dependencies.isEmpty })
        let fork = try MutationManifest(dataset: datasetID, mutation: UUID(), object: draft.manifest.object,
            dependencies: draft.manifest.dependencies, payload: draft.manifest.payload)
        try await deliver([.mutation(fork)], to: forkPeer)
        XCTAssertEqual(try headIDs(forkPeer, kind: .netWorthSnapshot, id: draft.manifest.object.id).count, 2)
        let forkConflict = try XCTUnwrap(forkPeer.coordinator.identityConflicts.first)
        let priorQueue = try outboxCount(forkPeer)
        XCTAssertThrowsError(try forkPeer.coordinator.resolveIdentity(forkConflict, keeping: .init(kind: .netWorthSnapshot, id: ids[1])))
        XCTAssertEqual(try outboxCount(forkPeer), priorQueue)
        let count = try revisions(b).count, queued = try outboxCount(b)
        XCTAssertThrowsError(try b.coordinator.resolveIdentity(conflict, keeping: .init(kind: .netWorthSnapshot, id: ids[1])))
        XCTAssertEqual(try revisions(b).count, count); XCTAssertEqual(try outboxCount(b), queued)
        try b.coordinator.resolveIdentity(conflict, keeping: .init(kind: .netWorthSnapshot, id: ids[0]))
        let snapshots = try ModelContext(b.container).fetch(FetchDescriptor<NetWorthSnapshot>()).map { try $0.value() }
        XCTAssertEqual(snapshots.filter(\.confirmed).map(\.id), [ids[0]])
        XCTAssertEqual(snapshots.first { !$0.confirmed }?.editingID, ids[0])
        let retained = try revisions(b)
        for original in originalB {
            let row = try XCTUnwrap(retained.first { $0.manifest.mutation == original.manifest.mutation })
            XCTAssertEqual(row.payload, original.payload); XCTAssertEqual(row.manifest, original.manifest)
        }
    }

    func testDefaultParticipantChoiceRetainsBothPeopleAndActivityRelationships() async throws {
        let a = try device(), b = try device()
        var people: [UUID] = []
        for (index, device) in [a, b].enumerated() {
            let person = InvestmentParticipant(name: "Person \(index)", isDefault: true)
            let activity = InvestmentActivity(participantID: person.id, name: "activity \(index)")
            people.append(person.id)
            try write(device) { $0.insert(person); $0.insert(activity) }
        }
        try await deliver(allPackets(a), to: b)
        let conflict = try XCTUnwrap(b.coordinator.identityConflicts.first)
        XCTAssertEqual(conflict.kind, .investmentParticipant)
        try b.coordinator.resolveIdentity(conflict, keeping: .init(kind: .investmentParticipant, id: people[0]))
        try await deliver(allPackets(b), to: a)
        for device in [a, b] {
            let reader = ModelContext(device.container), participants = try reader.fetch(FetchDescriptor<InvestmentParticipant>())
            XCTAssertEqual(Set(participants.map(\.id)), Set(people))
            XCTAssertEqual(participants.filter(\.isDefault).map(\.id), [people[0]])
            XCTAssertEqual(Set(try reader.fetch(FetchDescriptor<InvestmentActivity>()).map(\.participantID)), Set(people))
        }
    }

    func testOppositeCrossUUIDSleepChoicesBecomeConcurrentVersionsRatherThanDeletingBoth() async throws {
        let a = try device(), b = try device()
        var ids: [UUID] = []
        for (index, device) in [a, b].enumerated() {
            let row = try SleepRecord(wakeDay: "2023-11-14", timeZoneID: "UTC", values: .init(note: "original \(index)"), createdAt: instant)
            ids.append(row.id); try write(device) { $0.insert(row) }
        }
        let aPackets = try allPackets(a), bPackets = try allPackets(b)
        try await deliver(aPackets, to: b); try await deliver(bPackets, to: a)
        for (index, device) in [a, b].enumerated() {
            let conflict = try XCTUnwrap(device.coordinator.identityConflicts.first)
            try device.coordinator.resolveIdentity(conflict, keeping: .init(kind: .sleepRecord, id: ids[index]))
            try await device.coordinator.applyDurableInbox(session: device.session)
            XCTAssertEqual(try ModelContext(device.container).fetch(FetchDescriptor<SleepRecord>()).map(\.id), [ids[index]])
        }
        let resolvedA = try allPackets(a), resolvedB = try allPackets(b)
        try await deliver(resolvedA, to: b); try await deliver(resolvedB, to: a)
        for device in [a, b] {
            XCTAssertEqual(device.coordinator.conflicts.count, 2)
            XCTAssertEqual(try ModelContext(device.container).fetchCount(FetchDescriptor<SleepRecord>()), 1)
            XCTAssertEqual(try revisions(device).filter { $0.payload != nil }.count, 4)
        }
    }

    func testRemoteTodoPublicationNotifiesReminderConsumersOnlyAfterCommitAndNotOnReplay() async throws {
        let a = try device(), b = try device()
        let context = ModelContext(a.container)
        let service = TodoTaskService(context: context, now: { self.instant })
        let task = try service.create(TodoDraft(title: "Remote reminder"))
        var observedTitles: [[String]] = []
        let token = NotificationCenter.default.addObserver(forName: .todoTasksChanged, object: nil, queue: .main) { notification in
            guard notification.object as? ModelContainer === b.container else { return }
            MainActor.assumeIsolated {
                observedTitles.append((try? ModelContext(b.container).fetch(FetchDescriptor<TodoTask>()).map(\.title)) ?? [])
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        let packets = try allPackets(a)
        try await b.coordinator.durableInbox(packets, session: b.session)
        XCTAssertTrue(observedTitles.isEmpty)
        try await b.coordinator.applyDurableInbox(session: b.session)
        XCTAssertEqual(observedTitles, [[task.title]])
        try await deliver(packets, to: b)
        XCTAssertEqual(observedTitles.count, 1)
        XCTAssertEqual(try outboxCount(b), 0)
    }

    func testValueDraftCannotSilentlyOverwriteRemoteEntryEvenWithUnchangedTimestamp() async throws {
        let a = try device(), b = try device(), id = try createEntry(a, body: "base")
        try await deliver(try allPackets(a), to: b)
        let editing = try XCTUnwrap(b.container.mainContext.fetch(FetchDescriptor<Entry>()).first)
        let baseline = EntryEditingSnapshot(editing)
        let draft = EntryEditingDraft(title: nil, body: "local unsaved draft", occurredAt: editing.occurredAt,
                                      retainedImageIDs: [], addedImages: [])
        // SwiftUI stores these fields in @State, so mainContext.hasChanges remains false.
        XCTAssertFalse(b.container.mainContext.hasChanges)
        try write(a) { context in
            try XCTUnwrap(context.fetch(FetchDescriptor<Entry>()).first).body = "remote same-clock edit"
        }
        try await deliver(try allPackets(a), to: b)
        XCTAssertEqual(try body(b, id: id), "remote same-clock edit")
        let service = EntryEditingService(persistence: ModelContextEntryPersistence(context: b.container.mainContext), mediaStore: MediaStore(rootURL: b.root))
        XCTAssertThrowsError(try service.update(editing, with: draft, expected: baseline)) {
            XCTAssertEqual($0 as? EntryEditingFailure, .changedSinceEditing)
        }
        XCTAssertEqual(try body(b, id: id), "remote same-clock edit")
        XCTAssertEqual(try outboxCount(b), 0)
        XCTAssertEqual(draft.body, "local unsaved draft")
    }

    func testEntryDraftStillSavesAfterUnrelatedRemoteEditButRejectsRemoteDeletion() async throws {
        let a = try device(), b = try device()
        let id = try createEntry(a, body: "editable"), other = try createEntry(a, body: "unrelated")
        try await deliver(try allPackets(a), to: b)
        let editing = try XCTUnwrap(b.container.mainContext.fetch(FetchDescriptor<Entry>()).first { $0.id == id })
        let cachedOther = try XCTUnwrap(b.container.mainContext.fetch(FetchDescriptor<Entry>()).first { $0.id == other })
        let baseline = EntryEditingSnapshot(editing)
        try edit(a, id: other, body: "remote unrelated change")
        try await deliver(try allPackets(a), to: b)
        let service = EntryEditingService(persistence: ModelContextEntryPersistence(context: b.container.mainContext), mediaStore: MediaStore(rootURL: b.root))
        let draft = EntryEditingDraft(title: nil, body: "saved local draft", occurredAt: editing.occurredAt, retainedImageIDs: [], addedImages: [])
        try service.update(editing, with: draft, expected: baseline)
        XCTAssertEqual(try body(b, id: id), "saved local draft")
        XCTAssertEqual(try body(b, id: other), "remote unrelated change")
        XCTAssertEqual(try outboxCount(b), 1, "Saving A must not republish a cached old B")
        _ = cachedOther.body // Keep the pre-projection model alive as a mounted @Query would.
        // Return B's edit to A so deletion causally follows it; no fabricated conflict.
        try await deliver(try allPackets(b), to: a)
        let editedBaseline = EntryEditingSnapshot(editing)
        try write(a) { context in
            context.delete(try XCTUnwrap(context.fetch(FetchDescriptor<Entry>()).first { $0.id == id }))
        }
        try await deliver(try allPackets(a), to: b)
        XCTAssertNil(try body(b, id: id))
        XCTAssertThrowsError(try service.update(editing, with: draft, expected: editedBaseline)) {
            XCTAssertEqual($0 as? EntryEditingFailure, .changedSinceEditing)
        }
        XCTAssertNil(try body(b, id: id))
    }

    func testRemoteDayAndSleepChangesPublishAfterLeaseAndDoNotEcho() async throws {
        let a = try device(), b = try device()
        try write(a) { context in
            context.insert(try ImportantDay(title: "Remote day", rule: .init(), createdAt: instant))
            var values = SleepValues(); values.feeling = 3
            context.insert(try SleepRecord(wakeDay: "2023-11-14", timeZoneID: "UTC", values: values, createdAt: instant))
        }
        var notifications: [Notification.Name] = []
        let tokens = [Notification.Name.importantDaysChanged, .sleepRecordsChanged].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { notification in
                guard notification.object as? ModelContainer === b.container else { return }
                MainActor.assumeIsolated {
                    do { try StorePublication.perform(at: b.root) {} }
                    catch { XCTFail("Consumer notified before publication lease released: \(error)") }
                    notifications.append(name)
                }
            }
        }
        defer { tokens.forEach(NotificationCenter.default.removeObserver) }
        let packets = try allPackets(a)
        // A complete valid graph must be present before consumers receive any event.
        try await deliver(packets.filter { if case .mutation = $0 { return true }; return false }, to: b)
        XCTAssertTrue(notifications.isEmpty)
        try await deliver(packets, to: b)
        XCTAssertEqual(Set(notifications), [.importantDaysChanged, .sleepRecordsChanged])
        XCTAssertEqual(notifications.count, 2)
        try await deliver(packets, to: b)
        XCTAssertEqual(notifications.count, 2)
        XCTAssertEqual(try outboxCount(b), 0)
    }

    func testTodoValueDraftCannotOverwriteRemoteEdit() async throws {
        let a = try device(), b = try device()
        let first = TodoTaskService(context: ModelContext(a.container), now: { self.instant })
        let task = try first.create(TodoDraft(title: "base task"))
        try await deliver(try allPackets(a), to: b)
        let local = try XCTUnwrap(ModelContext(b.container).fetch(FetchDescriptor<TodoTask>()).first)
        let expected = TodoTaskTransfer(local)
        var draft = TodoDraft(local); draft.notes = "local unsaved notes"
        try first.edit(id: task.id, draft: TodoDraft(title: "remote latest title"))
        try await deliver(try allPackets(a), to: b)
        let editor = TodoTaskService(context: ModelContext(b.container))
        XCTAssertThrowsError(try editor.edit(id: task.id, draft: draft, expected: expected)) {
            guard case TodoFailure.staleTask = $0 else { return XCTFail("Expected stale draft rejection: \($0)") }
        }
        XCTAssertEqual(try ModelContext(b.container).fetch(FetchDescriptor<TodoTask>()).first?.title, "remote latest title")
        XCTAssertEqual(try outboxCount(b), 0)
        let latest = try editor.task(id: task.id)
        let refreshedBaseline = TodoTaskTransfer(latest)
        var reviewedDraft = TodoDraft(latest); reviewedDraft.notes = draft.notes
        try editor.edit(id: task.id, draft: reviewedDraft, expected: refreshedBaseline)
        let saved = try XCTUnwrap(ModelContext(b.container).fetch(FetchDescriptor<TodoTask>()).first)
        XCTAssertEqual(saved.title, "remote latest title"); XCTAssertEqual(saved.notes, "local unsaved notes")
        XCTAssertEqual(try outboxCount(b), 1)
    }

    func testSyncEditorBaselineFencesOnlyChangedPublishedObjectAndSurvivesClockRollback() async throws {
        let a = try device(), b = try device()
        let id = UUID(), other = try createEntry(a, body: "unrelated")
        try write(a) { $0.insert(WeightRecord(id: id, weightKilograms: 70, recordedAt: instant, createdAt: instant)) }
        try await deliver(try allPackets(a), to: b)
        let reader = ModelContext(b.container)
        let weight = try XCTUnwrap(reader.fetch(FetchDescriptor<WeightRecord>()).first)
        let baseline = SyncEditorBaseline.capture(weight, key: .init(kind: .weight, id: id))
        XCTAssertNoThrow(try baseline.validate(b.container))
        try edit(a, id: other, body: "unrelated updated")
        try await deliver(try allPackets(a), to: b)
        XCTAssertNoThrow(try baseline.validate(b.container))
        try write(a) { context in
            let remote = try XCTUnwrap(context.fetch(FetchDescriptor<WeightRecord>()).first)
            remote.weightKilograms = 71 // Keep the same timestamp deliberately.
        }
        try await deliver(try allPackets(a), to: b)
        XCTAssertThrowsError(try baseline.validate(b.container))
        // Reopening from a cached SwiftData model must not pair old values with a
        // newly published fingerprint and authorize an overwrite.
        XCTAssertEqual(weight.weightKilograms, 70)
        let reopenedFromCache = SyncEditorBaseline.capture(weight, key: .init(kind: .weight, id: id))
        XCTAssertThrowsError(try reopenedFromCache.validate(b.container))
        let freshReader = ModelContext(b.container)
        let fresh = try XCTUnwrap(freshReader.fetch(FetchDescriptor<WeightRecord>()).first)
        let freshBaseline = SyncEditorBaseline.capture(fresh, key: .init(kind: .weight, id: id))
        XCTAssertNoThrow(try freshBaseline.validate(b.container))
        XCTAssertEqual(try ModelContext(b.container).fetch(FetchDescriptor<WeightRecord>()).first?.weightKilograms, 71)
        try write(a) { context in
            context.delete(try XCTUnwrap(context.fetch(FetchDescriptor<WeightRecord>()).first))
        }
        try await deliver(try allPackets(a), to: b)
        XCTAssertThrowsError(try freshBaseline.validate(b.container))
        XCTAssertTrue(try ModelContext(b.container).fetch(FetchDescriptor<WeightRecord>()).isEmpty)
        XCTAssertEqual(try outboxCount(b), 0)
    }

    func testRemoteInvestmentPublicationInvalidatesCachedWorkspaceWithoutReplayEcho() async throws {
        let a = try device(), b = try device()
        let workspace = InvestmentWorkspace()
        workspace.refresh(b.container.mainContext)
        XCTAssertTrue(workspace.participants.isEmpty)
        try write(a) { $0.insert(InvestmentParticipant(name: "Remote participant", isDefault: true)) }
        let packets = try allPackets(a)
        let prior = InvestmentChanges.version(b.container).sequence
        try await deliver(packets, to: b)
        XCTAssertEqual(InvestmentChanges.version(b.container).sequence, prior + 1)
        workspace.refresh(b.container.mainContext)
        XCTAssertEqual(workspace.participants.map(\.name), ["Remote participant"])
        try await deliver(packets, to: b)
        XCTAssertEqual(InvestmentChanges.version(b.container).sequence, prior + 1)
        XCTAssertEqual(try outboxCount(b), 0)
    }

    func testManyDownloadedRecordsStayDurableWithoutPerRecordProjectionThenApplyOnceAfterReopen() async throws {
        let a = try device(), b = try device(), count = 64
        try write(a) { context in
            for index in 0..<count { context.insert(Entry(body: "Synthetic batch \(index)", createdAt: instant)) }
        }
        let records = try allPackets(a)
        XCTAssertEqual(records.count, count * 2) // One exact manifest and payload chunk per independent entry.
        for record in records { try await b.coordinator.durableInbox([record], session: b.session) }
        XCTAssertEqual(b.coordinator.projectionPassCount, 0)
        XCTAssertEqual(try ModelContext(b.container).fetchCount(FetchDescriptor<Entry>()), 0)
        XCTAssertEqual(try ModelContext(b.container).fetchCount(FetchDescriptor<ProductSyncInbox>()), records.count)
        let checkpoint = Data("synthetic-durable-checkpoint".utf8)
        try await b.coordinator.saveEngineState(checkpoint, session: b.session)
        XCTAssertEqual(try ModelContext(b.container).fetch(FetchDescriptor<ProductSyncEngineState>()).first?.bytes, checkpoint)
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: b.root.appendingPathComponent("Store/PersonalGrowthOS.sqlite"))
        reopened.mainContext.autosaveEnabled = false
        let replay = SyncProductCoordinator(container: reopened, mediaRoot: b.root, environment: .development, automaticSync: false)
        try await replay.applyDurableInbox(session: SyncCloudSession(binding: b.session.binding))
        XCTAssertEqual(replay.projectionPassCount, 1)
        XCTAssertEqual(try ModelContext(reopened).fetch(FetchDescriptor<Entry>()).map { try XCTUnwrap($0.body) }.sorted(),
                       (0..<count).map { "Synthetic batch \($0)" }.sorted())
        XCTAssertEqual(try ModelContext(reopened).fetchCount(FetchDescriptor<ProductSyncOutbox>()), 0)
        XCTAssertEqual(try ModelContext(reopened).fetchCount(FetchDescriptor<ProductSyncInbox>()), records.count)
    }
    func testDiskStoresConvergeAfterChildBeforeParentAndDuplicateDeliveryWithoutEcho() async throws {
        let a=try device(),b=try device()
        XCTAssertNotEqual(a.session.binding.generation,b.session.binding.generation)
        let id=try createEntry(a,body:"base"),base=try head(a,id:id)
        try edit(a,id:id,body:"second");let latest=try head(a,id:id)
        XCTAssertEqual(latest.manifest.parents,[base.manifest.mutation]);XCTAssertEqual(try outboxCount(a),2)
        let latestPackets=try packets(latest,from:a)
        try await deliver([.mutation(latest.manifest)],to:b)
        XCTAssertNil(try body(b,id:id))
        try await deliver(Array(latestPackets.dropFirst()),to:b)
        XCTAssertNil(try body(b,id:id)) // Complete assets cannot replace a missing causal parent.
        try await deliver(Array(try packets(base,from:a).reversed()),to:b)
        XCTAssertEqual(try body(b,id:id),"second")
        let all=try allPackets(a)
        try await deliver(Array(all.reversed())+all+latestPackets,to:b)
        XCTAssertEqual(try body(b,id:id),try body(a,id:id))
        XCTAssertEqual(try headIDs(a,id:id),try headIDs(b,id:id))
        XCTAssertEqual(try revisions(b).count,2);XCTAssertEqual(try outboxCount(b),0)
        XCTAssertEqual(try SyncDomainCodec.capture(context:ModelContext(a.container)),try SyncDomainCodec.capture(context:ModelContext(b.container)))
    }

    func testMissingParentWaitAutomaticallyFetchesLaterParentWithoutEchoOrAttentionBlock() async throws {
        let a = try device(), b = try device(), id = try createEntry(a, body: "parent")
        let parent = try head(a, id: id)
        try edit(a, id: id, body: "later child"); let child = try head(a, id: id)
        let childPackets = try packets(child, from: a), parentPackets = try packets(parent, from: a)
        let driver = SyntheticSyncDriver()
        driver.onFetch = { value in
            try await value.persistence!.durableInbox(value.cycles == 1 ? childPackets : parentPackets, session: XCTUnwrap(value.session))
        }
        let live = SyncProductCoordinator(container: b.container, mediaRoot: b.root, environment: .development, automaticSync: true,
            accountReader: { String(repeating: "a", count: 64) }, transportFactory: { persistence in driver.persistence = persistence; return driver })
        await live.resumeIfEnabled()
        XCTAssertNil(try body(b, id: id)); XCTAssertFalse(live.requiresAttention)
        XCTAssertNil(try ModelContext(b.container).fetch(FetchDescriptor<ProductSyncDataset>()).first?.lastSuccess)
        for _ in 0..<800 {
            if try body(b, id: id) == "later child" { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(try body(b, id: id), "later child")
        XCTAssertEqual(driver.cycles, 2); XCTAssertEqual(driver.maxActiveCycles, 1)
        XCTAssertEqual(try outboxCount(b), 0)
        XCTAssertNotNil(try ModelContext(b.container).fetch(FetchDescriptor<ProductSyncDataset>()).first?.lastSuccess)
        await live.disable()
    }

    func testConcurrentEditsRemainAsTwoHeadsUntilExplicitAllParentResolution() async throws {
        let a=try device(),b=try device(),id=try createEntry(a,body:"base")
        try await deliver(try allPackets(a),to:b)
        try edit(a,id:id,body:"branch A");try edit(b,id:id,body:"branch B")
        let branchA=try head(a,id:id),branchB=try head(b,id:id)
        let aPackets=try packets(branchA,from:a),bPackets=try packets(branchB,from:b)
        try await deliver(aPackets,to:b);try await deliver(bPackets,to:a)
        let expected:Set<UUID>=[branchA.manifest.mutation,branchB.manifest.mutation]
        XCTAssertEqual(try headIDs(a,id:id),expected);XCTAssertEqual(try headIDs(b,id:id),expected)
        XCTAssertEqual(try body(a,id:id),"branch A");XCTAssertEqual(try body(b,id:id),"branch B")
        XCTAssertThrowsError(try edit(a, id: id, body: "implicit resolution")) {
            guard case ProductSyncFailure.unresolvedConflict = $0 else { return XCTFail("Expected unresolved conflict: \($0)") }
        }
        XCTAssertEqual(try body(a, id: id), "branch A")
        XCTAssertEqual(try revisions(a).count,3);XCTAssertEqual(try revisions(b).count,3)
        let conflict=try XCTUnwrap(a.coordinator.conflicts.first{$0.key.id==id})
        XCTAssertEqual(Set(conflict.heads),expected)
        XCTAssertEqual(Set(try a.coordinator.conflictVersions(conflict).map(\.id)),expected)
        try a.coordinator.resolve(conflict,choosing:branchB.manifest.mutation)
        let resolution=try head(a,id:id)
        XCTAssertEqual(Set(resolution.manifest.parents),expected)
        XCTAssertEqual(resolution.payload,branchB.payload)
        try await deliver([],to:a)
        try await deliver(try packets(resolution,from:a),to:b)
        try await deliver(aPackets+bPackets,to:a);try await deliver(bPackets+aPackets,to:b)
        XCTAssertEqual(try body(a,id:id),"branch B");XCTAssertEqual(try body(b,id:id),"branch B")
        XCTAssertEqual(try headIDs(a,id:id),[resolution.manifest.mutation])
        XCTAssertEqual(try headIDs(b,id:id),[resolution.manifest.mutation])
        XCTAssertEqual(try revisions(a).count,4);XCTAssertEqual(try revisions(b).count,4)
        XCTAssertEqual(try outboxCount(a),3);XCTAssertEqual(try outboxCount(b),1)
        XCTAssertTrue(a.coordinator.conflicts.isEmpty);XCTAssertTrue(b.coordinator.conflicts.isEmpty)
    }

    func testOriginalBytesGatePublicationAndDeletionWaitsForRelationshipTombstone() async throws {
        let a=try device(),entryID=UUID(),imageID=UUID(),tagID=UUID(),linkID=UUID()
        var b = try device()
        let png=UIGraphicsImageRenderer(size:.init(width:8,height:8)).pngData {context in
            UIColor.blue.setFill();context.fill(.init(x:0,y:0,width:8,height:8))
        }
        let input=a.root.appendingPathComponent("synthetic-input.png");try png.write(to:input)
        let mediaStore=MediaStore(rootURL:a.root)
        let stored=try mediaStore.storeOriginal(.init(url:input,originalFilename:"synthetic.png",contentType:"image/png"),id:imageID)
        try write(a){context in
            let entry=Entry(id:entryID,body:"photo",createdAt:instant)
            let image=ImageMetadata(id:imageID,relativePath:stored.relativePath,originalFilename:"synthetic.png",contentType:"image/png",byteCount:stored.byteCount,pixelWidth:stored.pixelWidth,pixelHeight:stored.pixelHeight,checksum:stored.checksum,createdAt:instant)
            image.entry=entry;context.insert(entry);context.insert(image)
            context.insert(Tag(id:tagID,displayName:"Synthetic",normalizedName:"synthetic",createdAt:instant))
            context.insert(ObjectLink(id:linkID,sourceType:.entry,sourceID:entryID,targetType:.tag,targetID:tagID,kind:.entryUsesTag,createdAt:instant))
        }
        let originalRecords=try allPackets(a)
        let withoutOriginal=originalRecords.filter {if case .original = $0 {return false};return true}
        let originals=originalRecords.filter {if case .original = $0 {return true};return false}
        XCTAssertEqual(originals.count,1)
        try await deliver(Array(withoutOriginal.reversed()),to:b)
        XCTAssertNil(try body(b,id:entryID));XCTAssertEqual(try outboxCount(b),0)
        // R1: an unseen remote entry is not a local deletion baseline.
        let independentID = try createEntry(b, body: "independent local")
        try edit(b, id: independentID, body: "independent edited")
        XCTAssertEqual(try body(b, id: independentID), "independent edited")
        XCTAssertFalse(try revisions(b).contains { $0.manifest.object.id == entryID && $0.manifest.deleted })
        await b.coordinator.disable()
        try edit(b, id: independentID, body: "saved with sync off")
        XCTAssertFalse(try revisions(b).contains { $0.manifest.object.id == entryID && $0.manifest.deleted })
        // Reopen the disk store and use real enable -> initialize -> transport -> apply.
        // The fake transport supplies only the missing original, never bypassing startup.
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: b.root.appendingPathComponent("Store/PersonalGrowthOS.sqlite"))
        reopened.mainContext.autosaveEnabled = false
        let scripted = SyntheticSyncDriver()
        scripted.onFetch = { driver in
            try await driver.persistence!.durableInbox(originals, session: XCTUnwrap(driver.session))
        }
        let replay = SyncProductCoordinator(container: reopened, mediaRoot: b.root, environment: .development, automaticSync: false,
            accountReader: { String(repeating: "a", count: 64) }, transportFactory: { persistence in scripted.persistence = persistence; return scripted })
        await replay.enable()
        XCTAssertEqual(scripted.starts, 1); XCTAssertEqual(scripted.cycles, 1)
        XCTAssertFalse(replay.requiresAttention)
        b = Device(root: b.root, container: reopened, coordinator: replay, session: try XCTUnwrap(scripted.session))
        XCTAssertEqual(try body(b, id: independentID), "saved with sync off")
        XCTAssertEqual(try body(b,id:entryID),"photo")
        let remoteImage=try XCTUnwrap(ModelContext(b.container).fetch(FetchDescriptor<ImageMetadata>()).first)
        XCTAssertEqual(remoteImage.id,imageID)
        XCTAssertEqual(try Data(contentsOf:MediaStore(rootURL:b.root).fileURL(for:remoteImage.relativePath)),png)
        let deletion=ModelContext(a.container);deletion.autosaveEnabled=false
        let entry=try XCTUnwrap(deletion.fetch(FetchDescriptor<Entry>()).first{$0.id==entryID})
        try EntryDeletionService(persistence:ModelContextEntryPersistence(context:deletion),mediaStore:mediaStore).permanentlyDelete(entry)
        XCTAssertFalse(FileManager.default.fileExists(atPath:try mediaStore.fileURL(for:stored.relativePath).path))
        XCTAssertEqual(try SyncAssetStore(root:a.root).read(AssetDescriptor(bytes:png)),png)
        let entryDelete=try head(a,id:entryID),linkDelete=try head(a,kind:.objectLink,id:linkID)
        XCTAssertTrue(entryDelete.manifest.deleted);XCTAssertTrue(linkDelete.manifest.deleted)
        try await deliver(try packets(entryDelete,from:a),to:b)
        XCTAssertEqual(try body(b,id:entryID),"photo") // Live relationship keeps the combined graph unpublished.
        try await deliver(try packets(linkDelete,from:a),to:b)
        try await deliver(originalRecords,to:b) // Old immutable revisions must not resurrect either object.
        let read=ModelContext(b.container)
        XCTAssertEqual(try read.fetch(FetchDescriptor<Entry>()).map(\.id), [independentID])
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<ImageMetadata>()),0)
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<ObjectLink>()),0)
        XCTAssertEqual(try read.fetch(FetchDescriptor<Tag>()).map(\.id),[tagID])
        XCTAssertEqual(try outboxCount(b),3)
        XCTAssertEqual(try SyncAssetStore(root:b.root).read(AssetDescriptor(bytes:png)),png)
    }

    func testDownloadedChangesWaitForDraftRollbackOrSaveThenReplayFromDurableInbox() async throws {
        let a=try device(),b=try device(),id=try createEntry(a,body:"base")
        try await deliver(try allPackets(a),to:b)
        let draft=try XCTUnwrap(b.container.mainContext.fetch(FetchDescriptor<Entry>()).first{$0.id==id})
        draft.body="unsaved draft"
        try edit(a,id:id,body:"remote second");let second=try head(a,id:id)
        try await deliver(try packets(second,from:a),to:b)
        XCTAssertEqual(draft.body,"unsaved draft");XCTAssertEqual(try body(b,id:id),"base")
        XCTAssertGreaterThan(try ModelContext(b.container).fetchCount(FetchDescriptor<ProductSyncInbox>()),0)
        b.container.mainContext.rollback()
        try await deliver([],to:b)
        XCTAssertEqual(try body(b,id:id),"remote second");XCTAssertEqual(try outboxCount(b),0)
        let weight=WeightRecord(weightKilograms:70.5,recordedAt:instant,createdAt:instant)
        b.container.mainContext.insert(weight)
        try edit(a,id:id,body:"remote third");let third=try head(a,id:id)
        try await deliver(try packets(third,from:a),to:b)
        XCTAssertEqual(try body(b,id:id),"remote second")
        try ProductSyncCommit.save(b.container.mainContext)
        try await deliver([],to:b)
        XCTAssertEqual(try body(b,id:id),"remote third")
        let read=ModelContext(b.container)
        XCTAssertEqual(try read.fetch(FetchDescriptor<WeightRecord>()).map(\.weightKilograms),[70.5])
        XCTAssertEqual(try outboxCount(b),1)
        let local=try read.fetch(FetchDescriptor<ProductSyncMutation>()).filter(\.local)
        XCTAssertEqual(try local.map{try MutationManifest.decode($0.manifest).object.kind},[SyncDomainKind.weight.rawValue])
    }
}

/// Controlled send/fetch boundary, using the production persistence and ACK contracts.
@MainActor final class SyntheticSyncDriver: SyncCloudDriving {
    weak var persistence: (any SyncCloudPersistence)?
    var session: SyncCloudSession?
    var starts = 0, cycles = 0, activeCycles = 0, maxActiveCycles = 0
    var requestedZoneCreation: [Bool] = []
    var acknowledgeUploads = false
    var onFetch: ((SyntheticSyncDriver) async throws -> Void)?
    func start(binding: SyncBinding, signedEnvironment: CloudEnvironment, createZone: Bool) async throws {
        XCTAssertEqual(binding.environment, signedEnvironment)
        requestedZoneCreation.append(createZone)
        starts += 1; session = SyncCloudSession(binding: binding)
    }
    func synchronize() async throws {
        let session = try XCTUnwrap(session), persistence = try XCTUnwrap(persistence)
        try session.check(); cycles += 1; activeCycles += 1; maxActiveCycles = max(maxActiveCycles, activeCycles)
        defer { activeCycles -= 1 }
        try persistence.didChangeActivity(.uploading, session: session)
        if acknowledgeUploads {
            let records = try persistence.pendingRecordIDs(session: session)
            for id in records {
                if let upload = try await persistence.uploadRecord(id: id, session: session) {
                    try await persistence.acknowledge([upload.acknowledgement()], session: session)
                }
            }
        }
        try persistence.didChangeActivity(.downloading, session: session)
        try await onFetch?(self)
        try session.check()
    }
    func stop() async { session?.invalidate(); session = nil }
}
