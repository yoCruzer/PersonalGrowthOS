import XCTest
import Foundation
import FormalProbeCore
import SyncFoundation
@testable import FormalDevelopmentSDK

@MainActor final class OwnerExecutionApprovalTests: XCTestCase {
    private let start: Int64 = 2_000_000_000
    private func approval() throws -> OwnerExecutionApproval {
        let fixture = try ProbeFixture.make(run: UUID(), dataset: UUID())
        let receipt = Data("synthetic receipt; runtime inspector must reject this".utf8)
        let pins = Data("synthetic pins; not code qualification".utf8)
        return OwnerExecutionApproval(version: 1, disposition: "OWNER_APPROVED_DEVELOPMENT_WINDOW",
            purpose: "FIXED_SYNTHETIC_DEVELOPMENT_BATCH", ownerDecisionSHA256: String(repeating: "1", count: 64),
            ownerSessionSHA256: String(repeating: "2", count: 64), window: UUID(), startsAt: start,
            expiresAt: start + 900, osUserID: 501, run: fixture.plan.run, dataset: fixture.plan.dataset,
            planSHA256: try fixture.plan.digest, schemaSHA256: FormalProbeIdentity.schemaSHA256,
            runtime: ApprovedRuntimeBinding(signedBinarySHA256: String(repeating: "3", count: 64),
                codeDirectoryHash: String(repeating: "4", count: 40), profileSHA256: String(repeating: "5", count: 64),
                packagingReceiptSHA256: syncDigest(receipt), sourcePinsSHA256: syncDigest(pins)),
            packagingReceipt: receipt, sourcePins: pins)
    }
    private func validate(_ bytes: Data, at offset: Int64 = 0, user: UInt32 = 501) throws -> ValidatedOwnerWindow {
        try OwnerExecutionApproval.validate(bytes, expectedSHA256: syncDigest(bytes),
            now: Date(timeIntervalSince1970: Double(start + offset)), userID: user)
    }
    private func changed(_ bytes: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any]); change(&value)
        return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
    func testCanonicalDecisionIsOnlyAWindowNotRuntimeQualification() throws {
        let value = try approval(), bytes = try value.encoded(), window = try validate(bytes)
        XCTAssertEqual(window.approval, value)
        XCTAssertThrowsError(try RuntimeSigningInspector.validateReceipt(value.packagingReceipt,
            sourcePins: value.sourcePins, expected: value.runtime.expectation()))
    }
    func testWindowStartInclusiveEndExclusiveAndWrongUser() throws {
        let bytes = try approval().encoded()
        XCTAssertNoThrow(try validate(bytes))
        XCTAssertNoThrow(try validate(bytes, at: 899))
        XCTAssertThrowsError(try validate(bytes, at: -1))
        XCTAssertThrowsError(try validate(bytes, at: 900))
        XCTAssertThrowsError(try validate(bytes, user: 502))
    }
    func testLaterClockRollbackCannotReopenWindow() throws {
        let window = try validate(approval().encoded())
        try window.check(now: Date(timeIntervalSince1970: Double(start + 4)))
        XCTAssertThrowsError(try window.check(now: Date(timeIntervalSince1970: Double(start + 3))))
        XCTAssertThrowsError(try window.check(now: Date(timeIntervalSince1970: Double(start + 5))))
    }
    func testFrozenWallClockCannotExtendRemainingSecond() throws {
        let window = try validate(approval().encoded(), at: 899)
        XCTAssertThrowsError(try window.check(now: Date(timeIntervalSince1970: Double(start + 899)),
            uptime: ProcessInfo.processInfo.systemUptime + 2))
    }
    func testTemplateUnknownPurposeAndMissingDecisionRejectEvenWithNewHash() throws {
        let bytes = try approval().encoded()
        for (key, value) in [("disposition", "OFFLINE_APPROVAL_REQUEST"), ("purpose", "Production"),
                             ("ownerDecisionSHA256", String(repeating: "0", count: 64))] {
            XCTAssertThrowsError(try validate(changed(bytes) { $0[key] = value }))
        }
    }
    func testUnknownFieldsAndNoncanonicalBytesReject() throws {
        let bytes = try approval().encoded()
        XCTAssertThrowsError(try validate(changed(bytes) { $0["allowLive"] = true }))
        XCTAssertThrowsError(try validate(bytes + Data([10])))
        XCTAssertThrowsError(try OwnerExecutionApproval.validate(bytes, expectedSHA256: String(repeating: "0", count: 64),
            now: Date(timeIntervalSince1970: Double(start)), userID: 501))
    }
    func testPlanAndArtifactInputsRemainBound() throws {
        let bytes = try approval().encoded()
        for key in ["planSHA256", "schemaSHA256"] {
            XCTAssertThrowsError(try validate(changed(bytes) { $0[key] = String(repeating: "f", count: 64) }))
        }
        for key in ["run", "dataset"] {
            XCTAssertThrowsError(try validate(changed(bytes) { $0[key] = UUID().uuidString }))
        }
        XCTAssertThrowsError(try validate(changed(bytes) { $0["packagingReceipt"] = Data("replaced".utf8).base64EncodedString() }))
        XCTAssertThrowsError(try validate(changed(bytes) { $0["sourcePins"] = Data("replaced".utf8).base64EncodedString() }))
    }
    func testUnboundedWindowOrRootIdentityReject() throws {
        let bytes = try approval().encoded()
        XCTAssertThrowsError(try validate(changed(bytes) { $0["expiresAt"] = start + 901 }))
        XCTAssertThrowsError(try validate(changed(bytes) { $0["expiresAt"] = start }))
        XCTAssertThrowsError(try validate(changed(bytes) { $0["startsAt"] = -1 }))
        XCTAssertThrowsError(try validate(changed(bytes) { $0["osUserID"] = 0 }, user: 0))
    }
}
