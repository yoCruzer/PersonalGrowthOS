import Foundation
import SyncFoundation

/// Checks the compiled product environment and provisioning *allowances*. A provisioning
/// allowlist is not the running executable's effective entitlements. iOS validates installed
/// code/profile signatures; delivery additionally verifies the signed artifact's actual
/// CloudKit environment. Production activation is deliberately unavailable in this build.
enum SyncBuildConfiguration {
    static let profileByteLimit = 4 * 1_024 * 1_024
    static let productBundleIdentifier = "com.yocruzer.PersonalGrowthOS"
    static let productTeamIdentifier = "83SKX2PM7B"

    static func environment(bundle: Bundle = .main) -> CloudEnvironment? {
        #if DEBUG && !targetEnvironment(simulator)
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        guard let bytes = try? file.read(upToCount: profileByteLimit + 1) else { return nil }
        return permittedDevelopmentEnvironment(
            pin: bundle.object(forInfoDictionaryKey: "PGOSCloudEnvironment") as? String,
            bundleIdentifier: bundle.bundleIdentifier, profileBytes: bytes)
        #else
        // Release and simulator never activate CloudKit, even if a runtime plist pin is supplied.
        return nil
        #endif
    }

    /// Pure metadata parser for offline verification. CMS bytes are already part of the signed
    /// installed bundle; this parser neither verifies CMS signatures nor claims effective rights.
    static func permittedDevelopmentEnvironment(pin: String?, bundleIdentifier: String?,
                                                profileBytes: Data) -> CloudEnvironment? {
        guard profileBytes.count <= profileByteLimit,
              let start = profileBytes.range(of: Data("<?xml".utf8)),
              let end = profileBytes.range(of: Data("</plist>".utf8), in: start.lowerBound..<profileBytes.endIndex),
              let profile = try? PropertyListSerialization.propertyList(
                from: profileBytes[start.lowerBound..<end.upperBound], format: nil) as? [String: Any] else { return nil }
        return permittedDevelopmentEnvironment(pin: pin, bundleIdentifier: bundleIdentifier, profile: profile)
    }

    static func permittedDevelopmentEnvironment(pin: String?, bundleIdentifier: String?,
                                                profile: [String: Any]) -> CloudEnvironment? {
        guard pin == "development", bundleIdentifier == productBundleIdentifier,
              let entitlements = profile["Entitlements"] as? [String: Any],
              entitlements["com.apple.developer.team-identifier"] as? String == productTeamIdentifier,
              entitlements["application-identifier"] as? String == productTeamIdentifier + "." + productBundleIdentifier,
              (entitlements["com.apple.developer.icloud-container-identifiers"] as? [String])?.contains(SyncProductCoordinator.containerID) == true,
              let services = allowanceStrings(entitlements["com.apple.developer.icloud-services"]),
              services.contains("CloudKit") || services.contains("*"),
              let environments = allowanceStrings(entitlements["com.apple.developer.icloud-container-environment"]),
              environments.contains(where: { $0.lowercased() == "development" }) else { return nil }
        return .development
    }

    private static func allowanceStrings(_ value: Any?) -> [String]? {
        if let string = value as? String { return [string] }
        return value as? [String]
    }
}
