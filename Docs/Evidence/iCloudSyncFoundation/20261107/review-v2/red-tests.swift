import XCTest
import CloudKit
import CryptoKit
@testable import SyncFoundation

final class IndependentChunkTests: XCTestCase {
    var root: URL!
    let width = 4 * 1024 * 1024
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("V2Independent-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func write(_ data: Data) throws -> URL {
        let url = root.appendingPathComponent(UUID().uuidString); try data.write(to: url); return url
    }
    func verify(_ manifest: PayloadManifest, _ chunks: [IndexedPayloadChunk]) throws {
        var remaining = chunks.makeIterator()
        try manifest.verifyChunks { remaining.next() }
    }
    func testPrepareRejectsSourceTruncatedDuringEmit() throws {
        let source = try write(Data(repeating: 0x31, count: width * 2))
        var emitted = 0
        XCTAssertThrowsError(try PayloadManifest.prepare(fileURL: source) { index, _, _ in
            emitted += 1
            if index == 0 { let h = try FileHandle(forWritingTo: source); try h.truncate(atOffset: UInt64(self.width)); try h.close() }
        })
        XCTAssertEqual(emitted, 1)
    }
    func testPrepareRejectsSourceGrowthDuringEmit() throws {
        let source = try write(Data(repeating: 0x31, count: width))
        XCTAssertThrowsError(try PayloadManifest.prepare(fileURL: source) { index, _, _ in
            if index == 0 { let h = try FileHandle(forWritingTo: source); try h.seekToEnd(); try h.write(contentsOf: Data([0x32])); try h.close() }
        })
    }
    func testOrderedChunksMissingDuplicateAndExtraAreRejected() throws {
        let a = Data(repeating: 0x41, count: width), b = Data([0x42,0x43])
        let manifest = try PayloadManifest(bytes: a + b)
        let first = IndexedPayloadChunk(index:0,bytes:a), last = IndexedPayloadChunk(index:1,bytes:b)
        XCTAssertNoThrow(try verify(manifest,[first,last]))
        for bad in [[last,first],[first],[first,first],[first,last,last], [IndexedPayloadChunk(index:-1,bytes:a),last]] {
            XCTAssertThrowsError(try verify(manifest,bad))
        }
    }
    func testRepeatedEqualChunksAtDifferentPositionsAreLegal() throws {
        let chunk = Data(repeating: 0x7f, count: width)
        let manifest = try PayloadManifest(bytes: chunk + chunk)
        XCTAssertEqual(manifest.chunks[0],manifest.chunks[1])
        XCTAssertNoThrow(try verify(manifest,[.init(index:0,bytes:chunk),.init(index:1,bytes:chunk)]))
        XCTAssertThrowsError(try verify(manifest,[.init(index:0,bytes:chunk),.init(index:0,bytes:chunk)]))
    }
    func testValidChunkHashesCannotHideWrongWholeHash() throws {
        let a = Data(repeating:0x41,count:width), b = Data([0x42])
        let valid = try PayloadManifest(bytes:a+b)
        let poisoned = try PayloadManifest(total:.init(sha256:String(repeating:"0",count:64),byteCount:width+1),chunks:valid.chunks)
        XCTAssertThrowsError(try verify(poisoned,[.init(index:0,bytes:a),.init(index:1,bytes:b)]))
    }
    func testManifestTotalsAndIndexShapeAreStrict() throws {
        let hash = String(repeating:"a",count:64)
        for bad in [0,-1,Int.max,128*1024*1024+1] {
            XCTAssertThrowsError(try PayloadManifest(total:.init(sha256:hash,byteCount:bad),chunks:[.init(sha256:hash,byteCount:1)]))
        }
        XCTAssertThrowsError(try PayloadManifest(total:.init(sha256:hash,byteCount:width+1),chunks:[.init(sha256:hash,byteCount:1),.init(sha256:hash,byteCount:width)]))
        XCTAssertThrowsError(try PayloadManifest(total:.init(sha256:hash,byteCount:1),chunks:[]))
        let tooMany = Array(repeating:AssetDescriptor(sha256:hash,byteCount:width),count:33)
        XCTAssertThrowsError(try PayloadManifest(total:.init(sha256:hash,byteCount:128*1024*1024),chunks:tooMany))
    }
    func testChunkRecordRoutingTypesIntegrityAndVersionAreStrict() throws {
        let dataset = UUID(), bytes = Data([1,2,3]), desc = AssetDescriptor(bytes:Data([1,2,3]))
        let r = try CloudRecordCodec.encodeChunk(desc,dataset:dataset,url:write(bytes))
        XCTAssertEqual(try CloudRecordCodec.decodeChunk(r,dataset:dataset).1,bytes)
        XCTAssertThrowsError(try CloudRecordCodec.decodeChunk(r,dataset:UUID()))
        r["wireVersion"] = NSNumber(value:true)
        XCTAssertThrowsError(try CloudRecordCodec.decodeChunk(r,dataset:dataset))
        r["wireVersion"] = 2 as CKRecordValue
        r["byteCount"] = 4 as CKRecordValue
        XCTAssertThrowsError(try CloudRecordCodec.decodeChunk(r,dataset:dataset))
        r["byteCount"] = 3 as CKRecordValue
        r["payload"] = "unexpected" as CKRecordValue
        XCTAssertThrowsError(try CloudRecordCodec.decodeChunk(r,dataset:dataset))
    }
    func testStreamPreparesMaximumPayloadWithoutAssemblingIt() throws {
        let source = root.appendingPathComponent("maximum")
        FileManager.default.createFile(atPath:source.path,contents:nil)
        let h = try FileHandle(forWritingTo:source)
        let chunk = Data(repeating:0x5a,count:width)
        for _ in 0..<32 { try h.write(contentsOf:chunk) }
        try h.close()
        var seen = 0, peakChunk = 0
        let manifest = try PayloadManifest.prepare(fileURL:source) { i,d,b in
            XCTAssertEqual(i,seen); XCTAssertEqual(b.count,width); XCTAssertEqual(d.byteCount,width)
            seen += 1; peakChunk = max(peakChunk,b.count)
        }
        XCTAssertEqual(seen,32);XCTAssertEqual(peakChunk,width);XCTAssertEqual(manifest.total.byteCount,134217728)
        var i = 0
        try manifest.verifyChunks {
            guard i<32 else{return nil};defer{i+=1}
            return .init(index:i,bytes:chunk)
        }
    }
}
