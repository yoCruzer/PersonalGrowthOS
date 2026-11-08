import XCTest
import SyncFoundation
@testable import PersonalGrowthOS

final class SyncBuildConfigurationTests: XCTestCase {
    private var entitlements: [String: Any] {
        ["com.apple.developer.team-identifier": "83SKX2PM7B",
         "application-identifier": "83SKX2PM7B.com.yocruzer.PersonalGrowthOS",
         "com.apple.developer.icloud-container-identifiers": ["iCloud.com.yocruzer.PersonalGrowthOS"],
         "com.apple.developer.icloud-services": "*",
         "com.apple.developer.icloud-container-environment": ["Production", "Development"]]
    }
    private func allowed(_ values: [String: Any], pin: String? = "development",
                         bundle: String? = "com.yocruzer.PersonalGrowthOS") -> CloudEnvironment? {
        SyncBuildConfiguration.permittedDevelopmentEnvironment(pin: pin, bundleIdentifier: bundle,
                                                               profile: ["Entitlements": values])
    }
    func testAppleProfileAllowsStringWildcardServicesAndEnvironmentArray() {
        XCTAssertEqual(allowed(entitlements), .development)
        var specific = entitlements
        specific["com.apple.developer.icloud-services"] = ["CloudKit"]
        specific["com.apple.developer.icloud-container-environment"] = "Development"
        XCTAssertEqual(allowed(specific), .development)
    }
    func testProductionPinAndUnsupportedEnvironmentNeverActivate() {
        XCTAssertNil(allowed(entitlements, pin: "production"))
        XCTAssertNil(allowed(entitlements, pin: nil))
        for environment: Any in ["Production", ["Production"], "*", true, ["Development", 1]] {
            var invalid = entitlements; invalid["com.apple.developer.icloud-container-environment"] = environment
            XCTAssertNil(allowed(invalid))
        }
    }
    func testIdentityMustMatchExactlyAndCannotUseWildcardIdentifiers() {
        for (key, value): (String, Any) in [
            ("com.apple.developer.team-identifier", "OTHERTEAM"),
            ("application-identifier", "83SKX2PM7B.*"),
            ("application-identifier", "83SKX2PM7B.com.yocruzer.PersonalGrowthOS.FormalSyncProbe"),
            ("com.apple.developer.icloud-container-identifiers", ["*"]),
            ("com.apple.developer.icloud-container-identifiers", ["iCloud.com.synthetic.other"])
        ] {
            var invalid = entitlements; invalid[key] = value
            XCTAssertNil(allowed(invalid))
        }
        XCTAssertNil(allowed(entitlements, bundle: nil))
        XCTAssertNil(allowed(entitlements, bundle: "com.synthetic.other"))
    }
    func testServicesNeedCloudKitOrExplicitProfileWildcard() {
        for services: Any in ["CloudDocuments", ["CloudDocuments"], true, ["CloudKit", 1]] {
            var invalid = entitlements; invalid["com.apple.developer.icloud-services"] = services
            XCTAssertNil(allowed(invalid))
        }
        var explicit = entitlements; explicit["com.apple.developer.icloud-services"] = "CloudKit"
        XCTAssertEqual(allowed(explicit), .development)
    }
    func testBoundedProfileParserRejectsMalformedAndAcceptsWrappedXML() throws {
        let xml = try PropertyListSerialization.data(fromPropertyList: ["Entitlements": entitlements], format: .xml, options: 0)
        let wrapped = Data([0x30,0x82,0x01,0x00]) + xml + Data([0x01,0x02])
        XCTAssertEqual(SyncBuildConfiguration.permittedDevelopmentEnvironment(pin: "development",
            bundleIdentifier: "com.yocruzer.PersonalGrowthOS", profileBytes: wrapped), .development)
        for invalid in [Data(), Data("<?xml><plist>broken</plist>".utf8), Data(repeating: 0, count: SyncBuildConfiguration.profileByteLimit + 1)] {
            XCTAssertNil(SyncBuildConfiguration.permittedDevelopmentEnvironment(pin: "development",
                bundleIdentifier: "com.yocruzer.PersonalGrowthOS", profileBytes: invalid))
        }
    }
    func testReleaseProductionDoesNotRequireEmbeddedProfile() {
        XCTAssertEqual(SyncBuildConfiguration.permittedEnvironment(buildMode: .release, isSimulator: false,
            pin: "production", bundleIdentifier: SyncBuildConfiguration.productBundleIdentifier), .production)
        // An optional profile does not become Release signing evidence or alter the selected realm.
        XCTAssertEqual(SyncBuildConfiguration.permittedEnvironment(buildMode: .release, isSimulator: false,
            pin: "production", bundleIdentifier: SyncBuildConfiguration.productBundleIdentifier,
            profileBytes: Data("not a profile".utf8)), .production)
    }
    func testReleaseRejectsUnknownPinsAndWrongBundle() {
        for pin in [nil, "development", "Production", " production", "production ", "$(PGOS_CLOUD_RUNTIME_ENVIRONMENT)"] as [String?] {
            XCTAssertNil(SyncBuildConfiguration.permittedEnvironment(buildMode: .release, isSimulator: false,
                pin: pin, bundleIdentifier: SyncBuildConfiguration.productBundleIdentifier))
        }
        for bundle in [nil, "com.synthetic.other", SyncBuildConfiguration.productBundleIdentifier + ".FormalSyncProbe"] as [String?] {
            XCTAssertNil(SyncBuildConfiguration.permittedEnvironment(buildMode: .release, isSimulator: false,
                pin: "production", bundleIdentifier: bundle))
        }
    }
    func testDebugDeviceRequiresDevelopmentMetadataAndProfile() throws {
        let xml = try PropertyListSerialization.data(fromPropertyList: ["Entitlements": entitlements], format: .xml, options: 0)
        XCTAssertEqual(SyncBuildConfiguration.permittedEnvironment(buildMode: .debug, isSimulator: false,
            pin: "development", bundleIdentifier: SyncBuildConfiguration.productBundleIdentifier,
            profileBytes: xml), .development)
        XCTAssertNil(SyncBuildConfiguration.permittedEnvironment(buildMode: .debug, isSimulator: false,
            pin: "development", bundleIdentifier: SyncBuildConfiguration.productBundleIdentifier))
        XCTAssertNil(SyncBuildConfiguration.permittedEnvironment(buildMode: .debug, isSimulator: false,
            pin: "production", bundleIdentifier: SyncBuildConfiguration.productBundleIdentifier, profileBytes: xml))
        var invalid = entitlements
        invalid["com.apple.developer.team-identifier"] = "OTHERTEAM"
        let badXML = try PropertyListSerialization.data(fromPropertyList: ["Entitlements": invalid], format: .xml, options: 0)
        XCTAssertNil(SyncBuildConfiguration.permittedEnvironment(buildMode: .debug, isSimulator: false,
            pin: "development", bundleIdentifier: SyncBuildConfiguration.productBundleIdentifier, profileBytes: badXML))
    }
    func testSimulatorNeverActivatesEvenWithValidBuildMetadataAndProfile() throws {
        let xml = try PropertyListSerialization.data(fromPropertyList: ["Entitlements": entitlements], format: .xml, options: 0)
        for (mode, pin): (SyncBuildConfiguration.BuildMode, String) in [(.debug, "development"), (.release, "production")] {
            XCTAssertNil(SyncBuildConfiguration.permittedEnvironment(buildMode: mode, isSimulator: true,
                pin: pin, bundleIdentifier: SyncBuildConfiguration.productBundleIdentifier, profileBytes: xml))
        }
        #if targetEnvironment(simulator)
        XCTAssertNil(SyncBuildConfiguration.environment())
        #endif
    }
    func testLocalMetadataSelectorDoesNotRequireCloudEligibility() {
        XCTAssertEqual(SyncBuildConfiguration.metadataEnvironment(buildMode: .debug, pin: "development",
            bundleIdentifier: SyncBuildConfiguration.productBundleIdentifier), .development)
        XCTAssertEqual(SyncBuildConfiguration.metadataEnvironment(buildMode: .release, pin: "production",
            bundleIdentifier: SyncBuildConfiguration.productBundleIdentifier), .production)
        for (mode, wrongPin): (SyncBuildConfiguration.BuildMode, String) in [(.debug, "production"), (.release, "development")] {
            XCTAssertNil(SyncBuildConfiguration.metadataEnvironment(buildMode: mode, pin: wrongPin,
                bundleIdentifier: SyncBuildConfiguration.productBundleIdentifier))
            XCTAssertNil(SyncBuildConfiguration.metadataEnvironment(buildMode: mode, pin: nil,
                bundleIdentifier: SyncBuildConfiguration.productBundleIdentifier))
            XCTAssertNil(SyncBuildConfiguration.metadataEnvironment(buildMode: mode, pin: wrongPin,
                bundleIdentifier: "com.synthetic.other"))
        }
    }
}
