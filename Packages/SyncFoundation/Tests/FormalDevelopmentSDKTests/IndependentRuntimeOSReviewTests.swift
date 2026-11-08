import XCTest
import Foundation
@testable import FormalDevelopmentSDK

final class IndependentRuntimeOSReviewTests: XCTestCase {
    func testEveryCombinationOfAuthorityAndSelfSigningBitsUsesKernelMeaning() throws {
        // Independent truth table: valid + validated restricted entitlements,
        // with neither ad hoc nor linker signing. Other flags add no authority.
        let flags: [UInt32] = [0x1, 0x4000, 0x2, 0x20000]
        for combination in 0..<16 {
            let number = flags.enumerated().reduce(UInt32(0)) { result, item in
                result | (combination & (1 << item.offset) == 0 ? 0 : item.element)
            }
            for additional: UInt32 in [0, 0x10000, 0x20000000, 0x80000000] {
                let value = NSNumber(value: number | additional)
                let encoded = try PropertyListSerialization.data(fromPropertyList: ["status": value], format: .binary, options: 0)
                let roundtrip = try XCTUnwrap(PropertyListSerialization.propertyList(from: encoded, format: nil) as? [String: Any])
                if combination == 3 {
                    XCTAssertEqual(try RuntimeSigningInspector.validateOperatingSystemCodeStatus(roundtrip["status"]), number | additional)
                } else {
                    XCTAssertThrowsError(try RuntimeSigningInspector.validateOperatingSystemCodeStatus(roundtrip["status"]))
                }
            }
        }
        for invalid: Any in [NSNumber(value: 16385.0), NSNumber(value: -16385), NSNumber(value: UInt64(0x100004001)), true] {
            XCTAssertThrowsError(try RuntimeSigningInspector.validateOperatingSystemCodeStatus(invalid))
        }
    }
    func testMalformedRuntimeReportsNeverClaimOldDeviceProofOrOSAdmission() throws {
        for input in [Data("{}".utf8), Data("{\"secret\":\"SYNTHETIC_PRIVATE_VALUE\"}".utf8), Data(repeating: 32, count: 131_073)] {
            let bytes = try FormalDevelopmentRuntimeInspection.inspect(input)
            let result = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            XCTAssertEqual(result["evidenceVersion"] as? Int, 2)
            XCTAssertEqual(result["status"] as? String, "NOT_READY")
            for key in ["signatureProfileDeviceVerified", "signatureAndProfileVerified", "operatingSystemEntitlementsValidated", "p0Passed", "networkAuthorized"] {
                XCTAssertEqual(result[key] as? Bool, false, key)
            }
            XCTAssertEqual(result["exactProfileDeviceMembership"] as? String, "NOT_RECHECKED_AT_RUNTIME")
            XCTAssertEqual(result["deviceEligibilityEvidence"] as? String, "NOT_VERIFIED")
            XCTAssertNil(result["operatingSystemCodeStatus"])
            XCTAssertEqual(result["networkOperations"] as? Int, 0)
            XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("SYNTHETIC_PRIVATE_VALUE"))
        }
    }
}
