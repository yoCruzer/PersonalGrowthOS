import XCTest
import Foundation
import Darwin
import FormalProbeCore
import SyncFoundation
@testable import FormalDevelopmentSDK

@MainActor final class IndependentProductionEntryTests: XCTestCase {
    private func directory() throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp/EntryIndependent-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return root
    }
    func testReadOnlyDoesNotCreateAndEnrollmentCreatesOnlySelectedLeaf() throws {
        let root = try directory(), leaf = root.appendingPathComponent("SyntheticApplicationSupport")
        XCTAssertThrowsError(try GuardedExecutionPaths.checkedRoot(leaf, createMissingLeaf: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: leaf.path))
        XCTAssertEqual(try GuardedExecutionPaths.checkedRoot(leaf, createMissingLeaf: true), leaf)
        var s = stat(); XCTAssertEqual(lstat(leaf.path, &s), 0)
        XCTAssertEqual(s.st_mode & 0o777, 0o700)
        let inode = s.st_ino
        let marker = leaf.appendingPathComponent("immutable-marker")
        let original = Data("independent immutable input".utf8); try original.write(to: marker)
        XCTAssertEqual(try GuardedExecutionPaths.checkedRoot(leaf, createMissingLeaf: true), leaf)
        XCTAssertEqual(lstat(leaf.path, &s), 0); XCTAssertEqual(s.st_ino, inode)
        XCTAssertEqual(try Data(contentsOf: marker), original)
    }
    func testMissingAncestorCannotTriggerRecursiveCreation() throws {
        let root = try directory(), missing = root.appendingPathComponent("missing"), leaf = missing.appendingPathComponent("leaf")
        XCTAssertThrowsError(try GuardedExecutionPaths.checkedRoot(leaf, createMissingLeaf: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }
    func testSymlinkParentAndLeafAndRegularFileAreRejectedWithoutMutation() throws {
        let root = try directory(), target = try directory()
        let leafLink = root.appendingPathComponent("leaf-link")
        try FileManager.default.createSymbolicLink(at: leafLink, withDestinationURL: target)
        let parentLink = root.appendingPathComponent("parent-link")
        try FileManager.default.createSymbolicLink(at: parentLink, withDestinationURL: target)
        let regular = root.appendingPathComponent("regular"); let original = Data("retain".utf8); try original.write(to: regular)
        for candidate in [leafLink, parentLink.appendingPathComponent("new-leaf"), regular] {
            for create in [false, true] { XCTAssertThrowsError(try GuardedExecutionPaths.checkedRoot(candidate, createMissingLeaf: create)) }
        }
        XCTAssertEqual(try Data(contentsOf: regular), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), [])
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: leafLink.path), target.path)
    }
    func testOSSessionDigestHasDomainAndEverySessionDimension() throws {
        let boot = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let value = try OSExecutionSession.validated(userID: 501, effectiveUserID: 501, securitySessionID: 82, attributes: 0x10, bootSession: boot)
        let expected = syncDigest(Data("PGOS.OSExecutionSession.v1\u{0}501\u{0}82\u{0}16\u{0}aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee".utf8))
        XCTAssertEqual(value.digest, expected)
        for attributes: UInt32 in [0, 1, 0x11, 0x1010] {
            XCTAssertThrowsError(try OSExecutionSession.validated(userID: 501, effectiveUserID: 501, securitySessionID: 82, attributes: attributes, bootSession: boot))
        }
        XCTAssertThrowsError(try OSExecutionSession.validated(userID: 501, effectiveUserID: 502, securitySessionID: 82, attributes: 0x10, bootSession: boot))
    }
    func testPublicEntrypointsRejectMalformedInputBeforeAnyAuthorityAndDoNotCallFatal() async throws {
        let input = Data("{}".utf8)
        for _ in 0..<2 {
            XCTAssertThrowsError(try FormalDevelopmentGuardedExecution.enroll(approval: input, expectedSHA256: syncDigest(input)))
            do {
                _ = try await FormalDevelopmentGuardedExecution.run(approval: input, expectedSHA256: syncDigest(input), onEvidenceFatal: { XCTFail("no runtime authority exists") })
                XCTFail("malformed input cannot execute")
            } catch { XCTAssertFalse(error is GuardedEntryError, "must fail decoding, before any runtime/session/state access") }
        }
    }
    func testOfflineEntryFailureDoesNotClaimOSOrPathQualification() throws {
        let result = try FormalDevelopmentRuntimeInspection.inspect(Data("{\"private\":\"DO_NOT_ECHO\"}".utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: result) as? [String: Any])
        XCTAssertEqual(object["status"] as? String, "NOT_READY")
        for key in ["signatureProfileDeviceVerified", "osSessionVerified", "applicationSupportParentVerified", "ownerApprovalVerified", "networkAuthorized", "p0Passed"] {
            XCTAssertEqual(object[key] as? Bool, false)
        }
        XCTAssertEqual(object["networkOperations"] as? Int, 0)
        XCTAssertFalse(String(decoding: result, as: UTF8.self).contains("DO_NOT_ECHO"))
    }
}
