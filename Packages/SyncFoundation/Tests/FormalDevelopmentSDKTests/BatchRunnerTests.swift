import XCTest
import CloudKit
import FormalProbeCore
import SyncFoundation
@testable import FormalDevelopmentSDK

@MainActor final class FakeTransport: BatchTransport {
    var calls: [String] = []
    var storage: [CKRecord.ID: CKRecord] = [:]
    var existing = false
    var fault: String?
    var hook: ((String) async throws -> Void)?
    func visit(_ label: String) async throws { calls.append(label); try await hook?(label) }
    func zoneExists(_ id: CKRecordZone.ID) async throws -> Bool { try await visit("probe"); return existing }
    func createZone(_ id: CKRecordZone.ID) async throws -> CKRecordZone.ID {
        try await visit("zone"); return fault == "wrongZone" ? CKRecordZone.ID(zoneName: "wrong") : id
    }
    func save(_ records: [CKRecord]) async throws -> [CKRecord.ID: Result<CKRecord, Error>] {
        let label = records[0].recordType == CloudRecordCodec.mutationType ? "mutations" : "assets"
        try await visit(label)
        var result: [CKRecord.ID: Result<CKRecord, Error>] = [:]
        for record in records { storage[record.recordID] = record; result[record.recordID] = .success(record) }
        if fault == "partial" && label == "assets" { result[records[0].recordID] = .failure(CKError(.quotaExceeded)) }
        if fault == "missingSave" { result.removeValue(forKey: records[0].recordID) }
        if fault == "extraSave" { let extra = CKRecord(recordType: "Extra"); result[extra.recordID] = .success(extra) }
        if fault == "throw" { throw CKError(.networkFailure) }
        return result
    }
    func fetch(_ ids: [CKRecord.ID]) async throws -> [CKRecord.ID: Result<CKRecord, Error>] {
        try await visit("fetch")
        var result = Dictionary(uniqueKeysWithValues: ids.map { ($0, Result<CKRecord, Error>.success(storage[$0]!)) })
        if fault == "missingFetch" { result.removeValue(forKey: ids[0]) }
        if fault == "extraFetch" { let extra = CKRecord(recordType: "Extra"); result[extra.recordID] = .success(extra) }
        if fault == "badBytes" { storage[ids[0]]!["sha256"] = String(repeating: "0", count: 64) as CKRecordValue }
        return result
    }
}

@MainActor final class BatchRunnerTests: XCTestCase {
    struct Context {
        let root: URL, plan: URL, fixture: ProbeFixture, ticket: BatchTicket, runner: BatchRunner, transport: FakeTransport
        var output: URL { root.appendingPathComponent("output") }
    }
    func context() throws -> Context {
        let root = URL(fileURLWithPath: "/private/tmp/pgos-sdk-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let plan = root.appendingPathComponent("plan")
        let value = try ProbeFixture.prepare(at: plan)
        let fixture = try ProbeFixture.load(from: plan, expectedSHA256: value.digest), epoch = UUID()
        return Context(root: root, plan: plan, fixture: fixture, ticket: try BatchTicket(fixture: fixture, epoch: epoch), runner: BatchRunner(epoch: epoch), transport: FakeTransport())
    }
    func run(_ c: Context) async throws -> BatchReport { try await c.runner.run(planURL: c.plan, ticket: c.ticket, output: c.output, transport: c.transport) }
    func failure(_ c: Context) async throws -> [String: Any] {
        do { _ = try await run(c); XCTFail("Unexpected success") } catch {}
        let data = try Data(contentsOf: c.output.appendingPathComponent("report.json"))
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(result["status"] as? String, "FAILED"); XCTAssertEqual(result["p0Passed"] as? Bool, false)
        return result
    }
    func testExactSixRecordRoundtripAndNoAuthorityClaim() async throws {
        let c = try context(); let report = try await run(c)
        XCTAssertEqual(report.status, "INJECTED_TRANSPORT_VERIFIED"); XCTAssertFalse(report.realAuthorityVerified); XCTAssertFalse(report.p0Passed)
        XCTAssertEqual(c.transport.calls, ["probe", "zone", "assets", "mutations", "fetch"])
        XCTAssertEqual(c.transport.storage.count, 6); XCTAssertFalse(report.zoneCreationAtomic)
        XCTAssertEqual(try Data(contentsOf: c.output.appendingPathComponent("lease-original.png")), ProbeFixture.png)
    }
    func testExistingZoneStopsBeforeWrites() async throws {
        let c = try context(); c.transport.existing = true
        let report = try await failure(c); XCTAssertEqual(report["failure"] as? String, "existingZone"); XCTAssertEqual(c.transport.calls, ["probe"])
    }
    func testWrongZoneStopsBeforeRecords() async throws {
        let c = try context(); c.transport.fault = "wrongZone"
        _ = try await failure(c); XCTAssertEqual(c.transport.calls, ["probe", "zone"])
    }
    func testPartialSavePreservesReturnedEvidenceAndStops() async throws {
        let c = try context(); c.transport.fault = "partial"
        let report = try await failure(c); XCTAssertEqual(report["failure"] as? String, "partialFailure")
        XCTAssertEqual(c.transport.calls, ["probe", "zone", "assets"])
        let raw = try String(contentsOf: c.output.appendingPathComponent("005-returned.json"))
        XCTAssertTrue(raw.contains("RETURNED_FAILURE")); XCTAssertTrue(raw.contains("RETURNED_SUCCESS_UNVERIFIED")); XCTAssertTrue(raw.contains("errorCode"))
    }
    func testMissingAndExtraSaveResultsFail() async throws {
        for fault in ["missingSave", "extraSave"] {
            let c = try context(); c.transport.fault = fault
            let report = try await failure(c); XCTAssertEqual(report["failure"] as? String, "unexpectedResults")
            XCTAssertEqual(c.transport.calls.last, "assets")
        }
    }
    func testFetchRequiresExactSetAndBytes() async throws {
        for fault in ["missingFetch", "extraFetch", "badBytes"] {
            let c = try context(); c.transport.fault = fault
            _ = try await failure(c); XCTAssertEqual(c.transport.calls.last, "fetch")
        }
    }
    func testThrownCloudErrorRetainedAndNoRetry() async throws {
        let c = try context(); c.transport.fault = "throw"
        let report = try await failure(c); XCTAssertEqual(report["failure"] as? String, "CK_4")
        XCTAssertEqual(c.transport.calls, ["probe", "zone", "assets"])
    }
    func testEpochChangedDuringEveryAwaitStopsFollowingOperation() async throws {
        for stage in ["probe", "zone", "assets", "mutations", "fetch"] {
            let c = try context()
            c.transport.hook = { current in if current == stage { c.runner.invalidateEpoch() }; await Task.yield() }
            let report = try await failure(c); XCTAssertEqual(report["failure"] as? String, "staleEpoch"); XCTAssertEqual(c.transport.calls.last, stage)
        }
    }
    func testTicketInvalidationDuringAwait() async throws {
        let c = try context(); c.transport.hook = { _ in c.ticket.invalidate(); await Task.yield() }
        let report = try await failure(c); XCTAssertEqual(report["failure"] as? String, "staleEpoch"); XCTAssertEqual(c.transport.calls, ["probe"])
    }
    func testCancellationAfterAcknowledgmentStops() async throws {
        let c = try context()
        c.transport.hook = { stage in if stage == "assets" { withUnsafeCurrentTask { $0?.cancel() } }; await Task.yield() }
        // Isolate cancellation from XCTest's task.
        let task = Task { try await self.failure(c) }
        let report = try await task.value; XCTAssertEqual(report["failure"] as? String, "cancelled")
        XCTAssertEqual(c.transport.calls.last, "assets")
    }
    func testPlanAndLeaseChangesDuringAwaitStop() async throws {
        for lease in [false, true] {
            let c = try context()
            c.transport.hook = { stage in
                if stage == "assets" {
                    let url = lease ? c.output.appendingPathComponent("lease-original.png") : c.plan.appendingPathComponent("original.png")
                    try Data("tampered".utf8).write(to: url)
                }
            }
            _ = try await failure(c); XCTAssertEqual(c.transport.calls.last, "assets")
        }
    }
    func testSingleFlightAndTicketCannotBeReusedInNewOutput() async throws {
        let c = try context(); var rejected = false
        c.transport.hook = { stage in
            if stage == "probe" {
                do { _ = try await c.runner.run(planURL: c.plan, ticket: c.ticket, output: c.root.appendingPathComponent("concurrent"), transport: c.transport) }
                catch BatchFailure.busy { rejected = true }
            }
        }
        _ = try await run(c); XCTAssertTrue(rejected)
        do { _ = try await c.runner.run(planURL: c.plan, ticket: c.ticket, output: c.root.appendingPathComponent("reused"), transport: c.transport); XCTFail() }
        catch BatchFailure.consumed {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: c.root.appendingPathComponent("reused").path))
    }
    func testExistingOutputPreservedTicketStillConsumed() async throws {
        let c = try context(); try FileManager.default.createDirectory(at: c.output, withIntermediateDirectories: false)
        try Data("preserve".utf8).write(to: c.output.appendingPathComponent("sentinel"))
        do { _ = try await run(c); XCTFail() } catch {}
        XCTAssertEqual(c.transport.calls, []); XCTAssertTrue(c.ticket.used)
        XCTAssertEqual(try String(contentsOf: c.output.appendingPathComponent("sentinel")), "preserve")
    }
    func testLockedHostNeverAuthorizes() throws {
        let c = try context()
        try FormalDevelopmentLockedHost.inspect(planURL: c.plan, expectedSHA256: c.ticket.planSHA256, output: c.output)
        let report = try JSONSerialization.jsonObject(with: Data(contentsOf: c.output.appendingPathComponent("report.json"))) as! [String: Any]
        XCTAssertEqual(report["status"] as? String, "NOT_READY"); XCTAssertEqual(report["networkOperations"] as? Int, 0)
        XCTAssertEqual(report["networkAuthorized"] as? Bool, false)
    }
    func testDirectoryReplacementDuringAwaitStops() async throws {
        let c = try context()
        c.transport.hook = { stage in
            if stage == "assets" {
                try FileManager.default.moveItem(at: c.output, to: c.root.appendingPathComponent("original-output"))
                try FileManager.default.createDirectory(at: c.output, withIntermediateDirectories: false)
            }
        }
        do { _ = try await run(c); XCTFail() } catch {}
        XCTAssertEqual(c.transport.calls.last, "assets")
        let original = c.root.appendingPathComponent("original-output/report.json")
        let raw = try String(contentsOf: original)
        XCTAssertTrue(raw.contains("FAILED")); XCTAssertFalse(raw.contains("INJECTED_TRANSPORT_VERIFIED"))
    }
    func testFinalReportCollisionCannotReturnSuccess() async throws {
        let c = try context()
        c.transport.hook = { stage in
            if stage == "fetch" { try Data("sentinel".utf8).write(to: c.output.appendingPathComponent("report.json")) }
        }
        do { _ = try await run(c); XCTFail() } catch {}
        XCTAssertEqual(try String(contentsOf: c.output.appendingPathComponent("report.json")), "sentinel")
    }
    func testErrorsRedactUnknownIdentityAndLocalizedDetails() throws {
        let id = CKRecord.ID(recordName: "private-account-identifier")
        let error = NSError(domain: CKErrorDomain, code: CKError.partialFailure.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "secret-account-and-path", CKPartialErrorsByItemIDKey: [id: CKError(.permissionFailure)]])
        let result = outcome("private-record-name", .failure(error))
        let raw = String(decoding: try json(result), as: UTF8.self)
        XCTAssertFalse(raw.contains("private-account")); XCTAssertFalse(raw.contains("private-record")); XCTAssertFalse(raw.contains("secret-account"))
        XCTAssertTrue(raw.contains("UNEXPECTED_RECORD_ID")); XCTAssertTrue(raw.contains("errorCode"))
    }

}
