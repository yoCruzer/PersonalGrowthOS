import XCTest
import CloudKit
import ImageIO
@testable import SyncLab

final class SyncLabTests: XCTestCase {
    func m(_ id: String, _ object: String = "entry", parents: [String] = [], requires: [String] = [], deleted: Bool = false) -> Mutation {
        Mutation(id: id, object: object, parents: parents, requires: requires, text: "SYNTHETIC-" + id, deleted: deleted)
    }
    @MainActor func store(_ base: URL? = nil, account: String = "A", dataset: String = "test") throws -> LabStore {
        try LabStore(base: base ?? FileManager.default.temporaryDirectory.appendingPathComponent("SyncLabTest-" + UUID().uuidString), binding: Binding(accountHash: digest(Data(account.utf8)), dataset: dataset))
    }
    func testDeletedDependencyDoesNotPublish() throws {
        let p = try Graph([m("a", "parent"), m("b", "parent", parents: ["a"], deleted: true), m("link", requires: ["parent"])]).project("entry")
        XCTAssertEqual(p.state, "staged"); XCTAssertFalse(p.complete)
    }
    func testMissingAncestorDoesNotPublish() throws {
        XCTAssertEqual(try Graph([m("p", "parent", parents: ["unknown"]), m("link", requires: ["parent"])]).project("entry").state, "staged")
    }
    func testTransitiveMissingDependencyDoesNotPublish() throws {
        XCTAssertEqual(try Graph([m("p", "parent", requires: ["missing"]), m("link", requires: ["parent"])]).project("entry").state, "staged")
    }
    func testDependencyCycleDoesNotPublish() throws {
        XCTAssertEqual(try Graph([m("p", "parent", requires: ["entry"]), m("link", requires: ["parent"])]).project("entry").state, "staged")
    }
    func testNewInvalidHeadDoesNotFallbackAndCanRecover() throws {
        let rows = [m("a"), m("b", parents: ["a"], requires: ["parent"])]
        XCTAssertEqual(try Graph(rows).project("entry").state, "staged")
        XCTAssertEqual(try Graph(rows + [m("p", "parent")]).project("entry").preview?.id, "b")
    }
    func testConflictProjectionOrderAndReplayInvariant() throws {
        let rows = [m("base"), m("a", parents: ["base"]), m("b", parents: ["base"])]
        let expected = try Graph(rows).project("entry")
        XCTAssertEqual(expected.state, "conflict"); XCTAssertEqual(expected.preview?.id, "base"); XCTAssertFalse(expected.complete)
        for permutation in [rows.reversed().map { $0 }, [rows[1], rows[0], rows[2]], rows + rows] {
            XCTAssertEqual(try Graph(permutation).project("entry"), expected)
        }
        XCTAssertEqual(try Graph(rows + [m("resolved", parents: ["a", "b"])]).project("entry").state, "ready")
    }
    func testNoCommonBaselineAndDeleteConflict() throws {
        XCTAssertNil(try Graph([m("a"), m("b")]).project("entry").preview)
        let p = try Graph([m("a"), m("b", deleted: true)]).project("entry")
        XCTAssertEqual(p.state, "deleted_conflict"); XCTAssertNil(p.preview); XCTAssertFalse(p.complete)
    }
    func testTwoNearestCommonAncestorsRemainPending() throws {
        let rows = [m("a"),m("b"),m("c",parents:["a","b"]),m("d",parents:["a","b"])]
        XCTAssertNil(try Graph(rows).project("entry").preview)
    }
    func testCausalCycleAndForeignParentFailClosed() throws {
        XCTAssertEqual(try Graph([m("a", parents: ["b"]), m("b", parents: ["a"])]).project("entry").state, "staged")
        XCTAssertEqual(try Graph([m("p", "other"), m("a", parents: ["p"])]).project("entry").state, "staged")
    }
    func testWireUnknownVersionCollisionAndBound() throws {
        var future = m("a"); future.version = 2
        XCTAssertThrowsError(try Envelope(object: "entry", mutations: [future]).encoded())
        XCTAssertThrowsError(try Graph([m("a"), Mutation(id: "a", object: "entry", text: "DIFFERENT")]))
        XCTAssertThrowsError(try Envelope(object: "entry", mutations: [Mutation(id: "a", object: "entry", text: String(repeating: "a", count: 32769))]).encoded())
    }
    @MainActor func testFactAndOutboxRollbackTogether() async throws {
        let s = try store(); s.failBeforeCommit = true
        XCTAssertThrowsError(try s.save(m("a")))
        XCTAssertTrue(try s.envelopes().isEmpty); XCTAssertTrue(try s.pending().isEmpty)
        s.failBeforeCommit = false; try s.save(m("b")); XCTAssertEqual(try s.pending().count, 1)
    }
    @MainActor func testOldACKRetainsNewVersionAndExactACKClearsIt() async throws {
        let s = try store(); try s.save(m("a")); let old = try XCTUnwrap(s.pending().first)
        try s.save(m("b", parents: ["a"]))
        try s.acknowledge(old.key, sent: old.payload, fields: Data(), ticket: s.epoch)
        XCTAssertEqual(try s.pending().count, 1)
        let current = try XCTUnwrap(s.pending().first)
        XCTAssertNotEqual(current.payload, old.payload)
        try s.acknowledge(current.key, sent: current.payload, fields: Data(), ticket: s.epoch)
        XCTAssertTrue(try s.pending().isEmpty)
    }
    @MainActor func testFetchedUnionPreservesBothAndNeedsUpload() async throws {
        let s = try store(); try s.save(m("a"))
        let remote = try Envelope(object: "entry", mutations: [m("b")]).encoded()
        try s.receiveEnvelope(remote, key: "object-entry", fields: Data(), ticket: s.epoch)
        XCTAssertEqual(try s.envelopes().first?.mutations.map(\.id), ["a", "b"])
        XCTAssertEqual(try s.pending().count, 1); XCTAssertEqual(try s.projections()["entry"]?.state, "conflict")
    }
    @MainActor func testReceiptRetainsCollisionWithoutReplacingOriginal() async throws {
        let s = try store(); try s.save(m("a"))
        let invalid = try Envelope(object: "entry", mutations: [Mutation(id: "a", object: "entry", text: "DIFFERENT")]).encoded()
        XCTAssertThrowsError(try s.receiveEnvelope(invalid, key: "object-entry", fields: Data(), ticket: s.epoch))
        XCTAssertEqual(try s.envelopes().first?.mutations.first, m("a"))
        XCTAssertEqual(try s.rows().filter { $0.key.hasPrefix("inbox-") }.count, 1)
    }
    @MainActor func testCrossObjectMutationIdentityRejected() async throws {
        let s = try store(); try s.save(m("a"))
        XCTAssertThrowsError(try s.save(m("a", "other")))
        XCTAssertThrowsError(try s.receiveEnvelope(Envelope(object: "other", mutations: [m("a", "other")]).encoded(), key: "object-other", fields: Data(), ticket: s.epoch))
    }
    @MainActor func testImageBytesExportAndMissingOriginalFail() async throws {
        let s = try store(); let bytes = Data("SYNTHETIC-ORIGINAL".utf8); let hash = digest(bytes)
        try s.save(Mutation(id: "a", object: "entry", text: "", imageHash: hash, imageBytes: bytes.count), image: bytes)
        XCTAssertEqual(try s.image(hash, count: bytes.count), bytes)
        XCTAssertEqual(try s.pending().count, 2)
        XCTAssertFalse(try s.exportSnapshot().isEmpty)
        try Data("truncated".utf8).write(to: s.imageURL(hash))
        XCTAssertThrowsError(try s.exportSnapshot()); XCTAssertFalse(try XCTUnwrap(s.projections()["entry"]).complete)
        XCTAssertThrowsError(try Wire.record(XCTUnwrap(s.pending().first { $0.key.hasPrefix("image-") }), dataset: "test", imageURL: s.imageURL))
    }
    @MainActor func testWrongImageDoesNotCreateFact() async throws {
        let s = try store(); let bytes = Data("SYNTHETIC".utf8)
        XCTAssertThrowsError(try s.save(Mutation(id: "a", object: "entry", text: "", imageHash: digest(bytes), imageBytes: bytes.count), image: Data("OTHER".utf8)))
        XCTAssertTrue(try s.envelopes().isEmpty)
    }
    @MainActor func testLateCallbacksAndCheckpointRejectedAfterFence() async throws {
        let s = try store(); try s.save(m("a")); let p = try XCTUnwrap(s.pending().first); let ticket = s.epoch
        s.fence()
        XCTAssertThrowsError(try s.acknowledge(p.key, sent: p.payload, fields: Data(), ticket: ticket))
        XCTAssertThrowsError(try s.receiveEnvelope(p.payload, key: p.key, fields: Data(), ticket: ticket))
        XCTAssertThrowsError(try s.saveCheckpoint(Data("STATE".utf8), ticket: ticket))
        XCTAssertEqual(try s.pending().count, 1); XCTAssertNil(try s.checkpoint())
    }
    @MainActor func testAccountPartitionsReopenAtoBtoA() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var a: LabStore? = try store(base); try a!.save(m("a")); a!.fence(); a = nil
        let b = try store(base, account: "B"); XCTAssertTrue(try b.envelopes().isEmpty)
        try b.save(m("b")); let reopened = try store(base)
        XCTAssertEqual(try reopened.envelopes().first?.mutations.map(\.id), ["a"])
        XCTAssertEqual(try reopened.pending().count, 1)
    }
    @MainActor func testRestoreIsolatedAndFencesRacingCallback() async throws {
        let source = try store(); try source.save(m("a")); let bytes = try source.exportSnapshot()
        let target = try store(dataset: "restore"); let oldEpoch = target.epoch
        try target.importSnapshot(bytes)
        XCTAssertThrowsError(try target.receiveEnvelope(Envelope(object: "entry", mutations: [m("remote")]).encoded(), key: "object-entry", fields: Data(), ticket: oldEpoch))
        XCTAssertEqual(try target.envelopes().first?.mutations.map(\.id), ["a"])
        XCTAssertNil(try target.checkpoint()); XCTAssertNil(try target.pending().first?.systemFields)
        XCTAssertThrowsError(try source.importSnapshot(bytes))
    }
    @MainActor func testMissingImageRestoreRetainsEmptyFactsAndFenced() async throws {
        let target = try store(); let bytes = Data("IMAGE".utf8)
        let snap = LabSnapshot(envelopes: [Envelope(object: "entry", mutations: [Mutation(id: "a", object: "entry", text: "", imageHash: digest(bytes), imageBytes: bytes.count)])], images: [:])
        XCTAssertThrowsError(try target.importSnapshot(canonical(snap)))
        XCTAssertTrue(try target.envelopes().isEmpty); XCTAssertTrue(target.stopped)
    }
    @MainActor func testCloudCodecAllFieldsAndWrongZone() async throws {
        let s = try store(); try s.save(m("a"))
        let p = try XCTUnwrap(s.pending().first)
        let r = try Wire.record(p, dataset: "test", imageURL: s.imageURL)
        XCTAssertEqual(try Wire.payload(r, dataset: "test"), p.payload)
        XCTAssertThrowsError(try Wire.payload(r, dataset: "another"))
        r["sha256"] = "wrong" as CKRecordValue
        XCTAssertThrowsError(try Wire.payload(r, dataset: "test"))
    }
    @MainActor func testCheckpointFailureDoesNotChangePersistedState() async throws {
        let s = try store(); try s.saveCheckpoint(Data("old".utf8), ticket: s.epoch)
        s.failBeforeCommit = true
        XCTAssertThrowsError(try s.saveCheckpoint(Data("new".utf8), ticket: s.epoch))
        XCTAssertEqual(try s.checkpoint(), Data("old".utf8))
    }
    @MainActor func testTruncatedImageCanBeRepairedWithoutErasingBadEvidence() async throws {
        let s = try store(); let bytes = Data("SYNTHETIC-ORIGINAL".utf8); let hash = digest(bytes)
        try s.save(Mutation(id: "a", object: "entry", text: "", imageHash: hash, imageBytes: bytes.count), image: bytes)
        let damaged = Data("TRUNCATED".utf8)
        try damaged.write(to: s.imageURL(hash))
        try s.receiveImage(bytes, hash: hash, count: bytes.count, fields: Data(), ticket: s.epoch)
        XCTAssertEqual(try s.image(hash, count: bytes.count), bytes)
        XCTAssertEqual(try Data(contentsOf: s.root.appendingPathComponent("quarantine").appendingPathComponent(digest(damaged))), damaged)
    }
    @MainActor func testActualCloudCodecFailureRetainsOriginalRecord() async throws {
        let s = try store(); let driver = CloudDriver(store: s)
        let record = CKRecord(recordType: Wire.objectType, recordID: CKRecord.ID(recordName: "object-entry", zoneID: Wire.zone("test")))
        record["wireVersion"] = 999 as CKRecordValue
        record["payload"] = Data("SYNTHETIC-FUTURE-OPAQUE".utf8) as CKRecordValue
        XCTAssertThrowsError(try driver.accept(record))
        XCTAssertEqual(try s.rows().filter { $0.key.hasPrefix("inbox-") }.count, 1)
        XCTAssertTrue(try s.envelopes().isEmpty)
    }

    @MainActor func testMissingParentImageBlocksLinkThenRepairs() async throws {
        let s = try store(); let bytes = Data("SYNTHETIC-PARENT".utf8); let hash = digest(bytes)
        let parent = Envelope(object: "parent", mutations: [Mutation(id: "p", object: "parent", text: "parent", imageHash: hash, imageBytes: bytes.count)])
        try s.receiveEnvelope(parent.encoded(), key: "object-parent", fields: Data(), ticket: s.epoch)
        try s.save(m("link", requires: ["parent"]))
        XCTAssertFalse(try XCTUnwrap(s.projections()["entry"]).complete)
        try s.receiveImage(bytes, hash: hash, count: bytes.count, fields: Data(), ticket: s.epoch)
        XCTAssertEqual(try s.projections()["entry"]?.state, "ready")
    }
    @MainActor func testRestoredPartitionCannotSendAfterReopen() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = try store(); try source.save(m("a"))
        var target: LabStore? = try store(base, dataset: "restore")
        try target!.importSnapshot(source.exportSnapshot()); target = nil
        let reopened = try store(base, dataset: "restore")
        XCTAssertThrowsError(try reopened.check(reopened.epoch))
        XCTAssertFalse(try reopened.exportSnapshot().isEmpty)
    }
    @MainActor func testNetworkFencePreservesOfflineEditing() async throws {
        let s = try store(); try s.save(m("a")); s.fence()
        try s.save(m("b", parents: ["a"]))
        XCTAssertEqual(try s.projections()["entry"]?.preview?.id, "b")
        XCTAssertEqual(try s.pending().count, 1)
    }

    func testSharedAncestorDAGHasBoundedProjectionCost() throws {
        var rows = [m("n0"), m("n1")]
        for i in 2..<160 { rows.append(m("n" + String(i), parents: ["n" + String(i-1), "n" + String(i-2)])) }
        let start = Date()
        let p = try Graph(rows).project("entry")
        XCTAssertEqual(p.preview?.id, "n159")
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0)
    }

    @MainActor func testInjectedCASAndPartialQuotaRetainExactPendingWork() async throws {
        let s = try store(); try s.save(m("a")); try s.save(m("other", "other"))
        let driver = CloudDriver(store: s)
        let remoteBytes = try Envelope(object: "entry", mutations: [m("b")]).encoded()
        let remote = try Wire.record(Pending(key: "object-entry", payload: remoteBytes, systemFields: nil), dataset: "test", imageURL: s.imageURL)
        try driver.processSaveFailure(CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: remote]))
        XCTAssertEqual(try s.projections()["entry"]?.candidates, ["a", "b"])
        let other = try XCTUnwrap(s.pending().first { $0.key == "object-other" })
        try s.acknowledge(other.key, sent: other.payload, fields: Data(), ticket: s.epoch)
        try driver.processSaveFailure(CKError(.quotaExceeded))
        try driver.processSaveFailure(CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 2]))
        XCTAssertEqual(try s.pending().map(\.key), ["object-entry"])
        XCTAssertTrue(driver.events.contains("SERVER_RECORD_CHANGED_MERGED"))
    }
    func testSyntheticOriginalIsDecodablePNG() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 1); XCTAssertEqual(image.height, 1)
    }

    @MainActor func testExportRejectsSnapshotOutsideRestoreObjectLimit() async throws {
        let s = try store()
        for i in 0..<129 { try s.save(m("m" + String(i), "o" + String(i))) }
        XCTAssertThrowsError(try s.exportSnapshot())
        XCTAssertEqual(try s.envelopes().count, 129)
    }

    @MainActor func testSnapshotMutationLimitPairsExportAndRestore() async throws {
        let s = try store()
        for i in 0..<8 {
            let object = "o" + String(i)
            let rows = (0..<512).map { m(object + "m" + String($0), object) }
            try s.receiveEnvelope(Envelope(object: object, mutations: rows).encoded(), key: "object-" + object, fields: Data(), ticket: s.epoch)
        }
        let bytes = try s.exportSnapshot()
        let target = try store(dataset: "restore-boundary")
        try target.importSnapshot(bytes)
        XCTAssertEqual(try target.envelopes().flatMap(\.mutations).count, 4096)
        try s.save(m("overflow", "extra"))
        XCTAssertThrowsError(try s.exportSnapshot())
        XCTAssertEqual(try s.envelopes().flatMap(\.mutations).count, 4097)
    }

}
