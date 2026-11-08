import Foundation
import CoreFoundation
import CryptoKit
import FormalProbeCore
#if os(macOS)
import Security
import Darwin
#endif

enum RuntimeSigningError: String, Error {
    case unsupportedPlatform, invalidExpectation, receiptMismatch, sourcePinsMismatch
    case selfSignatureUnavailable, selfSignatureInvalid, codeTrustUnavailable, identityMismatch, entitlementMismatch
    case artifactPathInvalid, artifactChanged, binaryMismatch, codeDirectoryMismatch
    case profileMismatch, profileSignatureInvalid, profileTrustUnavailable, profileExpired
    case certificateMismatch, deviceEvidenceUnavailable, deviceNotProvisioned
}

/// Bounded diagnostics only: no CFError, certificate, account, device or path values.
struct RuntimeSigningDiagnosticFailure: Error {
    enum Stage: String {
        case dynamicValidity, staticCodeCopy, staticValidity
        case deviceReadConfiguration, deviceLaunch, deviceRead, deviceOutputLimit, deviceTimeout, deviceExit, deviceParse
    }
    let stage: Stage
    let status: Int32
    var reason: RuntimeSigningError {
        switch stage {
        case .dynamicValidity, .staticCodeCopy, .staticValidity: return .selfSignatureInvalid
        default: return .deviceEvidenceUnavailable
        }
    }
}

/// These are reviewed input bindings, not an Owner permission or a code-signing result.
struct RuntimeSigningExpectation: Equatable, Sendable {
    let signedBinarySHA256: String
    let codeDirectoryHash: String
    let profileSHA256: String
    let packagingReceiptSHA256: String
    let sourcePinsSHA256: String

    init(signedBinarySHA256: String, codeDirectoryHash: String, profileSHA256: String,
         packagingReceiptSHA256: String, sourcePinsSHA256: String) throws {
        guard [signedBinarySHA256, profileSHA256, packagingReceiptSHA256, sourcePinsSHA256]
            .allSatisfy({ RuntimeSigningInspector.isHex($0, bytes: 32) }),
            RuntimeSigningInspector.isHex(codeDirectoryHash, bytes: 20) else { throw RuntimeSigningError.invalidExpectation }
        self.signedBinarySHA256 = signedBinarySHA256; self.codeDirectoryHash = codeDirectoryHash
        self.profileSHA256 = profileSHA256; self.packagingReceiptSHA256 = packagingReceiptSHA256
        self.sourcePinsSHA256 = sourcePinsSHA256
    }
}

/// Only this file's real self-inspector can create this value. It is deliberately not Codable,
/// not publicly constructible, and not a CloudKit, account, window or Owner authority.
/// A later consumer must re-inspect; this observation is not a perpetual credential.
final class RuntimeSigningQualification {
    let binding: RuntimeSigningExpectation
    let observedAt: Date
    let profileExpiresAt: Date
    fileprivate init(binding: RuntimeSigningExpectation, observedAt: Date, profileExpiresAt: Date) {
        self.binding = binding; self.observedAt = observedAt; self.profileExpiresAt = profileExpiresAt
    }
}

enum RuntimeSigningInspector {
    static let team = "83SKX2PM7B"
    static let bundle = "com.yocruzer.PersonalGrowthOS.FormalSyncProbe"
    static let container = "iCloud.com.yocruzer.PersonalGrowthOS"
    static let executable = "FormalDevelopmentHost"

    static func inspect(expected: RuntimeSigningExpectation, packagingReceipt: Data,
                        sourcePins: Data) throws -> RuntimeSigningQualification {
        #if os(macOS)
        let receipt = try validateReceipt(packagingReceipt, sourcePins: sourcePins, expected: expected)
        var selfReference: SecCode?
        guard SecCodeCopySelf([], &selfReference) == errSecSuccess, let code = selfReference else {
            throw RuntimeSigningError.selfSignatureUnavailable
        }
        // Explicit no-network validation. No keychain mutation.
        var requirementReference: SecRequirement?
        let requirementText = "anchor apple generic and identifier \"\(bundle)\" and certificate leaf[subject.OU] = \"\(team)\""
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirementReference) == errSecSuccess,
              let requirement = requirementReference else { throw RuntimeSigningError.selfSignatureUnavailable }
        try validateSelf(code, requirement)
        let before = try codeObservation(code)
        guard before.identifier == bundle, before.team == team else { throw RuntimeSigningError.identityMismatch }
        guard before.cdHash == expected.codeDirectoryHash else { throw RuntimeSigningError.codeDirectoryMismatch }
        try validateEntitlements(before.entitlements)
        let app = try ProbeDirectory(before.appURL, create: false)
        let contents = try ProbeDirectory(before.appURL.appendingPathComponent("Contents"), create: false)
        let binaries = try ProbeDirectory(contents.url.appendingPathComponent("MacOS"), create: false)
        guard before.appURL.pathExtension == "app",
              before.executableURL.path == binaries.url.appendingPathComponent(executable).path else {
            throw RuntimeSigningError.artifactPathInvalid
        }
        let binary = try binaries.read(executable, maximum: 64 * 1_024 * 1_024)
        let profileBytes = try contents.read("embedded.provisionprofile", maximum: 1_048_576)
        let infoBytes = try contents.read("Info.plist", maximum: 65_536)
        guard digest(binary) == expected.signedBinarySHA256 else { throw RuntimeSigningError.binaryMismatch }
        guard digest(profileBytes) == expected.profileSHA256 else { throw RuntimeSigningError.profileMismatch }
        guard digest(infoBytes) == receipt.infoSHA256,
              let info = try PropertyListSerialization.propertyList(from: infoBytes, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == bundle,
              info["CFBundleExecutable"] as? String == executable,
              NSDictionary(dictionary: info).isEqual(to: before.info) else { throw RuntimeSigningError.artifactChanged }
        let profile = try trustedProfile(profileBytes)
        let device = try currentProvisioningUDID()
        let expires = try validateProfile(profile, signingLeaf: before.leaf, provisioningUDID: device, now: Date())
        // A second dynamic validation binds the disk metadata back to this running process.
        try validateSelf(code, requirement)
        let after = try codeObservation(code)
        guard before.same(as: after), try binaries.read(executable, maximum: 64 * 1_024 * 1_024) == binary,
              try contents.read("embedded.provisionprofile", maximum: 1_048_576) == profileBytes,
              try contents.read("Info.plist", maximum: 65_536) == infoBytes else { throw RuntimeSigningError.artifactChanged }
        try app.requirePathBinding(); try contents.requirePathBinding(); try binaries.requirePathBinding()
        let observed = Date()
        guard observed < expires else { throw RuntimeSigningError.profileExpired }
        return RuntimeSigningQualification(binding: expected, observedAt: observed, profileExpiresAt: expires)
        #else
        throw RuntimeSigningError.unsupportedPlatform
        #endif
    }

    static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    static func isHex(_ value: String, bytes: Int) -> Bool {
        value.utf8.count == bytes * 2 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func trueBoolean(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue
    }
    static func validateEntitlements(_ entitlements: [String: Any]) throws {
        let expectedKeys: Set<String> = ["com.apple.application-identifier", "com.apple.developer.team-identifier",
            "com.apple.developer.icloud-container-identifiers", "com.apple.developer.icloud-services",
            "com.apple.developer.icloud-container-environment", "com.apple.security.app-sandbox", "com.apple.security.network.client"]
        guard Set(entitlements.keys) == expectedKeys,
              entitlements["com.apple.application-identifier"] as? String == team + "." + bundle,
              entitlements["com.apple.developer.team-identifier"] as? String == team,
              entitlements["com.apple.developer.icloud-container-identifiers"] as? [String] == [container],
              entitlements["com.apple.developer.icloud-services"] as? [String] == ["CloudKit"],
              entitlements["com.apple.developer.icloud-container-environment"] as? String == "Development",
              trueBoolean(entitlements["com.apple.security.app-sandbox"]), trueBoolean(entitlements["com.apple.security.network.client"])
        else { throw RuntimeSigningError.entitlementMismatch }
    }

    /// Pure metadata validation is testable but cannot mint a qualification.
    static func validateProfile(_ profile: [String: Any], signingLeaf: Data,
                                provisioningUDID: String, now: Date) throws -> Date {
        guard profile["Platform"] as? [String] == ["OSX"], profile["TeamIdentifier"] as? [String] == [team],
              let ent = profile["Entitlements"] as? [String: Any],
              ent["com.apple.application-identifier"] as? String == team + "." + bundle,
              ent["com.apple.developer.team-identifier"] as? String == team,
              ent["com.apple.developer.icloud-container-identifiers"] as? [String] == [container],
              ProbeProfileCloudAllowance(services: ent["com.apple.developer.icloud-services"],
                                        environment: ent["com.apple.developer.icloud-container-environment"]).permitsDevelopmentCloudKit,
              let created = profile["CreationDate"] as? Date, created <= now,
              let expires = profile["ExpirationDate"] as? Date, created < expires else { throw RuntimeSigningError.profileMismatch }
        guard now < expires else { throw RuntimeSigningError.profileExpired }
        guard let certificates = profile["DeveloperCertificates"] as? [Data], !signingLeaf.isEmpty,
              !certificates.isEmpty, certificates.count <= 16, certificates.contains(signingLeaf) else { throw RuntimeSigningError.certificateMismatch }
        guard !provisioningUDID.isEmpty, let devices = profile["ProvisionedDevices"] as? [String],
              !devices.isEmpty, devices.count <= 1_000, Set(devices).count == devices.count,
              devices.contains(provisioningUDID), profile["ProvisionsAllDevices"] == nil else { throw RuntimeSigningError.deviceNotProvisioned }
        return expires
    }

    struct ReceiptFacts { let infoSHA256: String }
    static func validateReceipt(_ bytes: Data, sourcePins: Data, expected: RuntimeSigningExpectation) throws -> ReceiptFacts {
        guard bytes.count <= 262_144, digest(bytes) == expected.packagingReceiptSHA256,
              let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let version = object["formatVersion"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version == 1,
              object["bundle"] as? String == bundle, object["container"] as? String == container,
              object["environment"] as? String == "Development", object["status"] as? String == "UNPROVISIONED_NO_DEVELOPER_SIGNATURE",
              let binaryHash = object["binarySHA256"] as? String, isHex(binaryHash, bytes: 32),
              let infoHash = object["infoSHA256"] as? String, isHex(infoHash, bytes: 32),
              let sources = object["sourceSHA256"] as? [String: String], !sources.isEmpty else { throw RuntimeSigningError.receiptMismatch }
        guard sourcePins.count <= 262_144, digest(sourcePins) == expected.sourcePinsSHA256,
              let pins = try? JSONSerialization.jsonObject(with: sourcePins) as? [String: String], pins == sources,
              pins.count <= 256, pins["Package.swift"] != nil,
              pins["Sources/FormalDevelopmentSDK/RuntimeSigningInspector.swift"] != nil,
              pins.allSatisfy({ name, hash in
                  isHex(hash, bytes: 32) && !name.hasPrefix("/") && !name.split(separator: "/").contains("..") &&
                    (name == "Package.swift" || name.hasPrefix("Sources/") || name.hasPrefix("Tests/"))
              }) else { throw RuntimeSigningError.sourcePinsMismatch }
        return ReceiptFacts(infoSHA256: infoHash)
    }

    /// Only an explicit OS provisioningUDID field is accepted. Hardware UUID is never a fallback.
    static func provisioningUDID(from bytes: Data) throws -> String {
        guard bytes.count <= 262_144 else { throw RuntimeSigningDiagnosticFailure(stage: .deviceOutputLimit, status: 1) }
        guard let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw RuntimeSigningDiagnosticFailure(stage: .deviceParse, status: 1)
        }
        guard let entries = object["SPHardwareDataType"] as? [[String: Any]], entries.count == 1 else {
            throw RuntimeSigningDiagnosticFailure(stage: .deviceParse, status: 2)
        }
        let matches = entries[0].filter { $0.key.lowercased().filter({ $0.isLetter || $0.isNumber }) == "provisioningudid" }
        guard matches.count == 1 else { throw RuntimeSigningDiagnosticFailure(stage: .deviceParse, status: 3) }
        guard let value = matches.first?.value as? String, value.utf8.count >= 16, value.utf8.count <= 64,
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) || $0 == 45 })
        else { throw RuntimeSigningDiagnosticFailure(stage: .deviceParse, status: 4) }
        return value
    }
}

#if os(macOS)
extension RuntimeSigningInspector {
    private struct CodeObservation {
        let identifier: String; let team: String; let cdHash: String; let leaf: Data
        let appURL: URL; let executableURL: URL; let entitlements: [String: Any]; let info: [String: Any]
        func same(as other: Self) -> Bool {
            identifier == other.identifier && team == other.team && cdHash == other.cdHash && leaf == other.leaf &&
            appURL == other.appURL && executableURL == other.executableURL &&
            NSDictionary(dictionary: entitlements).isEqual(to: other.entitlements) && NSDictionary(dictionary: info).isEqual(to: other.info)
        }
    }
    private static func validateSelf(_ code: SecCode, _ requirement: SecRequirement) throws {
        // Apple's SecCode.cpp and SecStaticCode.cpp validation allowlists do NOT
        // accept kSecCSCheckTrustedAnchors. Verify trust separately below instead.
        let localFlags: SecCSFlags = [.noNetworkAccess, .considerExpiration]
        let dynamicStatus = SecCodeCheckValidity(code, localFlags, requirement)
        guard dynamicStatus == errSecSuccess else { throw RuntimeSigningDiagnosticFailure(stage: .dynamicValidity, status: dynamicStatus) }
        var staticReference: SecStaticCode?
        let copyStatus = SecCodeCopyStaticCode(code, [], &staticReference)
        guard copyStatus == errSecSuccess, let staticCode = staticReference else { throw RuntimeSigningDiagnosticFailure(stage: .staticCodeCopy, status: copyStatus) }
        let staticStatus = SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode).union(localFlags), requirement)
        guard staticStatus == errSecSuccess else { throw RuntimeSigningDiagnosticFailure(stage: .staticValidity, status: staticStatus) }
    }
    private static func codeObservation(_ code: SecCode) throws -> CodeObservation {
        // Security documents this argument as accepting both SecCode and SecStaticCode.
        let generic = unsafeBitCast(code, to: SecStaticCode.self)
        var dictionary: CFDictionary?; var path: CFURL?
        guard SecCodeCopySigningInformation(generic, SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSDynamicInformation), &dictionary) == errSecSuccess,
              SecCodeCopyPath(generic, [], &path) == errSecSuccess,
              let values = dictionary as? [String: Any], let path,
              let identifier = values[kSecCodeInfoIdentifier as String] as? String,
              let team = values[kSecCodeInfoTeamIdentifier as String] as? String,
              let cdHash = values[kSecCodeInfoUnique as String] as? Data, cdHash.count == 20,
              let certificates = values[kSecCodeInfoCertificates as String] as? [SecCertificate], let first = certificates.first,
              let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              let info = values[kSecCodeInfoPList as String] as? [String: Any],
              let executableURL = values[kSecCodeInfoMainExecutable as String] as? URL else { throw RuntimeSigningError.selfSignatureUnavailable }
        try validateCodeSignerChain(certificates)
        return CodeObservation(identifier: identifier, team: team, cdHash: cdHash.map { String(format: "%02x", $0) }.joined(),
            leaf: SecCertificateCopyData(first) as Data, appURL: path as URL, executableURL: executableURL, entitlements: entitlements, info: info)
    }
    static func trustedProfile(_ bytes: Data) throws -> [String: Any] {
        guard !bytes.isEmpty else { throw RuntimeSigningError.profileSignatureInvalid }
        var reference: CMSDecoder?
        guard CMSDecoderCreate(&reference) == errSecSuccess, let decoder = reference else { throw RuntimeSigningError.profileSignatureInvalid }
        guard bytes.withUnsafeBytes({ CMSDecoderUpdateMessage(decoder, $0.baseAddress!, $0.count) }) == errSecSuccess,
              CMSDecoderFinalizeMessage(decoder) == errSecSuccess else { throw RuntimeSigningError.profileSignatureInvalid }
        var count = 0
        guard CMSDecoderGetNumSigners(decoder, &count) == errSecSuccess, count == 1 else { throw RuntimeSigningError.profileSignatureInvalid }
        var status: CMSSignerStatus = .unsigned; var trust: SecTrust?; var ignored: OSStatus = 0
        guard CMSDecoderCopySignerStatus(decoder, 0, SecPolicyCreateBasicX509(), false, &status, &trust, &ignored) == errSecSuccess,
              status == .valid, let trust else { throw RuntimeSigningError.profileSignatureInvalid }
        guard SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
              SecTrustSetVerifyDate(trust, Date() as CFDate) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil) else { throw RuntimeSigningError.profileTrustUnavailable }
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else { throw RuntimeSigningError.profileTrustUnavailable }
        try validateProfileSignerChain(chain)
        var content: CFData?
        guard CMSDecoderCopyContent(decoder, &content) == errSecSuccess, let content,
              let profile = try PropertyListSerialization.propertyList(from: content as Data, format: nil) as? [String: Any] else { throw RuntimeSigningError.profileMismatch }
        return profile
    }
    /// Additional constraints on an already cryptographically validated CMS trust chain.
    /// These public roots were fetched from https://www.apple.com/certificateauthority/.
    /// Marker OIDs follow Apple Security SecPolicyCreateOSXProvisioningProfileSigning:
    /// OSX/sec/Security/SecPolicy.c (Apple public source). The v1.32 WWDR CPS
    /// omits the .100 arc in section 4.11.10; that shortened OID is not accepted.
    /// Unknown future roots/purposes fail closed until explicitly reviewed.
    static func validateProfileSignerChain(_ chain: [SecCertificate]) throws {
        guard validAppleRoot(chain), chain.count >= 3, let first = chain.first,
              hasCertificateMarker(first, oid: "1.2.840.113635.100.4.11"), certificateAllowsDigitalSignature(first),
              chain.dropFirst().dropLast().contains(where: { hasCertificateMarker($0, oid: "1.2.840.113635.100.6.2.1") })
        else { throw RuntimeSigningError.profileTrustUnavailable }
    }
    /// Query the standalone certificate extension, never an EKU value or subject text.
    static func hasCertificateMarker(_ certificate: SecCertificate, oid: String) -> Bool {
        guard let properties = SecCertificateCopyValues(certificate, [oid] as CFArray, nil) as? [String: Any],
              let property = properties[oid] as? [String: Any], property[kSecPropertyKeyValue as String] != nil else { return false }
        return true
    }
    static func certificateAllowsDigitalSignature(_ certificate: SecCertificate) -> Bool {
        guard let properties = SecCertificateCopyValues(certificate, [kSecOIDKeyUsage] as CFArray, nil) as? [String: Any],
              let property = properties[kSecOIDKeyUsage as String] as? [String: Any],
              let usage = property[kSecPropertyKeyValue as String] as? NSNumber,
              CFGetTypeID(usage) != CFBooleanGetTypeID() else { return false }
        return usage.uint32Value & 1 == 1 // kSecKeyUsageDigitalSignature; high bit marks a critical extension.
    }
    private static func validAppleRoot(_ chain: [SecCertificate]) -> Bool {
        let roots: Set<String> = [
            "b0b1730ecbc7ff4505142c49f1295e6eda6bcaed7e2c68c5be91b5a11001f024", // Apple Inc. Root
            "c2b9b042dd57830e7d117dac55ac8ae19407d38e41d88f3215bc3a890444a050", // Apple Root CA G2
            "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179"  // Apple Root CA G3
        ]
        guard chain.count >= 2, chain.count <= 8, let last = chain.last else { return false }
        return roots.contains(digest(SecCertificateCopyData(last) as Data))
    }
    /// Make a fresh trust object: never mutate the live kSecCodeInfoTrust object.
    /// Current-date CodeSigning policy, offline chain evaluation and pinned Apple
    /// roots implement the trust requirement independently of unsupported CS flags.
    static func validateCodeSignerChain(_ certificates: [SecCertificate]) throws {
        guard !certificates.isEmpty, certificates.count <= 8,
              let policy = SecPolicyCreateWithProperties(kSecPolicyAppleCodeSigning, nil) else { throw RuntimeSigningError.codeTrustUnavailable }
        var reference: SecTrust?
        guard SecTrustCreateWithCertificates(certificates as CFArray, policy, &reference) == errSecSuccess,
              let trust = reference, SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
              SecTrustSetVerifyDate(trust, Date() as CFDate) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil),
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], validAppleRoot(chain)
        else { throw RuntimeSigningError.codeTrustUnavailable }
    }
    private static func currentProvisioningUDID() throws -> String {
        let task = Process(); let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPHardwareDataType", "-json", "-timeout", "5"]
        task.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C", "LC_ALL": "C"]
        task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        let fd = pipe.fileHandleForReading.fileDescriptor
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { throw RuntimeSigningDiagnosticFailure(stage: .deviceReadConfiguration, status: errno) }
        do { try task.run() } catch { throw RuntimeSigningDiagnosticFailure(stage: .deviceLaunch, status: Int32(clamping: (error as NSError).code)) }
        defer {
            if task.isRunning { task.terminate(); _ = kill(task.processIdentifier, SIGKILL) }
            try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close()
        }
        try? pipe.fileHandleForWriting.close()
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                guard data.count + count <= 262_144 else { throw RuntimeSigningDiagnosticFailure(stage: .deviceOutputLimit, status: 1) }
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 { break }
            else if errno != EAGAIN && errno != EINTR { throw RuntimeSigningDiagnosticFailure(stage: .deviceRead, status: errno) }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw RuntimeSigningDiagnosticFailure(stage: .deviceTimeout, status: 1) }
            if count < 0 { Thread.sleep(forTimeInterval: 0.01) }
        }
        while task.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.01) }
        guard !task.isRunning else { throw RuntimeSigningDiagnosticFailure(stage: .deviceTimeout, status: 2) }
        guard task.terminationStatus == 0 else { throw RuntimeSigningDiagnosticFailure(stage: .deviceExit, status: task.terminationStatus) }
        return try provisioningUDID(from: data)
    }
}
#endif
