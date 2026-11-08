import XCTest
import Foundation
import Darwin
import FormalProbeCore
import SyncFoundation
@testable import FormalDevelopmentSDK

@MainActor final class OwnerCloseoutApprovalTests: XCTestCase {
    private func envelope() throws -> OwnerCloseoutApproval {
        let fixture = try ProbeFixture.make(run: UUID(), dataset: UUID())
        let receipt = Data("synthetic invalid receipt: cannot qualify or open Keychain".utf8)
        let pins = Data("synthetic invalid source pins".utf8)
        let start = Int64(Date().timeIntervalSince1970) - 1
        let owner = OwnerExecutionApproval(version: 1, disposition: "OWNER_APPROVED_DEVELOPMENT_WINDOW",
            purpose: "LOCAL_GUARD_CLOSEOUT_UNKNOWN", ownerDecisionSHA256: String(repeating: "1", count: 64),
            ownerSessionSHA256: String(repeating: "2", count: 64), window: UUID(), startsAt: start,
            expiresAt: start + 300, osUserID: getuid(), run: fixture.plan.run, dataset: fixture.plan.dataset,
            planSHA256: try fixture.plan.digest, schemaSHA256: FormalProbeIdentity.schemaSHA256,
            runtime: ApprovedRuntimeBinding(signedBinarySHA256: String(repeating: "3", count: 64),
                codeDirectoryHash: String(repeating: "4", count: 40), profileSHA256: String(repeating: "5", count: 64),
                packagingReceiptSHA256: syncDigest(receipt), sourcePinsSHA256: syncDigest(pins)),
            packagingReceipt: receipt, sourcePins: pins)
        return OwnerCloseoutApproval(version: 1, purpose: "LOCAL_CLOSEOUT_UNKNOWN", approval: owner,
            expectedHeadSequence: 5, expectedHeadFileSHA256: String(repeating: "6", count: 64))
    }
    private func changed(_ bytes: Data, _ update: (inout [String: Any]) -> Void) throws -> Data {
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any]); update(&value)
        return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    func testCanonicalOuterDigestBindsHeadAndTargetWithoutGrantingRuntimeAuthority() throws {
        let value = try envelope(), bytes = try json(value)
        let (window, target) = try OwnerCloseoutApproval.validate(bytes, expectedSHA256: syncDigest(bytes))
        XCTAssertEqual(window.approval.purpose, "LOCAL_GUARD_CLOSEOUT_UNKNOWN")
        XCTAssertEqual(target.run, value.approval.run); XCTAssertEqual(target.dataset, value.approval.dataset)
        XCTAssertEqual(target.planSHA256, value.approval.planSHA256)
        XCTAssertEqual(target.expectedHeadSequence, 5)
        XCTAssertEqual(target.expectedHeadFileSHA256, value.expectedHeadFileSHA256)
        XCTAssertEqual(target.approvalSHA256, syncDigest(bytes))
        XCTAssertNotEqual(target.approvalSHA256, window.inputSHA256, "Persist the entire head-bound approval, not merely the inner window")
    }
    func testRejectsUnboundOrNoncanonicalHeadAndExtraFields() throws {
        let bytes = try json(envelope())
        for bad in [bytes + Data([10]), try changed(bytes) { $0["expectedHeadSequence"] = 0 },
                    try changed(bytes) { $0["expectedHeadSequence"] = 2_049 },
                    try changed(bytes) { $0["expectedHeadFileSHA256"] = String(repeating: "0", count: 64) },
                    try changed(bytes) { $0["path"] = "/arbitrary" },
                    try changed(bytes) { $0["purpose"] = "FIXED_SYNTHETIC_DEVELOPMENT_BATCH" }] {
            XCTAssertThrowsError(try OwnerCloseoutApproval.validate(bad, expectedSHA256: syncDigest(bad)))
        }
        XCTAssertThrowsError(try OwnerCloseoutApproval.validate(bytes, expectedSHA256: String(repeating: "7", count: 64)))
    }
    func testRejectsWrongUserExpiredWindowAndCloudPurpose() throws {
        let value = try envelope(), bytes = try json(value)
        XCTAssertThrowsError(try OwnerCloseoutApproval.validate(bytes, expectedSHA256: syncDigest(bytes), userID: getuid()+1))
        XCTAssertThrowsError(try OwnerCloseoutApproval.validate(bytes, expectedSHA256: syncDigest(bytes),
            now: Date(timeIntervalSince1970: Double(value.approval.expiresAt))))
        let bad = try changed(bytes) {
            var owner = $0["approval"] as! [String: Any]; owner["purpose"] = "FIXED_SYNTHETIC_DEVELOPMENT_BATCH"; $0["approval"] = owner
        }
        XCTAssertThrowsError(try OwnerCloseoutApproval.validate(bad, expectedSHA256: syncDigest(bad)))
    }
    func testPublicCloseoutRejectsFakeArtifactBeforeKeychainOrStorage() throws {
        let bytes = try json(envelope())
        for _ in 0..<2 {
            XCTAssertThrowsError(try FormalDevelopmentGuardedExecution.closeoutUnknown(approval: bytes, expectedSHA256: syncDigest(bytes))) {
                XCTAssertEqual($0 as? RuntimeSigningError, .receiptMismatch)
            }
        }
    }
    func testLocalCloseoutApprovalCannotEnterEnrollmentOrCloudRun() async throws {
        let bytes = try envelope().approval.encoded()
        XCTAssertThrowsError(try FormalDevelopmentGuardedExecution.enroll(approval: bytes, expectedSHA256: syncDigest(bytes))) {
            XCTAssertEqual($0 as? GuardedEntryError, .wrongPurpose)
        }
        do {
            _ = try await FormalDevelopmentGuardedExecution.run(approval: bytes, expectedSHA256: syncDigest(bytes), onEvidenceFatal: { XCTFail() })
            XCTFail()
        } catch { XCTAssertEqual(error as? GuardedEntryError, .wrongPurpose) }
    }
}
