import Foundation
import SwiftData
import XCTest
import SyncFoundation
@testable import PersonalGrowthOS

@MainActor final class SyncCommitBoundaryTests: XCTestCase {
    private let instant=Date(timeIntervalSince1970:1_700_000_000)
    private func saveInventory(count:Int) throws -> (ModelContainer,UUID,[NetWorthItemValue],NetWorthSnapshotValue) {
        let container=try PersistenceContainerFactory.makeInMemory(),context=container.mainContext
        context.autosaveEnabled=false
        let dataset=ProductSyncDataset();context.insert(dataset)
        try ProductSyncCommit.initialize(context,dataset:dataset)
        dataset.enabled=true;dataset.accountHash=String(repeating:"a",count:64)
        let items=(0..<count).map { index in
            var value=NetWorthItemValue(name:"Synthetic item \(index)",side:.asset,category:.cash)
            value.createdAt=instant;value.updatedAt=instant;return value
        }
        var snapshot=NetWorthSnapshotValue(day:"2023-11-14")
        snapshot.timeZoneID="UTC";snapshot.createdAt=instant;snapshot.updatedAt=instant;snapshot.completedAt=instant
        snapshot.confirmed=true;snapshot.assetsConfirmed=true;snapshot.liabilitiesConfirmed=true
        snapshot.items=items.map { item in
            var row=NetWorthSnapshotItem(item);row.cents=1;row.state = .entered;row.amountDay=snapshot.day;return row
        }
        // Independent domain truth: the input is legal; the tested rejection is the sync wire bound.
        try NetWorthLedger(items:items,snapshots:[snapshot]).validate()
        for item in items {context.insert(try NetWorthItem(item))}
        context.insert(try NetWorthSnapshot(snapshot))
        try ProductSyncCommit.save(context)
        return (container,dataset.id,items,snapshot)
    }
    private func pendingRecords(_ container:ModelContainer) throws -> Int {
        let dataset=try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<ProductSyncDataset>()).first)
        let binding=try SyncBinding(container:SyncProductCoordinator.containerID,environment:.development,
            accountHash:try XCTUnwrap(dataset.accountHash),dataset:dataset.id,generation:dataset.generation)
        let coordinator=SyncProductCoordinator(container:container,mediaRoot:FileManager.default.temporaryDirectory.appendingPathComponent("PGOS-Synthetic-Boundary-"+UUID().uuidString),environment:.development,automaticSync:false)
        // Pure durable send admission; this does not start a transport or query CloudKit.
        return try coordinator.pendingRecordIDs(session:SyncCloudSession(binding:binding)).count
    }
    func testSmallLegalInventoryCommitsCompleteFactsAndOutbox() throws {
        let (container,_,items,snapshot)=try saveInventory(count:2),read=ModelContext(container)
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<ProductSyncOutbox>()),3)
        XCTAssertFalse(try XCTUnwrap(read.fetch(FetchDescriptor<ProductSyncDataset>()).first).needsReconciliation)
        XCTAssertEqual(try read.fetch(FetchDescriptor<NetWorthSnapshot>()).first?.value(),snapshot)
        XCTAssertEqual(try NetWorthMoney.sum(items.map{_ in Int64(1)}),2)
        XCTAssertGreaterThan(try pendingRecords(container),0)
    }
    func testLegalInventoryBeyondDependencyLimitRemainsDurableAndBlocksSender() throws {
        let count=SyncLimits.dependencies+1
        XCTAssertLessThanOrEqual(count,10_000)
        let (container,datasetID,items,snapshot)=try saveInventory(count:count),read=ModelContext(container)
        let dataset=try XCTUnwrap(read.fetch(FetchDescriptor<ProductSyncDataset>()).first)
        XCTAssertEqual(dataset.id,datasetID);XCTAssertTrue(dataset.needsReconciliation);XCTAssertNotNil(dataset.blockedReason)
        let actualItems=try read.fetch(FetchDescriptor<NetWorthItem>()).map{try $0.value()}
        XCTAssertEqual(actualItems.sorted{$0.id.uuidString<$1.id.uuidString},items.sorted{$0.id.uuidString<$1.id.uuidString})
        XCTAssertEqual(try read.fetch(FetchDescriptor<NetWorthSnapshot>()).first?.value(),snapshot)
        XCTAssertEqual(try snapshot.totals().assets,Int64(count))
        // No truncated snapshot is advertised as a complete immutable mutation.
        let manifests=try read.fetch(FetchDescriptor<ProductSyncMutation>()).map{try MutationManifest.decode($0.manifest)}
        XCTAssertFalse(manifests.contains{$0.object.kind == SyncDomainKind.netWorthSnapshot.rawValue})
        XCTAssertTrue(manifests.allSatisfy{$0.dataset == datasetID})
        XCTAssertThrowsError(try pendingRecords(container))
    }
}
