import XCTest
import Foundation
import Darwin
import FormalProbeCore

final class IndependentDirectoryReviewTests: XCTestCase {
    func isolated() throws -> URL {
        let u=URL(fileURLWithPath:"/private/tmp/PGOS-DirectoryReview-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:u,withIntermediateDirectories:false); return u
    }
    func testSearchAncestorsAndReadableLeafRoundTrip() throws {
        let root=try isolated();let a=try ProbeDirectory(root.appendingPathComponent("a"),create:true)
        try a.write("one.json",bytes:Data("synthetic".utf8));XCTAssertEqual(try a.read("one.json"),Data("synthetic".utf8))
        try a.verifyNames(["one.json"]);try a.requirePathBinding()
        let b=try ProbeDirectory(a.url.appendingPathComponent("b"),create:true);try b.write("two",bytes:Data([2]));XCTAssertEqual(try b.read("two"),Data([2]))
    }
    func testSymlinkAncestorCannotBeFollowed() throws {
        let root=try isolated();let target=root.appendingPathComponent("real");try FileManager.default.createDirectory(at:target,withIntermediateDirectories:false)
        let link=root.appendingPathComponent("link");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:target)
        XCTAssertThrowsError(try ProbeDirectory(link.appendingPathComponent("child"),create:true));XCTAssertFalse(FileManager.default.fileExists(atPath:target.appendingPathComponent("child").path))
    }
    func testSymlinkLeafAndFileCannotBeFollowed() throws {
        let root=try isolated();let target=try ProbeDirectory(root.appendingPathComponent("real"),create:true);try target.write("sentinel",bytes:Data([7]))
        let link=root.appendingPathComponent("link");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:target.url)
        XCTAssertThrowsError(try ProbeDirectory(link,create:false));XCTAssertThrowsError(try ProbeDirectory(link,create:true))
        try FileManager.default.createSymbolicLink(at:target.url.appendingPathComponent("alias"),withDestinationURL:target.url.appendingPathComponent("sentinel"))
        XCTAssertThrowsError(try target.read("alias"));XCTAssertThrowsError(try target.assetURL("alias"));XCTAssertEqual(try target.read("sentinel"),Data([7]))
    }
    func testAncestorReplacementDetectedAndWritesStayOnHeldFD() throws {
        let root=try isolated();let parent=root.appendingPathComponent("parent");try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:false)
        let held=try ProbeDirectory(parent.appendingPathComponent("output"),create:true)
        try FileManager.default.moveItem(at:parent,to:root.appendingPathComponent("moved"));try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:false)
        let replacement=try ProbeDirectory(parent.appendingPathComponent("output"),create:true);try replacement.write("sentinel",bytes:Data([9]))
        XCTAssertThrowsError(try held.requirePathBinding());try held.write("original-only",bytes:Data([1]))
        XCTAssertThrowsError(try replacement.read("original-only"));XCTAssertEqual(try replacement.read("sentinel"),Data([9]));XCTAssertTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent("moved/output/original-only").path))
    }
    func testExistingOutputAndFileStayImmutable() throws {
        let root=try isolated();let leaf=root.appendingPathComponent("output");let d=try ProbeDirectory(leaf,create:true);try d.write("sentinel",bytes:Data([4]))
        XCTAssertThrowsError(try ProbeDirectory(leaf,create:true));XCTAssertThrowsError(try d.write("sentinel",bytes:Data([5])));XCTAssertEqual(try d.read("sentinel"),Data([4]))
    }
    func testTraversalAndSpecialFilesReject() throws {
        let root=try isolated();let d=try ProbeDirectory(root.appendingPathComponent("output"),create:true)
        for n in ["../outside","a/b",".hidden","","a\\b"] {XCTAssertThrowsError(try d.write(n,bytes:Data([0])));XCTAssertThrowsError(try d.read(n))}
        let fifo=d.url.appendingPathComponent("pipe");XCTAssertEqual(mkfifo(fifo.path,0o600),0);XCTAssertThrowsError(try d.read("pipe"));XCTAssertThrowsError(try d.assetURL("pipe"))
    }
}
