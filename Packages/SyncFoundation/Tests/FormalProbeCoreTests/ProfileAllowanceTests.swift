import XCTest
import FormalProbeCore

final class ProfileAllowanceTests: XCTestCase {
    private func parsed(_ services: Any?, _ environment: Any?) -> ProbeProfileCloudAllowance {
        ProbeProfileCloudAllowance(services: services, environment: environment)
    }
    func testObservedWildcardDualEnvironmentAllowsOnlyDevelopmentClaim() {
        for environments in [["Production", "Development"], ["Development", "Production"]] {
            let value = parsed("*", environments)
            XCTAssertTrue(value.isWellFormed); XCTAssertTrue(value.permitsDevelopmentCloudKit)
        }
    }
    func testLegacyExplicitAndSingleEnvironmentRemainCompatible() {
        for services: Any in ["*", ["CloudKit"]] {
            for environment: Any in ["Development", ["Development"]] {
                XCTAssertTrue(parsed(services, environment).permitsDevelopmentCloudKit)
            }
        }
    }
    func testProductionOnlyProfileDoesNotPermitDevelopment() {
        for environment: Any in ["Production", ["Production"]] {
            let value = parsed("*", environment)
            XCTAssertTrue(value.isWellFormed); XCTAssertFalse(value.permitsDevelopmentCloudKit)
        }
    }
    func testMissingUnknownMixedOrDuplicateServicesReject() {
        let values: [Any?] = [nil, NSNull(), true, 1, Data(), [:], [], "", "CloudKit", "Cloud*",
                              ["*"], ["CloudDocuments"], ["CloudKit", "CloudKit"], ["CloudKit", "*"],
                              ["CloudKit", 1], ["CloudKit", true], [["CloudKit"]]]
        for value in values {
            let parsed = parsed(value, ["Development", "Production"])
            XCTAssertFalse(parsed.isWellFormed, "Malformed service shape accepted: \(String(describing: value))")
            XCTAssertFalse(parsed.permitsDevelopmentCloudKit)
        }
    }
    func testMissingUnknownMixedOrDuplicateEnvironmentsReject() {
        let values: [Any?] = [nil, NSNull(), true, 1, Data(), [:], [], "", "*", "development", "Staging",
                              ["Development", "Development"], ["Production", "Production"],
                              ["Development", "Production", "Development"], ["Development", "Unknown"],
                              ["Development", 1], ["Development", true], [["Development"]]]
        for value in values {
            let parsed = parsed("*", value)
            XCTAssertFalse(parsed.isWellFormed, "Malformed environment shape accepted: \(String(describing: value))")
            XCTAssertFalse(parsed.permitsDevelopmentCloudKit)
        }
    }
    func testActualPropertyListTypesUseSameParser() throws {
        let plist: [String: Any] = ["services": "*", "environment": ["Production", "Development"]]
        for format in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
            let bytes = try PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0)
            let decoded = try XCTUnwrap(PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any])
            XCTAssertTrue(parsed(decoded["services"], decoded["environment"]).permitsDevelopmentCloudKit)
        }
    }
    func testAllowlistNeverWidensSignedEntitlementsOrIdentity() throws {
        let plan = try ProbeFixture.make(run: UUID(), dataset: UUID()).plan
        func evidence(services: [String] = ["CloudKit"], environment: String? = "Development", valid: Bool = true,
                      profileServices: Any? = "*", profileEnvironment: Any? = ["Production", "Development"],
                      profilePresent: Bool = true, unexpired: Bool = true, team: String? = nil,
                      containers: [String]? = nil) -> ProbeSigningEvidence {
            ProbeSigningEvidence(signatureVerified: valid, codeIdentifier: plan.candidateBundle, codeTeam: plan.team,
                applicationIdentifier: plan.team + "." + plan.candidateBundle, entitlementTeam: plan.team,
                containers: [plan.container], services: services, environment: environment, sandbox: true, networkClient: true,
                profilePresent: profilePresent, profileApplicationIdentifier: plan.team + "." + plan.candidateBundle,
                profileTeam: team ?? plan.team, profileContainers: containers ?? [plan.container],
                profileServices: profileServices, profileEnvironment: profileEnvironment, profileUnexpired: unexpired)
        }
        XCTAssertTrue(evidence().rejectionCodes(for: plan).isEmpty, "Injected metadata only, not a real signing/profile qualification")
        for claim in [["*"], ["CloudKit", "CloudDocuments"], [], ["CloudKit", "CloudKit"]] {
            XCTAssertTrue(evidence(services: claim).rejectionCodes(for: plan).contains("CLOUD_ENTITLEMENTS_MISMATCH"))
        }
        for claim: String? in ["Production", "*", nil] {
            XCTAssertTrue(evidence(environment: claim).rejectionCodes(for: plan).contains("CLOUD_ENTITLEMENTS_MISMATCH"))
        }
        XCTAssertTrue(evidence(valid: false).rejectionCodes(for: plan).contains("SIGNATURE_NOT_VERIFIED"))
        XCTAssertTrue(evidence(profilePresent: false).rejectionCodes(for: plan).contains("PROFILE_MISSING"))
        for value in [evidence(profileServices: ["CloudKit", 1]), evidence(profileEnvironment: ["Production"]),
                      evidence(profileEnvironment: ["Development", "Development"]), evidence(unexpired: false),
                      evidence(team: "WRONG_TEAM"), evidence(containers: ["iCloud.other"])] {
            XCTAssertTrue(value.rejectionCodes(for: plan).contains("PROFILE_MISMATCH_OR_EXPIRED"))
        }
    }
}
