import Foundation
import SyncFoundation

/// iOS validates the installed application's signature/provisioning. Read its bundled
/// provisioning entitlements and require agreement with our build's environment pin;
/// an arbitrary Info.plist value alone is never sufficient to activate the transport.
enum SyncBuildConfiguration {
    static func environment(bundle: Bundle = .main) -> CloudEnvironment? {
        #if targetEnvironment(simulator)
        return nil
        #else
        guard let pin = bundle.object(forInfoDictionaryKey: "PGOSCloudEnvironment") as? String,
              let environment = CloudEnvironment(rawValue: pin),
              let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let bytes = try? Data(contentsOf: url), bytes.count <= 4 * 1_024 * 1_024,
              let start = bytes.range(of: Data("<?xml".utf8)),
              let end = bytes.range(of: Data("</plist>".utf8), in: start.lowerBound..<bytes.endIndex),
              let profile = try? PropertyListSerialization.propertyList(from: bytes[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
              let entitlements = profile["Entitlements"] as? [String: Any],
              let team = entitlements["com.apple.developer.team-identifier"] as? String, team == "83SKX2PM7B",
              entitlements["application-identifier"] as? String == team + "." + (bundle.bundleIdentifier ?? ""),
              (entitlements["com.apple.developer.icloud-container-identifiers"] as? [String])?.contains(SyncProductCoordinator.containerID) == true,
              (entitlements["com.apple.developer.icloud-services"] as? [String])?.contains("CloudKit") == true,
              (entitlements["com.apple.developer.icloud-container-environment"] as? String)?.lowercased() == pin else { return nil }
        return environment
        #endif
    }
}
