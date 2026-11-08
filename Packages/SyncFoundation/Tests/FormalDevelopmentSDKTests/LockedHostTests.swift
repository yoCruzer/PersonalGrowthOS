import XCTest
import Foundation
import FormalProbeCore
@testable import FormalDevelopmentSDK

final class LockedHostTests: XCTestCase {
    private func root() throws -> URL {
        let url = URL(fileURLWithPath: "/private/tmp/pgos-locked-host-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
    private func report(_ data: Data) throws -> [String: Any] {
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(value["mode"] as? String, "OFFLINE_ONLY")
        XCTAssertEqual(value["status"] as? String, "NOT_READY")
        XCTAssertEqual(value["failure"] as? String, "EXTERNAL_GATE_NOT_COMPLETE")
        XCTAssertEqual(value["networkOperations"] as? Int, 0)
        XCTAssertEqual(value["networkAuthorized"] as? Bool, false)
        XCTAssertEqual(value["p0Passed"] as? Bool, false)
        XCTAssertEqual(value["environment"] as? String, "Development")
        XCTAssertEqual(value["container"] as? String, FormalProbeIdentity.container)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("/"))
        return value
    }
    func testInternalFixtureFreshIdentityAndLockedReport() throws {
        let first = try report(FormalDevelopmentLockedHost.inspectFixture())
        let second = try report(FormalDevelopmentLockedHost.inspectFixture())
        XCTAssertNotEqual(first["run"] as? String, second["run"] as? String)
        XCTAssertNotEqual(first["dataset"] as? String, second["dataset"] as? String)
        XCTAssertNotEqual(first["planSHA256"] as? String, second["planSHA256"] as? String)
    }
    func testReturnedReportMatchesExclusivePublishedBytes() throws {
        let root = try root(), planURL = root.appendingPathComponent("plan"), output = root.appendingPathComponent("output")
        let plan = try ProbeFixture.prepare(at: planURL)
        let bytes = try FormalDevelopmentLockedHost.inspect(planURL: planURL, expectedSHA256: plan.digest, output: output)
        _ = try report(bytes)
        XCTAssertEqual(bytes, try ProbeDirectory(output, create: false).read("report.json"))
        XCTAssertThrowsError(try FormalDevelopmentLockedHost.inspect(planURL: planURL, expectedSHA256: plan.digest, output: output))
        XCTAssertEqual(bytes, try ProbeDirectory(output, create: false).read("report.json"))
    }
    func testInvalidHashAndChangedFixtureCannotPublish() throws {
        let root = try root(), planURL = root.appendingPathComponent("plan"), output = root.appendingPathComponent("output")
        let plan = try ProbeFixture.prepare(at: planURL)
        XCTAssertThrowsError(try FormalDevelopmentLockedHost.inspect(planURL: planURL, expectedSHA256: String(repeating: "0", count: 64), output: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        try Data("tampered synthetic".utf8).write(to: planURL.appendingPathComponent("create.payload"))
        XCTAssertThrowsError(try FormalDevelopmentLockedHost.inspect(planURL: planURL, expectedSHA256: plan.digest, output: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
    func testSearchAncestorStillRejectsSymlinkAndReboundDirectory() throws {
        let root = try root(), source = root.appendingPathComponent("source"), link = root.appendingPathComponent("link")
        let directory = try ProbeDirectory(source, create: true)
        try directory.write("sentinel", bytes: Data("preserve".utf8))
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        XCTAssertThrowsError(try ProbeDirectory(link, create: false))
        XCTAssertThrowsError(try ProbeDirectory(link.appendingPathComponent("nested"), create: true))
        try FileManager.default.moveItem(at: source, to: root.appendingPathComponent("original"))
        _ = try ProbeDirectory(source, create: true)
        XCTAssertThrowsError(try directory.requirePathBinding())
        XCTAssertEqual(try directory.read("sentinel"), Data("preserve".utf8))
    }
}
