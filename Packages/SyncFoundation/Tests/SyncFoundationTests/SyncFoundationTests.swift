import XCTest
import CloudKit
@testable import SyncFoundation

final class SyncFoundationTests: XCTestCase {
    let dataset = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let objectID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let mutationID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    let payload = Data("{\"amountMinor\":123,\"unknown\":null}".utf8)
    var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("SyncFoundationTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func write(_ bytes: Data, name: String = UUID().uuidString) throws -> URL {
        let url = directory.appendingPathComponent(name); try bytes.write(to: url); return url
    }
    func manifest(bytes: Data? = nil, originals: [OriginalReference] = []) throws -> MutationManifest {
        try MutationManifest(dataset: dataset, mutation: mutationID,
                             object: SyncObject(kind: "NetWorthSnapshot", id: objectID),
                             payload: AssetDescriptor(bytes: bytes ?? payload), originals: originals)
    }
    func record() throws -> CKRecord { try CloudRecordCodec.encode(manifest(), payloadURL: write(payload)) }
    func json(_ bytes: Data, change: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        change(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    func copy(_ record: CKRecord, type: String? = nil, id: CKRecord.ID? = nil) -> CKRecord {
        let other = CKRecord(recordType: type ?? record.recordType, recordID: id ?? record.recordID)
        for key in record.allKeys() {
            if let asset = record[key] as? CKAsset, let url = asset.fileURL { other[key] = CKAsset(fileURL: url) }
            else { other[key] = record[key] }
        }
        return other
    }

    func testManifestAndSDKRecordRoundTripPreserveExactBytes() throws {
        let value = try manifest()
        XCTAssertEqual(try MutationManifest.decode(value.encoded()), value)
        let (decoded, bytes) = try CloudRecordCodec.decode(record(), dataset: dataset)
        XCTAssertEqual(decoded, value); XCTAssertEqual(bytes, payload)
        XCTAssertEqual(Set(try record().allKeys()), Set(CloudRecordCodec.mutationFields.keys))
    }
    func testTenThousandLineSnapshotUsesAssetNotInlineRecordBytes() throws {
        let rows = (0..<10_000).map { ["itemID": String($0), "amountMinor": "123456789", "state": "confirmed", "category": "synthetic-bank"] }
        let bytes = try JSONSerialization.data(withJSONObject: ["lines": rows], options: [.sortedKeys])
        XCTAssertGreaterThan(bytes.count, 262_144)
        let value = try manifest(bytes: bytes)
        let encoded = try CloudRecordCodec.encode(value, payloadURL: write(bytes))
        XCTAssertLessThan(try XCTUnwrap(encoded["manifest"] as? Data).count, 1_024)
        XCTAssertTrue(encoded["payload"] is CKAsset)
        XCTAssertEqual(try CloudRecordCodec.decode(encoded, dataset: dataset).1, bytes)
    }
    func testTwentyFiveMiBOriginalRoundTripAndCompleteNineImageManifest() throws {
        let bytes = Data(repeating: 0xA7, count: SyncLimits.originalBytes)
        let descriptor = AssetDescriptor(bytes: bytes)
        let encoded = try CloudRecordCodec.encodeOriginal(descriptor, dataset: dataset, url: write(bytes))
        let decoded = try CloudRecordCodec.decodeOriginal(encoded, dataset: dataset)
        XCTAssertEqual(decoded.0, descriptor); XCTAssertEqual(decoded.1, bytes)
        let small = Data([1, 2, 3])
        let originals = (0..<9).map { _ in OriginalReference(id: UUID(), asset: AssetDescriptor(bytes: small)) }
        let value = try manifest(originals: originals)
        XCTAssertNoThrow(try value.verifyAssetsComplete(payload: payload) { _ in small })
        XCTAssertThrowsError(try value.verifyAssetsComplete(payload: payload) { _ in Data([3, 2, 1]) })
    }
    func testMediaMissingTruncatedAndWrongHashAreNotComplete() throws {
        let original = OriginalReference(id: UUID(), asset: AssetDescriptor(bytes: Data([1, 2, 3])))
        let value = try manifest(originals: [original])
        XCTAssertThrowsError(try value.verifyAssetsComplete(payload: nil) { _ in Data([1, 2, 3]) })
        XCTAssertThrowsError(try value.verifyAssetsComplete(payload: payload) { _ in throw SyncValidationError.missingAsset })
        XCTAssertThrowsError(try value.verifyAssetsComplete(payload: payload) { _ in Data([1, 2]) })
        XCTAssertThrowsError(try value.verifyAssetsComplete(payload: Data([0])) { _ in Data([1, 2, 3]) })
    }
    func testIdentityReplayAcceptsExactAndRejectsChangedBytes() throws {
        let original = try manifest()
        XCTAssertNoThrow(try original.verifyReplay(of: original.encoded()))
        let changed = try manifest(bytes: Data([1]))
        XCTAssertThrowsError(try changed.verifyReplay(of: original.encoded()))
        let otherDataset = try MutationManifest(dataset: UUID(), mutation: mutationID, object: original.object, payload: original.payload)
        XCTAssertThrowsError(try otherDataset.verifyReplay(of: original.encoded()))
    }
    func testHistoryBeyond512DoesNotGrowCurrentRecord() throws {
        var previous: UUID?
        for _ in 0..<600 {
            let value = try MutationManifest(dataset: dataset, mutation: UUID(), object: SyncObject(kind: "Entry", id: objectID),
                parents: previous.map { [$0] } ?? [], payload: AssetDescriptor(bytes: payload))
            XCTAssertLessThan(try value.encoded().count, 1_024)
            previous = value.mutation
        }
    }
    func testTombstoneRoundTripNeedsNoDeletedDependenciesOrAssets() throws {
        let value = try MutationManifest(dataset: dataset, mutation: mutationID, object: SyncObject(kind: "Entry", id: objectID),
                                         parents: [UUID()], deleted: true)
        let result = try CloudRecordCodec.decode(CloudRecordCodec.encode(value, payloadURL: nil), dataset: dataset)
        XCTAssertEqual(result.0, value); XCTAssertNil(result.1)
        XCTAssertNoThrow(try value.verifyAssetsComplete(payload: nil) { _ in XCTFail("no original required"); return Data() })
        XCTAssertThrowsError(try CloudRecordCodec.encode(value, payloadURL: write(payload)))
        XCTAssertThrowsError(try MutationManifest(dataset: dataset, mutation: mutationID, object: value.object, deleted: true, payload: AssetDescriptor(bytes: payload)))
        XCTAssertThrowsError(try MutationManifest(dataset: dataset, mutation: mutationID, object: value.object, dependencies: [SyncObject(kind: "Entry", id: UUID())], deleted: true))
    }
    func testUnknownVersionUnknownKeysAndNoncanonicalBytesRejected() throws {
        let bytes = try manifest().encoded()
        for altered in [try json(bytes) { $0["wireVersion"] = 2 }, try json(bytes) { $0["accountHash"] = "private" }, Data(" ".utf8) + bytes] {
            XCTAssertThrowsError(try MutationManifest.decode(altered))
        }
    }
    func testDuplicateSelfAndUnsortedParentsRejected() throws {
        let value = try manifest(), parent = UUID()
        XCTAssertThrowsError(try MutationManifest(dataset: dataset, mutation: mutationID, object: value.object, parents: [parent, parent], payload: value.payload))
        XCTAssertThrowsError(try MutationManifest(dataset: dataset, mutation: mutationID, object: value.object, parents: [mutationID], payload: value.payload))
        let sorted = try MutationManifest(dataset: dataset, mutation: mutationID, object: value.object, parents: [UUID(), UUID()], payload: value.payload)
        let altered = try json(sorted.encoded()) { $0["parents"] = ($0["parents"] as! [String]).reversed().map { $0 } }
        XCTAssertThrowsError(try MutationManifest.decode(altered))
    }
    func testDependenciesAndMediaIdentityAreStrict() throws {
        let value = try manifest(), dependency = try SyncObject(kind: "Entry", id: UUID())
        XCTAssertThrowsError(try MutationManifest(dataset: dataset, mutation: mutationID, object: value.object, dependencies: [dependency, dependency], payload: value.payload))
        XCTAssertThrowsError(try MutationManifest(dataset: dataset, mutation: mutationID, object: value.object, dependencies: [value.object], payload: value.payload))
        XCTAssertThrowsError(try SyncObject(kind: "../Entry", id: objectID))
        let ref = OriginalReference(id: UUID(), asset: AssetDescriptor(bytes: Data([1])))
        XCTAssertThrowsError(try manifest(originals: [ref, ref]))
        let conflicting = OriginalReference(id: UUID(), asset: AssetDescriptor(sha256: ref.asset.sha256, byteCount: 2))
        XCTAssertThrowsError(try manifest(originals: [ref, conflicting]))
    }
    func testCrossDatasetRecordTypeNameAndZoneRejected() throws {
        let original = try record()
        XCTAssertThrowsError(try CloudRecordCodec.decode(original, dataset: UUID()))
        XCTAssertThrowsError(try CloudRecordCodec.decode(copy(original, type: "Unexpected"), dataset: dataset))
        let wrongID = CKRecord.ID(recordName: "mutation-" + UUID().uuidString.lowercased(), zoneID: original.recordID.zoneID)
        XCTAssertThrowsError(try CloudRecordCodec.decode(copy(original, id: wrongID), dataset: dataset))
        let wrongZone = CKRecord.ID(recordName: original.recordID.recordName, zoneID: CloudRecordCodec.zone(dataset: UUID()))
        XCTAssertThrowsError(try CloudRecordCodec.decode(copy(original, id: wrongZone), dataset: dataset))
    }
    func testTamperedManifestDigestExtraFieldsAndPayloadRejected() throws {
        var candidate = try record(); candidate["sha256"] = String(repeating: "0", count: 64) as CKRecordValue
        XCTAssertThrowsError(try CloudRecordCodec.decode(candidate, dataset: dataset))
        candidate = try record(); candidate["accountHash"] = "private" as CKRecordValue
        XCTAssertThrowsError(try CloudRecordCodec.decode(candidate, dataset: dataset))
        candidate = try record(); candidate["payload"] = CKAsset(fileURL: try write(Data(repeating: 0, count: payload.count)))
        XCTAssertThrowsError(try CloudRecordCodec.decode(candidate, dataset: dataset))
        candidate = try record(); candidate["payload"] = nil
        XCTAssertThrowsError(try CloudRecordCodec.decode(candidate, dataset: dataset))
    }
    func testFractionalAndBooleanIntegersRejected() throws {
        for value in [NSNumber(value: true), NSNumber(value: 1.5)] {
            let candidate = try record(); candidate["wireVersion"] = value
            XCTAssertThrowsError(try CloudRecordCodec.decode(candidate, dataset: dataset))
        }
        let bytes = Data([1]), descriptor = AssetDescriptor(bytes: Data([1]))
        let image = try CloudRecordCodec.encodeOriginal(descriptor, dataset: dataset, url: write(bytes))
        image["byteCount"] = NSNumber(value: true)
        XCTAssertThrowsError(try CloudRecordCodec.decodeOriginal(image, dataset: dataset))
    }
    func testOriginalRecordIntegrityAndRouting() throws {
        let bytes = Data([1, 2, 3]), descriptor = AssetDescriptor(bytes: Data([1, 2, 3]))
        let image = try CloudRecordCodec.encodeOriginal(descriptor, dataset: dataset, url: write(bytes))
        XCTAssertThrowsError(try CloudRecordCodec.decodeOriginal(image, dataset: UUID()))
        image["byteCount"] = 2 as CKRecordValue
        XCTAssertThrowsError(try CloudRecordCodec.decodeOriginal(image, dataset: dataset))
        image["byteCount"] = 3 as CKRecordValue
        image["original"] = CKAsset(fileURL: try write(Data([1, 2])))
        XCTAssertThrowsError(try CloudRecordCodec.decodeOriginal(image, dataset: dataset))
    }
    func testLimitsRejectInsteadOfTruncating() throws {
        let object = try SyncObject(kind: "Entry", id: objectID)
        for count in [0, SyncLimits.payloadBytes + 1] {
            XCTAssertThrowsError(try MutationManifest(dataset: dataset, mutation: mutationID, object: object,
                payload: AssetDescriptor(sha256: syncDigest(payload), byteCount: count)))
        }
        XCTAssertThrowsError(try MutationManifest(dataset: dataset, mutation: mutationID, object: object,
            parents: (0...SyncLimits.parents).map { _ in UUID() }, payload: AssetDescriptor(bytes: payload)))
        XCTAssertThrowsError(try MutationManifest.decode(Data(repeating: 0, count: SyncLimits.manifestBytes + 1)))
        let oversized = OriginalReference(id: UUID(), asset: AssetDescriptor(sha256: syncDigest(payload), byteCount: SyncLimits.originalBytes + 1))
        XCTAssertThrowsError(try manifest(originals: [oversized]))
    }
    func testAssetPathValidationAndMutationAfterEncodingDetected() throws {
        let url = try write(payload), link = directory.appendingPathComponent("symlink")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        XCTAssertThrowsError(try CloudRecordCodec.encode(manifest(), payloadURL: link))
        XCTAssertThrowsError(try CloudRecordCodec.encode(manifest(), payloadURL: directory))
        XCTAssertThrowsError(try CloudRecordCodec.encode(manifest(), payloadURL: directory.appendingPathComponent("absent")))
        let value = try CloudRecordCodec.encode(manifest(), payloadURL: url)
        try Data([0]).write(to: url)
        XCTAssertThrowsError(try CloudRecordCodec.decode(value, dataset: dataset))
    }
    @MainActor func testEpochFenceRejectsOldCallbacksAndReopenedBinding() throws {
        let binding = try SyncBinding(container: "iCloud.com.example.Test", environment: .development,
            accountHash: syncDigest(Data("synthetic-A".utf8)), dataset: dataset, generation: UUID())
        let a = SyncEpochFence(binding: binding), ticket = try a.ticket()
        XCTAssertNoThrow(try a.check(ticket))
        let bBinding = try SyncBinding(container: binding.container, environment: .production,
            accountHash: syncDigest(Data("synthetic-B".utf8)), dataset: dataset, generation: binding.generation)
        let b = SyncEpochFence(binding: bBinding)
        XCTAssertThrowsError(try b.check(ticket))
        a.invalidate(); XCTAssertThrowsError(try a.check(ticket)); XCTAssertThrowsError(try a.ticket())
        let reopened = SyncEpochFence(binding: binding)
        XCTAssertThrowsError(try reopened.check(ticket))
        XCTAssertNoThrow(try reopened.check(reopened.ticket()))
    }
    func testWireContainsNoLocalAccountOrEngineState() throws {
        let bytes = try manifest().encoded(), object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["wireVersion", "payloadVersion", "dataset", "mutation", "object", "parents", "dependencies", "deleted", "payload", "originals"]))
        XCTAssertThrowsError(try SyncBinding(container: "bad", environment: .development, accountHash: "bad", dataset: dataset, generation: UUID()))
    }
}
