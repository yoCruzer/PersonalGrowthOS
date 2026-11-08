import XCTest
import Foundation
@testable import FormalDevelopmentSDK

final class RuntimeDiagnosticTests: XCTestCase {
    func testTopLevelRejectionsKeepWhitelistedCausesWithoutClaimingSideEffects() throws {
        let cases: [(Error, String)] = [
            (OwnerWindowError.bindingMismatch, "WINDOW_bindingMismatch"),
            (LedgerFailure.replay, "LEDGER_replay"),
            (GuardedEntryError.osSessionChanged, "ENTRY_osSessionChanged"),
            (RuntimeSigningDiagnosticFailure(stage: .deviceTimeout, status: 2), "RUNTIME_deviceTimeout_2"),
            (RuntimeSigningError.profileExpired, "RUNTIME_profileExpired")
        ]
        for (error, expected) in cases {
            let bytes = try FormalDevelopmentFailureDiagnostics.report(error)
            let result = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            XCTAssertEqual(result["status"] as? String, "GUARDED_EXECUTION_FAILED")
            XCTAssertEqual(result["failure"] as? String, expected)
            XCTAssertEqual(result["sideEffects"] as? String, "NOT_INFERRED_FROM_ERROR")
            XCTAssertEqual(result["p0Passed"] as? Bool, false)
        }
    }
    func testUnknownErrorDescriptionAndUserInfoNeverEscape() throws {
        let secret = "synthetic-sensitive-path-or-account"
        let error = NSError(domain: secret, code: 7, userInfo: [NSLocalizedDescriptionKey: secret, "payload": secret])
        let bytes = try FormalDevelopmentFailureDiagnostics.report(error)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(secret))
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(result["failure"] as? String, "IO_OR_VALIDATION_FAILED")
    }
    @MainActor func testAsyncInspectionStopsOnFirstRejectedInputWithoutOpeningStorage() async throws {
        let bytes = try await FormalDevelopmentRuntimeInspection.inspectAsync(Data("{}".utf8))
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(result["status"] as? String, "NOT_READY")
        XCTAssertEqual(result["networkOperations"] as? Int, 0)
        XCTAssertEqual(result["keychainOperations"] as? Int, 0)
        let observations = try XCTUnwrap(result["observations"] as? [[String: Any]])
        XCTAssertEqual(observations.count, 1)
        XCTAssertEqual(observations.first?["phase"] as? String, "async-entry")
        let inner = try XCTUnwrap(Data(base64Encoded: observations[0]["report"] as! String))
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: inner) as? [String: Any])
        XCTAssertEqual(report["evidenceVersion"] as? Int, 2)
        XCTAssertEqual(report["signatureProfileDeviceVerified"] as? Bool, false)
        XCTAssertEqual(report["signatureAndProfileVerified"] as? Bool, false)
        XCTAssertEqual(report["operatingSystemEntitlementsValidated"] as? Bool, false)
        XCTAssertEqual(report["exactProfileDeviceMembership"] as? String, "NOT_RECHECKED_AT_RUNTIME")
        XCTAssertNil(report["operatingSystemCodeStatus"])
    }
}
