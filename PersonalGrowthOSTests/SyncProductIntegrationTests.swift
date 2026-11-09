import Foundation
import SwiftData
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
    var acknowledgeUploads = false
    var onFetch: ((SyntheticSyncDriver) async throws -> Void)?
    func start(binding: SyncBinding, signedEnvironment: CloudEnvironment, createZone: Bool) async throws {
        XCTAssertEqual(binding.environment, signedEnvironment)
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
