import Foundation
import SyncFoundation

/// Selects the build's CloudKit environment; this is not a signature or entitlement verifier.
/// Debug device builds additionally inspect provisioning allowances. Distribution builds may
/// have no embedded profile, so Release relies on exact compiled metadata and independently
/// verified distribution signing. Neither metadata nor profile parsing proves effective rights.
enum SyncBuildConfiguration {
    enum BuildMode { case debug, release }

    static let profileByteLimit = 4 * 1_024 * 1_024
    static let productBundleIdentifier = "com.yocruzer.PersonalGrowthOS"
    static let productTeamIdentifier = "83SKX2PM7B"

    private static var compiledBuildMode: BuildMode {
        #if DEBUG
        return .debug
        #else
        return .release
        #endif
    }

    /// Local persistence realm selection only. A simulator can select a local realm but cannot
    /// activate CloudKit. Unknown metadata must remain unknown, rather than relabel local facts.
    static func metadataEnvironment(bundle: Bundle = .main) -> CloudEnvironment? {
        metadataEnvironment(buildMode: compiledBuildMode,
            pin: bundle.object(forInfoDictionaryKey: "PGOSCloudEnvironment") as? String,
            bundleIdentifier: bundle.bundleIdentifier)
    }

    static func metadataEnvironment(buildMode: BuildMode, pin: String?,
                                    bundleIdentifier: String?) -> CloudEnvironment? {
        guard bundleIdentifier == productBundleIdentifier else { return nil }
        switch buildMode {
        case .debug: return pin == "development" ? .development : nil
        case .release: return pin == "production" ? .production : nil
        }
    }

    static func environment(bundle: Bundle = .main) -> CloudEnvironment? {
        #if targetEnvironment(simulator)
        return nil
        #elseif DEBUG
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        guard let bytes = try? file.read(upToCount: profileByteLimit + 1) else { return nil }
        return permittedEnvironment(buildMode: .debug, isSimulator: false,
            pin: bundle.object(forInfoDictionaryKey: "PGOSCloudEnvironment") as? String,
            bundleIdentifier: bundle.bundleIdentifier, profileBytes: bytes)
        #else
        return permittedEnvironment(buildMode: .release, isSimulator: false,
            pin: bundle.object(forInfoDictionaryKey: "PGOSCloudEnvironment") as? String,
            bundleIdentifier: bundle.bundleIdentifier)
        #endif
    }

    /// Pure routing policy for tests and offline review, not evidence of valid code signing.
    static func permittedEnvironment(buildMode: BuildMode, isSimulator: Bool,
                                     pin: String?, bundleIdentifier: String?,
                                     profileBytes: Data? = nil) -> CloudEnvironment? {
        guard !isSimulator,
              let selected = metadataEnvironment(buildMode: buildMode, pin: pin,
                                                   bundleIdentifier: bundleIdentifier) else { return nil }
        switch buildMode {
        case .debug:
            guard let profileBytes else { return nil }
            return permittedDevelopmentEnvironment(pin: pin, bundleIdentifier: bundleIdentifier,
                                                    profileBytes: profileBytes)
        case .release:
            // Profile presence/contents are not a Release runtime authority. Archive and
            // distribution checks must independently verify actual signed entitlements.
            return selected
        }
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
