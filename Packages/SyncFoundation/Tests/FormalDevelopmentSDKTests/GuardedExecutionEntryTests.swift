import XCTest
import Foundation
import Darwin
import FormalProbeCore
import SyncFoundation
@testable import FormalDevelopmentSDK

@MainActor final class GuardedExecutionEntryTests: XCTestCase {
    // Every public-entry call below fails before real self inspection completes.
    // No test supplies a usable profile/receipt, constructs a session, or invokes CLI.
    private func approval(_ purpose: String = "FIXED_SYNTHETIC_DEVELOPMENT_BATCH", now: Date = Date()) throws -> Data {
        let fixture = try ProbeFixture.make(run: UUID(), dataset: UUID())
        let receipt = Data("original synthetic invalid receipt; no credentials".utf8)
        let pins = Data("original synthetic pins; never a real artifact".utf8)
        let start = Int64(now.timeIntervalSince1970) - 1
        return try OwnerExecutionApproval(version: 1, disposition: "OWNER_APPROVED_DEVELOPMENT_WINDOW", purpose: purpose,
            ownerDecisionSHA256: String(repeating: "1", count: 64), ownerSessionSHA256: String(repeating: "2", count: 64),
            window: UUID(), startsAt: start, expiresAt: start + 60, osUserID: getuid(), run: fixture.plan.run, dataset: fixture.plan.dataset,
            planSHA256: fixture.plan.digest, schemaSHA256: FormalProbeIdentity.schemaSHA256,
            runtime: ApprovedRuntimeBinding(signedBinarySHA256: String(repeating: "3", count: 64), codeDirectoryHash: String(repeating: "4", count: 40),
                profileSHA256: String(repeating: "5", count: 64), packagingReceiptSHA256: syncDigest(receipt), sourcePinsSHA256: syncDigest(pins)),
            packagingReceipt: receipt, sourcePins: pins).encoded()
    }
    private func changing(_ bytes: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any]); change(&value)
        return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    func testPurePreflightRequiresCanonicalBytesAndExternalDigest() throws {
        let bytes = try approval()
        XCTAssertNoThrow(try FormalDevelopmentGuardedExecution.validateApproval(bytes, expectedSHA256: syncDigest(bytes), purpose: "FIXED_SYNTHETIC_DEVELOPMENT_BATCH"))
        for bad in [bytes + Data([10]), try changing(bytes) { $0["database"] = "caller supplied" }, Data(repeating: 32, count: 131_073)] {
            XCTAssertThrowsError(try FormalDevelopmentGuardedExecution.validateApproval(bad, expectedSHA256: syncDigest(bad), purpose: "FIXED_SYNTHETIC_DEVELOPMENT_BATCH"))
        }
        XCTAssertThrowsError(try FormalDevelopmentGuardedExecution.validateApproval(bytes, expectedSHA256: String(repeating: "0", count: 64), purpose: "FIXED_SYNTHETIC_DEVELOPMENT_BATCH"))
    }
    func testPublicEnrollRejectsBatchPurposeBeforeSigningOrStorage() throws {
        let bytes = try approval()
        XCTAssertThrowsError(try FormalDevelopmentGuardedExecution.enroll(approval: bytes, expectedSHA256: syncDigest(bytes))) {
            XCTAssertEqual($0 as? GuardedEntryError, .wrongPurpose)
        }
    }
    func testPublicRunRejectsEnrollmentPurposeBeforeSigningOrStorage() async throws {
        let bytes = try approval("LOCAL_GUARD_ENROLLMENT")
        do { _ = try await FormalDevelopmentGuardedExecution.run(approval: bytes, expectedSHA256: syncDigest(bytes), onEvidenceFatal: { XCTFail("no run exists") }); XCTFail() }
        catch { XCTAssertEqual(error as? GuardedEntryError, .wrongPurpose) }
    }
    func testPublicEnrollmentInvalidArtifactStopsBeforeKeychainAndCanRejectAgain() throws {
        let bytes = try approval("LOCAL_GUARD_ENROLLMENT")
        for _ in 0..<2 {
            XCTAssertThrowsError(try FormalDevelopmentGuardedExecution.enroll(approval: bytes, expectedSHA256: syncDigest(bytes))) {
                // validateReceipt executes before SecCode, device, OS session, or Keychain.
                XCTAssertEqual($0 as? RuntimeSigningError, .receiptMismatch)
            }
        }
    }
    func testPublicRunInvalidArtifactStopsBeforeAnyContainerOrAccount() async throws {
        let bytes = try approval()
        for _ in 0..<2 {
            do { _ = try await FormalDevelopmentGuardedExecution.run(approval: bytes, expectedSHA256: syncDigest(bytes), onEvidenceFatal: { XCTFail("no run exists") }); XCTFail() }
            catch { XCTAssertEqual(error as? RuntimeSigningError, .receiptMismatch) }
        }
    }
    func testTemplateWrongWindowAndArtifactBindingCannotBecomePermission() throws {
        let bytes = try approval(), now = Date()
        let variants = [try changing(bytes) { $0["disposition"] = "OFFLINE_APPROVAL_REQUEST" },
                        try changing(bytes) { $0["expiresAt"] = Int64(now.timeIntervalSince1970) - 2 },
                        try changing(bytes) { $0["osUserID"] = getuid() + 1 },
                        try changing(bytes) { $0["run"] = UUID().uuidString },
                        try changing(bytes) { $0["packagingReceipt"] = Data("replaced".utf8).base64EncodedString() }]
        for bad in variants {
            XCTAssertThrowsError(try FormalDevelopmentGuardedExecution.validateApproval(bad, expectedSHA256: syncDigest(bad), purpose: "FIXED_SYNTHETIC_DEVELOPMENT_BATCH"))
        }
    }
    func testPureOSSessionPolicyRejectsRootRemoteInvalidAndChangedEffectiveUID() throws {
        let boot = UUID()
        let valid = try OSExecutionSession.validated(userID: 501, effectiveUserID: 501, securitySessionID: 123, attributes: 0x10, bootSession: boot)
        XCTAssertEqual(valid.digest.count, 64)
        for (uid, euid, id, attributes): (UInt32, UInt32, UInt32, UInt32) in [(0,0,123,0x10),(501,0,123,0x10),(501,501,0,0x10),(501,501,UInt32.max,0x10),(501,501,UInt32.max-1,0x10),(501,501,123,0x11),(501,501,123,0x1010),(501,501,123,0)] {
            XCTAssertThrowsError(try OSExecutionSession.validated(userID: uid, effectiveUserID: euid, securitySessionID: id, attributes: attributes, bootSession: boot))
        }
    }
    func testPureOSBindingChangesForBootUserAuditSessionOrAttributes() throws {
        let boot = UUID()
        func make(_ uid: UInt32 = 501, _ id: UInt32 = 123, _ attributes: UInt32 = 0x10, _ epoch: UUID? = nil) throws -> OSExecutionSession {
            try .validated(userID: uid, effectiveUserID: uid, securitySessionID: id, attributes: attributes, bootSession: epoch ?? boot)
        }
        let baseline = try make()
        XCTAssertEqual(baseline, try make()); XCTAssertEqual(baseline.digest, try make().digest)
        for other in [try make(502), try make(501,124), try make(501,123,0x30), try make(501,123,0x10,UUID())] {
            XCTAssertNotEqual(baseline, other); XCTAssertNotEqual(baseline.digest, other.digest)
        }
    }
    func testProductionAttemptLatchIsIrreversibleAcrossSuccessOrFailure() throws {
        let latch = ProductionAttemptLatch()
        XCTAssertNoThrow(try latch.check()); XCTAssertNoThrow(try latch.consume())
        for _ in 0..<3 {
            XCTAssertThrowsError(try latch.check()) { XCTAssertEqual($0 as? GuardedEntryError, .attemptConsumed) }
            XCTAssertThrowsError(try latch.consume()) { XCTAssertEqual($0 as? GuardedEntryError, .attemptConsumed) }
        }
        // A new process has a new latch; durable ledger remains responsible for
        // rejecting reuse of a consumed Owner window across process launches.
        XCTAssertNoThrow(try ProductionAttemptLatch().check())
    }
}
