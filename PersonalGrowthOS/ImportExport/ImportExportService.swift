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

    func exportPackage() throws -> ExportPackageLease {
        log("export.started")
        try LinkIntegrityService.validate(context: context)
        let transfer = try TransferSnapshot.make(context: context)
        let operationID = UUID()
        let assembly = workspaceRoot
            .appendingPathComponent("Assembly", isDirectory: true)
            .appendingPathComponent(operationID.uuidString.lowercased(), isDirectory: true)
        let ready = workspaceRoot.appendingPathComponent("Ready", isDirectory: true)
        var archiveURL: URL?
        do {
            try fileManager.createDirectory(at: assembly, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: ready, withIntermediateDirectories: true)
            let dataURL = assembly.appendingPathComponent("data.json")
            let manifestURL = assembly.appendingPathComponent("manifest.json")
            let encodedData = try TransferCoding.encoder.encode(transfer)
            try encodedData.write(to: dataURL, options: .atomic)

            var sources = [ZIPSource(path: "data.json", fileURL: dataURL)]
            var mediaRecords: [ExportMediaFileRecord] = []
            for image in transfer.images.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                let sourceURL = try mediaStore.fileURL(for: image.relativePath)
                guard fileManager.fileExists(atPath: sourceURL.path) else {
                    throw TransferPackageError.missingMedia
                }
                let measured = try Hasher.sha256AndSize(fileAt: sourceURL)
                guard measured.size == image.byteCount, measured.sha256 == image.checksum else {
                    throw TransferPackageError.mediaMismatch
                }
                let packagePath = image.mediaPath
                let destination = assembly.appendingPathComponent(packagePath)
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: sourceURL, to: destination)
                sources.append(ZIPSource(path: packagePath, fileURL: destination))
                mediaRecords.append(ExportMediaFileRecord(
                    imageID: image.id,
                    path: packagePath,
                    byteCount: measured.size,
                    sha256: measured.sha256
                ))
            }

            let build = appVersion()
            let dataHash = Hasher.sha256(encodedData)
            let manifest = ExportManifest(
                formatIdentifier: ExportManifest.formatIdentifier,
                packageSchemaVersion: ExportManifest.currentPackageSchemaVersion,
                appVersion: build.version,
                appBuild: build.build,
                exportID: operationID,
                exportedAt: now(),
                objectCounts: transfer.objectCounts,
                dataFile: ExportFileRecord(
                    path: "data.json",
                    byteCount: Int64(encodedData.count),
                    sha256: dataHash
                ),
                mediaFiles: mediaRecords
            )
            try TransferCoding.encoder.encode(manifest).write(to: manifestURL, options: .atomic)
            sources.insert(ZIPSource(path: "manifest.json", fileURL: manifestURL), at: 0)

            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let filename = "PersonalGrowthOS-export-\(formatter.string(from: manifest.exportedAt)).zip"
            let destination = ready.appendingPathComponent(filename)
            archiveURL = destination
            try ZIPArchiveWriter.write(sources: sources, to: destination)
            try fileManager.removeItem(at: assembly)
            log("export.completed objects=\(transfer.totalObjectCount) media=\(transfer.images.count)")
            return ExportPackageLease(url: destination, fileManager: fileManager)
        } catch {
            try? fileManager.removeItem(at: assembly)
            if let archiveURL { try? fileManager.removeItem(at: archiveURL) }
            log("export.failed")
            throw error
        }
    }

    func importPackage(from selectedURL: URL) throws -> ImportResult {
        log("import.started")
        let operationRoot = workspaceRoot
            .appendingPathComponent("Import", isDirectory: true)
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        defer { try? fileManager.removeItem(at: operationRoot) }
        do {
            try ensureTargetIsEmpty(context)
            try fileManager.createDirectory(at: operationRoot, withIntermediateDirectories: true)
            let stagedArchive = operationRoot.appendingPathComponent("selected.zip")
            try fileManager.copyItem(at: selectedURL, to: stagedArchive)
            let extracted = operationRoot.appendingPathComponent("Extracted", isDirectory: true)
            let reader = try ZIPArchiveReader(
                archiveURL: stagedArchive,
                limits: limits,
                availableCapacity: try availableCapacity()
            )
            try reader.extractAll(to: extracted)
            let package = try decodeAndValidatePackage(at: extracted, archiveMembers: reader.members)

            let verificationRoot = operationRoot.appendingPathComponent("Verification", isDirectory: true)
            try verifyInIsolatedStore(package: package, rootURL: verificationRoot)
            try publicationCheckpoint?(.afterPreflight)
            try ensureTargetIsEmpty(context)
            try publish(package: package)
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

    private func decodeAndValidatePackage(
        at rootURL: URL,
        archiveMembers: [ZIPMember]
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

    private func verifyInIsolatedStore(package: ValidatedPackage, rootURL: URL) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let storeURL = rootURL.appendingPathComponent("Store.sqlite")
        do {
            let container = try PersistenceContainerFactory.makeOnDisk(at: storeURL)
            let temporaryMedia = MediaStore(
                rootURL: rootURL.appendingPathComponent("MediaRoot", isDirectory: true),
                fileManager: fileManager,
                availableCapacity: { .max }
            )
            _ = try materialize(package: package, context: container.mainContext, mediaStore: temporaryMedia)
            try container.mainContext.save()
            try LinkIntegrityService.validate(context: container.mainContext)
            try verifySnapshot(package.data, context: container.mainContext, mediaStore: temporaryMedia)
        }
        let reopened = try PersistenceContainerFactory.makeOnDisk(at: storeURL)
        let reopenedMedia = MediaStore(
            rootURL: rootURL.appendingPathComponent("MediaRoot", isDirectory: true),
            fileManager: fileManager,
            availableCapacity: { .max }
        )
        try LinkIntegrityService.validate(context: reopened.mainContext)
        try verifySnapshot(package.data, context: reopened.mainContext, mediaStore: reopenedMedia)
    }

    private func publish(package: ValidatedPackage) throws {
        var restoredPaths: [String] = []
        var didSave = false
        do {
            restoredPaths = try materialize(package: package, context: context, mediaStore: mediaStore)
            for index in restoredPaths.indices {
                try publicationCheckpoint?(.afterMediaCopy(index + 1))
            }
            try publicationCheckpoint?(.beforeSave)
            try LinkIntegrityService.validate(context: context)
            try context.save()
            didSave = true
            try LinkIntegrityService.validate(context: context)
            try verifySnapshot(package.data, context: context, mediaStore: mediaStore)
        } catch {
            if didSave {
                try? deleteAllData(context)
                try? context.save()
            } else {
                context.rollback()
            }
            for path in restoredPaths { try? mediaStore.removeOriginal(at: path) }
            throw error
        }
    }

    private func materialize(
        package: ValidatedPackage,
        context: ModelContext,
        mediaStore: MediaStore
    ) throws -> [String] {
        var entries: [UUID: Entry] = [:]
        for record in package.data.entries {
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
                guard let entry = entries[record.entryID] else { throw TransferPackageError.missingEndpoint }
                let packageURL = package.extractedRoot.appendingPathComponent(record.mediaPath)
                let stored = try mediaStore.storeOriginal(MediaSource(
                    url: packageURL,
                    originalFilename: record.originalFilename,
                    contentType: record.contentType
                ), id: record.id)
                restoredPaths.append(stored.relativePath)
                guard stored.relativePath == record.relativePath,
                      stored.byteCount == record.byteCount,
                      stored.checksum == record.checksum,
                      stored.pixelWidth == record.pixelWidth,
                      stored.pixelHeight == record.pixelHeight else {
                    throw TransferPackageError.mediaMismatch
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
                context.insert(Tag(
                    id: record.id,
                    displayName: record.displayName,
                    normalizedName: record.normalizedName,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
                ))
            }
            for record in package.data.habits {
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

    private func verifySnapshot(
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

    private func ensureTargetIsEmpty(_ context: ModelContext) throws {
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

    private func deleteAllData(_ context: ModelContext) throws {
        try context.fetch(FetchDescriptor<ObjectLink>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<HabitLog>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<GoalLifecycleEvent>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<ImageMetadata>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Entry>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Tag>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Habit>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Goal>()).forEach(context.delete)
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
            hasher.update(data: chunk)
            size += Int64(chunk.count)
        }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), size)
    }
}

@MainActor
private enum TransferSnapshot {
    static func make(context: ModelContext) throws -> TransferData {
        let entries = try context.fetch(FetchDescriptor<Entry>())
        let images = try context.fetch(FetchDescriptor<ImageMetadata>())
        let tags = try context.fetch(FetchDescriptor<Tag>())
        let links = try context.fetch(FetchDescriptor<ObjectLink>())
        let habits = try context.fetch(FetchDescriptor<Habit>())
        let logs = try context.fetch(FetchDescriptor<HabitLog>())
        let goals = try context.fetch(FetchDescriptor<Goal>())
        let events = try context.fetch(FetchDescriptor<GoalLifecycleEvent>())
        let sortUUID: (UUID, UUID) -> Bool = { $0.uuidString < $1.uuidString }
        return TransferData(
            entries: entries.map {
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
            images: try images.map { image in
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
            tags: tags.map {
                TagTransfer(
                    id: $0.id,
                    displayName: $0.displayName,
                    normalizedName: $0.normalizedName,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }.sorted { sortUUID($0.id, $1.id) },
            links: links.map {
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
            habits: habits.map {
                HabitTransfer(
                    id: $0.id,
                    name: $0.name,
                    normalizedName: $0.normalizedName,
                    status: $0.statusRawValue,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }.sorted { sortUUID($0.id, $1.id) },
            habitLogs: logs.map {
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
            goals: goals.map {
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
            goalEvents: events.map {
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
}
