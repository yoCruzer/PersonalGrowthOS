import XCTest
import Foundation
import CoreFoundation
@testable import FormalDevelopmentSDK

extension RuntimeSigningInspectorTests {
    func testOperatingSystemStatusRequiresLiveAuthorizationBitsAndRejectsSelfSigning() throws {
        for status: UInt32 in [0x4001, 0x20004201, 0x60004201] {
            XCTAssertEqual(try RuntimeSigningInspector.validateOperatingSystemCodeStatus(NSNumber(value: status)), status)
        }
        for status: UInt32 in [0, 1, 0x4000, 0x20000001, 0x4003, 0x24001, 0x24003] {
            XCTAssertThrowsError(try RuntimeSigningInspector.validateOperatingSystemCodeStatus(NSNumber(value: status))) { error in
                XCTAssertEqual(error as? RuntimeSigningError, .operatingSystemEntitlementsUnvalidated)
            }
        }
    }
    func testOperatingSystemStatusRejectsMissingBooleanStringFractionAndOutOfRangeNumbers() throws {
        let values: [Any?] = [nil, NSNull(), true, false, NSNumber(value: true), "16385", NSString(string: "16385"),
            Data([1]), ["status": 16385], NSNumber(value: -1), NSNumber(value: UInt64(UInt32.max) + 1),
            NSNumber(value: UInt64.max), NSNumber(value: 16385.5), NSNumber(value: Double.nan),
            NSNumber(value: Double.infinity), NSDecimalNumber(string: "16385.000000000000000001")]
        for value in values {
            XCTAssertThrowsError(try RuntimeSigningInspector.validateOperatingSystemCodeStatus(value)) { error in
                XCTAssertEqual(error as? RuntimeSigningError, .operatingSystemStatusUnavailable)
            }
        }
        // A static-flags dictionary is not a dynamic status observation.
        let staticOnly: [String: Any] = ["flags": NSNumber(value: 0x4001)]
        XCTAssertThrowsError(try RuntimeSigningInspector.validateOperatingSystemCodeStatus(staticOnly["status"]))
    }
    func testProfileMetadataDoesNotClaimExplicitDeviceMembership() throws {
        var value = profile()
        value["ProvisionedDevices"] = ["SYNTHETIC_DIFFERENT_DEVICE"]
        XCTAssertEqual(try RuntimeSigningInspector.validateProfileMetadata(value, signingLeaf: leaf, now: now), now.addingTimeInterval(100))
        XCTAssertThrowsError(try RuntimeSigningInspector.validateProfile(value, signingLeaf: leaf, provisioningUDID: device, now: now))
        XCTAssertNoThrow(try RuntimeSigningInspector.validateProfile(profile(), signingLeaf: leaf, provisioningUDID: device, now: now))
    }
    func testProfileMetadataRetainsDevelopmentAllowlistCertificateAndValidityGates() throws {
        let variants: [(String, Any)] = [
            ("Platform", ["iOS"]), ("TeamIdentifier", ["OTHER"]), ("CreationDate", now.addingTimeInterval(1)),
            ("ExpirationDate", now), ("DeveloperCertificates", [Data([0])]),
            ("ProvisionedDevices", []), ("ProvisionedDevices", [""]), ("ProvisionedDevices", [device, device]),
            ("ProvisionedDevices", ["bad\0device"]), ("ProvisionedDevices", [String(repeating: "a", count: 129)]),
            ("ProvisionedDevices", (0...1000).map { "SYNTHETIC_\($0)" }),
            ("ProvisionedDevices", [true]), ("ProvisionsAllDevices", true), ("ProvisionsAllDevices", false)
        ]
        for (key, replacement) in variants {
            var value = profile(); value[key] = replacement
            XCTAssertThrowsError(try RuntimeSigningInspector.validateProfileMetadata(value, signingLeaf: leaf, now: now), key)
        }
        for key in ["ProvisionedDevices", "DeveloperCertificates", "Entitlements", "CreationDate", "ExpirationDate"] {
            var value = profile(); value.removeValue(forKey: key)
            XCTAssertThrowsError(try RuntimeSigningInspector.validateProfileMetadata(value, signingLeaf: leaf, now: now), key)
        }
        var value = profile(), claims = entitlements()
        claims["com.apple.developer.icloud-container-environment"] = "Production"; value["Entitlements"] = claims
        XCTAssertThrowsError(try RuntimeSigningInspector.validateProfileMetadata(value, signingLeaf: leaf, now: now))
        for key in entitlements().keys {
            var claims = entitlements(); claims.removeValue(forKey: key)
            XCTAssertThrowsError(try RuntimeSigningInspector.validateEntitlements(claims), key)
        }
    }
}
