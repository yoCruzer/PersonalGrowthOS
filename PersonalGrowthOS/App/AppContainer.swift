import Foundation
import SwiftData

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
        var retainedStore: StartupRetainedData?
        var keepRetainedStore = false
        defer { if !keepRetainedStore { retainedStore?.cleanup() } }
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
            // Freeze SQLite/WAL bytes before opening/migrating or running any repair.
            retainedStore = try StartupRetainedData.capture(rootURL: rootURL)
            stage = .storeOpen
            let modelContainer = try PersistenceContainerFactory.makeOnDisk(
                at: storeDirectory.appendingPathComponent("PersonalGrowthOS.sqlite")
            )

            stage = .integrity
            modelContainer.mainContext.autosaveEnabled = false
            do { try TodoIntegrity.validate(context: modelContainer.mainContext) }
            catch {
                keepRetainedStore = true
                throw StartupRetainedDataFailure(diagnostic: FailureDiagnostic(error: error, stage: .integrity), retained: retainedStore!)
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
        } catch {
            throw AppDiagnosticFailure(error, stage: stage)
        }
    }
}


struct StartupRetainedDataFailure: Error {
    let diagnostic: FailureDiagnostic
    let retained: StartupRetainedData
}

/// A support recovery archive, deliberately separate from validated v7 restore.
/// No AppShell, import, reconciliation, autosave, bootstrap or normal writer runs
/// after a Todo integrity failure. The pre-open store bytes remain frozen.
struct StartupRetainedData: Sendable {
    let rootURL: URL
    let snapshotURL: URL
    static func capture(rootURL: URL) throws -> Self {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("PGOS-Retained-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        do {
            let store = rootURL.appendingPathComponent("Store", isDirectory: true)
            if FileManager.default.fileExists(atPath: store.path) {
                try FileManager.default.copyItem(at: store, to: temporary.appendingPathComponent("Store", isDirectory: true))
            }
            return Self(rootURL: rootURL, snapshotURL: temporary)
        } catch { try? FileManager.default.removeItem(at: temporary); throw error }
    }
    func archive(diagnostic: String) throws -> URL {
        let fm = FileManager.default
        let diagnosticURL = snapshotURL.appendingPathComponent("RECOVERY.txt")
        try Data(("Raw retained data for support recovery. This is NOT a v7 import package. Keep this private.\n" + diagnostic).utf8).write(to: diagnosticURL, options: .atomic)
        var sources = [ZIPSource(path: "RECOVERY.txt", fileURL: diagnosticURL)]
        func appendFiles(from directory: URL, prefix: String, excludingStore: Bool = false) throws {
            guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { throw CocoaError(.fileReadUnknown) }
            for case let url as URL in enumerator {
                try Task.checkCancellation()
                let relative = String(url.path.dropFirst(directory.path.count + 1))
                if excludingStore && (relative == "Store" || relative.hasPrefix("Store/")) { enumerator.skipDescendants(); continue }
                let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard attributes.isSymbolicLink != true else { throw ZIPArchiveError.unsafePath }
                if attributes.isRegularFile == true { sources.append(ZIPSource(path: prefix + relative, fileURL: url)) }
            }
        }
        let store = snapshotURL.appendingPathComponent("Store", isDirectory: true)
        if fm.fileExists(atPath: store.path) { try appendFiles(from: store, prefix: "Store/") }
        try appendFiles(from: rootURL, prefix: "", excludingStore: true)
        let output = snapshotURL.appendingPathComponent("PersonalGrowthOS-Retained-Data.zip")
        do { try ZIPArchiveWriter.write(sources: sources, to: output); return output }
        catch { try? fm.removeItem(at: output); throw error }
    }
    func cleanup() { try? FileManager.default.removeItem(at: snapshotURL) }
}
