import Foundation
import Darwin
import FormalProbeCore
import SyncFoundation

func json<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
}
#if os(macOS)
struct ProcessResult { let exit: Int32; let bytes: Data }
func capture(_ executable: String, _ arguments: [String], maximum: Int = 131_072) throws -> ProcessResult {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
    process.standardOutput = pipe; process.standardError = pipe
    try process.run()
    var bytes = Data()
    while let part = try pipe.fileHandleForReading.read(upToCount: min(65_536, maximum - bytes.count + 1)), !part.isEmpty {
        if bytes.count + part.count > maximum { process.terminate(); process.waitUntilExit(); throw FormalProbeError.limit }
        bytes.append(part)
    }
    process.waitUntilExit(); return ProcessResult(exit: process.terminationStatus, bytes: bytes)
}
func xmlBytes(_ bytes: Data) -> Data? {
    guard let text = String(data: bytes, encoding: .utf8), let start = text.range(of: "<?xml"),
          let end = text.range(of: "</plist>", range: start.lowerBound..<text.endIndex) else { return nil }
    return Data(text[start.lowerBound..<end.upperBound].utf8)
}
func dictionary(_ bytes: Data) -> [String: Any] {
    // Never publish raw codesign or profile output (profiles may contain device identifiers).
    guard let body = xmlBytes(bytes) else { return [:] }
    return (try? PropertyListSerialization.propertyList(from: body, format: nil)) as? [String: Any] ?? [:]
}
func sameArtifact(_ a: stat, _ b: stat) -> Bool {
    a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_mode == b.st_mode && a.st_size == b.st_size &&
    a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
    a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
}
func field(_ key: String, in bytes: Data) -> String? {
    String(data: bytes, encoding: .utf8)?.split(separator: "\n").first(where: { $0.hasPrefix(key + "=") }).map { String($0.dropFirst(key.count + 1)) }
}
func inspect(_ artifact: URL) -> (ProbeSigningEvidence, String?, String?, [String]) {
    var rejection: [String] = [], valid = false
    var details = Data(), entitlements: [String: Any] = [:], profile: [String: Any] = [:], profileHash: String?
    do {
        let parent = try ProbeDirectory(artifact.deletingLastPathComponent(), create: false)
        try parent.requirePathBinding()
        var state = stat()
        guard lstat(artifact.path, &state) == 0,
              [S_IFREG, S_IFDIR].contains(state.st_mode & S_IFMT) else { throw FormalProbeError.invalidPath }
        let check = try capture("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--all-architectures", artifact.path])
        valid = check.exit == 0
        if valid {
            let output = try capture("/usr/bin/codesign", ["-d", "--verbose=4", "--entitlements", ":-", artifact.path])
            guard output.exit == 0 else { throw FormalProbeError.signatureUnavailable }
            details = output.bytes
            entitlements = dictionary(output.bytes)
        }
        if artifact.pathExtension == "app" {
            let contents = try ProbeDirectory(artifact.appendingPathComponent("Contents", isDirectory: true), create: false)
            let bytes = try contents.read("embedded.provisionprofile", maximum: 2_097_152)
            profileHash = syncDigest(bytes)
            let url = try contents.assetURL("embedded.provisionprofile")
            let cms = try capture("/usr/bin/security", ["cms", "-D", "-i", url.path], maximum: 2_097_152)
            if cms.exit == 0 { profile = dictionary(cms.bytes) }
            else { rejection.append("PROFILE_DECODE_FAILED") }
            guard try contents.read("embedded.provisionprofile", maximum: 2_097_152) == bytes else { throw FormalProbeError.fileChanged }
            try contents.requirePathBinding()
        }
        let finalCheck = try capture("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--all-architectures", artifact.path])
        guard (finalCheck.exit == 0) == valid else { throw FormalProbeError.fileChanged }
        if valid {
            let final = try capture("/usr/bin/codesign", ["-d", "--verbose=4", "--entitlements", ":-", artifact.path])
            guard final.exit == 0, field("CDHash", in: final.bytes) == field("CDHash", in: details),
                  field("Identifier", in: final.bytes) == field("Identifier", in: details),
                  field("TeamIdentifier", in: final.bytes) == field("TeamIdentifier", in: details),
                  xmlBytes(final.bytes) == xmlBytes(details) else { throw FormalProbeError.fileChanged }
        }
        var finalState = stat()
        guard lstat(artifact.path, &finalState) == 0, sameArtifact(state, finalState) else { throw FormalProbeError.fileChanged }
        try parent.requirePathBinding()
    } catch {
        valid = false
        rejection.append(error is FormalProbeError && String(describing: error) == "fileChanged" ? "ARTIFACT_CHANGED" : "ARTIFACT_OR_METADATA_UNAVAILABLE")
    }
    let pe = profile["Entitlements"] as? [String: Any] ?? [:]
    let evidence = ProbeSigningEvidence(signatureVerified: valid,
        codeIdentifier: field("Identifier", in: details), codeTeam: field("TeamIdentifier", in: details),
        applicationIdentifier: (entitlements["com.apple.application-identifier"] ?? entitlements["application-identifier"]) as? String,
        entitlementTeam: entitlements["com.apple.developer.team-identifier"] as? String,
        containers: entitlements["com.apple.developer.icloud-container-identifiers"] as? [String] ?? [],
        services: entitlements["com.apple.developer.icloud-services"] as? [String] ?? [],
        environment: entitlements["com.apple.developer.icloud-container-environment"] as? String,
        sandbox: entitlements["com.apple.security.app-sandbox"] as? Bool == true,
        networkClient: entitlements["com.apple.security.network.client"] as? Bool == true,
        profilePresent: !profile.isEmpty,
        profileApplicationIdentifier: (pe["com.apple.application-identifier"] ?? pe["application-identifier"]) as? String,
        profileTeam: pe["com.apple.developer.team-identifier"] as? String,
        profileContainers: pe["com.apple.developer.icloud-container-identifiers"] as? [String] ?? [],
        profileServices: pe["com.apple.developer.icloud-services"],
        profileEnvironment: pe["com.apple.developer.icloud-container-environment"],
        profileUnexpired: (profile["ExpirationDate"] as? Date).map { $0 > Date() } ?? false)
    return (evidence, field("CDHash", in: details), profileHash, rejection)
}
struct PreflightReport: Encodable {
    let mode = "OFFLINE_ONLY"
    let operation = "READ_ONLY_PREFLIGHT"
    let status: String
    let planSHA256: String
    let run: UUID
    let dataset: UUID
    let container: String
    let environment: String
    let candidateBundle: String
    let candidateRegistration = "NOT_VERIFIED_BY_PREFLIGHT"
    let signatureVerified: Bool
    let codeDirectoryHash: String?
    let profileSHA256: String?
    let rejectionCodes: [String]
    let networkOperations = 0
    let networkAuthorized = false
    let readyForCloudRun = false
    let p0Passed = false
    let certificateProfileDeviceEligibility = "NOT_VERIFIED"
    let actualServiceAccess = "NOT_RUN"
}
#endif

func run() throws -> Int32 {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else { throw FormalProbeError.invalidPlan }
    if command == "plan", args.count == 2 {
        let plan = try ProbeFixture.prepare(at: URL(fileURLWithPath: args[1], isDirectory: true))
        print("OFFLINE_ONLY plan SHA256 \(try plan.digest)"); return 0
    }
    guard args.count >= 3, args[2].utf8.count == 64,
          args[2].utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw FormalProbeError.invalidPlan }
    let planURL = URL(fileURLWithPath: args[1], isDirectory: true), hash = args[2]
    if command == "replay", args.count == 4 {
        let report = try FormalProbeReplay.run(planURL: planURL, expectedSHA256: hash, output: URL(fileURLWithPath: args[3], isDirectory: true))
        print("OFFLINE_ONLY \(report.commands.count) SDK checks passed; no cloud operation or P0 claim."); return 0
    }
    #if os(macOS)
    if command == "preflight", args.count == 5 {
        try FormalProbeReplay.verifySchemaPin()
        let fixture = try ProbeFixture.load(from: planURL, expectedSHA256: hash)
        let output = try ProbeDirectory(URL(fileURLWithPath: args[4], isDirectory: true), create: true)
        let (evidence, codeHash, profileHash, errors) = inspect(URL(fileURLWithPath: args[3]))
        let rejected = errors + evidence.rejectionCodes(for: fixture.plan)
        let report = PreflightReport(status: rejected.isEmpty ? "STATIC_SIGNING_MATCH_REQUIRES_OWNER_GATE" : "NOT_READY",
            planSHA256: hash, run: fixture.plan.run, dataset: fixture.plan.dataset, container: fixture.plan.container,
            environment: fixture.plan.environment, candidateBundle: fixture.plan.candidateBundle,
            signatureVerified: evidence.signatureVerified, codeDirectoryHash: codeHash, profileSHA256: profileHash, rejectionCodes: rejected)
        try output.write("report.json", bytes: json(report))
        print("\(report.status); no signing, installation, account change or network operation.")
        return rejected.isEmpty ? 0 : 2
    }
    #endif
    throw FormalProbeError.invalidPlan
}
do { exit(try run()) }
catch {
    fputs("FormalDevelopmentProbe rejected input or operation. Use plan NEW_DIR; replay PLAN_DIR EXPECTED_SHA NEW_DIR; preflight PLAN_DIR EXPECTED_SHA APP_OR_BINARY NEW_DIR. No network operation occurred.\n", stderr)
    exit(2)
}
