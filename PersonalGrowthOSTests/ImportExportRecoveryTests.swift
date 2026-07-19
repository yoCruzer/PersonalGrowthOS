import CryptoKit
import Foundation
import SwiftData
import UIKit
import XCTest
@testable import PersonalGrowthOS

@MainActor
final class ImportExportRecoveryTests: XCTestCase {
    func testFullRoundTripPreservesEveryObjectIdentityRelationshipAndOriginal() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let logs = LogRecorder()
        let source = try fixture.makePopulatedStore(log: { logs.values.append($0) })
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }

        let target = try fixture.makeEmptyStore(named: "Target", log: { logs.values.append($0) })
        let result = try await target.service.importPackage(from: lease.url)

        XCTAssertEqual(result.objectCounts, source.expectedCounts)
        XCTAssertEqual(result.restoredMediaCount, 1)
        XCTAssertEqual(try ids(in: target.container.mainContext), source.expectedIDs)
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: target.container.mainContext))
        let restoredImage = try XCTUnwrap(target.container.mainContext.fetch(FetchDescriptor<ImageMetadata>()).first)
        XCTAssertEqual(
            try Data(contentsOf: target.mediaStore.fileURL(for: restoredImage.relativePath)),
            fixture.imageData
        )
        let joinedLogs = logs.values.joined(separator: "|")
        XCTAssertFalse(joinedLogs.contains(TransferTestFixture.secretBody))
        XCTAssertFalse(joinedLogs.contains(fixture.root.path))
        XCTAssertFalse(joinedLogs.contains(fixture.imageData.base64EncodedString()))
    }

    func testDeleteIsolatedDatasetThenRestoreSameOnDiskStore() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore(onDisk: true)
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        let originalIDs = source.expectedIDs
        let originalPaths = try source.container.mainContext
            .fetch(FetchDescriptor<ImageMetadata>())
            .map(\.relativePath)

        try deleteAllFixtureData(source.container.mainContext)
        try source.container.mainContext.save()
        for path in originalPaths { try source.mediaStore.removeOriginal(at: path) }
        XCTAssertEqual(try totalObjectCount(in: source.container.mainContext), 0)

        _ = try await source.service.importPackage(from: lease.url)

        XCTAssertEqual(try ids(in: source.container.mainContext), originalIDs)
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: source.container.mainContext))
        XCTAssertEqual(try originalFiles(at: source.mediaStore.rootURL).count, 1)
    }

    func testImportedOnDiskStoreReopensWithoutDanglingLinksAndCanReExportEquivalentData() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let firstLease = try await source.service.exportPackage()
        defer { firstLease.cleanup() }
        let target = try fixture.makeEmptyStore(named: "PersistentTarget", onDisk: true)

        _ = try await target.service.importPackage(from: firstLease.url)
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: target.storeURL)
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: reopened.mainContext))
        XCTAssertEqual(try ids(in: reopened.mainContext), source.expectedIDs)

        let reexportService = ImportExportService(
            context: reopened.mainContext,
            mediaStore: target.mediaStore,
            workspaceRoot: fixture.root.appendingPathComponent("Reexport"),
            availableCapacity: { .max },
            now: { Date(timeIntervalSince1970: 9_000) },
            appVersion: { ("1.0", "1") }
        )
        let secondLease = try await reexportService.exportPackage()
        defer { secondLease.cleanup() }
        XCTAssertEqual(
            try extractedDataJSON(from: firstLease.url, under: fixture.root.appendingPathComponent("ExtractOne")),
            try extractedDataJSON(from: secondLease.url, under: fixture.root.appendingPathComponent("ExtractTwo"))
        )
    }

    func testNonEmptyTargetRejectsImportWithoutMutation() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        let target = try fixture.makeEmptyStore(named: "NonEmpty")
        let existing = Entry(body: "Keep me", createdAt: Date(timeIntervalSince1970: 50))
        target.container.mainContext.insert(existing)
        try target.container.mainContext.save()

        await assertThrows({ try await target.service.importPackage(from: lease.url) }) {
            XCTAssertEqual($0 as? TransferPackageError, .targetNotEmpty)
        }
        XCTAssertEqual(try target.container.mainContext.fetch(FetchDescriptor<Entry>()).map(\.id), [existing.id])
        XCTAssertEqual(try regularFiles(at: target.mediaStore.rootURL), [])
    }

    func testInterruptedPublicationLeavesEmptyTargetAndNoOriginals() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        let target = try fixture.makeEmptyStore(
            named: "Interrupted",
            publicationCheckpoint: { checkpoint in
                if checkpoint == .afterMediaCopy(1) { throw TransferPackageError.interrupted }
            }
        )

        await assertThrows({ try await target.service.importPackage(from: lease.url) }) {
            XCTAssertEqual($0 as? TransferPackageError, .interrupted)
        }
        XCTAssertEqual(try totalObjectCount(in: target.container.mainContext), 0)
        XCTAssertEqual(try originalFiles(at: target.mediaStore.rootURL), [])
        XCTAssertNoThrow(try LinkIntegrityService.validate(context: target.container.mainContext))

        let beforeSaveTarget = try fixture.makeEmptyStore(
            named: "InterruptedBeforeSave",
            publicationCheckpoint: { checkpoint in
                if checkpoint == .beforeSave { throw TransferPackageError.interrupted }
            }
        )
        await assertThrows({ try await beforeSaveTarget.service.importPackage(from: lease.url) }) {
            XCTAssertEqual($0 as? TransferPackageError, .interrupted)
        }
        XCTAssertEqual(try totalObjectCount(in: beforeSaveTarget.container.mainContext), 0)
        XCTAssertEqual(try originalFiles(at: beforeSaveTarget.mediaStore.rootURL), [])
    }

    func testMissingMediaAndCorruptDataAreRejectedBeforePublication() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }

        let missingMedia = try mutatePackage(
            lease.url,
            under: fixture.root.appendingPathComponent("MissingMedia"),
            mutation: { root, _, _ in
                let media = try XCTUnwrap(try regularFiles(at: root.appendingPathComponent("media")).first)
                try FileManager.default.removeItem(at: media)
            }
        )
        let corruptManifest = try mutatePackage(
            lease.url,
            under: fixture.root.appendingPathComponent("CorruptManifest"),
            mutation: { root, _, _ in
                try Data("{".utf8).write(to: root.appendingPathComponent("manifest.json"))
            }
        )
        let corruptData = try mutatePackage(
            lease.url,
            under: fixture.root.appendingPathComponent("CorruptData"),
            mutation: { root, _, _ in
                try Data("tampered".utf8).write(to: root.appendingPathComponent("data.json"))
            }
        )

        for package in [missingMedia, corruptManifest, corruptData] {
            let target = try fixture.makeEmptyStore(named: UUID().uuidString)
            await assertThrows({ try await target.service.importPackage(from: package) })
            XCTAssertEqual(try totalObjectCount(in: target.container.mainContext), 0)
            XCTAssertEqual(try originalFiles(at: target.mediaStore.rootURL), [])
        }
    }

    func testDuplicateObjectIDAndUnsupportedSchemaAreRejected() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }

        let duplicate = try mutatePackage(
            lease.url,
            under: fixture.root.appendingPathComponent("Duplicate"),
            rewriteJSON: { manifest, data in
                let duplicateData = TransferData(
                    entries: data.entries + [try XCTUnwrap(data.entries.first)],
                    images: data.images,
                    tags: data.tags,
                    links: data.links,
                    habits: data.habits,
                    habitLogs: data.habitLogs,
                    goals: data.goals,
                    goalEvents: data.goalEvents
                )
                return (manifest, duplicateData)
            }
        )
        let unsupported = try mutatePackage(
            lease.url,
            under: fixture.root.appendingPathComponent("Unsupported"),
            rewriteJSON: { manifest, data in
                (ExportManifest(
                    formatIdentifier: manifest.formatIdentifier,
                    packageSchemaVersion: 99,
                    appVersion: manifest.appVersion,
                    appBuild: manifest.appBuild,
                    exportID: manifest.exportID,
                    exportedAt: manifest.exportedAt,
                    objectCounts: manifest.objectCounts,
                    dataFile: manifest.dataFile,
                    mediaFiles: manifest.mediaFiles
                ), data)
            },
            refreshManifest: false
        )

        let duplicateTarget = try fixture.makeEmptyStore(named: "DuplicateTarget")
        await assertThrows({ try await duplicateTarget.service.importPackage(from: duplicate) }) {
            XCTAssertEqual($0 as? TransferPackageError, .duplicateID("entry"))
        }
        let schemaTarget = try fixture.makeEmptyStore(named: "SchemaTarget")
        await assertThrows({ try await schemaTarget.service.importPackage(from: unsupported) }) {
            XCTAssertEqual($0 as? TransferPackageError, .unsupportedSchema(99))
        }
    }

    func testArchiveAndExpandedFileAndObjectLimitsAreEnforced() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        let archiveSize = try fileSize(lease.url)

        let cases = [
            ZIPImportLimits(maximumArchiveBytes: archiveSize - 1, maximumExpandedBytes: .max,
                            capacitySafetyReserve: 0, maximumFileCount: 100, maximumObjectCount: 100,
                            maximumCompressionRatio: 100),
            ZIPImportLimits(maximumArchiveBytes: .max, maximumExpandedBytes: 1,
                            capacitySafetyReserve: 0, maximumFileCount: 100, maximumObjectCount: 100,
                            maximumCompressionRatio: 100),
            ZIPImportLimits(maximumArchiveBytes: .max, maximumExpandedBytes: .max,
                            capacitySafetyReserve: 0, maximumFileCount: 2, maximumObjectCount: 100,
                            maximumCompressionRatio: 100),
            ZIPImportLimits(maximumArchiveBytes: .max, maximumExpandedBytes: .max,
                            capacitySafetyReserve: 0, maximumFileCount: 100, maximumObjectCount: 1,
                            maximumCompressionRatio: 100),
            ZIPImportLimits(maximumArchiveBytes: .max, maximumExpandedBytes: .max,
                            capacitySafetyReserve: 0, maximumFileCount: 100, maximumObjectCount: 100,
                            maximumCompressionRatio: 100, maximumManifestBytes: 1),
            ZIPImportLimits(maximumArchiveBytes: .max, maximumExpandedBytes: .max,
                            capacitySafetyReserve: 0, maximumFileCount: 100, maximumObjectCount: 100,
                            maximumCompressionRatio: 100, maximumDataBytes: 1)
        ]
        for (index, limits) in cases.enumerated() {
            let target = try fixture.makeEmptyStore(named: "Limit-\(index)", limits: limits)
            await assertThrows({ try await target.service.importPackage(from: lease.url) })
            XCTAssertEqual(try totalObjectCount(in: target.container.mainContext), 0)
            XCTAssertEqual(try regularFiles(at: fixture.root.appendingPathComponent("Workspace-Limit-\(index)")), [])
        }

        XCTAssertThrowsError(try ZIPArchiveReader(
            archiveURL: lease.url,
            limits: .production,
            availableCapacity: 0
        )) {
            XCTAssertEqual($0 as? ZIPArchiveError, .insufficientCapacity)
        }
    }

    func testExportEnforcesItsOwnImportCompatibilityLimits() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lowObjectLimits = ZIPImportLimits(
            maximumArchiveBytes: .max,
            maximumExpandedBytes: .max,
            capacitySafetyReserve: 0,
            maximumFileCount: 100,
            maximumObjectCount: 1,
            maximumCompressionRatio: 100
        )
        let lowDataLimits = ZIPImportLimits(
            maximumArchiveBytes: .max,
            maximumExpandedBytes: .max,
            capacitySafetyReserve: 0,
            maximumFileCount: 100,
            maximumObjectCount: 100,
            maximumCompressionRatio: 100,
            maximumDataBytes: 1
        )

        for (name, limits) in [("Object", lowObjectLimits), ("Data", lowDataLimits)] {
            let workspace = fixture.root.appendingPathComponent("ExportLimit-\(name)")
            let service = ImportExportService(
                context: source.container.mainContext,
                mediaStore: source.mediaStore,
                workspaceRoot: workspace,
                limits: limits,
                availableCapacity: { .max }
            )
            await assertThrows({ try await service.exportPackage() })
            XCTAssertEqual(try regularFiles(at: workspace), [])
        }
    }

    func testOversizedMediaMemberIsRejectedBeforeJSONDecodeAndExtraction() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let files = fixture.root.appendingPathComponent("OversizedMemberFiles", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let manifest = files.appendingPathComponent("manifest.json")
        let data = files.appendingPathComponent("data.json")
        let media = files.appendingPathComponent("oversized.png")
        try Data("{}".utf8).write(to: manifest)
        try Data("{}".utf8).write(to: data)
        try Data(repeating: 0, count: Int(MediaStore.maximumOriginalByteCount + 1)).write(to: media)
        let archive = fixture.root.appendingPathComponent("oversized-member.zip")
        try ZIPArchiveWriter.write(sources: [
            ZIPSource(path: "manifest.json", fileURL: manifest),
            ZIPSource(path: "data.json", fileURL: data),
            ZIPSource(path: "media/oversized.png", fileURL: media)
        ], to: archive)
        let target = try fixture.makeEmptyStore(named: "OversizedMember")

        await assertThrows({ try await target.service.importPackage(from: archive) }) {
            XCTAssertEqual($0 as? ZIPArchiveError, .expandedSizeExceeded)
        }
        XCTAssertEqual(try totalObjectCount(in: target.container.mainContext), 0)
        XCTAssertEqual(try originalFiles(at: target.mediaStore.rootURL), [])
    }

    func testCompressionRatioUnsafePathSymlinkAndCaseCollisionFixturesAreRejected() throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let files = fixture.root.appendingPathComponent("ZIPFiles", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let first = files.appendingPathComponent("first")
        let second = files.appendingPathComponent("second")
        try Data(repeating: 7, count: 256).write(to: first)
        try Data(repeating: 8, count: 16).write(to: second)

        let ratio = fixture.root.appendingPathComponent("ratio.zip")
        try ZIPArchiveWriter.write(sources: [ZIPSource(path: "ratio.bin", fileURL: first)], to: ratio)
        try patchCentralDirectory(at: ratio) { data, offset in
            writeUInt32(1, to: &data, at: offset + 20)
        }
        XCTAssertThrowsError(try ZIPArchiveReader(archiveURL: ratio, limits: .production, availableCapacity: .max)) {
            XCTAssertEqual($0 as? ZIPArchiveError, .compressionRatioExceeded)
        }

        let unsafe = fixture.root.appendingPathComponent("unsafe.zip")
        try ZIPArchiveWriter.write(sources: [ZIPSource(path: "safe.txt", fileURL: second)], to: unsafe)
        try replaceASCII("safe.txt", with: "../x.txt", in: unsafe)
        XCTAssertThrowsError(try ZIPArchiveReader(archiveURL: unsafe, limits: .production, availableCapacity: .max)) {
            XCTAssertEqual($0 as? ZIPArchiveError, .unsafePath)
        }

        let symlink = fixture.root.appendingPathComponent("symlink.zip")
        try ZIPArchiveWriter.write(sources: [ZIPSource(path: "link.txt", fileURL: second)], to: symlink)
        try patchCentralDirectory(at: symlink) { data, offset in
            writeUInt32(UInt32(0o120777) << 16, to: &data, at: offset + 38)
        }
        XCTAssertThrowsError(try ZIPArchiveReader(archiveURL: symlink, limits: .production, availableCapacity: .max)) {
            XCTAssertEqual($0 as? ZIPArchiveError, .unsupportedFileType)
        }

        let collision = fixture.root.appendingPathComponent("collision.zip")
        try ZIPArchiveWriter.write(sources: [
            ZIPSource(path: "A/a.txt", fileURL: second),
            ZIPSource(path: "B/b.txt", fileURL: second)
        ], to: collision)
        try replaceASCII("B/b.txt", with: "a/A.txt", in: collision)
        XCTAssertThrowsError(try ZIPArchiveReader(archiveURL: collision, limits: .production, availableCapacity: .max)) {
            XCTAssertEqual($0 as? ZIPArchiveError, .duplicatePath)
        }
    }

    func testZIP64ExactAndAboveEntryCountSentinelsRoundTrip() throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let empty = fixture.root.appendingPathComponent("empty")
        try Data().write(to: empty)
        let sources = (0...Int(UInt16.max)).map {
            ZIPSource(path: "f/\($0)", fileURL: empty)
        }
        let limits = ZIPImportLimits(
            maximumArchiveBytes: 32 * 1_024 * 1_024,
            maximumExpandedBytes: 1,
            capacitySafetyReserve: 0,
            maximumFileCount: 70_000,
            maximumObjectCount: 1,
            maximumCompressionRatio: 100
        )

        for count in [Int(UInt16.max), Int(UInt16.max) + 1] {
            let archive = fixture.root.appendingPathComponent("zip64-count-\(count).zip")
            try ZIPArchiveWriter.write(sources: Array(sources.prefix(count)), to: archive)
            let reader = try ZIPArchiveReader(
                archiveURL: archive,
                limits: limits,
                availableCapacity: .max
            )
            XCTAssertEqual(reader.members.count, count)
            XCTAssertEqual(reader.members.first?.path, "f/0")
            XCTAssertEqual(reader.members.last?.path, "f/\(count - 1)")
        }
    }

    func testExportLeaseAndLaunchRecoveryCleanupTemporaryArtifacts() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()
        let lease = try await source.service.exportPackage()
        let archiveURL = lease.url
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        lease.cleanup()
        lease.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))

        let interrupted = source.mediaStore.rootURL.appendingPathComponent("Transfer/Import/interrupted.tmp")
        try FileManager.default.createDirectory(
            at: interrupted.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("private".utf8).write(to: interrupted)
        try ImportExportService.cleanupInterruptedTransfers(mediaRootURL: source.mediaStore.rootURL)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: source.mediaStore.rootURL.appendingPathComponent("Transfer").path
        ))
    }

    func testCancelledExportAndImportLeaveNoTemporaryOrPublishedData() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let source = try fixture.makePopulatedStore()

        let cancelledExport = Task { try await source.service.exportPackage() }
        cancelledExport.cancel()
        await assertThrows({ try await cancelledExport.value }) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertEqual(try regularFiles(at: fixture.root.appendingPathComponent("Workspace-Source")), [])

        let lease = try await source.service.exportPackage()
        defer { lease.cleanup() }
        let target = try fixture.makeEmptyStore(named: "CancelledImport")
        let cancelledImport = Task { try await target.service.importPackage(from: lease.url) }
        cancelledImport.cancel()
        await assertThrows({ try await cancelledImport.value }) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertEqual(try totalObjectCount(in: target.container.mainContext), 0)
        XCTAssertEqual(try originalFiles(at: target.mediaStore.rootURL), [])
        XCTAssertEqual(try regularFiles(at: fixture.root.appendingPathComponent("Workspace-CancelledImport")), [])
    }

    func testStartupReconciliationQuarantinesCrashWindowImportOriginals() throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let target = try fixture.makeEmptyStore(named: "CrashWindow")
        let id = UUID()
        let idString = id.uuidString.lowercased()
        let relativePath = "Media/Originals/\(idString.prefix(2))/\(idString).png"
        let installedURL = try target.mediaStore.fileURL(for: relativePath)
        try FileManager.default.createDirectory(
            at: installedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fixture.imageData.write(to: installedURL)

        let report = try target.mediaStore.reconcile(referencedOriginalPaths: [])

        XCTAssertEqual(try originalFiles(at: target.mediaStore.rootURL), [])
        XCTAssertEqual(report.recoveryFilePaths.count, 1)
        XCTAssertEqual(try regularFiles(at: target.mediaStore.rootURL.appendingPathComponent("Recovery")).count, 1)
        XCTAssertEqual(try totalObjectCount(in: target.container.mainContext), 0)
    }

    func testExportFailureCleansAssemblyAndLogsAreRedacted() async throws {
        let fixture = try TransferTestFixture()
        defer { fixture.remove() }
        let logs = LogRecorder()
        let store = try fixture.makePopulatedStore(log: { logs.values.append($0) })
        let image = try XCTUnwrap(store.container.mainContext.fetch(FetchDescriptor<ImageMetadata>()).first)
        try store.mediaStore.removeOriginal(at: image.relativePath)

        await assertThrows({ try await store.service.exportPackage() })
        let workspace = fixture.root.appendingPathComponent("Workspace-Source")
        XCTAssertEqual(try regularFiles(at: workspace), [])
        let joined = logs.values.joined(separator: "|")
        XCTAssertFalse(joined.contains(TransferTestFixture.secretBody))
        XCTAssertFalse(joined.contains(fixture.root.path))
        XCTAssertFalse(joined.contains(fixture.imageData.base64EncodedString()))
    }
}

@MainActor
private final class LogRecorder {
    var values: [String] = []
}

@MainActor
private func assertThrows<T>(
    _ operation: () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    verify: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await operation()
        XCTFail("Expected operation to throw", file: file, line: line)
    } catch {
        verify(error)
    }
}

@MainActor
private struct TransferStore {
    let container: ModelContainer
    let mediaStore: MediaStore
    let service: ImportExportService
    let storeURL: URL
    let expectedCounts: [String: Int]
    let expectedIDs: [String: Set<UUID>]
}

@MainActor
private final class TransferTestFixture {
    static let secretBody = "SECRET-BODY-749ac"

    let root: URL
    let imageData: Data

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PGOS-S9-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        imageData = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format).pngData {
            UIColor.purple.setFill()
            $0.cgContext.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    func makePopulatedStore(
        onDisk: Bool = false,
        log: @escaping (String) -> Void = { _ in }
    ) throws -> TransferStore {
        let store = try makeEmptyStore(named: "Source", onDisk: onDisk, log: log)
        let context = store.container.mainContext
        let mediaSourceURL = root.appendingPathComponent("secret-source.png")
        try imageData.write(to: mediaSourceURL)
        let media = try store.mediaStore.storeOriginal(MediaSource(
            url: mediaSourceURL,
            originalFilename: "private-memory.png",
            contentType: "image/png"
        ))
        let base = Date(timeIntervalSince1970: 1_000)
        let image = ImageMetadata(
            id: media.id,
            relativePath: media.relativePath,
            originalFilename: "private-memory.png",
            contentType: "image/png",
            byteCount: media.byteCount,
            pixelWidth: media.pixelWidth,
            pixelHeight: media.pixelHeight,
            checksum: media.checksum,
            createdAt: base
        )
        let entry = Entry(
            status: .organized,
            title: "Private title",
            body: Self.secretBody,
            createdAt: base,
            images: [image]
        )
        image.entry = entry
        let review = Entry(
            kind: .review,
            status: .organized,
            body: "Weekly reflection",
            createdAt: Date(timeIntervalSince1970: 2_000),
            periodStart: Date(timeIntervalSince1970: 500),
            periodEnd: Date(timeIntervalSince1970: 1_500)
        )
        let tag = Tag(displayName: "Health", normalizedName: "health", createdAt: base)
        let habit = Habit(name: "Walk", normalizedName: "walk", createdAt: base)
        let goal = Goal(kind: .flag, title: "Feel stronger", normalizedTitle: "feel stronger", createdAt: base)
        let log = HabitLog(
            habitID: habit.id,
            occurredAt: Date(timeIntervalSince1970: 1_100),
            isCompleted: true,
            quantity: 2,
            unit: "km",
            result: "steady",
            linkedEntryID: entry.id,
            createdAt: Date(timeIntervalSince1970: 1_100)
        )
        let event = GoalLifecycleEvent(
            goalID: goal.id,
            kind: .created,
            occurredAt: base,
            createdAt: base
        )
        let links = [
            ObjectLink(sourceType: .entry, sourceID: entry.id, targetType: .tag, targetID: tag.id,
                       kind: .entryUsesTag, createdAt: base),
            ObjectLink(sourceType: .entry, sourceID: entry.id, targetType: .habit, targetID: habit.id,
                       kind: .entryRelatesHabit, createdAt: base),
            ObjectLink(sourceType: .habit, sourceID: habit.id, targetType: .goal, targetID: goal.id,
                       kind: .habitSupportsGoal, createdAt: base),
            ObjectLink(sourceType: .entry, sourceID: review.id, targetType: .entry, targetID: entry.id,
                       kind: .reviewsEntry, createdAt: base),
            ObjectLink(sourceType: .entry, sourceID: review.id, targetType: .goal, targetID: goal.id,
                       kind: .reviewsGoal, createdAt: base)
        ]
        [entry, review].forEach(context.insert)
        context.insert(tag)
        context.insert(habit)
        context.insert(goal)
        context.insert(log)
        context.insert(event)
        links.forEach(context.insert)
        try context.save()
        try LinkIntegrityService.validate(context: context)
        return TransferStore(
            container: store.container,
            mediaStore: store.mediaStore,
            service: store.service,
            storeURL: store.storeURL,
            expectedCounts: [
                "entries": 2, "images": 1, "tags": 1, "links": 5,
                "habits": 1, "habitLogs": 1, "goals": 1, "goalEvents": 1
            ],
            expectedIDs: try ids(in: context)
        )
    }

    func makeEmptyStore(
        named name: String,
        onDisk: Bool = false,
        limits: ZIPImportLimits = .production,
        log: @escaping (String) -> Void = { _ in },
        publicationCheckpoint: ((ImportPublicationCheckpoint) throws -> Void)? = nil
    ) throws -> TransferStore {
        let storeURL = root.appendingPathComponent("\(name).sqlite")
        let container = try onDisk
            ? PersistenceContainerFactory.makeOnDisk(at: storeURL)
            : PersistenceContainerFactory.makeInMemory()
        let mediaRoot = root.appendingPathComponent("Media-\(name)", isDirectory: true)
        let mediaStore = MediaStore(rootURL: mediaRoot, availableCapacity: { .max })
        let service = ImportExportService(
            context: container.mainContext,
            mediaStore: mediaStore,
            workspaceRoot: root.appendingPathComponent("Workspace-\(name)"),
            limits: limits,
            availableCapacity: { .max },
            now: { Date(timeIntervalSince1970: 8_000) },
            appVersion: { ("1.0", "1") },
            log: log,
            publicationCheckpoint: publicationCheckpoint
        )
        return TransferStore(
            container: container,
            mediaStore: mediaStore,
            service: service,
            storeURL: storeURL,
            expectedCounts: [:],
            expectedIDs: [:]
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private func ids(in context: ModelContext) throws -> [String: Set<UUID>] {
    [
        "entries": Set(try context.fetch(FetchDescriptor<Entry>()).map(\.id)),
        "images": Set(try context.fetch(FetchDescriptor<ImageMetadata>()).map(\.id)),
        "tags": Set(try context.fetch(FetchDescriptor<Tag>()).map(\.id)),
        "links": Set(try context.fetch(FetchDescriptor<ObjectLink>()).map(\.id)),
        "habits": Set(try context.fetch(FetchDescriptor<Habit>()).map(\.id)),
        "habitLogs": Set(try context.fetch(FetchDescriptor<HabitLog>()).map(\.id)),
        "goals": Set(try context.fetch(FetchDescriptor<Goal>()).map(\.id)),
        "goalEvents": Set(try context.fetch(FetchDescriptor<GoalLifecycleEvent>()).map(\.id))
    ]
}

@MainActor
private func totalObjectCount(in context: ModelContext) throws -> Int {
    try ids(in: context).values.reduce(0) { $0 + $1.count }
}

@MainActor
private func deleteAllFixtureData(_ context: ModelContext) throws {
    try context.fetch(FetchDescriptor<ObjectLink>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<HabitLog>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<GoalLifecycleEvent>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<ImageMetadata>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<Entry>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<Tag>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<Habit>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<Goal>()).forEach(context.delete)
}

private func originalFiles(at mediaRoot: URL) throws -> [URL] {
    try regularFiles(at: mediaRoot.appendingPathComponent("Media/Originals"))
}

private func regularFiles(at root: URL) throws -> [URL] {
    guard FileManager.default.fileExists(atPath: root.path),
          let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey]
          ) else { return [] }
    return try (enumerator.allObjects as? [URL] ?? []).filter {
        try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
    }.sorted { $0.path < $1.path }
}

private func extractedDataJSON(from archive: URL, under root: URL) throws -> Data {
    let reader = try ZIPArchiveReader(archiveURL: archive, availableCapacity: .max)
    try reader.extractAll(to: root)
    return try Data(contentsOf: root.appendingPathComponent("data.json"))
}

private func mutatePackage(
    _ archive: URL,
    under root: URL,
    mutation: ((URL, ExportManifest, TransferData) throws -> Void)? = nil,
    rewriteJSON: ((ExportManifest, TransferData) throws -> (ExportManifest, TransferData))? = nil,
    refreshManifest: Bool = true
) throws -> URL {
    let extracted = root.appendingPathComponent("Extracted", isDirectory: true)
    let reader = try ZIPArchiveReader(archiveURL: archive, availableCapacity: .max)
    try reader.extractAll(to: extracted)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let manifestURL = extracted.appendingPathComponent("manifest.json")
    let dataURL = extracted.appendingPathComponent("data.json")
    var manifest = try decoder.decode(ExportManifest.self, from: Data(contentsOf: manifestURL))
    var data = try decoder.decode(TransferData.self, from: Data(contentsOf: dataURL))
    try mutation?(extracted, manifest, data)
    if let rewriteJSON {
        (manifest, data) = try rewriteJSON(manifest, data)
        let encodedData = try encoder.encode(data)
        try encodedData.write(to: dataURL)
        if refreshManifest {
            manifest = ExportManifest(
                formatIdentifier: manifest.formatIdentifier,
                packageSchemaVersion: manifest.packageSchemaVersion,
                appVersion: manifest.appVersion,
                appBuild: manifest.appBuild,
                exportID: manifest.exportID,
                exportedAt: manifest.exportedAt,
                objectCounts: data.objectCounts,
                dataFile: ExportFileRecord(
                    path: "data.json",
                    byteCount: Int64(encodedData.count),
                    sha256: SHA256.hash(data: encodedData).map { String(format: "%02x", $0) }.joined()
                ),
                mediaFiles: manifest.mediaFiles
            )
        }
        try encoder.encode(manifest).write(to: manifestURL)
    }
    let output = root.appendingPathComponent("mutated.zip")
    let sources = try regularFiles(at: extracted).map { file -> ZIPSource in
        let prefix = extracted.standardizedFileURL.path + "/"
        return ZIPSource(path: String(file.standardizedFileURL.path.dropFirst(prefix.count)), fileURL: file)
    }
    try ZIPArchiveWriter.write(sources: sources, to: output)
    return output
}

private func fileSize(_ url: URL) throws -> Int64 {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.size] as? NSNumber)?.int64Value ?? 0
}

private func patchCentralDirectory(
    at url: URL,
    patch: (inout Data, Int) -> Void
) throws {
    var data = try Data(contentsOf: url)
    let signature = Data([0x50, 0x4b, 0x01, 0x02])
    guard let range = data.range(of: signature) else { throw ZIPArchiveError.malformedArchive }
    patch(&data, range.lowerBound)
    try data.write(to: url)
}

private func replaceASCII(_ source: String, with replacement: String, in url: URL) throws {
    precondition(source.utf8.count == replacement.utf8.count)
    var data = try Data(contentsOf: url)
    let sourceData = Data(source.utf8)
    let replacementData = Data(replacement.utf8)
    var searchStart = data.startIndex
    while searchStart < data.endIndex,
          let range = data.range(of: sourceData, in: searchStart..<data.endIndex) {
        data.replaceSubrange(range, with: replacementData)
        searchStart = range.lowerBound + replacementData.count
    }
    try data.write(to: url)
}

private func writeUInt32(_ value: UInt32, to data: inout Data, at offset: Int) {
    data[offset] = UInt8(value & 0xff)
    data[offset + 1] = UInt8((value >> 8) & 0xff)
    data[offset + 2] = UInt8((value >> 16) & 0xff)
    data[offset + 3] = UInt8((value >> 24) & 0xff)
}
