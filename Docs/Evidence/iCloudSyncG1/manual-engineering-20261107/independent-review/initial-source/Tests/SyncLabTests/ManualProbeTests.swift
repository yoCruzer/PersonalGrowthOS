#if DEBUG
import XCTest
import Darwin
@testable import SyncLab

final class ManualProbeTests: XCTestCase {
    func plan() -> ManualProbePlan {
        ManualProbePlan(id: "probe-manual-plan", dataset: "synthetic-g1-manual", runID: "probe-manual-run",
                        commands: [ProbeCommand(id: "probe-read", action: .snapshot)])
    }
    func report(_ plan: ManualProbePlan, bytes: Data) throws -> ManualProbeReport {
        let command = plan.commands[0]
        return ManualProbeReport(planID: plan.id, dataset: plan.dataset, runID: plan.runID, planDigest: digest(bytes),
                                 results: [ProbeResult(id: command.id, dataset: plan.dataset, runID: plan.runID,
                                                       commandDigest: try digest(canonical(command)), status: "PASS", events: [], halted: false, platform: "TEST_ONLY")],
                                 completedAllCommands: true)
    }
    func testPlanBoundsAndWholeBatchValidationBeforeExecution() throws {
        var p = plan(); XCTAssertNoThrow(try ManualProbePlan.decode(canonical(p)))
        p.commands += p.commands; XCTAssertThrowsError(try p.validate())
        p = plan(); p.commands = []; XCTAssertThrowsError(try p.validate())
        p = plan(); p.commands = (0..<17).map { ProbeCommand(id: "probe-c\($0)", action: .snapshot) }; XCTAssertThrowsError(try p.validate())
        p = plan(); p.dataset = "daily"; XCTAssertThrowsError(try p.validate())
        p = plan(); p.id = "../file"; XCTAssertThrowsError(try p.validate())
        p = plan(); p.version = 2; XCTAssertThrowsError(try p.validate())
        p = plan(); p.commands.append(ProbeCommand(id: "probe-private", action: .save,
                                                  mutation: Mutation(id: "probe-m", object: "probe-o", text: "private")))
        XCTAssertThrowsError(try p.validate())
        XCTAssertThrowsError(try ManualProbePlan.decode(Data(repeating: 32, count: 262_145)))
    }
    func testInterruptedAndChangedPlanNeverReplayOrOverwrite() throws {
        let p = plan(), bytes = try canonical(p)
        let journal = try ManualProbeJournal(root: .temporaryDirectory.appendingPathComponent(UUID().uuidString), plan: p)
        XCTAssertNil(try journal.claim(bytes))
        XCTAssertThrowsError(try journal.claim(bytes))
        let value = try report(p, bytes: bytes); try journal.complete(value)
        let original = try Data(contentsOf: journal.resultURL)
        XCTAssertTrue(try XCTUnwrap(journal.claim(bytes)).completedAllCommands)
        XCTAssertThrowsError(try journal.complete(value))
        XCTAssertThrowsError(try journal.claim(bytes + Data(" ".utf8)))
        XCTAssertEqual(try Data(contentsOf: journal.resultURL), original)
    }
    func testReportIdentityAndCompletionCannotBeForged() throws {
        let p = plan(), bytes = try canonical(p), good = try report(p, bytes: bytes)
        XCTAssertNoThrow(try good.validate(plan: p, bytes: bytes))
        for corruption in ["run", "dataset", "command", "digest", "omitted", "failure", "error"] {
            var bad = good
            switch corruption {
            case "run": bad.runID = "probe-wrong"
            case "dataset": bad.results[0].dataset = "synthetic-g1-wrong"
            case "command": bad.results[0].id = "probe-wrong"
            case "digest": bad.results[0].commandDigest = String(repeating: "0", count: 64)
            case "omitted": bad.results = []
            case "failure": bad.results[0].status = "FAIL"
            default: bad.errorCode = "LOCAL_FAILURE"
            }
            XCTAssertThrowsError(try bad.validate(plan: p, bytes: bytes), corruption)
        }
    }
    func testFixedImportRejectsSymlinkAndOversize() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("SyncLab-Probe-Plan.json"), other = root.appendingPathComponent("other.json")
        try canonical(plan()).write(to: other)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: other)
        XCTAssertThrowsError(try ManualProbePlan.readImportedPlan(documents: root))
        try FileManager.default.removeItem(at: target)
        XCTAssertEqual(mkfifo(target.path, 0o600), 0)
        XCTAssertThrowsError(try ManualProbePlan.readImportedPlan(documents: root))
        try FileManager.default.removeItem(at: target)
        try Data(repeating: 32, count: 262_145).write(to: target)
        XCTAssertThrowsError(try ManualProbePlan.readImportedPlan(documents: root))
        try canonical(plan()).write(to: target)
        XCTAssertEqual(try ManualProbePlan.readImportedPlan(documents: root), try canonical(plan()))
    }
    @MainActor func testManualOptInIsNotAmbientAndDefaultCannotTouchStorage() async throws {
        XCTAssertFalse(DevelopmentAuthorization.fromEnvironment().isEnabled)
        XCTAssertTrue(DevelopmentAuthorization.afterExplicitManualConsent().isEnabled)
        XCTAssertFalse(DevelopmentAuthorization.fromEnvironment().isEnabled)
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString), p = plan()
        let probe = try DevelopmentProbe(base: root.appendingPathComponent("store"), dataset: p.dataset, runID: p.runID)
        do { _ = try await probe.runManualPlan(canonical(p), documents: root); XCTFail("default-off should reject") }
        catch let error as LabError { XCTAssertEqual(String(describing: error), "blocked") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}
#endif
