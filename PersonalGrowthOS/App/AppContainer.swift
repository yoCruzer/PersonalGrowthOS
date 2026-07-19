import Foundation
import SwiftData

enum StartupMediaReconciler {
    static func reconcile(
        mediaStore: MediaStore,
        thumbnailStore: ThumbnailStore,
        imageMetadata: [ImageMetadata]
    ) throws -> MediaIntegrityReport {
        let referencedPaths = Set(imageMetadata.map(\.relativePath))
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
        fileManager: FileManager = .default
    ) throws -> AppContainer {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryName = configuration.launchMode == .uiTesting
            ? "PersonalGrowthOS-UITesting"
            : "PersonalGrowthOS"
        let rootURL = applicationSupport.appendingPathComponent(directoryName, isDirectory: true)

        if configuration.launchMode == .uiTesting,
           configuration.resetDataOnLaunch,
           fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.removeItem(at: rootURL)
        }

        let storeDirectory = rootURL.appendingPathComponent("Store", isDirectory: true)
        try fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let modelContainer = try PersistenceContainerFactory.makeOnDisk(
            at: storeDirectory.appendingPathComponent("PersonalGrowthOS.sqlite")
        )

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
        try LinkIntegrityService.validate(context: modelContainer.mainContext)
        return AppContainer(
            configuration: configuration,
            modelContainer: modelContainer,
            mediaStore: mediaStore,
            thumbnailStore: thumbnailStore,
            mediaIntegrityReport: integrityReport
        )
    }
}
