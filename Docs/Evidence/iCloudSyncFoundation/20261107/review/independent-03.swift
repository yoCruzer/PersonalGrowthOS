import XCTest
import CloudKit
import Darwin
@testable import SyncFoundation

final class IndependentBoundaryTests: XCTestCase {
    let dataset = UUID(uuidString: "BAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    let mutation = UUID(uuidString: "CAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    let object = try! SyncObject(kind: "Entry", id: UUID(uuidString: "DAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
    let content = Data("SYNTHETIC 独立协议证据".utf8)
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func file(_ data: Data) throws -> URL {
        let url = root.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        return url
    }
    func make() throws -> MutationManifest {
        try MutationManifest(dataset: dataset, mutation: mutation, object: object, payload: AssetDescriptor(bytes: content))
    }
    func testIndependentFixedDigestBytesAndTypedCollision() throws {
        let a = try make(), encoded = try a.encoded()
        XCTAssertEqual(a.payload?.byteCount, 28)
        XCTAssertEqual(a.payload?.sha256, "7c0d97d131313a6c71b14d8773fb557033fe6bca03d48f2e7901e8c643cf379e")
        let alternative = try MutationManifest(dataset: dataset, mutation: mutation,
            object: SyncObject(kind: "Goal", id: object.id), payload: a.payload)
        XCTAssertThrowsError(try alternative.verifyReplay(of: encoded))
        XCTAssertNoThrow(try a.verifyReplay(of: encoded))
    }
    func testReorderCanonicalizesCollectionsButDoesNotRewritePayload() throws {
        let p1 = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let p2 = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let a = try MutationManifest(dataset: dataset, mutation: mutation, object: object, parents: [p1,p2], payload: AssetDescriptor(bytes: content))
        let b = try MutationManifest(dataset: dataset, mutation: mutation, object: object, parents: [p2,p1], payload: AssetDescriptor(bytes: content))
        XCTAssertEqual(try a.encoded(), try b.encoded())
        let record = try CloudRecordCodec.encode(a, payloadURL: file(content))
        XCTAssertEqual(try CloudRecordCodec.decode(record, dataset: dataset).1, content)
    }
    func testForeignOwnerZoneIsRejectedWithSameDatasetAndName() throws {
        let encoded = try CloudRecordCodec.encode(make(), payloadURL: file(content))
        let foreign = CKRecord(recordType: encoded.recordType, recordID: CKRecord.ID(recordName: encoded.recordID.recordName,
            zoneID: CKRecordZone.ID(zoneName: encoded.recordID.zoneID.zoneName, ownerName: "foreign-owner")))
        for key in encoded.allKeys() {
            if let asset = encoded[key] as? CKAsset { foreign[key] = CKAsset(fileURL: try XCTUnwrap(asset.fileURL)) }
            else { foreign[key] = encoded[key] }
        }
        XCTAssertThrowsError(try CloudRecordCodec.decode(foreign, dataset: dataset))
    }
    func testHardLimitsUseActualFileSizeNotAdvertisedMetadata() throws {
        let url = try file(content)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(SyncLimits.payloadBytes + 1)); try handle.close()
        XCTAssertThrowsError(try CloudRecordCodec.encode(make(), payloadURL: url))
        let image = CKRecord(recordType: CloudRecordCodec.originalType, recordID: CloudRecordCodec.originalID(syncDigest(content), dataset: dataset))
        image["wireVersion"] = 1 as CKRecordValue; image["sha256"] = syncDigest(content) as CKRecordValue
        image["byteCount"] = content.count as CKRecordValue; image["original"] = CKAsset(fileURL: url)
        XCTAssertThrowsError(try CloudRecordCodec.decodeOriginal(image, dataset: dataset))
    }
    func testSpecialFileDoesNotHangAndFileSchemeRequired() throws {
        let fifo = root.appendingPathComponent("fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertThrowsError(try CloudRecordCodec.encode(make(), payloadURL: fifo))
        XCTAssertThrowsError(try CloudRecordCodec.encode(make(), payloadURL: URL(string: "https://example.invalid/payload")!))
    }
    func testIntegerOverflowNegativeAndIntegralFloatRejected() throws {
        for number in [NSNumber(value: UInt64.max), NSNumber(value: -1), NSNumber(value: 1.0)] {
            let r = try CloudRecordCodec.encode(make(), payloadURL: file(content))
            r["wireVersion"] = number
            XCTAssertThrowsError(try CloudRecordCodec.decode(r, dataset: dataset))
        }
    }
    func testUnknownNestedFieldAndNullOptionAreRejected() throws {
        let original = try make().encoded()
        var json = try JSONSerialization.jsonObject(with: original) as! [String:Any]
        var payload = json["payload"] as! [String:Any]
        payload["deviceID"] = "forbidden"; json["payload"] = payload
        XCTAssertThrowsError(try MutationManifest.decode(JSONSerialization.data(withJSONObject: json, options: [.sortedKeys,.withoutEscapingSlashes])))
        json = try JSONSerialization.jsonObject(with: original) as! [String:Any]
        json["wireVersion"] = true
        XCTAssertThrowsError(try MutationManifest.decode(JSONSerialization.data(withJSONObject: json, options: [.sortedKeys,.withoutEscapingSlashes])))
    }
    @MainActor func testEveryRoutingDimensionAndInstanceHasFenceBoundary() throws {
        let a = try SyncBinding(container: "iCloud.com.synthetic.A", environment: .development,
            accountHash: syncDigest(Data([1])), dataset: dataset, generation: mutation)
        let original = SyncEpochFence(binding: a), ticket = try original.ticket()
        for b in [
            try SyncBinding(container: "iCloud.com.synthetic.B", environment: a.environment, accountHash: a.accountHash, dataset: a.dataset, generation: a.generation),
            try SyncBinding(container: a.container, environment: .production, accountHash: a.accountHash, dataset: a.dataset, generation: a.generation),
            try SyncBinding(container: a.container, environment: a.environment, accountHash: syncDigest(Data([2])), dataset: a.dataset, generation: a.generation),
            try SyncBinding(container: a.container, environment: a.environment, accountHash: a.accountHash, dataset: UUID(), generation: a.generation),
            try SyncBinding(container: a.container, environment: a.environment, accountHash: a.accountHash, dataset: a.dataset, generation: UUID()), a
        ] { XCTAssertThrowsError(try SyncEpochFence(binding: b).check(ticket)) }
        XCTAssertNoThrow(try original.check(ticket)); original.invalidate()
        XCTAssertThrowsError(try original.check(ticket))
    }
}
