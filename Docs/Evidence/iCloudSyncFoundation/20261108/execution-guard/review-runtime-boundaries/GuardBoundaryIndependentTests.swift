import XCTest
import Foundation
import FormalProbeCore
import SyncFoundation
@testable import FormalDevelopmentSDK

@MainActor final class GuardBoundaryIndependentTests: XCTestCase {
    private func ownerBytes(start: Int64, expires: Int64) throws -> Data {
        let fixture = try ProbeFixture.make(run: UUID(), dataset: UUID())
        let r = Data("independent synthetic receipt".utf8), p = Data("independent synthetic pins".utf8)
        return try OwnerExecutionApproval(version: 1, disposition: "OWNER_APPROVED_DEVELOPMENT_WINDOW", purpose: "FIXED_SYNTHETIC_DEVELOPMENT_BATCH",
            ownerDecisionSHA256: String(repeating:"1",count:64), ownerSessionSHA256:String(repeating:"2",count:64),window:UUID(),startsAt:start,expiresAt:expires,
            osUserID:501,run:fixture.plan.run,dataset:fixture.plan.dataset,planSHA256:fixture.plan.digest,schemaSHA256:FormalProbeIdentity.schemaSHA256,
            runtime:ApprovedRuntimeBinding(signedBinarySHA256:String(repeating:"3",count:64),codeDirectoryHash:String(repeating:"4",count:40),profileSHA256:String(repeating:"5",count:64),packagingReceiptSHA256:syncDigest(r),sourcePinsSHA256:syncDigest(p)),packagingReceipt:r,sourcePins:p).encoded()
    }
    func testWindowMonotonicRollbackIsStickyAndCannotBeReopened() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_010), bytes = try ownerBytes(start:2_000_000_000,expires:2_000_000_100)
        let window = try OwnerExecutionApproval.validate(bytes,expectedSHA256:syncDigest(bytes),now:now,userID:501)
        let uptime = ProcessInfo.processInfo.systemUptime
        try window.check(now: now.addingTimeInterval(1),uptime:uptime+1)
        XCTAssertThrowsError(try window.check(now:now.addingTimeInterval(2),uptime:uptime))
        XCTAssertThrowsError(try window.check(now:now.addingTimeInterval(3),uptime:uptime+3))
    }
    func testWindowElapsedBudgetExpiresEvenWithFrozenWallTime() throws {
        let bytes = try ownerBytes(start:2_000_000_000,expires:2_000_000_100), now=Date(timeIntervalSince1970:2_000_000_099)
        let window = try OwnerExecutionApproval.validate(bytes,expectedSHA256:syncDigest(bytes),now:now,userID:501)
        let uptime=ProcessInfo.processInfo.systemUptime
        XCTAssertNoThrow(try window.check(now:now,uptime:uptime))
        XCTAssertThrowsError(try window.check(now:now,uptime:uptime+1.1))
        XCTAssertThrowsError(try window.check(now:now,uptime:uptime+1.2))
    }
    func testAccountEpochCrossQueueChangeIsImmediateStickyAndSafe() throws {
        let latch=AccountEpochLatch();try latch.check()
        DispatchQueue.global().sync { latch.invalidate(.changed) }
        latch.invalidate(.cancelled)
        for _ in 0..<20 { XCTAssertThrowsError(try latch.check()) { XCTAssertEqual($0 as? GuardedAccountError,.changed) } }
        let other=AccountEpochLatch(); XCTAssertNotEqual(latch.epoch,other.epoch);XCTAssertNoThrow(try other.check())
    }
    func testOfflineInspectionRejectsInputWithoutEchoOrAuthority() throws {
        let secret="INVENTED_PRIVATE_PAYLOAD_DO_NOT_ECHO"
        for request in [Data(secret.utf8),Data(repeating:65,count:131073),Data("{\"mode\":\"RUN_APPROVED\",\"path\":\"/invented/private/\(secret)\"}".utf8)] {
            let output=try FormalDevelopmentRuntimeInspection.inspect(request)
            XCTAssertLessThan(output.count,1024)
            XCTAssertFalse(String(decoding:output,as:UTF8.self).contains(secret))
            let result=try XCTUnwrap(JSONSerialization.jsonObject(with:output) as? [String:Any])
            XCTAssertEqual(result["status"] as? String,"NOT_READY")
            XCTAssertEqual(result["networkOperations"] as? Int,0)
            for key in ["networkAuthorized","ownerApprovalVerified","signatureProfileDeviceVerified","p0Passed"] { XCTAssertEqual(result[key] as? Bool,false,key) }
            XCTAssertEqual(result["accountQualification"] as? String,"NOT_RUN")
            XCTAssertEqual(result["actualServiceAccess"] as? String,"NOT_RUN")
        }
    }
    func testLocalWaitCancellationScopeSurvivesLateAccountCallbackWithoutPayload() async throws {
        var events:[TransportOperationEvidence]=[]
        let secret="invented-opaque-account-not-for-evidence"
        let bridge=OperationCallbackBridge<String,String,String>(stage:"account-record-id",expected:["account-record-id"],label:{$0},validValue:{_,_ in true},sink:{events.append($0)},onFailure:{_ in XCTFail()},cancellationScope:.localWaitOnly) { results, result in
            try result.get();return try XCTUnwrap(results["account-record-id"]).get()
        }
        let queued=expectation(description:"local read started"), operation=Operation()
        let task=Task { try await bridge.execute(operation:operation) {queued.fulfill()} }
        await fulfillment(of:[queued],timeout:2)
        bridge.requestCancellation()
        do { _=try await task.value;XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        bridge.receive("account-record-id",.success(secret));bridge.complete(.success(()))
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        XCTAssertEqual(events.map(\.event),["OPERATION_ENQUEUE_REQUESTED","CANCEL_REQUESTED","LATE_ITEM_RETURNED","LATE_OPERATION_RETURNED"])
        XCTAssertTrue(events.allSatisfy{$0.cancellationScope == .localWaitOnly})
        XCTAssertTrue(events.dropFirst().allSatisfy{$0.remoteOutcomeUnknown})
        XCTAssertEqual(Set(events.map(\.operationID)).count,1)
        XCTAssertFalse(String(decoding:try JSONEncoder().encode(events),as:UTF8.self).contains(secret))
        XCTAssertTrue(operation.isCancelled) // local wait handle only; never a CKOperation/server claim.
    }
    func testDefaultSDKScopeDoesNotBecomeLocalWaitScope() async throws {
        var events:[TransportOperationEvidence]=[]
        let bridge=OperationCallbackBridge<Int,Int,Int>(stage:"synthetic",expected:[1],label:{_ in "planned"},validValue:{_,_ in true},sink:{events.append($0)},onFailure:{_ in XCTFail()}) { _, result in try result.get(); return 1 }
        _=try await bridge.execute(operation:Operation()) {bridge.receive(1,.success(1));bridge.complete(.success(()))}
        XCTAssertEqual(events.count,3)
        XCTAssertTrue(events.allSatisfy{$0.cancellationScope == .sdkOperation})
        XCTAssertFalse(events.last!.remoteOutcomeUnknown)
    }
}
