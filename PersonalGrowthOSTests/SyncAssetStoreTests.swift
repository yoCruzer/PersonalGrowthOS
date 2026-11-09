import Foundation
import XCTest
import SyncFoundation
@testable import PersonalGrowthOS

final class SyncAssetStoreTests: XCTestCase {
    private func scratch() throws -> URL {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("PGOS-Synthetic-SyncAssets-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:root)}
        return root
    }
    private let bytes=Data("Synthetic immutable original bytes".utf8)

    func testRetainedOriginalSurvivesBusinessOriginalDeletionAsIndependentFile() throws {
        let root=try scratch(),mediaStore=MediaStore(rootURL:root),store=SyncAssetStore(root:root)
        let identity=UUID(),descriptor=AssetDescriptor(bytes:bytes)
        let relative=try mediaStore.originalRelativePath(id:identity,contentType:"image/png")
        let source=try mediaStore.fileURL(for:relative)
        try FileManager.default.createDirectory(at:source.deletingLastPathComponent(),withIntermediateDirectories:true)
        try bytes.write(to:source)
        let retained=try store.retainOriginal(.init(id:identity,sha256:descriptor.sha256,byteCount:Int64(bytes.count),contentType:"image/png"),mediaStore:mediaStore)
        XCTAssertNotEqual(source,retained)
        let sourceInode=try FileManager.default.attributesOfItem(atPath:source.path)[.systemFileNumber] as? NSNumber
        let retainedInode=try FileManager.default.attributesOfItem(atPath:retained.path)[.systemFileNumber] as? NSNumber
        XCTAssertNotNil(sourceInode);XCTAssertNotNil(retainedInode);XCTAssertNotEqual(sourceInode,retainedInode)
        try mediaStore.removeOriginal(at:relative)
        XCTAssertFalse(FileManager.default.fileExists(atPath:source.path))
        XCTAssertEqual(try store.read(descriptor),bytes)
    }

    func testHashAndSizeMismatchAreRejectedWithoutInstallingOrReplacingBytes() throws {
        let root=try scratch(),store=SyncAssetStore(root:root),descriptor=AssetDescriptor(bytes:bytes)
        let wrongHash=AssetDescriptor(sha256:String(repeating:"0",count:64),byteCount:bytes.count)
        let wrongSize=AssetDescriptor(sha256:descriptor.sha256,byteCount:bytes.count+1)
        XCTAssertThrowsError(try store.retain(bytes,as:wrongHash))
        XCTAssertThrowsError(try store.retain(bytes,as:wrongSize))
        XCTAssertFalse(FileManager.default.fileExists(atPath:try store.url(for:descriptor).path))
        let path=try store.retain(bytes,as:descriptor)
        XCTAssertThrowsError(try store.read(wrongSize))
        var corrupt=bytes;corrupt[0] ^= 1;try corrupt.write(to:path)
        XCTAssertThrowsError(try store.read(descriptor))
        XCTAssertThrowsError(try store.retain(bytes,as:descriptor))
        XCTAssertEqual(try Data(contentsOf:path),corrupt)
    }

    func testExactHashReplayKeepsSameInodeAndModificationTime() throws {
        let root=try scratch(),store=SyncAssetStore(root:root),descriptor=AssetDescriptor(bytes:bytes)
        let path=try store.retain(bytes,as:descriptor)
        let before=try FileManager.default.attributesOfItem(atPath:path.path)
        XCTAssertEqual(try store.retain(bytes,as:descriptor),path)
        let after=try FileManager.default.attributesOfItem(atPath:path.path)
        XCTAssertEqual(before[.systemFileNumber] as? NSNumber,after[.systemFileNumber] as? NSNumber)
        XCTAssertEqual(before[.modificationDate] as? Date,after[.modificationDate] as? Date)
        XCTAssertEqual(try store.read(descriptor),bytes)
    }

    func testLeafAndDanglingSymlinksAreNeverReadOrReplaced() throws {
        let root=try scratch(),store=SyncAssetStore(root:root),descriptor=AssetDescriptor(bytes:bytes)
        let destination=try store.url(for:descriptor),external=root.appendingPathComponent("synthetic-outside")
        try bytes.write(to:external)
        try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
        try FileManager.default.createSymbolicLink(at:destination,withDestinationURL:external)
        XCTAssertThrowsError(try store.read(descriptor));XCTAssertThrowsError(try store.retain(bytes,as:descriptor))
        XCTAssertEqual(try Data(contentsOf:external),bytes)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath:destination.path),external.path)
        try FileManager.default.removeItem(at:destination)
        let absent=root.appendingPathComponent("must-stay-absent")
        try FileManager.default.createSymbolicLink(at:destination,withDestinationURL:absent)
        XCTAssertThrowsError(try store.retain(bytes,as:descriptor))
        XCTAssertFalse(FileManager.default.fileExists(atPath:absent.path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath:destination.path),absent.path)
    }

    func testParentDirectorySymlinkCannotRedirectLeaseWriteOrRead() throws {
        let root=try scratch(),outside=try scratch(),store=SyncAssetStore(root:root),descriptor=AssetDescriptor(bytes:bytes)
        let redirected=outside.appendingPathComponent("Assets",isDirectory:true)
        try FileManager.default.createDirectory(at:redirected,withIntermediateDirectories:true)
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("Sync"),withDestinationURL:outside)
        XCTAssertThrowsError(try store.retain(bytes,as:descriptor))
        let target=redirected.appendingPathComponent(descriptor.sha256)
        XCTAssertFalse(FileManager.default.fileExists(atPath:target.path))
        try bytes.write(to:target)
        XCTAssertThrowsError(try store.read(descriptor))
        XCTAssertEqual(try Data(contentsOf:target),bytes)
    }

    func testOriginalSymlinkIsRejectedWithoutCreatingLease() throws {
        let root=try scratch(),mediaStore=MediaStore(rootURL:root),store=SyncAssetStore(root:root)
        let identity=UUID(),descriptor=AssetDescriptor(bytes:bytes)
        let source=try mediaStore.fileURL(for:mediaStore.originalRelativePath(id:identity,contentType:"image/png"))
        let external=root.appendingPathComponent("synthetic-source")
        try bytes.write(to:external)
        try FileManager.default.createDirectory(at:source.deletingLastPathComponent(),withIntermediateDirectories:true)
        try FileManager.default.createSymbolicLink(at:source,withDestinationURL:external)
        XCTAssertThrowsError(try store.retainOriginal(.init(id:identity,sha256:descriptor.sha256,byteCount:Int64(bytes.count),contentType:"image/png"),mediaStore:mediaStore))
        XCTAssertFalse(FileManager.default.fileExists(atPath:try store.url(for:descriptor).path))
        XCTAssertEqual(try Data(contentsOf:external),bytes)
    }
}
