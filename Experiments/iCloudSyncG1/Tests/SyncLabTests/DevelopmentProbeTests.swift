#if DEBUG
import XCTest
@testable import SyncLab

final class DevelopmentProbeTests: XCTestCase {
    func testProbeJournalPreservesOriginalAndSeparatesRuns() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let command = ProbeCommand(id: "probe-command", action: .snapshot)
        let bytes = try canonical(command)
        let journal = try ProbeJournal(root: root, dataset: "synthetic-g1-test", runID: "probe-run")
        XCTAssertNil(try journal.claim(command, bytes: bytes))
        XCTAssertThrowsError(try journal.claim(command, bytes: bytes)) // interrupted, not silently replayed
        let result = ProbeResult(id: command.id, dataset: "synthetic-g1-test", runID: "probe-run", commandDigest: digest(bytes), status: "PASS", events: [], halted: false, platform: "TEST_ONLY")
        try journal.complete(result)
        XCTAssertEqual(try journal.claim(command, bytes: bytes)?.commandDigest, digest(bytes))
        let old = try Data(contentsOf: journal.directory.appendingPathComponent(command.id + ".json"))
        XCTAssertThrowsError(try journal.complete(result))
        XCTAssertThrowsError(try journal.claim(command, bytes: Data("different command".utf8)))
        XCTAssertEqual(try Data(contentsOf: journal.directory.appendingPathComponent(command.id + ".json")), old)
        let other = try ProbeJournal(root: root, dataset: "synthetic-g1-test", runID: "probe-other")
        XCTAssertNil(try other.claim(command, bytes: bytes))
    }
    func testProbeJournalRejectsWrongEvidenceIdentity() throws {
        let journal = try ProbeJournal(root: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString), dataset: "synthetic-g1-test", runID: "probe-run")
        let command = ProbeCommand(id: "probe-command", action: .snapshot)
        let bytes = try canonical(command)
        XCTAssertNil(try journal.claim(command, bytes: bytes))
        var result = ProbeResult(id: command.id, dataset: "synthetic-g1-other", runID: "probe-run", commandDigest: digest(bytes), status: "PASS", events: [], halted: false, platform: "TEST_ONLY")
        XCTAssertThrowsError(try journal.complete(result))
        result.dataset = "synthetic-g1-test"; result.commandDigest = String(repeating: "a", count: 64)
        XCTAssertThrowsError(try journal.complete(result))
    }
    func testDuplicateProcessLockRejectedUntilOwnerReleasesIt() throws {
        let base = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var first: ProbeProcessLock? = try ProbeProcessLock(base: base, dataset: "synthetic-g1-test")
        XCTAssertNotNil(first)
        XCTAssertThrowsError(try ProbeProcessLock(base: base, dataset: "synthetic-g1-test"))
        first = nil
        XCTAssertNoThrow(try ProbeProcessLock(base: base, dataset: "synthetic-g1-test"))
    }
    func testSyntheticCommandsRejectPrivateContentPathsAndWrongImage() throws {
        let valid = Mutation(id: "probe-m1", object: "probe-entry", text: "SYNTHETIC one", imageHash: digest(DevelopmentProbe.png), imageBytes: DevelopmentProbe.png.count)
        XCTAssertNoThrow(try ProbeCommand(id: "probe-command1", action: .save, mutation: valid).validate())
        for change in ["text", "object", "parent", "image"] {
            var m = valid
            switch change {
            case "text": m.text = "private text"
            case "object": m.object = "real-entry"
            case "parent": m.parents = ["real-id"]
            default: m.imageHash = String(repeating: "a", count: 64)
            }
            XCTAssertThrowsError(try ProbeCommand(id: "probe-command1", action: .save, mutation: m).validate())
        }
        XCTAssertThrowsError(try ProbeCommand(id: "../file", action: .snapshot).validate())
        XCTAssertThrowsError(try ProbeCommand(id: "probe-command1", action: .sync, mutation: valid).validate())
        XCTAssertThrowsError(try ProbeCommand(id: "probe-command1", action: .save).validate())
    }
    @MainActor func testProbeOnlyAcceptsExplicitLoopbackAndSyntheticDataset() throws {
        XCTAssertEqual(try DevelopmentProbe.loopbackURL("http://127.0.0.1:23456").host, "127.0.0.1")
        for address in ["https://example.com:23456", "http://localhost:23456", "http://127.0.0.1:80", "http://u:p@127.0.0.1:23456", "http://127.0.0.1:23456/data", "http://127.0.0.1:23456?token=x"] {
            XCTAssertThrowsError(try DevelopmentProbe.loopbackURL(address))
        }
        XCTAssertThrowsError(try DevelopmentProbe(base: URL.temporaryDirectory, dataset: "daily", runID: "probe-run"))
        XCTAssertThrowsError(try DevelopmentProbe(base: URL.temporaryDirectory, dataset: "synthetic-g1-test", runID: "../path"))
    }
    @MainActor func testProbeDoesNotStartCloudWithoutExplicitOptIn() async throws {
        // XCTest environment intentionally has no Development opt-in.
        XCTAssertNotEqual(ProcessInfo.processInfo.environment["SYNCLAB_ENABLE_DEVELOPMENT"], "YES")
        let base = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let probe = try DevelopmentProbe(base: base, dataset: "synthetic-g1-test", runID: "probe-run")
        let result = await probe.perform(ProbeCommand(id: "probe-connect", action: .connect))
        XCTAssertEqual(result.status, "FAIL"); XCTAssertEqual(result.errorCode, "LAB_blocked")
        XCTAssertNil(result.accountFingerprint); XCTAssertFalse(FileManager.default.fileExists(atPath: base.path))
    }
}
#endif
