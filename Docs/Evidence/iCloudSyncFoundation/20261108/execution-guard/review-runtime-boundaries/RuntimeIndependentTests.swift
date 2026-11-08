import XCTest
import Foundation
@testable import FormalDevelopmentSDK
final class RuntimeIndependentTests: XCTestCase {
    func testCryptographicallyValidButUntrustedSyntheticCMSRejects() throws {
        let cms = try Data(contentsOf: URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["PGOS_SYNTHETIC_CMS"])))
        XCTAssertThrowsError(try RuntimeSigningInspector.trustedProfile(cms)) { error in
            XCTAssertEqual(error as? RuntimeSigningError, .profileTrustUnavailable)
        }
    }
    func testDuplicateAliasesAndUnknownDeviceFieldsReject() throws {
        let id = "00000000-0000-0000-0000-000000000099"
        for item: [String: Any] in [["serial_number":id], ["platform_UUID":id], ["provisioningUDID":id,"Provisioning_UDID":id], ["provisioningUDID":String(repeating:"A",count:65)]] {
            let bytes = try JSONSerialization.data(withJSONObject:["SPHardwareDataType":[item]])
            XCTAssertThrowsError(try RuntimeSigningInspector.provisioningUDID(from:bytes))
        }
    }
    func testNonBooleanSandboxAndUnknownEntitlementReject() throws {
        var ent: [String:Any] = ["com.apple.application-identifier":RuntimeSigningInspector.team+"."+RuntimeSigningInspector.bundle,
            "com.apple.developer.team-identifier":RuntimeSigningInspector.team,"com.apple.developer.icloud-container-identifiers":[RuntimeSigningInspector.container],
            "com.apple.developer.icloud-services":["CloudKit"],"com.apple.developer.icloud-container-environment":"Development",
            "com.apple.security.app-sandbox":true,"com.apple.security.network.client":true]
        XCTAssertNoThrow(try RuntimeSigningInspector.validateEntitlements(ent))
        for value: Any in [1, 1.0, "true", [true]] { ent["com.apple.security.app-sandbox"]=value;XCTAssertThrowsError(try RuntimeSigningInspector.validateEntitlements(ent)) }
        ent["com.apple.security.app-sandbox"]=true;ent["com.apple.security.get-task-allow"]=true
        XCTAssertThrowsError(try RuntimeSigningInspector.validateEntitlements(ent))
    }
}
