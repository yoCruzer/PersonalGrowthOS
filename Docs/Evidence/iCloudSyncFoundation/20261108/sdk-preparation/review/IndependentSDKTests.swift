import XCTest
import CloudKit
import FormalProbeCore
import SyncFoundation
@testable import FormalDevelopmentSDK

@MainActor private final class ReviewGate {
    var entered = false
    var waiter: CheckedContinuation<Void, Never>?
    var blocked: CheckedContinuation<Void, Never>?
    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func suspend() async {
        entered = true; waiter?.resume(); waiter = nil
        await withCheckedContinuation { blocked = $0 }
    }
    func release() { blocked?.resume(); blocked = nil }
}

@MainActor private final class ReviewTransport: BatchTransport {
    var calls: [String] = []
    var storage: [CKRecord.ID: CKRecord] = [:]
    var suspendedStage: String?
    let gate = ReviewGate()
    var fault = ""
    var hook: ((String) throws -> Void)?
    func step(_ stage: String) async throws {
        calls.append(stage)
        if suspendedStage == stage { await gate.suspend() }
        try hook?(stage)
    }
    func zoneExists(_ id: CKRecordZone.ID) async throws -> Bool { try await step("zone-probe"); return fault == "existing" }
    func createZone(_ id: CKRecordZone.ID) async throws -> CKRecordZone.ID { try await step("zone-save"); return id }
    func save(_ records: [CKRecord]) async throws -> [CKRecord.ID: Result<CKRecord, Error>] {
        let stage = records.first!.recordType == CloudRecordCodec.mutationType ? "mutations-save" : "assets-save"
        try await step(stage)
        var results: [CKRecord.ID: Result<CKRecord, Error>] = [:]
        for record in records { storage[record.recordID] = record; results[record.recordID] = .success(record) }
        if fault == "partial-private" && stage == "assets-save" {
            let first = records.first!.recordID
            let sameNameForeignZone = CKRecord.ID(recordName: first.recordName, zoneID: CKRecordZone.ID(zoneName: "PRIVATE_ZONE_MUST_NOT_LEAK"))
            let privateID = CKRecord.ID(recordName: "PRIVATE_USER_EMAIL_MUST_NOT_LEAK", zoneID: first.zoneID)
            let error = NSError(domain: CKErrorDomain, code: CKError.partialFailure.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "PRIVATE_LOCALIZED_MUST_NOT_LEAK",
                    CKPartialErrorsByItemIDKey: [first: CKError(.quotaExceeded), privateID: CKError(.permissionFailure), sameNameForeignZone: CKError(.permissionFailure)]])
            results[first] = .failure(error)
        }
        if fault == "extra-private" && stage == "assets-save" {
            let names = ["PRIVATE_RESULT_MUST_NOT_LEAK", records.first!.recordID.recordName]
            for name in names {
                let id = CKRecord.ID(recordName: name, zoneID: CKRecordZone.ID(zoneName: "PRIVATE_ZONE_MUST_NOT_LEAK"))
                results[id] = .success(CKRecord(recordType: "PRIVATE_TYPE_MUST_NOT_LEAK", recordID: id))
            }
        }
        return results
    }
    func fetch(_ ids: [CKRecord.ID]) async throws -> [CKRecord.ID: Result<CKRecord, Error>] {
        try await step("exact-fetch")
        var results = Dictionary(uniqueKeysWithValues: ids.map { ($0, Result<CKRecord, Error>.success(storage[$0]!)) })
        if fault == "missing-fetch" { results.removeValue(forKey: ids[0]) }
        if fault == "changed-fetch" {
            let record = storage.values.first(where: { $0.recordType == CloudRecordCodec.mutationType })!
            record["manifest"] = Data("wrong bytes".utf8) as CKRecordValue
        }
        return results
    }
}

@MainActor final class IndependentSDKTests: XCTestCase {
    private struct Context {
        let root: URL, plan: URL, output: URL, fixture: ProbeFixture, runner: BatchRunner, ticket: BatchTicket, transport: ReviewTransport
    }
    private func context() throws -> Context {
        let root = URL(fileURLWithPath: "/private/tmp/PGOS-IndependentSDK-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let plan = root.appendingPathComponent("plan"), value = try ProbeFixture.prepare(at: plan)
        let fixture = try ProbeFixture.load(from: plan, expectedSHA256: value.digest), epoch = UUID()
        return Context(root: root, plan: plan, output: root.appendingPathComponent("output"), fixture: fixture,
            runner: BatchRunner(epoch: epoch), ticket: try BatchTicket(fixture: fixture, epoch: epoch), transport: ReviewTransport())
    }
    private func run(_ c: Context) async throws -> BatchReport { try await c.runner.run(planURL: c.plan, ticket: c.ticket, output: c.output, transport: c.transport) }
    private func report(_ url: URL) throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(contentsOf: url.appendingPathComponent("report.json"))) as! [String: Any] }
    private func rejected(_ task: Task<BatchReport, Error>, output: URL, failure: String? = nil) async throws {
        do { _ = try await task.value; XCTFail("Returned success") } catch {}
        let r = try report(output); XCTAssertEqual(r["status"] as? String, "FAILED"); XCTAssertEqual(r["p0Passed"] as? Bool, false)
        if let failure { XCTAssertEqual(r["failure"] as? String, failure) }
    }
    private func journal(_ output: URL) throws -> String {
        try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.map { try String(contentsOf: $0) }.joined(separator: "\n")
    }
    func testIndependentExactFixtureAndExistingZoneNegative() async throws {
        let c = try context(), result = try await run(c)
        XCTAssertEqual(result.status, "INJECTED_TRANSPORT_VERIFIED"); XCTAssertFalse(result.realAuthorityVerified); XCTAssertFalse(result.p0Passed)
        XCTAssertEqual(c.transport.calls, ["zone-probe", "zone-save", "assets-save", "mutations-save", "exact-fetch"])
        XCTAssertEqual(c.transport.storage.count, 6)
        XCTAssertEqual(try String(contentsOf: c.output.appendingPathComponent("lease-create.payload")), "{\"synthetic\":true,\"text\":\"Formal Development create 原始文字\"}")
        let n = try context(); n.transport.fault = "existing"
        try await rejected(Task { try await self.run(n) }, output: n.output, failure: "existingZone")
        XCTAssertEqual(n.transport.calls, ["zone-probe"])
    }
    func testRealSuspensionEpochFencesEveryBoundary() async throws {
        for stage in ["zone-probe", "zone-save", "assets-save", "mutations-save", "exact-fetch"] {
            let c = try context(); c.transport.suspendedStage = stage
            let task = Task { try await self.run(c) }
            await c.transport.gate.waitForEntry(); c.runner.invalidateEpoch(); c.transport.gate.release()
            try await rejected(task, output: c.output, failure: "staleEpoch")
            XCTAssertEqual(c.transport.calls.last, stage)
        }
    }
    func testDistinctConcurrentTicketRejectedAndConsumedTicketCannotReplay() async throws {
        let c = try context(); c.transport.suspendedStage = "zone-probe"
        let first = Task { try await self.run(c) }; await c.transport.gate.waitForEntry()
        let second = try BatchTicket(fixture: c.fixture, epoch: c.runner.epoch), other = c.root.appendingPathComponent("other")
        do { _ = try await c.runner.run(planURL: c.plan, ticket: second, output: other, transport: c.transport); XCTFail("Concurrent run accepted") }
        catch BatchFailure.busy {}
        XCTAssertFalse(second.used); XCTAssertFalse(FileManager.default.fileExists(atPath: other.path))
        c.transport.gate.release(); _ = try await first.value
        let previousCalls = c.transport.calls
        do { _ = try await c.runner.run(planURL: c.plan, ticket: c.ticket, output: other, transport: c.transport); XCTFail("Ticket replay accepted") }
        catch BatchFailure.consumed {}
        XCTAssertEqual(c.transport.calls, previousCalls)
    }
    func testRealSuspensionCancellationDoesNotAdvanceAfterReturn() async throws {
        let c = try context(); c.transport.suspendedStage = "assets-save"
        let task = Task { try await self.run(c) }; await c.transport.gate.waitForEntry()
        task.cancel(); c.transport.gate.release()
        try await rejected(task, output: c.output, failure: "cancelled"); XCTAssertEqual(c.transport.calls.last, "assets-save")
    }
    func testPlanAndLeasedBytesChangedDuringActualAwaitReject() async throws {
        for lease in [false, true] {
            let c = try context(); c.transport.suspendedStage = "assets-save"
            let task = Task { try await self.run(c) }; await c.transport.gate.waitForEntry()
            let file = lease ? c.output.appendingPathComponent("lease-original.png") : c.plan.appendingPathComponent("original.png")
            try Data("SYNTHETIC_CHANGED_AFTER_SUSPEND".utf8).write(to: file)
            c.transport.gate.release(); try await rejected(task, output: c.output)
            XCTAssertEqual(c.transport.calls.last, "assets-save")
        }
    }
    func testOutputDirectoryReplacementDuringAwaitCannotPublishSuccess() async throws {
        let c = try context(); c.transport.suspendedStage = "assets-save"
        let task = Task { try await self.run(c) }; await c.transport.gate.waitForEntry()
        let original = c.root.appendingPathComponent("preserved-output")
        try FileManager.default.moveItem(at: c.output, to: original)
        try FileManager.default.createDirectory(at: c.output, withIntermediateDirectories: false)
        c.transport.gate.release(); try await rejected(task, output: original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: c.output.appendingPathComponent("report.json").path))
        XCTAssertEqual(c.transport.calls.last, "assets-save")
    }
    func testPartialErrorsRetainNumericEvidenceAndRedactForeignIdentities() async throws {
        let c = try context(); c.transport.fault = "partial-private"
        try await rejected(Task { try await self.run(c) }, output: c.output, failure: "partialFailure")
        let raw = try journal(c.output)
        for secret in ["PRIVATE_USER_EMAIL", "PRIVATE_ZONE", "PRIVATE_LOCALIZED"] { XCTAssertFalse(raw.contains(secret)) }
        XCTAssertTrue(raw.contains("RETURNED_FAILURE")); XCTAssertTrue(raw.contains("errorCode")); XCTAssertEqual(c.transport.calls.last, "assets-save")
    }
    func testUnexpectedResultsIncludingSameNameWrongZoneAreRedactedAndRejected() async throws {
        let c = try context(); c.transport.fault = "extra-private"
        try await rejected(Task { try await self.run(c) }, output: c.output, failure: "unexpectedResults")
        let raw = try journal(c.output)
        for secret in ["PRIVATE_RESULT", "PRIVATE_ZONE", "PRIVATE_TYPE"] { XCTAssertFalse(raw.contains(secret)) }
        XCTAssertEqual(c.transport.calls.last, "assets-save")
    }
    func testFetchedSetAndBytesMustMatchEvenAfterAllSaveAcknowledgments() async throws {
        for fault in ["missing-fetch", "changed-fetch"] {
            let c = try context(); c.transport.fault = fault
            try await rejected(Task { try await self.run(c) }, output: c.output)
            XCTAssertEqual(c.transport.calls.last, "exact-fetch")
        }
    }
    func testReportCollisionNeverReturnsSuccessOrOverwritesEvidence() async throws {
        let c = try context()
        c.transport.hook = { stage in if stage == "exact-fetch" { try Data("INDEPENDENT_SENTINEL".utf8).write(to: c.output.appendingPathComponent("report.json")) } }
        do { _ = try await run(c); XCTFail("Evidence write failure returned success") } catch {}
        XCTAssertEqual(try String(contentsOf: c.output.appendingPathComponent("report.json")), "INDEPENDENT_SENTINEL")
        XCTAssertTrue(try journal(c.output).contains("failed"))
    }
    func testLockedHostFinalBoundReportStillRefusesAllAuthority() throws {
        let c = try context()
        try FormalDevelopmentLockedHost.inspect(planURL: c.plan, expectedSHA256: c.ticket.planSHA256, output: c.output)
        let r = try report(c.output)
        XCTAssertEqual(r["status"] as? String, "NOT_READY")
        XCTAssertEqual(r["failure"] as? String, "EXTERNAL_GATE_NOT_COMPLETE")
        XCTAssertEqual(r["networkOperations"] as? Int, 0)
        XCTAssertEqual(r["networkAuthorized"] as? Bool, false)
        XCTAssertEqual(r["p0Passed"] as? Bool, false)
        XCTAssertEqual(c.transport.calls, [])
    }
}
