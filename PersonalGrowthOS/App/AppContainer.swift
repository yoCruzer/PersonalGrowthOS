import Foundation
import SwiftData
import SQLite3
import CryptoKit

enum StartupMediaReconciler {
    static func reconcile(
        mediaStore: MediaStore,
        thumbnailStore: ThumbnailStore,
        imageMetadata: [ImageMetadata]
    ) throws -> MediaIntegrityReport {
        let referencedPaths = Set(imageMetadata.map(\.relativePath))
        CaptureMediaJournal.reconcile(mediaStore: mediaStore, referencedPaths: referencedPaths)
        try mediaStore.recoverInterruptedTrash(referencedOriginalPaths: referencedPaths)
        var report = try mediaStore.reconcile(referencedOriginalPaths: referencedPaths)
        report.removedThumbnailCount = try thumbnailStore.reconcile(
            liveImageIDs: Set(imageMetadata.map(\.id))
        )
        return report
    }
}

@MainActor
struct AppContainer {
    let configuration: AppConfiguration
    let modelContainer: ModelContainer
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore
    let importExportService: ImportExportService
    let mediaIntegrityReport: MediaIntegrityReport

    init(
        configuration: AppConfiguration,
        modelContainer: ModelContainer,
        mediaStore: MediaStore,
        thumbnailStore: ThumbnailStore? = nil,
        importExportService: ImportExportService? = nil,
        mediaIntegrityReport: MediaIntegrityReport = MediaIntegrityReport()
    ) {
        self.configuration = configuration
        self.modelContainer = modelContainer
        self.mediaStore = mediaStore
        self.thumbnailStore = thumbnailStore ?? ThumbnailStore(
            rootURL: mediaStore.rootURL.appendingPathComponent("ThumbnailCache", isDirectory: true),
            mediaStore: mediaStore
        )
        self.importExportService = importExportService ?? ImportExportService(
            context: modelContainer.mainContext,
            mediaStore: mediaStore
        )
        self.mediaIntegrityReport = mediaIntegrityReport
    }

    static func make(
        configuration: AppConfiguration,
        fileManager: FileManager = .default,
        rootURLOverride: URL? = nil
    ) throws -> AppContainer {
        var stage = FailureDiagnostic.Stage.startupPaths
        var startupStep: FailureDiagnostic.StartupStep?
        var retainedStore: StartupRetainedData?
        func integrityFailure(_ error: Error, rootURL: URL) -> StartupRetainedDataFailure {
            let diagnostic = FailureDiagnostic(error: error, stage: .integrity)
            do {
                return StartupRetainedDataFailure(diagnostic: diagnostic,
                    retained: try StartupRetainedData.capture(rootURL: rootURL, fileManager: fileManager), snapshotFailure: nil)
            } catch {
                return StartupRetainedDataFailure(diagnostic: diagnostic, retained: retainedStore,
                    snapshotFailure: (error as? AppDiagnosticFailure)?.diagnostic ?? FailureDiagnostic(error: error, stage: .storeOpen))
            }
        }
        do {
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directoryName = configuration.launchMode == .uiTesting
                ? "PersonalGrowthOS-UITesting"
                : "PersonalGrowthOS"
            let rootURL = rootURLOverride ?? applicationSupport.appendingPathComponent(directoryName, isDirectory: true)

            if configuration.launchMode == .uiTesting,
               configuration.resetDataOnLaunch,
               fileManager.fileExists(atPath: rootURL.path) {
                try fileManager.removeItem(at: rootURL)
            }

            let storeDirectory = rootURL.appendingPathComponent("Store", isDirectory: true)
            try fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
            stage = .storeOpen
            let storeURL = storeDirectory.appendingPathComponent("PersonalGrowthOS.sqlite")
            // Only a store that may migrate needs a mandatory pre-open copy.
            if fileManager.fileExists(atPath: storeURL.path) {
                if StartupStoreProtection.isCurrentStore(at: storeURL) {
                    startupStep = .storeReadOnlyOpen
                    // Read-only preflight prevents even a normal writable open
                    // from touching an already-invalid current store.
                    try autoreleasepool {
                        let readOnly = try PersistenceContainerFactory.makeOnDisk(at: storeURL, allowsSave: false)
                        readOnly.mainContext.autosaveEnabled = false
                        do { try TodoIntegrity.validate(context: readOnly.mainContext) }
                        catch { throw integrityFailure(error, rootURL: rootURL) }
                    }
                } else {
                    startupStep = .preMigrationProtection
                    retainedStore = try StartupRetainedData.capture(rootURL: rootURL, purpose: .beforeMigration, fileManager: fileManager)
                }
            }
            startupStep = .storeWritableOpen
            let modelContainer = try PersistenceContainerFactory.makeOnDisk(
                at: storeDirectory.appendingPathComponent("PersonalGrowthOS.sqlite")
            )

            stage = .integrity
            startupStep = nil
            modelContainer.mainContext.autosaveEnabled = false
            do { try TodoIntegrity.validate(context: modelContainer.mainContext) }
            catch {
                throw integrityFailure(error, rootURL: rootURL)
            }
            modelContainer.mainContext.autosaveEnabled = true
            stage = .mediaRecovery
            let mediaStore = MediaStore(rootURL: rootURL, fileManager: fileManager)
            try? ImportExportService.cleanupInterruptedTransfers(
                mediaRootURL: rootURL,
                fileManager: fileManager
            )
            let imageMetadata = try modelContainer.mainContext.fetch(FetchDescriptor<ImageMetadata>())
            let caches = try fileManager.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let thumbnailStore = ThumbnailStore(
                rootURL: caches.appendingPathComponent("PersonalGrowthOS/Thumbnails", isDirectory: true),
                mediaStore: mediaStore,
                fileManager: fileManager
            )
            let integrityReport = try StartupMediaReconciler.reconcile(
                mediaStore: mediaStore,
                thumbnailStore: thumbnailStore,
                imageMetadata: imageMetadata
            )
            stage = .integrity
            _ = try HabitAnalyticsMigrationBootstrap.apply(context: modelContainer.mainContext)
            try LinkIntegrityService.validate(context: modelContainer.mainContext)
            return AppContainer(
                configuration: configuration,
                modelContainer: modelContainer,
                mediaStore: mediaStore,
                thumbnailStore: thumbnailStore,
                mediaIntegrityReport: integrityReport
            )
        } catch let retained as StartupRetainedDataFailure {
            throw retained
        } catch let diagnostic as AppDiagnosticFailure {
            throw diagnostic
        } catch {
            throw AppDiagnosticFailure(error, stage: stage, startupStep: startupStep)
        }
    }
}


struct StartupRetainedDataFailure: Error {
    let diagnostic: FailureDiagnostic
    let retained: StartupRetainedData?
    let snapshotFailure: FailureDiagnostic?
}

/// Inspect SQLite metadata read-only, including committed WAL, without opening
/// SwiftData or allowing migration. Unreadable/unknown metadata is conservative.
enum StartupStoreProtection {
    static func isCurrentStore(at url: URL) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }; return false
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1_000)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT Z_PLIST FROM Z_METADATA", -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { return false }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        guard let metadata = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return false }
        return metadata["NSStoreModelVersionIdentifiers"] as? [String] == [PersonalGrowthSchemaV11.versionIdentifier.description]
    }

    // Content identity ignores SQLite header/checkpoint changes. Equal logical
    // stores reuse a fault snapshot across process restart; a genuinely changed
    // store gets its own copy without overwriting earlier unexported evidence.
    static func fingerprint(at url: URL) throws -> String {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }; throw CocoaError(.fileReadCorruptFile)
        }
        defer { sqlite3_close(db) }
        var hash = SHA256()
        func add(_ data: Data) { hash.update(data: Data("\(data.count):".utf8)); hash.update(data: data) }
        func query(_ sql: String, row: (OpaquePointer) throws -> Void) throws {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw CocoaError(.fileReadCorruptFile) }
            defer { sqlite3_finalize(statement) }
            var result = sqlite3_step(statement)
            while result == SQLITE_ROW { try row(statement); result = sqlite3_step(statement) }
            guard result == SQLITE_DONE else { throw CocoaError(.fileReadCorruptFile) }
        }
        var tables: [String] = []
        try query("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name != 'Z_METADATA' ORDER BY name") {
            tables.append(String(cString: sqlite3_column_text($0, 0)))
        }
        for table in tables {
            add(Data(table.utf8))
            let quoted = table.replacingOccurrences(of: "\"", with: "\"\"")
            try query("SELECT * FROM \"\(quoted)\" ORDER BY rowid") { statement in
                add(Data("row".utf8))
                for column in 0..<sqlite3_column_count(statement) {
                    let type = sqlite3_column_type(statement, column)
                    add(Data("\(type)".utf8))
                    switch type {
                    case SQLITE_INTEGER: add(Data("\(sqlite3_column_int64(statement, column))".utf8))
                    case SQLITE_FLOAT: add(Data("\(sqlite3_column_double(statement, column).bitPattern)".utf8))
                    case SQLITE_TEXT, SQLITE_BLOB:
                        let count = Int(sqlite3_column_bytes(statement, column))
                        if let bytes = sqlite3_column_blob(statement, column) { add(Data(bytes: bytes, count: count)) }
                        else { add(Data()) }
                    default: add(Data())
                    }
                }
            }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// A reader pins the WAL while BEGIN IMMEDIATE excludes writers. Keep the
    /// reader alive through writer close so that closing our writer cannot
    /// checkpoint/truncate the source WAL. SHM is disposable, never archived.
    static func withFrozenStore<T>(at url: URL, _ body: () throws -> T) throws -> T {
        var reader: OpaquePointer?, writer: OpaquePointer?
        func check(_ code: Int32) throws {
            guard code == SQLITE_OK else { throw NSError(domain: "SQLite", code: Int(code)) }
        }
        try check(sqlite3_open_v2(url.path, &reader, SQLITE_OPEN_READONLY, nil))
        defer { if let reader { sqlite3_close(reader) } }
        try check(sqlite3_open_v2(url.path, &writer, SQLITE_OPEN_READWRITE, nil))
        defer { if let writer { sqlite3_close(writer) } }
        sqlite3_busy_timeout(writer, 1_000)
        try check(sqlite3_exec(writer, "BEGIN IMMEDIATE", nil, nil, nil))
        defer { sqlite3_exec(writer, "ROLLBACK", nil, nil, nil) }
        sqlite3_busy_timeout(reader, 1_000)
        try check(sqlite3_exec(reader, "BEGIN; SELECT Z_PLIST FROM Z_METADATA", nil, nil, nil))
        return try body()
    }
}

/// Durable pre-migration protection plus one snapshot per failing store content.
/// Completed copies are never automatically deleted, including after ZIP creation
/// or ShareLink dismissal: neither proves an external export was safely saved.
struct StartupRetainedData: Sendable {
    enum Purpose: String { case beforeMigration = "BeforeMigration", integrityFailure = "IntegrityFailure" }
    let rootURL: URL
    let snapshotURL: URL

    private static func storeSignature(_ directory: URL) throws -> [String: String] {
        let fm = FileManager.default
        guard let files = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { throw CocoaError(.fileReadUnknown) }
        var result: [String: String] = [:]
        for case let url as URL in files {
            let relative = String(url.path.dropFirst(directory.path.count + 1))
            if relative == "PersonalGrowthOS.sqlite-shm" { continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw ZIPArchiveError.unsafePath }
            if values.isRegularFile == true {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                var hash = SHA256()
                while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
                result[relative] = hash.finalize().map { String(format: "%02x", $0) }.joined()
            }
        }
        guard result["PersonalGrowthOS.sqlite"] != nil else { throw CocoaError(.fileReadCorruptFile) }
        return result
    }

    static func capture(rootURL: URL, purpose: Purpose = .integrityFailure, fileManager: FileManager = .default) throws -> Self {
        let recoveryRoot = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        try fileManager.createDirectory(at: recoveryRoot, withIntermediateDirectories: true)
        let lease = try CaptureFileLease(url: recoveryRoot.appendingPathComponent(".lock"))
        defer { withExtendedLifetime(lease) {} }
        let store = rootURL.appendingPathComponent("Store", isDirectory: true)
        return try StartupStoreProtection.withFrozenStore(at: store.appendingPathComponent("PersonalGrowthOS.sqlite")) {
            let signature = try storeSignature(store)
            let identity: String
            if purpose == .integrityFailure {
                let logical = try StartupStoreProtection.fingerprint(at: store.appendingPathComponent("PersonalGrowthOS.sqlite"))
                let external = signature.filter { !["PersonalGrowthOS.sqlite", "PersonalGrowthOS.sqlite-wal"].contains($0.key) }
                let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
                let hash = SHA256.hash(data: Data(logical.utf8) + (try encoder.encode(external)))
                identity = "-" + hash.map { String(format: "%02x", $0) }.joined()
            } else { identity = "" }
            let snapshot = recoveryRoot.appendingPathComponent(purpose.rawValue + identity, isDirectory: true)
            let completed = snapshot.appendingPathComponent("COMPLETE")
            if fileManager.fileExists(atPath: snapshot.path) {
                do {
                    let expected = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: completed))
                    guard try storeSignature(snapshot.appendingPathComponent("Store")) == expected else { throw CocoaError(.fileReadCorruptFile) }
                } catch {
                    throw AppDiagnosticFailure(error, stage: .storeOpen, startupStep: .snapshotValidation)
                }
                return Self(rootURL: rootURL, snapshotURL: snapshot)
            }
            let staging = recoveryRoot.appendingPathComponent("." + purpose.rawValue + "-building", isDirectory: true)
            // Only incomplete, unpublished staging is disposable. Source stays intact.
            if fileManager.fileExists(atPath: staging.path) { try fileManager.removeItem(at: staging) }
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            do {
                let original = signature
                try fileManager.copyItem(at: store, to: staging.appendingPathComponent("Store", isDirectory: true))
                let shm = staging.appendingPathComponent("Store/PersonalGrowthOS.sqlite-shm")
                if fileManager.fileExists(atPath: shm.path) { try fileManager.removeItem(at: shm) }
                // PASSIVE checkpoints may copy WAL pages without taking the
                // writer lock. Publish only if both source and copied raw files
                // match the same signature; a race fails closed for safe Retry.
                guard try storeSignature(store) == original,
                      try storeSignature(staging.appendingPathComponent("Store")) == original else { throw CocoaError(.fileReadUnknown) }
                try JSONEncoder().encode(original).write(to: staging.appendingPathComponent("COMPLETE"), options: .atomic)
                try fileManager.moveItem(at: staging, to: snapshot)
                return Self(rootURL: rootURL, snapshotURL: snapshot)
            } catch { try? fileManager.removeItem(at: staging); throw error }
        }
    }

    func archive(diagnostic: String, write: ([ZIPSource], URL) throws -> Void = ZIPArchiveWriter.write) throws -> URL {
        let fm = FileManager.default
        let lease = try CaptureFileLease(url: snapshotURL.deletingLastPathComponent().appendingPathComponent(".lock"))
        defer { withExtendedLifetime(lease) {} }
        let expected = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: snapshotURL.appendingPathComponent("COMPLETE")))
        guard try Self.storeSignature(snapshotURL.appendingPathComponent("Store")) == expected else { throw CocoaError(.fileReadCorruptFile) }
        let diagnosticURL = snapshotURL.appendingPathComponent("RECOVERY.txt")
        try Data(("Raw retained data for support recovery. This is NOT a v7 import package. Keep this private.\n" + diagnostic).utf8).write(to: diagnosticURL, options: .atomic)
        var sources = [ZIPSource(path: "RECOVERY.txt", fileURL: diagnosticURL)]
        func appendFiles(from directory: URL, prefix: String, excludingInfrastructure: Bool = false) throws {
            guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { throw CocoaError(.fileReadUnknown) }
            for case let url as URL in enumerator {
                try Task.checkCancellation()
                let relative = String(url.path.dropFirst(directory.path.count + 1))
                if excludingInfrastructure && (["Store", "Recovery"].contains(relative) || relative.hasPrefix("Store/") || relative.hasPrefix("Recovery/")) { enumerator.skipDescendants(); continue }
                let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard attributes.isSymbolicLink != true else { throw ZIPArchiveError.unsafePath }
                if attributes.isRegularFile == true { sources.append(ZIPSource(path: prefix + relative, fileURL: url)) }
            }
        }
        try appendFiles(from: snapshotURL.appendingPathComponent("Store", isDirectory: true), prefix: "Store/")
        try appendFiles(from: rootURL, prefix: "", excludingInfrastructure: true)
        let output = snapshotURL.appendingPathComponent("PersonalGrowthOS-Retained-Data.zip")
        let partial = snapshotURL.appendingPathComponent(".export-building.zip")
        do {
            try write(sources, partial)
            if fm.fileExists(atPath: output.path) { _ = try fm.replaceItemAt(output, withItemAt: partial) }
            else { try fm.moveItem(at: partial, to: output) }
            return output
        } catch { try? fm.removeItem(at: partial); throw error }
    }
}
