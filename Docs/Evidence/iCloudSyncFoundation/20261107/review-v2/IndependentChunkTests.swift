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
    func fileDescriptor(_ url: URL) throws -> AssetDescriptor {
        let handle = try FileHandle(forReadingFrom:url);defer{try? handle.close()}
        var hash = SHA256(),count = 0
        while let bytes = try handle.read(upToCount:4*1024*1024),!bytes.isEmpty {hash.update(data:bytes);count+=bytes.count}
        return AssetDescriptor(sha256:hash.finalize().map{String(format:"%02x",$0)}.joined(),byteCount:count)
    }
    func verify(_ manifest: PayloadManifest, _ chunks: [IndexedPayloadChunk]) throws {
        var remaining = chunks.makeIterator()
        try manifest.verifyChunks { remaining.next() }
    }
    func testPrepareRejectsSourceTruncatedDuringEmit() throws {
        let source = try write(Data(repeating: 0x31, count: width * 2))
        var emitted = 0
        XCTAssertThrowsError(try PayloadManifest.prepare(fileURL: source, expected: try fileDescriptor(source)) { index, _, _ in
            emitted += 1
            if index == 0 { let h = try FileHandle(forWritingTo: source); try h.truncate(atOffset: UInt64(self.width)); try h.close() }
        })
        XCTAssertEqual(emitted, 1)
    }
    func testPrepareRejectsSourceGrowthDuringEmit() throws {
        let source = try write(Data(repeating: 0x31, count: width))
        XCTAssertThrowsError(try PayloadManifest.prepare(fileURL: source, expected: try fileDescriptor(source)) { index, _, _ in
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
        let manifest = try PayloadManifest.prepare(fileURL:source, expected: AssetDescriptor(sha256:"5a3575e72eb2283ba32069397852008f571119c98e9ce9973ff12e50b0ff7cdb",byteCount:134217728)) { i,d,b in
            XCTAssertEqual(i,seen); XCTAssertEqual(b.count,width); XCTAssertEqual(d.byteCount,width)
            seen += 1; peakChunk = max(peakChunk,b.count)
        }
        XCTAssertEqual(seen,32);XCTAssertEqual(peakChunk,width);XCTAssertEqual(manifest.total.byteCount,134217728)
        XCTAssertEqual(manifest.total.sha256,"5a3575e72eb2283ba32069397852008f571119c98e9ce9973ff12e50b0ff7cdb")
        var i = 0
        try manifest.verifyChunks {
            guard i<32 else{return nil};defer{i+=1}
            return .init(index:i,bytes:chunk)
        }
    }
    func testPrepareRejectsSameSizeSourceRewriteDuringEmit() throws {
        let source = try write(Data(repeating: 0x31, count: width * 2))
        XCTAssertThrowsError(try PayloadManifest.prepare(fileURL: source, expected: try fileDescriptor(source)) { index, _, _ in
            if index == 0 { let h = try FileHandle(forWritingTo: source); try h.seek(toOffset: UInt64(self.width)); try h.write(contentsOf: Data([0x32])); try h.close() }
        })
    }
    func testStreamingOneChunkMemoryBaseline() throws {
        let chunk = Data(repeating:0x5a,count:width),source = try write(Data(repeating:0x5a,count:width))
        let manifest = try PayloadManifest.prepare(fileURL:source, expected: try fileDescriptor(source)) { _,_,b in XCTAssertEqual(b.count,self.width) }
        var used = false
        try manifest.verifyChunks { if used{return nil};used=true;return .init(index:0,bytes:chunk) }
    }
    func testActualV16MaximumLegalPayloadHasTwelveChunksAndExactReplay() throws {
        let source = URL(fileURLWithPath:"/private/tmp/pgos-sync-v16-capacity-20261107/actual-v16-payload.json")
        let dataset = UUID()
        var paths: [String:URL] = [:]
        let manifest = try PayloadManifest.prepare(fileURL:source, expected: try fileDescriptor(source)) { _,descriptor,bytes in
            let url = try self.write(bytes)
            paths[descriptor.sha256] = url
            let encoded = try CloudRecordCodec.encodeChunk(descriptor,dataset:dataset,url:url)
            let decoded = try CloudRecordCodec.decodeChunk(encoded,dataset:dataset)
            XCTAssertEqual(decoded.0,descriptor);XCTAssertEqual(decoded.1,bytes)
        }
        XCTAssertEqual(manifest.total.byteCount,49_190_297)
        XCTAssertEqual(manifest.total.sha256,"9e97f46caef1fb89babb217a5cb7e25ee223beec74d6ce71408f211672fb9b13")
        XCTAssertEqual(manifest.chunks.count,12)
        let output = root.appendingPathComponent("replayed")
        FileManager.default.createFile(atPath:output.path,contents:nil)
        let writer = try FileHandle(forWritingTo:output)
        var index = 0
        try manifest.verifyChunks {
            guard index<manifest.chunks.count else{return nil}
            let descriptor = manifest.chunks[index]
            let bytes = try Data(contentsOf:XCTUnwrap(paths[descriptor.sha256]))
            try writer.write(contentsOf:bytes)
            defer{index+=1}
            return .init(index:index,bytes:bytes)
        }
        try writer.close()
        let a = try FileHandle(forReadingFrom:source), b = try FileHandle(forReadingFrom:output)
        defer{try? a.close();try? b.close()}
        while let left = try a.read(upToCount:width),!left.isEmpty {
            XCTAssertEqual(left,try b.read(upToCount:width))
        }
        XCTAssertEqual(try b.read(upToCount:1)?.count ?? 0,0)
    }

    func testExpectedDescriptorRejectsSourceChangedBeforePreparation() throws {
        let source = try write(Data(repeating:0x61,count:width))
        let expected = try fileDescriptor(source)
        try Data(repeating:0x62,count:width).write(to:source)
        XCTAssertThrowsError(try PayloadManifest.prepare(fileURL:source,expected:expected){_,_,_ in})
        let wrongSize = AssetDescriptor(sha256:expected.sha256,byteCount:width+1)
        var calls = 0
        XCTAssertThrowsError(try PayloadManifest.prepare(fileURL:source,expected:wrongSize){_,_,_ in calls+=1})
        XCTAssertEqual(calls,0)
    }

}
