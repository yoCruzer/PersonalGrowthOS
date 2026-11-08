import Foundation

/// Provisioning profiles describe allowed entitlements, not the app's actual claims
/// (Apple TN3125). This narrow parser supports observed CloudKit profile shapes only.
/// A Production entry in this allowance never changes the fixed Development target.
public struct ProbeProfileCloudAllowance: Sendable {
    public let isWellFormed: Bool
    public let permitsDevelopmentCloudKit: Bool

    public init(services: Any?, environment: Any?) {
        let servicesValid: Bool
        if let wildcard = services as? String {
            servicesValid = wildcard == "*"
        } else if let explicit = services as? [String] {
            servicesValid = explicit == ["CloudKit"]
        } else {
            servicesValid = false
        }
        let values: [String]?
        if let single = environment as? String { values = [single] }
        else { values = environment as? [String] }
        let environmentValid = values.map {
            !$0.isEmpty && $0.count <= 2 && Set($0).count == $0.count &&
                Set($0).isSubset(of: ["Development", "Production"])
        } ?? false
        isWellFormed = servicesValid && environmentValid
        permitsDevelopmentCloudKit = isWellFormed && values?.contains("Development") == true
    }
}

/// Parsed metadata only. Runtime caller must obtain it from actual codesign/profile inspection.
/// Pure checks are injectable for tests; that never constitutes an actual signature pass.
public struct ProbeSigningEvidence: Sendable {
    public let signatureVerified: Bool
    public let codeIdentifier: String?
    public let codeTeam: String?
    public let applicationIdentifier: String?
    public let entitlementTeam: String?
    public let containers: [String]
    public let services: [String]
    public let environment: String?
    public let sandbox: Bool
    public let networkClient: Bool
    public let profilePresent: Bool
    public let profileApplicationIdentifier: String?
    public let profileTeam: String?
    public let profileContainers: [String]
    public let profileCloudAllowance: ProbeProfileCloudAllowance
    public let profileUnexpired: Bool
    public init(signatureVerified: Bool, codeIdentifier: String?, codeTeam: String?, applicationIdentifier: String?,
        entitlementTeam: String?, containers: [String], services: [String], environment: String?, sandbox: Bool,
        networkClient: Bool, profilePresent: Bool, profileApplicationIdentifier: String?, profileTeam: String?,
        profileContainers: [String], profileServices: Any?, profileEnvironment: Any?, profileUnexpired: Bool) {
        self.signatureVerified = signatureVerified; self.codeIdentifier = codeIdentifier; self.codeTeam = codeTeam
        self.applicationIdentifier = applicationIdentifier; self.entitlementTeam = entitlementTeam
        self.containers = containers; self.services = services; self.environment = environment
        self.sandbox = sandbox; self.networkClient = networkClient; self.profilePresent = profilePresent
        self.profileApplicationIdentifier = profileApplicationIdentifier; self.profileTeam = profileTeam
        self.profileContainers = profileContainers
        self.profileCloudAllowance = ProbeProfileCloudAllowance(services: profileServices, environment: profileEnvironment)
        self.profileUnexpired = profileUnexpired
    }
    public func rejectionCodes(for plan: FormalProbePlan) -> [String] {
        var failures: [String] = []
        let applicationID = plan.team + "." + plan.candidateBundle
        if !signatureVerified { failures.append("SIGNATURE_NOT_VERIFIED") }
        if codeIdentifier != plan.candidateBundle || codeTeam != plan.team { failures.append("CODE_IDENTITY_MISMATCH") }
        if applicationIdentifier != applicationID || entitlementTeam != plan.team { failures.append("ENTITLEMENT_IDENTITY_MISMATCH") }
        if containers != [plan.container] || services != ["CloudKit"] || environment != "Development" || plan.environment != "Development" { failures.append("CLOUD_ENTITLEMENTS_MISMATCH") }
        if !sandbox || !networkClient { failures.append("SANDBOX_NETWORK_CAPABILITY_MISSING") }
        if !profilePresent { failures.append("PROFILE_MISSING") }
        if profileApplicationIdentifier != applicationID || profileTeam != plan.team || profileContainers != [plan.container]
            || !profileCloudAllowance.permitsDevelopmentCloudKit || !profileUnexpired {
            failures.append("PROFILE_MISMATCH_OR_EXPIRED")
        }
        return failures
    }
}
