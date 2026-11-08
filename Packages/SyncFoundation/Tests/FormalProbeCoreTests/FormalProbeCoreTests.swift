import XCTest
import ImageIO
import Darwin
import FormalProbeCore
import SyncFoundation

final class FormalProbeCoreTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        let physical = try XCTUnwrap(realpath(FileManager.default.temporaryDirectory.path, nil))
        defer { free(physical) }
        root = URL(fileURLWithPath: String(cString: physical), isDirectory: true).appendingPathComponent("FormalProbeTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func path(_ name: String) -> URL { root.appendingPathComponent(name) }
    func prepared(_ name: String = "plan") throws -> FormalProbePlan { try ProbeFixture.prepare(at: path(name)) }
    func alteredPlan(_ change: (inout [String: Any]) -> Void) throws -> String {
        let file = path("plan/plan.json")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        change(&object)
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        try bytes.write(to: file)
        let hash = syncDigest(bytes)
        try Data((hash + "\n").utf8).write(to: path("plan/plan.sha256"))
        return hash
    }
    func testFreshPlanExactSDKReplayAndDeleteChain() throws {
        let plan = try prepared()
        let loaded = try ProbeFixture.load(from: path("plan"), expectedSHA256: plan.digest)
        XCTAssertEqual(loaded.manifests[1].parents, [loaded.manifests[0].mutation])
        XCTAssertEqual(loaded.manifests[2].parents, [loaded.manifests[1].mutation]); XCTAssertTrue(loaded.manifests[2].deleted)
        let report = try FormalProbeReplay.run(planURL: path("plan"), expectedSHA256: plan.digest, output: path("replay"))
        XCTAssertEqual(report.status, "OFFLINE_PASS"); XCTAssertEqual(report.mode, "OFFLINE_ONLY")
        XCTAssertEqual(report.commands.count, 6); XCTAssertEqual(report.commands.map(\.index), Array(0..<6))
        XCTAssertEqual(report.networkOperations, 0); XCTAssertFalse(report.p0Passed); XCTAssertFalse(report.serverSchemaChecked)
        XCTAssertEqual(try Data(contentsOf: path("replay/lease-original.png")), ProbeFixture.png)
        XCTAssertEqual(try ProbeFixture.load(from: path("plan"), expectedSHA256: plan.digest).plan, plan)
    }
    func testPlansHaveDistinctFreshRunAndDatasetWithStableSchema() throws {
        let a = try prepared("a"), b = try prepared("b")
        XCTAssertNotEqual(a.run, b.run); XCTAssertNotEqual(a.dataset, b.dataset)
        XCTAssertNotEqual(try a.digest, try b.digest); XCTAssertEqual(a.schemaSHA256, b.schemaSHA256)
        XCTAssertEqual(a.container, "iCloud.com.yocruzer.PersonalGrowthOS")
        XCTAssertEqual(a.environment, "Development")
        XCTAssertEqual(a.candidateBundle, "com.yocruzer.PersonalGrowthOS.FormalSyncProbe")
    }
    func testCandidateSchemaPinAndPNGDecode() throws {
        XCTAssertNoThrow(try FormalProbeReplay.verifySchemaPin())
        let source = try XCTUnwrap(CGImageSourceCreateWithData(ProbeFixture.png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 1); XCTAssertEqual(image.height, 1)
    }
    func testHashAndFixtureByteTamperingRejectAndRetainFailureReport() throws {
        let plan = try prepared()
        XCTAssertThrowsError(try ProbeFixture.load(from: path("plan"), expectedSHA256: String(repeating: "0", count: 64)))
        try Data("tampered".utf8).write(to: path("plan/create.payload"))
        XCTAssertThrowsError(try FormalProbeReplay.run(planURL: path("plan"), expectedSHA256: plan.digest, output: path("failed")))
        let report = try JSONDecoder().decode(ProbeReport.self, from: Data(contentsOf: path("failed/report.json")))
        XCTAssertEqual(report.status, "OFFLINE_FAIL"); XCTAssertEqual(report.failureStage, "plan-load")
        XCTAssertEqual(report.commands.count, 0); XCTAssertFalse(report.p0Passed)
        XCTAssertEqual(try Data(contentsOf: path("plan/create.payload")), Data("tampered".utf8))
    }
    func testChangedIdentityEnvironmentSchemaAndExtraFieldRejectEvenWithRehashedPlan() throws {
        _ = try prepared()
        let original = try Data(contentsOf: path("plan/plan.json")), hashFile = try Data(contentsOf: path("plan/plan.sha256"))
        for (key, value) in [("container", "iCloud.other"), ("environment", "Production"), ("schemaSHA256", "wrong"),
                             ("dataset", UUID().uuidString), ("unexpected", "value")] {
            try original.write(to: path("plan/plan.json")); try hashFile.write(to: path("plan/plan.sha256"))
            let hash = try alteredPlan { $0[key] = value }
            XCTAssertThrowsError(try ProbeFixture.load(from: path("plan"), expectedSHA256: hash))
        }
    }
    func testMissingExtraDuplicatedAndReorderedRecordsReject() throws {
        _ = try prepared()
        let original = try Data(contentsOf: path("plan/plan.json"))
        for variant in 0..<3 {
            try original.write(to: path("plan/plan.json"))
            let hash = try alteredPlan {
                var rows = $0["records"] as! [[String: Any]]
                if variant == 0 { rows.removeLast() }
                if variant == 1 { rows.append(rows[0]) }
                if variant == 2 { rows.swapAt(0, 1) }
                $0["records"] = rows
            }
            XCTAssertThrowsError(try ProbeFixture.load(from: path("plan"), expectedSHA256: hash))
        }
        try original.write(to: path("plan/plan.json")); let hash = syncDigest(original)
        try Data((hash + "\n").utf8).write(to: path("plan/plan.sha256"))
        try Data([1]).write(to: path("plan/extra"))
        XCTAssertThrowsError(try ProbeFixture.load(from: path("plan"), expectedSHA256: hash))
        try FileManager.default.removeItem(at: path("plan/extra")); try FileManager.default.removeItem(at: path("plan/create.payload"))
        XCTAssertThrowsError(try ProbeFixture.load(from: path("plan"), expectedSHA256: hash))
    }
    func testSymlinksAndTraversalRejected() throws {
        let plan = try prepared()
        try FileManager.default.createSymbolicLink(at: path("link"), withDestinationURL: path("plan"))
        XCTAssertThrowsError(try ProbeFixture.load(from: path("link"), expectedSHA256: plan.digest))
        XCTAssertThrowsError(try ProbeFixture.prepare(at: path("link/child")))
        let original = try Data(contentsOf: path("plan/create.payload"))
        try original.write(to: path("payload")); try FileManager.default.removeItem(at: path("plan/create.payload"))
        try FileManager.default.createSymbolicLink(at: path("plan/create.payload"), withDestinationURL: path("payload"))
        XCTAssertThrowsError(try ProbeFixture.load(from: path("plan"), expectedSHA256: plan.digest))
        let directory = try ProbeDirectory(path("dir"), create: true)
        XCTAssertThrowsError(try directory.write("../escape", bytes: Data([1])))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path("escape").path))
    }
    func testOpenedDirectoryNeverMixesReplacementPath() throws {
        let directory = try ProbeDirectory(path("opened"), create: true)
        try directory.write("known", bytes: Data([1]))
        try FileManager.default.moveItem(at: path("opened"), to: path("renamed"))
        let replacement = try ProbeDirectory(path("opened"), create: true)
        try replacement.write("other", bytes: Data([2]))
        XCTAssertEqual(try directory.read("known"), Data([1]))
        XCTAssertNoThrow(try directory.verifyNames(["known"]))
        XCTAssertThrowsError(try directory.requirePathBinding())
        XCTAssertThrowsError(try directory.assetURL("known"))
    }
    func testExistingOutputsRemainUnchanged() throws {
        let plan = try prepared()
        let original = try Data(contentsOf: path("plan/plan.json"))
        XCTAssertThrowsError(try prepared())
        XCTAssertEqual(try Data(contentsOf: path("plan/plan.json")), original)
        let dir = try ProbeDirectory(path("output"), create: true); try dir.write("sentinel", bytes: Data([7]))
        XCTAssertThrowsError(try FormalProbeReplay.run(planURL: path("plan"), expectedSHA256: plan.digest, output: path("output")))
        XCTAssertEqual(try dir.read("sentinel"), Data([7])); XCTAssertNoThrow(try dir.verifyNames(["sentinel"]))
    }
    func testSigningPureMetadataPositiveAndProductionMismatchAreNotActualSignatureProof() throws {
        let plan = try prepared(), applicationID = plan.team + "." + plan.candidateBundle
        func evidence(valid: Bool = true, env: String = "Development", profile: Bool = true) -> ProbeSigningEvidence {
            ProbeSigningEvidence(signatureVerified: valid, codeIdentifier: plan.candidateBundle, codeTeam: plan.team,
                applicationIdentifier: applicationID, entitlementTeam: plan.team, containers: [plan.container], services: ["CloudKit"],
                environment: env, sandbox: true, networkClient: true, profilePresent: profile, profileApplicationIdentifier: applicationID,
                profileTeam: plan.team, profileContainers: [plan.container], profileServices: ["CloudKit"], profileEnvironment: env, profileUnexpired: true)
        }
        XCTAssertTrue(evidence().rejectionCodes(for: plan).isEmpty, "Injected metadata fixture only; no real signature validation")
        XCTAssertTrue(evidence(valid: false).rejectionCodes(for: plan).contains("SIGNATURE_NOT_VERIFIED"))
        XCTAssertTrue(evidence(env: "Production").rejectionCodes(for: plan).contains("CLOUD_ENTITLEMENTS_MISMATCH"))
        XCTAssertTrue(evidence(profile: false).rejectionCodes(for: plan).contains("PROFILE_MISSING"))
    }
}
