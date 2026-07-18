import Foundation
import SwiftData

@MainActor
struct AppContainer {
    let configuration: AppConfiguration
    let modelContainer: ModelContainer
    let mediaStore: MediaStore

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

        return AppContainer(
            configuration: configuration,
            modelContainer: modelContainer,
            mediaStore: MediaStore(rootURL: rootURL, fileManager: fileManager)
        )
    }
}
