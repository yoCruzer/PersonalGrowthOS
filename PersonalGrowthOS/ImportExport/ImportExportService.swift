import CryptoKit
import Foundation
import SwiftData

final class ExportPackageLease: Identifiable {
    let id = UUID()
    let url: URL
    private let fileManager: FileManager
    private var isCleaned = false

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    func cleanup() {
        guard !isCleaned else { return }
        isCleaned = true
        try? fileManager.removeItem(at: url)
        let parent = url.deletingLastPathComponent()
        if (try? fileManager.contentsOfDirectory(atPath: parent.path).isEmpty) == true {
            try? fileManager.removeItem(at: parent)
        }
    }

    deinit {
        cleanup()
    }
}

enum ImportPublicationCheckpoint: Equatable {
    case afterPreflight
    case afterMediaCopy(Int)
    case beforeSave
}

struct ImportResult: Equatable {
    let objectCounts: [String: Int]
    let restoredMediaCount: Int
}

@MainActor
final class ImportExportService {
    typealias Log = (String) -> Void

    private let context: ModelContext
    private let container: ModelContainer
    private let mediaStore: MediaStore
    private let fileManager: FileManager
    private let workspaceRoot: URL
    private let limits: ZIPImportLimits
    private let availableCapacity: () throws -> Int64
    private let now: () -> Date
    private let appVersion: () -> (version: String, build: String)
    private let log: Log
    private let publicationCheckpoint: ((ImportPublicationCheckpoint) throws -> Void)?

    init(
        context: ModelContext,
        mediaStore: MediaStore,
        fileManager: FileManager = .default,
        workspaceRoot: URL? = nil,
        limits: ZIPImportLimits = .production,
        availableCapacity: (() throws -> Int64)? = nil,
        now: @escaping () -> Date = Date.init,
        appVersion: @escaping () -> (version: String, build: String) = {
            let info = Bundle.main.infoDictionary
            return (
                info?["CFBundleShortVersionString"] as? String ?? "unknown",
                info?["CFBundleVersion"] as? String ?? "unknown"
            )
        },
        log: @escaping Log = { _ in },
        publicationCheckpoint: ((ImportPublicationCheckpoint) throws -> Void)? = nil
    ) {
        self.context = context
        self.container = context.container
        self.mediaStore = mediaStore
        self.fileManager = fileManager
        self.workspaceRoot = workspaceRoot
            ?? mediaStore.rootURL.appendingPathComponent("Transfer", isDirectory: true)
        self.limits = limits
        self.now = now
        self.appVersion = appVersion
        self.log = log
        self.publicationCheckpoint = publicationCheckpoint
        self.availableCapacity = availableCapacity ?? {
            let values = try mediaStore.rootURL.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])
            return values.volumeAvailableCapacityForImportantUsage
                ?? Int64(values.volumeAvailableCapacity ?? 0)
        }
    }

    static func cleanupInterruptedTransfers(
        mediaRootURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let transferRoot = mediaRootURL.appendingPathComponent("Transfer", isDirectory: true)
        if fileManager.fileExists(atPath: transferRoot.path) {
            try fileManager.removeItem(at: transferRoot)
        }
    }

    func exportPackage() async throws -> ExportPackageLease {
        log("export.started")
        let operationID = UUID()
        let exportDate = now()
        let build = appVersion()
        let capacity = try availableCapacity()
        let exportContainer = container
        let mediaRoot = mediaStore.rootURL
        let exportWorkspaceRoot = workspaceRoot
        let exportLimits = limits
        do {
            let worker = Task.detached {
                let snapshotContext = ModelContext(exportContainer)
                try LinkIntegrityService.validate(context: snapshotContext)
                let transfer = try TransferSnapshot.make(context: snapshotContext)
                let inputs = try transfer.images.map { record in
                    ExportMediaInput(
                        record: record,
                        sourceURL: try Self.mediaURL(root: mediaRoot, relativePath: record.relativePath)
                    )
                }
                let destination = try Self.buildExportPackage(
                    transfer: transfer,
                    mediaInputs: inputs,
                    operationID: operationID,
                    exportedAt: exportDate,
                    build: build,
                    workspaceRoot: exportWorkspaceRoot,
                    availableCapacity: capacity,
                    limits: exportLimits
                )
                return ExportBuildResult(
                    destination: destination,
                    objectCount: transfer.totalObjectCount,
                    mediaCount: transfer.images.count
                )
            }
            let result = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            do {
                try Task.checkCancellation()
            } catch {
                try? fileManager.removeItem(at: result.destination)
                throw error
            }
            log("export.completed objects=\(result.objectCount) media=\(result.mediaCount)")
            return ExportPackageLease(url: result.destination, fileManager: fileManager)
        } catch {
            log("export.failed")
            throw error
        }
    }

    private struct ExportMediaInput {
        let record: ImageTransfer
        let sourceURL: URL
    }

    private struct ExportBuildResult {
        let destination: URL
        let objectCount: Int
        let mediaCount: Int
    }

    nonisolated private static func buildExportPackage(
        transfer: TransferData,
        mediaInputs: [ExportMediaInput],
        operationID: UUID,
        exportedAt: Date,
        build: (version: String, build: String),
        workspaceRoot: URL,
        availableCapacity: Int64,
        limits: ZIPImportLimits
    ) throws -> URL {
        let fileManager = FileManager.default
        let assembly = workspaceRoot.appendingPathComponent(
            "Assembly/\(operationID.uuidString.lowercased())",
            isDirectory: true
        )
        let ready = workspaceRoot.appendingPathComponent("Ready", isDirectory: true)
        var archiveURL: URL?
        do {
            try Task.checkCancellation()
            try fileManager.createDirectory(at: assembly, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: ready, withIntermediateDirectories: true)
            let dataURL = assembly.appendingPathComponent("data.json")
            let manifestURL = assembly.appendingPathComponent("manifest.json")
            let encodedData = try TransferCoding.encoder.encode(transfer)
            guard transfer.totalObjectCount <= limits.maximumObjectCount else {
                throw TransferPackageError.objectLimitExceeded
            }
            guard mediaInputs.count + 2 <= limits.maximumFileCount else {
                throw ZIPArchiveError.tooManyFiles
            }
            guard Int64(encodedData.count) <= limits.maximumDataBytes else {
                throw ZIPArchiveError.expandedSizeExceeded
            }
            let mediaBytes = try mediaInputs.reduce(Int64(0)) { total, input in
                let (sum, overflow) = total.addingReportingOverflow(input.record.byteCount)
                guard !overflow else { throw ZIPArchiveError.insufficientCapacity }
                return sum
            }
            let dataBytes = Int64(encodedData.count)
            let (doubleData, dataOverflow) = dataBytes.multipliedReportingOverflow(by: 2)
            let (payload, payloadOverflow) = mediaBytes.addingReportingOverflow(doubleData)
            let (withOverhead, overheadOverflow) = payload.addingReportingOverflow(64 * 1_024 * 1_024)
            let (required, reserveOverflow) = withOverhead.addingReportingOverflow(limits.capacitySafetyReserve)
            guard !dataOverflow, !payloadOverflow, !overheadOverflow, !reserveOverflow,
                  availableCapacity >= required else {
                throw ZIPArchiveError.insufficientCapacity
            }
            try encodedData.write(to: dataURL, options: .atomic)

            var sources = [ZIPSource(path: "data.json", fileURL: dataURL)]
            var mediaRecords: [ExportMediaFileRecord] = []
            for input in mediaInputs.sorted(by: { $0.record.id.uuidString < $1.record.id.uuidString }) {
                try Task.checkCancellation()
                guard fileManager.fileExists(atPath: input.sourceURL.path) else {
                    throw TransferPackageError.missingMedia
                }
                let measured = try Hasher.sha256AndSize(fileAt: input.sourceURL)
                guard measured.size == input.record.byteCount,
                      measured.sha256 == input.record.checksum else {
                    throw TransferPackageError.mediaMismatch
                }
                sources.append(ZIPSource(path: input.record.mediaPath, fileURL: input.sourceURL))
                mediaRecords.append(ExportMediaFileRecord(
                    imageID: input.record.id,
                    path: input.record.mediaPath,
                    byteCount: measured.size,
                    sha256: measured.sha256
                ))
            }

            let manifest = ExportManifest(
                formatIdentifier: ExportManifest.formatIdentifier,
                packageSchemaVersion: ExportManifest.currentPackageSchemaVersion,
                appVersion: build.version,
                appBuild: build.build,
                exportID: operationID,
                exportedAt: exportedAt,
                objectCounts: transfer.objectCounts,
                dataFile: ExportFileRecord(
                    path: "data.json",
                    byteCount: dataBytes,
                    sha256: Hasher.sha256(encodedData)
                ),
                mediaFiles: mediaRecords
            )
            try TransferValidator.validate(manifest: manifest, data: transfer, limits: limits)
            let encodedManifest = try TransferCoding.encoder.encode(manifest)
            guard Int64(encodedManifest.count) <= limits.maximumManifestBytes else {
                throw ZIPArchiveError.expandedSizeExceeded
            }
            let expandedBytes = try checkedTransferAdd(
                mediaBytes,
                try checkedTransferAdd(dataBytes, Int64(encodedManifest.count))
            )
            guard expandedBytes <= limits.maximumExpandedBytes else {
                throw ZIPArchiveError.expandedSizeExceeded
            }
            try encodedManifest.write(to: manifestURL, options: .atomic)
            sources.insert(ZIPSource(path: "manifest.json", fileURL: manifestURL), at: 0)

            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let destination = ready.appendingPathComponent(
                "PersonalGrowthOS-export-\(formatter.string(from: exportedAt))-\(operationID.uuidString.prefix(8)).zip"
            )
            archiveURL = destination
            try ZIPArchiveWriter.write(sources: sources, to: destination)
            let archiveBytes = (try fileManager.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?
                .int64Value ?? 0
            guard archiveBytes <= limits.maximumArchiveBytes else {
                throw ZIPArchiveError.archiveTooLarge
            }
            _ = try ZIPArchiveReader(
                archiveURL: destination,
                limits: limits,
                availableCapacity: .max
            )
            try fileManager.removeItem(at: assembly)
            return destination
        } catch {
            try? fileManager.removeItem(at: assembly)
            if let archiveURL { try? fileManager.removeItem(at: archiveURL) }
            throw error
        }
    }

    nonisolated private static func checkedTransferAdd(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw ZIPArchiveError.expandedSizeExceeded }
        return sum
    }

    nonisolated private static func mediaURL(root: URL, relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains("..") else {
            throw MediaStoreError.invalidRelativePath
        }
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(root.standardizedFileURL.path + "/") else {
            throw MediaStoreError.invalidRelativePath
        }
        return candidate
    }

    func importPackage(from selectedURL: URL) async throws -> ImportResult {
        log("import.started")
        let operationRoot = workspaceRoot
            .appendingPathComponent("Import", isDirectory: true)
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        defer { try? fileManager.removeItem(at: operationRoot) }
        do {
            try Self.ensureTargetIsEmpty(context)
            let capacity = try availableCapacity()
            let importLimits = limits
            let worker = Task.detached {
                try Self.prepareAndVerifyImport(
                    selectedURL: selectedURL,
                    operationRoot: operationRoot,
                    limits: importLimits,
                    availableCapacity: capacity
                )
            }
            let package = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            try Task.checkCancellation()
            try publicationCheckpoint?(.afterPreflight)
            try Self.ensureTargetIsEmpty(context)
            try await publish(package: package)
            log("import.completed objects=\(package.data.totalObjectCount) media=\(package.data.images.count)")
            return ImportResult(
                objectCounts: package.data.objectCounts,
                restoredMediaCount: package.data.images.count
            )
        } catch {
            log("import.failed")
            throw error
        }
    }

    private struct ValidatedPackage {
        let manifest: ExportManifest
        let data: TransferData
        let extractedRoot: URL
    }

    nonisolated private static func prepareAndVerifyImport(
        selectedURL: URL,
        operationRoot: URL,
        limits: ZIPImportLimits,
        availableCapacity: Int64
    ) throws -> ValidatedPackage {
        let fileManager = FileManager.default
        try Task.checkCancellation()
        let selectedSize = (try fileManager.attributesOfItem(atPath: selectedURL.path)[.size] as? NSNumber)?
            .int64Value ?? 0
        guard selectedSize >= 0, selectedSize <= limits.maximumArchiveBytes else {
            throw ZIPArchiveError.archiveTooLarge
        }
        let remainingCapacity = availableCapacity >= selectedSize
            ? availableCapacity - selectedSize
            : 0
        try fileManager.createDirectory(at: operationRoot, withIntermediateDirectories: true)
        let stagedArchive = operationRoot.appendingPathComponent("selected.zip")
        try fileManager.copyItem(at: selectedURL, to: stagedArchive)
        let extracted = operationRoot.appendingPathComponent("Extracted", isDirectory: true)
        let reader = try ZIPArchiveReader(
            archiveURL: stagedArchive,
            limits: limits,
            availableCapacity: remainingCapacity
        )
        guard let manifestMember = reader.members.first(where: { $0.path == "manifest.json" }),
              let dataMember = reader.members.first(where: { $0.path == "data.json" }) else {
            throw ZIPArchiveError.missingMember("manifest.json/data.json")
        }
        guard manifestMember.uncompressedSize <= limits.maximumManifestBytes,
              dataMember.uncompressedSize <= limits.maximumDataBytes else {
            throw ZIPArchiveError.expandedSizeExceeded
        }
        for member in reader.members where member.path != "manifest.json" && member.path != "data.json" {
            guard member.path.hasPrefix("media/"),
                  member.uncompressedSize <= MediaStore.maximumOriginalByteCount else {
                throw ZIPArchiveError.expandedSizeExceeded
            }
        }
        try reader.extractAll(to: extracted)
        let package = try decodeAndValidatePackage(
            at: extracted,
            archiveMembers: reader.members,
            limits: limits,
            fileManager: fileManager
        )
        let verificationRoot = operationRoot.appendingPathComponent("Verification", isDirectory: true)
        try verifyInIsolatedStore(package: package, rootURL: verificationRoot, fileManager: fileManager)
        try fileManager.removeItem(at: verificationRoot)
        return package
    }

    nonisolated private static func decodeAndValidatePackage(
        at rootURL: URL,
        archiveMembers: [ZIPMember],
        limits: ZIPImportLimits,
        fileManager: FileManager
    ) throws -> ValidatedPackage {
        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        let dataURL = rootURL.appendingPathComponent("data.json")
        guard fileManager.fileExists(atPath: manifestURL.path),
              fileManager.fileExists(atPath: dataURL.path) else {
            throw ZIPArchiveError.missingMember("manifest.json/data.json")
        }
        let manifest: ExportManifest
        do {
            manifest = try TransferCoding.decoder.decode(
                ExportManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw TransferPackageError.corruptManifest
        }
        guard manifest.formatIdentifier == ExportManifest.formatIdentifier else {
            throw TransferPackageError.invalidFormat
        }
        guard manifest.packageSchemaVersion == ExportManifest.currentPackageSchemaVersion else {
            throw TransferPackageError.unsupportedSchema(manifest.packageSchemaVersion)
        }
        let measuredData = try Hasher.sha256AndSize(fileAt: dataURL)
        guard measuredData.size == manifest.dataFile.byteCount,
              measuredData.sha256 == manifest.dataFile.sha256 else {
            throw TransferPackageError.corruptData
        }
        let data: TransferData
        do {
            data = try TransferCoding.decoder.decode(TransferData.self, from: Data(contentsOf: dataURL))
        } catch {
            throw TransferPackageError.corruptData
        }
        try TransferValidator.validate(manifest: manifest, data: data, limits: limits)

        let expectedPaths = Set(["manifest.json", manifest.dataFile.path] + manifest.mediaFiles.map(\.path))
        guard expectedPaths.count == 2 + manifest.mediaFiles.count,
              expectedPaths == Set(archiveMembers.map(\.path)) else {
            throw TransferPackageError.countMismatch
        }
        for record in manifest.mediaFiles {
            let mediaURL = rootURL.appendingPathComponent(record.path).standardizedFileURL
            guard mediaURL.path.hasPrefix(rootURL.standardizedFileURL.path + "/"),
                  fileManager.fileExists(atPath: mediaURL.path) else {
                throw TransferPackageError.missingMedia
            }
            let measured = try Hasher.sha256AndSize(fileAt: mediaURL)
            guard measured.size == record.byteCount, measured.sha256 == record.sha256 else {
                throw TransferPackageError.mediaMismatch
            }
        }
        return ValidatedPackage(manifest: manifest, data: data, extractedRoot: rootURL)
    }

    nonisolated private static func verifyInIsolatedStore(
        package: ValidatedPackage,
        rootURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let storeURL = rootURL.appendingPathComponent("Store.sqlite")
        do {
            let container = try PersistenceContainerFactory.makeOnDisk(at: storeURL)
            let verificationContext = ModelContext(container)
            let temporaryMedia = MediaStore(
                rootURL: rootURL.appendingPathComponent("MediaRoot", isDirectory: true),
                fileManager: fileManager,
                availableCapacity: { .max }
            )
            _ = try materialize(package: package, context: verificationContext, mediaStore: temporaryMedia)
            try verificationContext.save()
            try verifySnapshot(package.data, context: verificationContext, mediaStore: temporaryMedia)
        }
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: storeURL)
        let reopenedContext = ModelContext(reopened)
        let reopenedMedia = MediaStore(
            rootURL: rootURL.appendingPathComponent("MediaRoot", isDirectory: true),
            fileManager: fileManager,
            availableCapacity: { .max }
        )
        try verifySnapshot(package.data, context: reopenedContext, mediaStore: reopenedMedia)
    }

    private func publish(package: ValidatedPackage) async throws {
        let importContainer = container
        let mediaRoot = mediaStore.rootURL
        let checkpoint = publicationCheckpoint
        let worker = Task.detached {
            try Self.publishPreparedPackage(
                package: package,
                container: importContainer,
                mediaRoot: mediaRoot,
                publicationCheckpoint: checkpoint
            )
        }
        try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        context.rollback()
    }

    nonisolated private static func publishPreparedPackage(
        package: ValidatedPackage,
        container: ModelContainer,
        mediaRoot: URL,
        publicationCheckpoint: ((ImportPublicationCheckpoint) throws -> Void)?
    ) throws {
        let fileManager = FileManager.default
        let publicationRoot = package.extractedRoot
            .deletingLastPathComponent()
            .appendingPathComponent("Publication", isDirectory: true)
        let stagedStore = MediaStore(
            rootURL: publicationRoot,
            fileManager: fileManager,
            availableCapacity: { .max }
        )
        let activeStore = MediaStore(rootURL: mediaRoot, fileManager: fileManager)
        let stagedOriginals = publicationRoot.appendingPathComponent("Media/Originals", isDirectory: true)
        let activeOriginals = mediaRoot.appendingPathComponent("Media/Originals", isDirectory: true)
        var installedOriginals = false
        var didSave = false
        let publicationContext = ModelContext(container)
        do {
            try fileManager.createDirectory(at: publicationRoot, withIntermediateDirectories: true)
            var copiedCount = 0
            for record in package.data.images.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                _ = try copyMedia(
                    record,
                    packageRoot: package.extractedRoot,
                    mediaRoot: stagedStore.rootURL
                )
                copiedCount += 1
                try publicationCheckpoint?(.afterMediaCopy(copiedCount))
            }
            try Task.checkCancellation()
            if !fileManager.fileExists(atPath: stagedOriginals.path) {
                try fileManager.createDirectory(at: stagedOriginals, withIntermediateDirectories: true)
            }
            guard try directoryIsEmptyOrAbsent(activeOriginals, fileManager: fileManager) else {
                throw TransferPackageError.targetNotEmpty
            }
            try fileManager.createDirectory(
                at: activeOriginals.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: activeOriginals.path) {
                try fileManager.removeItem(at: activeOriginals)
            }
            try fileManager.moveItem(at: stagedOriginals, to: activeOriginals)
            installedOriginals = true

            try ensureTargetIsEmpty(publicationContext)
            _ = try materialize(
                package: package,
                context: publicationContext,
                mediaStore: activeStore,
                copyOriginals: false
            )
            try Task.checkCancellation()
            try publicationCheckpoint?(.beforeSave)
            try LinkIntegrityService.validate(context: publicationContext)
            try Task.checkCancellation()
            try publicationContext.save()
            didSave = true
        } catch {
            publicationContext.rollback()
            if installedOriginals && !didSave {
                try? fileManager.removeItem(at: activeOriginals)
            }
            throw error
        }
    }

    nonisolated private static func directoryIsEmptyOrAbsent(
        _ directory: URL,
        fileManager: FileManager
    ) throws -> Bool {
        guard fileManager.fileExists(atPath: directory.path) else { return true }
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return true }
        for case let item as URL in enumerator {
            if try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory != true {
                return false
            }
        }
        return true
    }

    nonisolated private static func copyMedia(
        _ record: ImageTransfer,
        packageRoot: URL,
        mediaRoot: URL
    ) throws -> String {
        try Task.checkCancellation()
        let store = MediaStore(rootURL: mediaRoot, fileManager: .default)
        let stored = try store.storeOriginal(MediaSource(
            url: packageRoot.appendingPathComponent(record.mediaPath),
            originalFilename: record.originalFilename,
            contentType: record.contentType
        ), id: record.id)
        guard stored.relativePath == record.relativePath,
              stored.byteCount == record.byteCount,
              stored.checksum == record.checksum,
              stored.pixelWidth == record.pixelWidth,
              stored.pixelHeight == record.pixelHeight else {
            try? store.removeOriginal(at: stored.relativePath)
            throw TransferPackageError.mediaMismatch
        }
        return stored.relativePath
    }

    nonisolated private static func materialize(
        package: ValidatedPackage,
        context: ModelContext,
        mediaStore: MediaStore,
        copyOriginals: Bool = true
    ) throws -> [String] {
        var entries: [UUID: Entry] = [:]
        for record in package.data.entries {
            try Task.checkCancellation()
            guard let kind = EntryKind(rawValue: record.kind),
                  let status = EntryStatus(rawValue: record.status) else {
                throw TransferPackageError.invalidObject("entry")
            }
            let entry = Entry(
                id: record.id,
                kind: kind,
                status: status,
                title: record.title,
                body: record.body,
                createdAt: record.createdAt,
                occurredAt: record.occurredAt,
                updatedAt: record.updatedAt,
                periodStart: record.periodStart,
                periodEnd: record.periodEnd
            )
            entries[entry.id] = entry
            context.insert(entry)
        }

        var restoredPaths: [String] = []
        do {
            for record in package.data.images.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                try Task.checkCancellation()
                guard let entry = entries[record.entryID] else { throw TransferPackageError.missingEndpoint }
                if copyOriginals {
                    restoredPaths.append(try copyMedia(
                        record,
                        packageRoot: package.extractedRoot,
                        mediaRoot: mediaStore.rootURL
                    ))
                }
                let metadata = ImageMetadata(
                    id: record.id,
                    relativePath: record.relativePath,
                    originalFilename: record.originalFilename,
                    contentType: record.contentType,
                    byteCount: record.byteCount,
                    pixelWidth: record.pixelWidth,
                    pixelHeight: record.pixelHeight,
                    checksum: record.checksum,
                    sortOrder: record.sortOrder,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
                )
                metadata.entry = entry
                entry.images.append(metadata)
                context.insert(metadata)
            }
            for record in package.data.tags {
                try Task.checkCancellation()
                context.insert(Tag(
                    id: record.id,
                    displayName: record.displayName,
                    normalizedName: record.normalizedName,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
                ))
            }
            for record in package.data.habits {
                try Task.checkCancellation()
                guard let status = HabitStatus(rawValue: record.status) else {
                    throw TransferPackageError.invalidObject("habit")
                }
                context.insert(Habit(
                    id: record.id,
                    name: record.name,
                    normalizedName: record.normalizedName,
                    status: status,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
                ))
            }
            for record in package.data.goals {
                try Task.checkCancellation()
                guard let kind = GoalKind(rawValue: record.kind),
                      let status = GoalStatus(rawValue: record.status) else {
                    throw TransferPackageError.invalidObject("goal")
                }
                context.insert(Goal(
                    id: record.id,
                    kind: kind,
                    title: record.title,
                    normalizedTitle: record.normalizedTitle,
                    status: status,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt,
                    completedAt: record.completedAt
                ))
            }
            for record in package.data.habitLogs {
                try Task.checkCancellation()
                context.insert(HabitLog(
                    id: record.id,
                    habitID: record.habitID,
                    occurredAt: record.occurredAt,
                    isCompleted: record.isCompleted,
                    quantity: record.quantity,
                    unit: record.unit,
                    result: record.result,
                    linkedEntryID: record.linkedEntryID,
                    createdAt: record.createdAt
                ))
            }
            for record in package.data.goalEvents {
                try Task.checkCancellation()
                guard let kind = GoalLifecycleEventKind(rawValue: record.kind) else {
                    throw TransferPackageError.invalidObject("goalEvent")
                }
                context.insert(GoalLifecycleEvent(
                    id: record.id,
                    goalID: record.goalID,
                    kind: kind,
                    occurredAt: record.occurredAt,
                    createdAt: record.createdAt
                ))
            }
            for record in package.data.links {
                try Task.checkCancellation()
                guard let sourceType = LinkObjectType(rawValue: record.sourceType),
                      let targetType = LinkObjectType(rawValue: record.targetType),
                      let kind = ObjectLinkKind(rawValue: record.kind) else {
                    throw TransferPackageError.invalidObject("link")
                }
                context.insert(ObjectLink(
                    id: record.id,
                    sourceType: sourceType,
                    sourceID: record.sourceID,
                    targetType: targetType,
                    targetID: record.targetID,
                    kind: kind,
                    createdAt: record.createdAt
                ))
            }
            return restoredPaths
        } catch {
            for path in restoredPaths { try? mediaStore.removeOriginal(at: path) }
            throw error
        }
    }

    nonisolated private static func verifySnapshot(
        _ expected: TransferData,
        context: ModelContext,
        mediaStore: MediaStore
    ) throws {
        let actual = try TransferSnapshot.make(context: context)
        guard actual == expected else { throw TransferPackageError.verificationFailed }
        for image in actual.images {
            let measured = try Hasher.sha256AndSize(fileAt: mediaStore.fileURL(for: image.relativePath))
            guard measured.size == image.byteCount, measured.sha256 == image.checksum else {
                throw TransferPackageError.mediaMismatch
            }
        }
    }

    nonisolated private static func ensureTargetIsEmpty(_ context: ModelContext) throws {
        let count = try context.fetchCount(FetchDescriptor<Entry>())
            + context.fetchCount(FetchDescriptor<ImageMetadata>())
            + context.fetchCount(FetchDescriptor<Tag>())
            + context.fetchCount(FetchDescriptor<ObjectLink>())
            + context.fetchCount(FetchDescriptor<Habit>())
            + context.fetchCount(FetchDescriptor<HabitLog>())
            + context.fetchCount(FetchDescriptor<Goal>())
            + context.fetchCount(FetchDescriptor<GoalLifecycleEvent>())
        guard count == 0 else { throw TransferPackageError.targetNotEmpty }
    }

}

private enum TransferCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

private enum Hasher {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256AndSize(fileAt url: URL) throws -> (sha256: String, size: Int64) {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var hasher = SHA256()
        var size: Int64 = 0
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
            size += Int64(chunk.count)
        }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), size)
    }
}

private enum TransferSnapshot {
    static func make(context: ModelContext) throws -> TransferData {
        try Task.checkCancellation()
        let entries = try context.fetch(FetchDescriptor<Entry>())
        try Task.checkCancellation()
        let images = try context.fetch(FetchDescriptor<ImageMetadata>())
        try Task.checkCancellation()
        let tags = try context.fetch(FetchDescriptor<Tag>())
        try Task.checkCancellation()
        let links = try context.fetch(FetchDescriptor<ObjectLink>())
        try Task.checkCancellation()
        let habits = try context.fetch(FetchDescriptor<Habit>())
        try Task.checkCancellation()
        let logs = try context.fetch(FetchDescriptor<HabitLog>())
        try Task.checkCancellation()
        let goals = try context.fetch(FetchDescriptor<Goal>())
        try Task.checkCancellation()
        let events = try context.fetch(FetchDescriptor<GoalLifecycleEvent>())
        let sortUUID: (UUID, UUID) -> Bool = { $0.uuidString < $1.uuidString }
        return TransferData(
            entries: try cancellableMap(entries) {
                EntryTransfer(
                    id: $0.id,
                    kind: $0.kindRawValue,
                    status: $0.statusRawValue,
                    title: $0.title,
                    body: $0.body,
                    createdAt: $0.createdAt,
                    occurredAt: $0.occurredAt,
                    updatedAt: $0.updatedAt,
                    periodStart: $0.periodStart,
                    periodEnd: $0.periodEnd
                )
            }.sorted { sortUUID($0.id, $1.id) },
            images: try cancellableMap(images) { image in
                guard let entryID = image.entry?.id else {
                    throw TransferPackageError.missingEndpoint
                }
                let extensionValue = URL(fileURLWithPath: image.relativePath).pathExtension.lowercased()
                guard !extensionValue.isEmpty else { throw TransferPackageError.invalidObject("image") }
                return ImageTransfer(
                    id: image.id,
                    entryID: entryID,
                    relativePath: image.relativePath,
                    mediaPath: "media/image-\(image.id.uuidString.lowercased()).\(extensionValue)",
                    originalFilename: image.originalFilename,
                    contentType: image.contentType,
                    byteCount: image.byteCount,
                    pixelWidth: image.pixelWidth,
                    pixelHeight: image.pixelHeight,
                    checksum: image.checksum,
                    sortOrder: image.sortOrder,
                    createdAt: image.createdAt,
                    updatedAt: image.updatedAt
                )
            }.sorted { sortUUID($0.id, $1.id) },
            tags: try cancellableMap(tags) {
                TagTransfer(
                    id: $0.id,
                    displayName: $0.displayName,
                    normalizedName: $0.normalizedName,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }.sorted { sortUUID($0.id, $1.id) },
            links: try cancellableMap(links) {
                LinkTransfer(
                    id: $0.id,
                    sourceType: $0.sourceTypeRawValue,
                    sourceID: $0.sourceID,
                    targetType: $0.targetTypeRawValue,
                    targetID: $0.targetID,
                    kind: $0.kindRawValue,
                    deduplicationKey: $0.deduplicationKey,
                    createdAt: $0.createdAt
                )
            }.sorted { sortUUID($0.id, $1.id) },
            habits: try cancellableMap(habits) {
                HabitTransfer(
                    id: $0.id,
                    name: $0.name,
                    normalizedName: $0.normalizedName,
                    status: $0.statusRawValue,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }.sorted { sortUUID($0.id, $1.id) },
            habitLogs: try cancellableMap(logs) {
                HabitLogTransfer(
                    id: $0.id,
                    habitID: $0.habitID,
                    occurredAt: $0.occurredAt,
                    isCompleted: $0.isCompleted,
                    quantity: $0.quantity,
                    unit: $0.unit,
                    result: $0.result,
                    linkedEntryID: $0.linkedEntryID,
                    createdAt: $0.createdAt
                )
            }.sorted { sortUUID($0.id, $1.id) },
            goals: try cancellableMap(goals) {
                GoalTransfer(
                    id: $0.id,
                    kind: $0.kindRawValue,
                    title: $0.title,
                    normalizedTitle: $0.normalizedTitle,
                    status: $0.statusRawValue,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    completedAt: $0.completedAt
                )
            }.sorted { sortUUID($0.id, $1.id) },
            goalEvents: try cancellableMap(events) {
                GoalEventTransfer(
                    id: $0.id,
                    goalID: $0.goalID,
                    kind: $0.kindRawValue,
                    occurredAt: $0.occurredAt,
                    createdAt: $0.createdAt
                )
            }.sorted { sortUUID($0.id, $1.id) }
        )
    }

    private static func cancellableMap<Input, Output>(
        _ values: [Input],
        transform: (Input) throws -> Output
    ) throws -> [Output] {
        try values.map { value in
            try Task.checkCancellation()
            return try transform(value)
        }
    }
}
