import XCTest
import CloudKit
import CryptoKit
@testable import SyncFoundation

final class PayloadChunkTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PayloadChunkTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func file(_ data: Data, name: String = UUID().uuidString) throws -> URL {
        let url = root.appendingPathComponent(name); try data.write(to: url); return url
    }
    func testFortyMiBPlusTenThousandRowShapeStreamsThroughRealSDKChunks() throws {
        let url = try file(Data("{\"items\":[".utf8))
        let writer = try FileHandle(forWritingTo: url); try writer.seekToEnd()
        var oracle = SHA256(); oracle.update(data: Data("{\"items\":[".utf8))
        for index in 0..<10_000 {
            // Mirrors production snapshot-item shape; product validation is a separate independent probe.
            let row: [String: Any] = ["id": String(format: "00000000-0000-0000-0000-%012d", index),
                "name": String(repeating: "资", count: 160), "side": "asset", "category": "cash",
                "ownership": String(repeating: "家", count: 80), "included": true, "cents": 100,
                "state": "entered", "amountDay": "2026-11-07", "note": String(repeating: "😀", count: 1000), "pending": false]
            var bytes = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])
            if index > 0 { bytes.insert(0x2C, at: 0) }
            try writer.write(contentsOf: bytes); oracle.update(data: bytes)
        }
        let suffix = Data("],\"version\":1,\"day\":\"2026-11-07\",\"timeZoneID\":\"Asia/Shanghai\"}".utf8)
        try writer.write(contentsOf: suffix); oracle.update(data: suffix); try writer.close()
        let sourceSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int
        let expected = AssetDescriptor(sha256: oracle.finalize().map { String(format: "%02x", $0) }.joined(), byteCount: sourceSize)
        let dataset = UUID(); var records: [CKRecord] = []; var maximumCallbackBytes = 0
        let plan = try PayloadManifest.prepare(fileURL: url, expected: expected) { index, descriptor, bytes in
            maximumCallbackBytes = max(maximumCallbackBytes, bytes.count)
            records.append(try CloudRecordCodec.encodeChunk(descriptor, dataset: dataset, url: file(bytes, name: "chunk-\(index)")))
        }
        XCTAssertGreaterThan(plan.total.byteCount, 40 * 1024 * 1024)
        XCTAssertLessThanOrEqual(maximumCallbackBytes, SyncLimits.chunkBytes)
        XCTAssertEqual(plan.total.sha256, expected.sha256)
        var next = 0
        try plan.verifyChunks {
            guard next < records.count else { return nil }
            defer { next += 1 }
            return IndexedPayloadChunk(index: next, bytes: try CloudRecordCodec.decodeChunk(records[next], dataset: dataset).1)
        }
        let manifest = try MutationManifest(dataset: dataset, mutation: UUID(), object: SyncObject(kind: "NetWorthSnapshot", id: UUID()), payload: plan)
        let record = try CloudRecordCodec.encode(manifest)
        XCTAssertLessThan(try manifest.encoded().count, 10_000)
        XCTAssertNil(record["payload"])
        XCTAssertEqual(try CloudRecordCodec.decode(record, dataset: dataset), manifest)
        print("CHUNK_CAPACITY totalBytes=\(plan.total.byteCount) chunkCount=\(plan.chunks.count) maxCallbackBytes=\(maximumCallbackBytes)")
    }
    func testMissingReorderedDuplicateAndExtraIndicesReject() throws {
        let first = Data(repeating: 1, count: SyncLimits.chunkBytes), last = Data([2, 3])
        let plan = try PayloadManifest(bytes: first + last)
        let valid = [IndexedPayloadChunk(index: 0, bytes: first), IndexedPayloadChunk(index: 1, bytes: last)]
        for sequence in [Array(valid.prefix(1)), [valid[1], valid[0]], [valid[0], valid[0]], valid + [valid[1]]] {
            var cursor = 0
            XCTAssertThrowsError(try plan.verifyChunks {
                guard cursor < sequence.count else { return nil }; defer { cursor += 1 }; return sequence[cursor]
            })
        }
        var cursor = 0
        XCTAssertNoThrow(try plan.verifyChunks {
            guard cursor < valid.count else { return nil }; defer { cursor += 1 }; return valid[cursor]
        })
    }
    func testRepeatedContentAtDistinctPositionsIsLegal() throws {
        let chunk = Data(repeating: 7, count: SyncLimits.chunkBytes)
        let plan = try PayloadManifest(bytes: chunk + chunk)
        XCTAssertEqual(plan.chunks[0], plan.chunks[1])
        var cursor = 0
        XCTAssertNoThrow(try plan.verifyChunks {
            guard cursor < 2 else { return nil }; defer { cursor += 1 }; return IndexedPayloadChunk(index: cursor, bytes: chunk)
        })
    }
    func testWholeDigestAndPerChunkDigestAreBothRequired() throws {
        let bytes = Data([1, 2, 3]), plan = try PayloadManifest(bytes: Data([1, 2, 3]))
        let wrongTotal = try PayloadManifest(total: AssetDescriptor(sha256: syncDigest(Data([3, 2, 1])), byteCount: 3), chunks: plan.chunks)
        XCTAssertThrowsError(try wrongTotal.verify(bytes: bytes))
        let wrongChunk = try PayloadManifest(total: plan.total, chunks: [AssetDescriptor(bytes: Data([3, 2, 1]))])
        XCTAssertThrowsError(try wrongChunk.verify(bytes: bytes))
        XCTAssertThrowsError(try plan.verify(bytes: Data([1, 2])))
        XCTAssertThrowsError(try plan.verify(bytes: Data([1, 2, 3, 4])))
    }
    func testChunkBoundaryAndBudgetRejectBeforeUnboundedRead() throws {
        for count in [1, SyncLimits.chunkBytes, SyncLimits.chunkBytes + 1] {
            let bytes = Data(repeating: 1, count: count), plan = try PayloadManifest(bytes: Data(repeating: 1, count: count))
            XCTAssertEqual(plan.chunks.count, (count + SyncLimits.chunkBytes - 1) / SyncLimits.chunkBytes)
            XCTAssertNoThrow(try plan.verify(bytes: bytes))
        }
        let url = try file(Data([0]))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(SyncLimits.payloadBytes + 1)); try handle.close()
        var emitted = false
        XCTAssertThrowsError(try PayloadManifest.prepare(fileURL: url, expected: AssetDescriptor(sha256: syncDigest(Data([0])), byteCount: SyncLimits.payloadBytes + 1)) { _, _, _ in emitted = true })
        XCTAssertFalse(emitted)
        XCTAssertThrowsError(try PayloadManifest(total: AssetDescriptor(sha256: syncDigest(Data([1])), byteCount: 2), chunks: [AssetDescriptor(bytes: Data([1]))]))
        let chunk = AssetDescriptor(sha256: syncDigest(Data([1])), byteCount: SyncLimits.chunkBytes)
        let total = AssetDescriptor(sha256: syncDigest(Data([1])), byteCount: SyncLimits.payloadBytes)
        XCTAssertNoThrow(try PayloadManifest(total: total, chunks: Array(repeating: chunk, count: SyncLimits.payloadChunks)))
        XCTAssertThrowsError(try PayloadManifest(total: total, chunks: Array(repeating: chunk, count: SyncLimits.payloadChunks + 1)))
    }
    func testChunkSDKRoutingTruncationAndUnknownFieldsReject() throws {
        let data = Data([1, 2, 3]), dataset = UUID()
        let record = try CloudRecordCodec.encodeChunk(AssetDescriptor(bytes: data), dataset: dataset, url: file(data))
        XCTAssertThrowsError(try CloudRecordCodec.decodeChunk(record, dataset: UUID()))
        record["byteCount"] = 2 as CKRecordValue
        XCTAssertThrowsError(try CloudRecordCodec.decodeChunk(record, dataset: dataset))
        record["byteCount"] = 3 as CKRecordValue; record["extra"] = "unknown" as CKRecordValue
        XCTAssertThrowsError(try CloudRecordCodec.decodeChunk(record, dataset: dataset))
        record["extra"] = nil; record["chunk"] = CKAsset(fileURL: try file(Data([1, 2])))
        XCTAssertThrowsError(try CloudRecordCodec.decodeChunk(record, dataset: dataset))
    }
}
