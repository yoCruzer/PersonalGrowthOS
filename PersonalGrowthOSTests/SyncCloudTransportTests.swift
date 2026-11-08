import XCTest
import CloudKit
import SyncFoundation
@testable import PersonalGrowthOS

@MainActor final class SyncCloudTransportTests: XCTestCase {
    private final class Store: SyncCloudPersistence {
        var committed: [String] = []
        var acknowledgements: [SyncCloudAcknowledgement] = []
        var paused: [SyncCloudPauseReason] = []
        var inboxFailure = false
        var stateFailure = false
        var suspendInbox = false
        var waiting: CheckedContinuation<Void, Never>?
        func loadEngineState(binding: SyncBinding) throws -> Data? { nil }
        func pendingRecordIDs(session: SyncCloudSession) throws -> [CKRecord.ID] { try session.check(); return [] }
        func uploadRecord(id: CKRecord.ID, session: SyncCloudSession) async throws -> SyncCloudUpload? { nil }
        func durableInbox(_ records: [SyncCloudDownloaded], session: SyncCloudSession) async throws {
            if suspendInbox { await withCheckedContinuation { waiting = $0 } }
            try session.check() // Atomic store boundary, after the deliberately suspended work.
            if inboxFailure { throw SyncValidationError.corruptAsset }
            committed.append("inbox")
        }
        func acknowledge(_ records: [SyncCloudAcknowledgement], session: SyncCloudSession) async throws {
            try session.check(); acknowledgements += records; committed.append("ack")
        }
        func didSaveZone(session: SyncCloudSession) async throws {
            try session.check(); committed.append("zone")
        }
        func saveEngineState(_ bytes: Data, session: SyncCloudSession) async throws {
            try session.check()
            if stateFailure { throw SyncValidationError.corruptAsset }
            committed.append("state")
        }
        func didPause(_ reason: SyncCloudPauseReason, binding: SyncBinding) { paused.append(reason) }
    }
    private func session() throws -> SyncCloudSession {
        SyncCloudSession(binding: try SyncBinding(container: "iCloud.com.synthetic.product", environment: .development,
            accountHash: String(repeating: "1", count: 64), dataset: UUID(), generation: UUID()))
    }
    private func manifest(dataset: UUID, mutation: UUID = UUID()) throws -> MutationManifest {
        try MutationManifest(dataset: dataset, mutation: mutation,
                             object: SyncObject(kind: "Aggregate", id: UUID()),
                             payload: PayloadManifest(bytes: Data("synthetic".utf8)))
    }
    private func waitForInbox(_ store: Store) async throws {
        for _ in 0..<1_000 { if store.waiting != nil { return }; await Task.yield() }
        XCTFail("Synthetic inbox did not reach its suspension")
        throw SyncCloudTransportError.notStarted
    }

    func testInitDoesNotStartACloudSession() {
        let transport = SyncCloudTransport(persistence: Store())
        XCTAssertNil(transport.session)
    }
    func testCheckpointCannotOvertakeSuspendedDurableInbox() async throws {
        let store = Store(); store.suspendInbox = true
        let reducer = SyncCloudDurableEvents(session: try session(), persistence: store)
        let first = Task { try await reducer.accept(.downloaded([])) }
        try await waitForInbox(store)
        let second = Task { try await reducer.accept(.state(Data([1]))) }
        await Task.yield(); XCTAssertTrue(store.committed.isEmpty)
        store.waiting?.resume(); store.waiting = nil
        try await first.value; try await second.value
        XCTAssertEqual(store.committed, ["inbox", "state"])
    }
    func testInboxFailurePreventsSubsequentCheckpointAndAcknowledgement() async throws {
        let store = Store(); store.inboxFailure = true
        let active = try session(), reducer = SyncCloudDurableEvents(session: active, persistence: store)
        do { try await reducer.accept(.downloaded([])); XCTFail("Must reject") } catch {}
        do { try await reducer.accept(.state(Data([1]))); XCTFail("Must reject checkpoint") } catch {}
        do { try await reducer.accept(.acknowledged([])); XCTFail("Must reject ack") } catch {}
        XCTAssertTrue(store.committed.isEmpty); XCTAssertEqual(store.paused, [.persistenceFailure])
        XCTAssertFalse(active.active)
    }
    func testStopWhileInboxSuspendedRejectsCommitAndQueuedCheckpoint() async throws {
        let store = Store(); store.suspendInbox = true
        let active = try session(), reducer = SyncCloudDurableEvents(session: active, persistence: store)
        let first = Task { try await reducer.accept(.downloaded([])) }
        try await waitForInbox(store)
        let checkpoint = Task { try await reducer.accept(.state(Data([1]))) }
        active.invalidate(); store.waiting?.resume(); store.waiting = nil
        do { try await first.value; XCTFail("Old session must fail") } catch {}
        do { try await checkpoint.value; XCTFail("Old checkpoint must fail") } catch {}
        XCTAssertTrue(store.committed.isEmpty)
    }
    func testOldGenerationCannotAcknowledgeAndNewSessionStillWorks() async throws {
        let store = Store(), old = try session(), fresh = try session()
        old.invalidate()
        let oldEvents = SyncCloudDurableEvents(session: old, persistence: store)
        let ack = SyncCloudAcknowledgement.mutation(id: UUID(), manifestSHA256: String(repeating: "a", count: 64))
        do { try await oldEvents.accept(.acknowledged([ack])); XCTFail("Old ack must fail") } catch {}
        XCTAssertTrue(store.acknowledgements.isEmpty)
        try await SyncCloudDurableEvents(session: fresh, persistence: store).accept(.acknowledged([ack]))
        XCTAssertEqual(store.acknowledgements, [ack])
    }
    func testPauseReasonsRetainFactsAndFenceLaterState() async throws {
        for reason in [SyncCloudPauseReason.accountChanged, .zoneMissing, .conflict] {
            let store = Store(), active = try session()
            let reducer = SyncCloudDurableEvents(session: active, persistence: store)
            try await reducer.accept(.downloaded([]))
            do { try await reducer.accept(.pause(reason)); XCTFail("Must pause") } catch {}
            do { try await reducer.accept(.state(Data([1]))); XCTFail("Must not advance") } catch {}
            XCTAssertEqual(store.committed, ["inbox"]); XCTAssertEqual(store.paused, [reason])
        }
    }
    func testManifestAckBindsExactMutationAndCanonicalBytes() throws {
        let value = try manifest(dataset: UUID()), upload = SyncCloudUpload.mutation(value)
        XCTAssertEqual(try upload.acknowledgement(), .mutation(id: value.mutation, manifestSHA256: syncDigest(try value.encoded())))
        let record = try upload.makeRecord(dataset: value.dataset)
        XCTAssertEqual(try SyncCloudTransport.download(record, dataset: value.dataset), .mutation(value))
        XCTAssertTrue(SyncCloudTransport.matches(record, try CloudRecordCodec.encode(value)))
        let wrong = try manifest(dataset: value.dataset)
        XCTAssertFalse(SyncCloudTransport.matches(record, try CloudRecordCodec.encode(wrong)))
        record["sha256"] = String(repeating: "0", count: 64) as CKRecordValue
        XCTAssertFalse(SyncCloudTransport.matches(record, try CloudRecordCodec.encode(value)))
        XCTAssertThrowsError(try SyncCloudTransport.download(record, dataset: value.dataset))
    }
    func testWrongDatasetAndBooleanVersionAreRejected() throws {
        let value = try manifest(dataset: UUID())
        XCTAssertThrowsError(try SyncCloudUpload.mutation(value).makeRecord(dataset: UUID()))
        let record = try CloudRecordCodec.encode(value), expected = try CloudRecordCodec.encode(value)
        record["wireVersion"] = NSNumber(value: 2.5)
        XCTAssertFalse(SyncCloudTransport.matches(record, expected))
        record["wireVersion"] = NSNumber(value: true)
        XCTAssertFalse(SyncCloudTransport.matches(record, expected))
        XCTAssertThrowsError(try SyncCloudTransport.download(record, dataset: value.dataset))
    }
    func testChunkAndOriginalUseVerifiedBytesAndDistinctAcknowledgements() throws {
        let bytes = Data("synthetic-media".utf8), dataset = UUID(), descriptor = AssetDescriptor(bytes: Data("synthetic-media".utf8))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SyncTransport-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("immutable"); try bytes.write(to: url)
        let chunk = SyncCloudUpload.payloadChunk(descriptor, url), original = SyncCloudUpload.original(descriptor, url)
        XCTAssertEqual(try SyncCloudTransport.download(chunk.makeRecord(dataset: dataset), dataset: dataset), .payloadChunk(descriptor, bytes))
        XCTAssertEqual(try SyncCloudTransport.download(original.makeRecord(dataset: dataset), dataset: dataset), .original(descriptor, bytes))
        XCTAssertEqual(try chunk.acknowledgement(), .payloadChunk(descriptor))
        XCTAssertEqual(try original.acknowledgement(), .original(descriptor))
        try Data("corrupt".utf8).write(to: url)
        XCTAssertThrowsError(try chunk.makeRecord(dataset: dataset))
        XCTAssertThrowsError(try original.makeRecord(dataset: dataset))
    }
    func testCheckpointPersistenceFailureRetainsInboxAndStopsFurtherCommits() async throws {
        let store = Store(), active = try session()
        let reducer = SyncCloudDurableEvents(session: active, persistence: store)
        try await reducer.accept(.downloaded([])); store.stateFailure = true
        do { try await reducer.accept(.state(Data([1]))); XCTFail("Must fail") } catch {}
        do { try await reducer.accept(.acknowledged([])); XCTFail("Must fence") } catch {}
        XCTAssertEqual(store.committed, ["inbox"]); XCTAssertEqual(store.paused, [.persistenceFailure])
    }
    func testRestoredPendingCannotDeleteOrRecreateLostZones() throws {
        let dataset = UUID(), zone = CloudRecordCodec.zone(dataset: UUID())
        let own = CKRecordZone(zoneID: CloudRecordCodec.zone(dataset: dataset))
        XCTAssertNoThrow(try SyncCloudTransport.validatePending(recordChanges: [.saveRecord(CloudRecordCodec.mutationID(UUID(), dataset: dataset))], databaseChanges: [], dataset: dataset, createZone: false))
        XCTAssertNoThrow(try SyncCloudTransport.validatePending(recordChanges: [], databaseChanges: [.saveZone(own)], dataset: dataset, createZone: true))
        XCTAssertThrowsError(try SyncCloudTransport.validatePending(recordChanges: [], databaseChanges: [.saveZone(own)], dataset: dataset, createZone: false))
        XCTAssertThrowsError(try SyncCloudTransport.validatePending(recordChanges: [], databaseChanges: [.deleteZone(own.zoneID)], dataset: dataset, createZone: true))
        XCTAssertThrowsError(try SyncCloudTransport.validatePending(recordChanges: [], databaseChanges: [.saveZone(CKRecordZone(zoneID: zone))], dataset: dataset, createZone: true))
        XCTAssertThrowsError(try SyncCloudTransport.validatePending(recordChanges: [.deleteRecord(CloudRecordCodec.mutationID(UUID(), dataset: dataset))], databaseChanges: [], dataset: dataset, createZone: false))
        XCTAssertThrowsError(try SyncCloudTransport.validatePending(recordChanges: [.saveRecord(CKRecord.ID(recordName: "foreign", zoneID: zone))], databaseChanges: [], dataset: dataset, createZone: false))
    }
    func testZoneAcknowledgementCommitsBeforeCheckpointAndIsFencedAfterStop() async throws {
        let store = Store(), active = try session()
        let reducer = SyncCloudDurableEvents(session: active, persistence: store)
        try await reducer.accept(.zoneSaved)
        try await reducer.accept(.state(Data([1])))
        active.invalidate()
        do { try await reducer.accept(.zoneSaved); XCTFail("Old zone ACK must fail") } catch {}
        XCTAssertEqual(store.committed, ["zone", "state"])
    }
    func testSigningEnvironmentMismatchFailsBeforeCreatingSession() async throws {
        let transport = SyncCloudTransport(persistence: Store())
        let binding = try session().binding
        do { try await transport.start(binding: binding, signedEnvironment: .production); XCTFail("Must reject") }
        catch { XCTAssertEqual(error as? SyncCloudTransportError, .paused(.environmentMismatch)) }
        XCTAssertNil(transport.session)
    }
    func testExactServerReplayDurablyReceivesBeforeAcknowledgingAndCanRepeat() async throws {
        let store = Store(), active = try session()
        let value = try manifest(dataset: active.binding.dataset), upload = SyncCloudUpload.mutation(value)
        let reducer = SyncCloudDurableEvents(session: active, persistence: store)
        let server = try upload.makeRecord(dataset: active.binding.dataset)
        try await SyncCloudTransport.acceptServerReplay(server, upload: upload, events: reducer)
        try await SyncCloudTransport.acceptServerReplay(server, upload: upload, events: reducer)
        XCTAssertEqual(store.committed, ["inbox", "ack", "inbox", "ack"])
        XCTAssertEqual(store.acknowledgements, [try upload.acknowledgement(), try upload.acknowledgement()])
        XCTAssertTrue(active.active)
    }
    func testSameIDWithDifferentValidManifestIsRetainedButNeverAcknowledged() async throws {
        let store = Store(), active = try session()
        let value = try manifest(dataset: active.binding.dataset)
        let different = try manifest(dataset: active.binding.dataset, mutation: value.mutation)
        let reducer = SyncCloudDurableEvents(session: active, persistence: store)
        do {
            try await SyncCloudTransport.acceptServerReplay(CloudRecordCodec.encode(different), upload: .mutation(value), events: reducer)
            XCTFail("A real identity collision must not ACK")
        } catch {}
        XCTAssertEqual(store.committed, ["inbox"]); XCTAssertTrue(store.acknowledgements.isEmpty)
        XCTAssertEqual(store.paused, [.conflict]); XCTAssertFalse(active.active)
    }
    func testAssetReplayVerifiesActualBytesAndInboxFailureNeverAcknowledges() async throws {
        let store = Store(), active = try session()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SyncReplay-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data("synthetic-replay".utf8), descriptor = AssetDescriptor(bytes: Data("synthetic-replay".utf8))
        let staged = directory.appendingPathComponent("staged"), remote = directory.appendingPathComponent("remote")
        try bytes.write(to: staged); try bytes.write(to: remote)
        let upload = SyncCloudUpload.original(descriptor, staged)
        let server = try CloudRecordCodec.encodeOriginal(descriptor, dataset: active.binding.dataset, url: remote)
        let reducer = SyncCloudDurableEvents(session: active, persistence: store)
        try await SyncCloudTransport.acceptServerReplay(server, upload: upload, events: reducer)
        XCTAssertEqual(store.committed, ["inbox", "ack"])
        try Data("corrupt bytes".utf8).write(to: remote)
        do { try await SyncCloudTransport.acceptServerReplay(server, upload: upload, events: reducer); XCTFail("Bad bytes") } catch {}
        XCTAssertEqual(store.acknowledgements, [.original(descriptor)])
        try bytes.write(to: remote); store.inboxFailure = true
        do { try await SyncCloudTransport.acceptServerReplay(server, upload: upload, events: reducer); XCTFail("Failed inbox") } catch {}
        XCTAssertEqual(store.acknowledgements, [.original(descriptor)]); XCTAssertFalse(active.active)
    }

    func testAssetConflictFetchesOnlyExactRecordAndFencesLateFetch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SyncReplayFetch-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data("synthetic-fetch".utf8), url = directory.appendingPathComponent("bytes")
        try bytes.write(to: url)
        let descriptor = AssetDescriptor(bytes: bytes), store = Store(), active = try session()
        let upload = SyncCloudUpload.payloadChunk(descriptor, url)
        let complete = try upload.makeRecord(dataset: active.binding.dataset)
        let metadataOnly = CKRecord(recordType: complete.recordType, recordID: complete.recordID)
        var requested: [CKRecord.ID] = []
        let reducer = SyncCloudDurableEvents(session: active, persistence: store)
        try await SyncCloudTransport.acceptServerReplay(metadataOnly, upload: upload, events: reducer) { id in
            requested.append(id); return complete
        }
        XCTAssertEqual(requested, [complete.recordID]); XCTAssertEqual(store.committed, ["inbox", "ack"])
        let lateStore = Store(), late = try session()
        let lateRecord = try upload.makeRecord(dataset: late.binding.dataset)
        do {
            try await SyncCloudTransport.acceptServerReplay(lateRecord, upload: upload,
                events: SyncCloudDurableEvents(session: late, persistence: lateStore)) { _ in
                late.invalidate(); return lateRecord
            }
            XCTFail("An invalidated session cannot commit fetched bytes")
        } catch {}
        XCTAssertTrue(lateStore.committed.isEmpty)
        let wrongStore = Store(), wrong = try session()
        let wrongRecord = try upload.makeRecord(dataset: wrong.binding.dataset)
        do {
            try await SyncCloudTransport.acceptServerReplay(wrongRecord, upload: upload,
                events: SyncCloudDurableEvents(session: wrong, persistence: wrongStore)) { _ in complete }
            XCTFail("A fetched record from another dataset must be rejected")
        } catch {}
        XCTAssertTrue(wrongStore.committed.isEmpty)
    }

    func testDirectReplayFetchRechecksAccountBeforeAndAfterExactRead() async throws {
        let active = try session(), record = try CloudRecordCodec.encode(manifest(dataset: active.binding.dataset))
        var events: [String] = []
        let result = try await SyncCloudTransport.fetchReplayRecord(id: record.recordID, session: active,
            currentAccount: { events.append("account"); return active.binding.accountHash },
            fetch: { id in events.append("fetch"); XCTAssertEqual(id, record.recordID); return record })
        XCTAssertEqual(result.recordID, record.recordID)
        XCTAssertEqual(events, ["account", "fetch", "account"])
    }
    func testDirectReplayFetchRejectsObservedAccountSwitchesAndLateInvalidation() async throws {
        // before: no read allowed; after: bytes cannot reach durableInbox/ACK; stop: no later call.
        for phase in ["before", "after", "stop-before", "stop-fetch", "stop-after"] {
            let active = try session(), record = try CloudRecordCodec.encode(manifest(dataset: active.binding.dataset))
            var checks = 0, reads = 0
            do {
                _ = try await SyncCloudTransport.fetchReplayRecord(id: record.recordID, session: active,
                    currentAccount: {
                        checks += 1
                        if phase == "stop-before" || (phase == "stop-after" && checks == 2) { active.invalidate() }
                        if phase == "before" || (phase == "after" && checks == 2) { return String(repeating: "b", count: 64) }
                        return active.binding.accountHash
                    }, fetch: { _ in
                        reads += 1
                        if phase == "stop-fetch" { active.invalidate() }
                        return record
                    })
                XCTFail("Changed identity or invalidated activation must reject: " + phase)
            } catch {}
            XCTAssertEqual(reads, phase == "before" || phase == "stop-before" ? 0 : 1)
            XCTAssertEqual(checks, ["after", "stop-after"].contains(phase) ? 2 : 1)
        }
    }
    func testDirectReplayFetchRejectsForeignDatasetAndWrongRecordID() async throws {
        let active = try session(), record = try CloudRecordCodec.encode(manifest(dataset: active.binding.dataset))
        let wrong = try CloudRecordCodec.encode(manifest(dataset: active.binding.dataset))
        var checks = 0
        do {
            _ = try await SyncCloudTransport.fetchReplayRecord(id: CloudRecordCodec.mutationID(UUID(), dataset: UUID()), session: active,
                currentAccount: { checks += 1; return active.binding.accountHash }, fetch: { _ in record })
            XCTFail("Foreign zone must reject before account call")
        } catch {}
        XCTAssertEqual(checks, 0)
        do {
            _ = try await SyncCloudTransport.fetchReplayRecord(id: record.recordID, session: active,
                currentAccount: { checks += 1; return active.binding.accountHash }, fetch: { _ in wrong })
            XCTFail("Wrong fetched ID must not return")
        } catch {}
        XCTAssertEqual(checks, 1)
    }

}
