import XCTest
import Foundation
import Darwin
@testable import FormalDevelopmentSDK

@MainActor final class ReviewLedgerStore: ExecutionAnchorStore {
    var bytes:Data?
    var failReplace=false
    func load() throws -> Data? { bytes }
    func create(_ data:Data) throws { guard bytes==nil else {throw LedgerFailure.anchorFailure};bytes=data }
    func replace(expected:Data,with data:Data) throws { guard bytes==expected && !failReplace else {throw LedgerFailure.anchorFailure};bytes=data }
}
@MainActor final class ReviewLedgerClock: LedgerClock {
    var wall:Int64=1_900_000_000_000
    var uptime:UInt64=100_000_000_000
    func now()->LedgerTime{LedgerTime(wallMS:wall,uptimeNS:uptime)}
}
@MainActor final class IndependentLedgerReviewTests:XCTestCase {
    func testFrozenWallCannotExtendMonotonicWindow() throws {
        let p=URL(fileURLWithPath:"/private/tmp/PGOS-LedgerClockReview-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:p,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let store=ReviewLedgerStore(),clock=ReviewLedgerClock(),h=String(repeating:"a",count:64)
        let ledger=try ExecutionLedger.enrollForTesting(root:p.appendingPathComponent("ledger"),anchorStore:store,clock:clock,ownerDecisionSHA256:h)
        let binding=ExecutionBinding(ownerWindow:UUID(),approvalInputSHA256:h,ownerDecisionSHA256:h,windowStartMS:clock.wall-1000,windowEndMS:clock.wall+60_000,
            planSHA256:h,run:UUID(),dataset:UUID(),schemaSHA256:"6fcf5478c3307685f8a45154b44eeeaec6a907c33412a2c388a6cb8831f04003",
            binarySHA256:h,codeDirectoryHash:String(repeating:"b",count:40),profileSHA256:h,packagingReceiptSHA256:h,sourcePinsSHA256:h,osUserID:getuid(),
            osSessionSHA256:h,ownerConfirmedAccountSessionSHA256:h,accountSHA256:nil)
        let permit=try ledger.consume(.qualificationRead,binding:binding)
        clock.uptime += 61_000_000_000
        XCTAssertThrowsError(try ledger.intent(.accountStatus,permit:permit),"Wall clock remained in-window, but elapsed monotonic time exhausted its remaining lifetime")
    }
    @MainActor struct ReviewContext {
        let parent:URL,root:URL,store:ReviewLedgerStore,clock:ReviewLedgerClock
        func open() throws -> ExecutionLedger {try .openForTesting(root:root,anchorStore:store,clock:clock)}
    }
    let h=String(repeating:"a",count:64)
    func context()->ReviewContext {
        let p=URL(fileURLWithPath:"/private/tmp/PGOS-LedgerIndependent-"+UUID().uuidString)
        return ReviewContext(parent:p,root:p.appendingPathComponent("ledger"),store:ReviewLedgerStore(),clock:ReviewLedgerClock())
    }
    func enroll(_ c:ReviewContext)throws->ExecutionLedger {
        try FileManager.default.createDirectory(at:c.parent,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        return try .enrollForTesting(root:c.root,anchorStore:c.store,clock:c.clock,ownerDecisionSHA256:h)
    }
    func binding(_ c:ReviewContext,from old:ExecutionBinding?=nil,account:String?=nil,changedReceipt:Bool=false)->ExecutionBinding {
        ExecutionBinding(ownerWindow:old?.ownerWindow ?? UUID(),approvalInputSHA256:old?.approvalInputSHA256 ?? h,ownerDecisionSHA256:h,
            windowStartMS:old?.windowStartMS ?? c.clock.wall-1000,windowEndMS:old?.windowEndMS ?? c.clock.wall+60_000,
            planSHA256:old?.planSHA256 ?? h,run:old?.run ?? UUID(),dataset:old?.dataset ?? UUID(),
            schemaSHA256:"6fcf5478c3307685f8a45154b44eeeaec6a907c33412a2c388a6cb8831f04003",binarySHA256:h,
            codeDirectoryHash:String(repeating:"b",count:40),profileSHA256:h,packagingReceiptSHA256:changedReceipt ? String(repeating:"c",count:64):h,
            sourcePinsSHA256:h,osUserID:getuid(),osSessionSHA256:h,ownerConfirmedAccountSessionSHA256:h,accountSHA256:account)
    }
    func finishQualification(_ ledger:ExecutionLedger,_ binding:ExecutionBinding)throws->String {
        let account=try ledger.accountDigest("synthetic independent account only"),p=try ledger.consume(.qualificationRead,binding:binding)
        for op:LedgerOperation in [.accountStatus,.userRecordID] {
            try ledger.intent(op,permit:p);try ledger.returned(op,status:.success,summarySHA256:h,accountSHA256:op == .userRecordID ? account:nil,permit:p)
            try ledger.validated(op,permit:p)
        }
        try ledger.finishQualification(accountSHA256:account,permit:p);return account
    }
    func testFullFiveStageFlowThenDurableReplayRejection() throws {
        let c=context();var ledger:ExecutionLedger?=try enroll(c);let b=binding(c),account=try finishQualification(ledger!,b)
        let p=try ledger!.consume(.developmentBatch,binding:binding(c,from:b,account:account))
        for stage in LedgerStage.allCases {
            try ledger!.intent(.accountCheckBefore(stage),permit:p);try ledger!.returned(.accountCheckBefore(stage),status:.success,summarySHA256:h,accountSHA256:account,permit:p);try ledger!.validated(.accountCheckBefore(stage),permit:p)
            try ledger!.intent(.transport(stage),permit:p);try ledger!.returned(.transport(stage),status:.success,summarySHA256:h,permit:p)
            XCTAssertThrowsError(try ledger!.validated(.transport(stage),permit:p))
            try ledger!.intent(.accountCheckAfter(stage),permit:p);try ledger!.returned(.accountCheckAfter(stage),status:.success,summarySHA256:h,accountSHA256:account,permit:p);try ledger!.validated(.accountCheckAfter(stage),permit:p)
            try ledger!.validated(.transport(stage),permit:p)
        }
        try ledger!.finishBatch(permit:p);ledger=nil
        let reopened=try c.open();XCTAssertFalse(reopened.hasUnresolvedExecutions)
        XCTAssertThrowsError(try reopened.consume(.qualificationRead,binding:b));XCTAssertThrowsError(try reopened.consume(.developmentBatch,binding:binding(c,from:b,account:account)))
    }
    func testReopeningDoesNotResetQualificationMonotonicBudget() throws {
        let c=context();var ledger:ExecutionLedger?=try enroll(c);let b=binding(c),account=try finishQualification(ledger!,b);ledger=nil
        c.clock.uptime += 61_000_000_000
        let reopened=try c.open();XCTAssertThrowsError(try reopened.consume(.developmentBatch,binding:binding(c,from:b,account:account)))
    }
    func testQualificationCannotAuthorizeDifferentReceiptOrAccount() throws {
        let c=context(),ledger=try enroll(c),b=binding(c),account=try finishQualification(ledger,b)
        XCTAssertThrowsError(try ledger.consume(.developmentBatch,binding:binding(c,from:b,account:account,changedReceipt:true)))
        XCTAssertThrowsError(try ledger.consume(.developmentBatch,binding:binding(c,from:b,account:String(repeating:"f",count:64))))
        XCTAssertNoThrow(try ledger.consume(.developmentBatch,binding:binding(c,from:b,account:account)))
    }
    func testAnchorCommitGapPreservesFailureAndCannotReopenOrReenroll() throws {
        let c=context();var ledger:ExecutionLedger?=try enroll(c);let initial=c.store.bytes;c.store.failReplace=true
        XCTAssertThrowsError(try ledger!.consume(.qualificationRead,binding:binding(c)))
        let record=c.root.appendingPathComponent("00000001.json"),bytes=try Data(contentsOf:record)
        XCTAssertEqual(c.store.bytes,initial);XCTAssertThrowsError(try ledger!.accountDigest("synthetic"));ledger=nil;c.store.failReplace=false
        XCTAssertThrowsError(try c.open());XCTAssertThrowsError(try ExecutionLedger.enrollForTesting(root:c.root,anchorStore:c.store,clock:c.clock,ownerDecisionSHA256:h))
        XCTAssertEqual(try Data(contentsOf:record),bytes);XCTAssertEqual(c.store.bytes,initial)
    }
    func testMissingLedgerWithRetainedAnchorNeverCreatesFreshState() throws {
        let c=context();var ledger:ExecutionLedger?=try enroll(c);_ = try ledger!.consume(.qualificationRead,binding:binding(c));ledger=nil
        let anchor=c.store.bytes;try FileManager.default.moveItem(at:c.root,to:c.parent.appendingPathComponent("preserved-original"))
        XCTAssertThrowsError(try c.open());XCTAssertThrowsError(try ExecutionLedger.enrollForTesting(root:c.root,anchorStore:c.store,clock:c.clock,ownerDecisionSHA256:h))
        XCTAssertFalse(FileManager.default.fileExists(atPath:c.root.path));XCTAssertEqual(c.store.bytes,anchor)
    }
    func testHardlinkedRecordFailsIntegrityWithoutChangingEitherCopy() throws {
        let c=context(),ledger=try enroll(c);_ = try ledger.consume(.qualificationRead,binding:binding(c))
        let record=c.root.appendingPathComponent("00000001.json"),alias=c.parent.appendingPathComponent("alias");let bytes=try Data(contentsOf:record)
        XCTAssertEqual(link(record.path,alias.path),0);XCTAssertThrowsError(try ledger.accountDigest("synthetic"))
        XCTAssertEqual(try Data(contentsOf:record),bytes);XCTAssertEqual(try Data(contentsOf:alias),bytes)
    }
    func testLateReturnAndObservationPreserveEvidenceWithoutRevivingPermit() throws {
        let c=context(),ledger=try enroll(c),p=try ledger.consume(.qualificationRead,binding:binding(c))
        let op=try ledger.intent(.accountStatus,permit:p)
        c.clock.wall += 61_000;c.clock.uptime += 61_000_000_000
        XCTAssertNoThrow(try ledger.returned(.accountStatus,status:.success,summarySHA256:h,permit:p))
        XCTAssertThrowsError(try ledger.validated(.accountStatus,permit:p));try ledger.terminateUnknown(reason:.expired,permit:p)
        XCTAssertNoThrow(try ledger.recordObservation(operationID:op,event:.lateCallback,summarySHA256:h,permit:p))
        XCTAssertThrowsError(try ledger.recordObservation(operationID:UUID(),event:.lateCallback,summarySHA256:h,permit:p))
        XCTAssertThrowsError(try ledger.intent(.userRecordID,permit:p));XCTAssertThrowsError(try ledger.binding(for:p,requiring:.qualificationRead))
    }

    func testReplacedLockCannotAdmitSecondHolderWhileFirstLives() throws {
        let c=context(),first=try enroll(c)
        let path=c.root.appendingPathComponent("guard.lock"),preserved=c.parent.appendingPathComponent("original-held-lock")
        try FileManager.default.moveItem(at:path,to:preserved)
        XCTAssertTrue(FileManager.default.createFile(atPath:path.path,contents:Data(),attributes:[.posixPermissions:0o600]))
        XCTAssertThrowsError(try c.open(),"Persistent anchor must bind lock identity, not only root identity")
        withExtendedLifetime(first) {}
    }

    func testPendingIntentRetainsOriginalOriginAfterReopen() throws {
        let c=context();var first:ExecutionLedger?=try enroll(c);let b=binding(c),account=try finishQualification(first!,b);first=nil
        c.clock.uptime += 4_000_000_000
        let second=try c.open(),p=try second.consume(.developmentBatch,binding:binding(c,from:b,account:account))
        let op=LedgerOperation.accountCheckBefore(.zoneProbe),id=try second.intent(op,permit:p)
        XCTAssertNoThrow(try second.requirePendingIntent(op,operationID:id,permit:p))
        c.clock.uptime += 2_000_000_000
        XCTAssertThrowsError(try second.requirePendingIntent(op,operationID:id,permit:p),"Final enqueue gate must compare the original qualification origin, not the reopened ledger origin")
    }
    func testPendingIntentBindsExactOperationIDAndAwaitingState() throws {
        let c=context(),ledger=try enroll(c),p=try ledger.consume(.qualificationRead,binding:binding(c))
        let id=try ledger.intent(.accountStatus,permit:p)
        XCTAssertNoThrow(try ledger.requirePendingIntent(.accountStatus,operationID:id,permit:p))
        XCTAssertThrowsError(try ledger.requirePendingIntent(.userRecordID,operationID:id,permit:p))
        XCTAssertThrowsError(try ledger.requirePendingIntent(.accountStatus,operationID:UUID(),permit:p))
        try ledger.returned(.accountStatus,status:.success,summarySHA256:h,permit:p)
        XCTAssertThrowsError(try ledger.requirePendingIntent(.accountStatus,operationID:id,permit:p))
        try ledger.terminateUnknown(reason:.interrupted,permit:p)
        XCTAssertThrowsError(try ledger.requirePendingIntent(.accountStatus,operationID:id,permit:p))
    }

}
