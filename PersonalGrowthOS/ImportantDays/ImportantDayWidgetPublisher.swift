import Foundation
import SwiftData
import WidgetKit
import ImageIO
import UIKit
import OSLog
import Observation

/// Entirely synchronous on MainActor. No detached old snapshot can overtake a newer save/revocation.
@MainActor @Observable
final class ImportantDayWidgetPublisher {
    private static let log = Logger(subsystem: "com.yocruzer.PersonalGrowthOS", category: "ImportantDayWidget")
    private(set) var lastError: Bool = false
    func rebuild(context: ModelContext, mediaStore: MediaStore, store override: ImportantDayWidgetSnapshotStore? = nil) {
        do {
            let store = try override ?? ImportantDayWidgetSnapshotStore.shared()
            do { try store.revoke() }
            catch {
                WidgetCenter.shared.reloadAllTimelines()
                throw error
            }
            WidgetCenter.shared.reloadAllTimelines()
            let days = try context.fetch(FetchDescriptor<ImportantDay>())
            let covers = try context.fetch(FetchDescriptor<ImportantDayCover>())
            var records: [ImportantDayWidgetRecord] = [], images: [UUID: Data] = [:]
            for day in days.sorted(by: { $0.id.uuidString < $1.id.uuidString }) where !day.isArchived {
                let preferences = try day.preferences()
                guard preferences.desktopVisible else { continue }
                let rule = try day.rule(); try rule.validate()
                var name: String?
                if let cover = covers.first(where: { $0.dayID == day.id }),
                   let url = try? mediaStore.fileURL(for: cover.relativePath), let data = Self.smallImage(at: url) {
                    images[day.id] = data; name = day.id.uuidString.lowercased() + ".jpg"
                }
                records.append(.init(id: day.id, title: day.title, rule: rule, photoStyle: preferences.photoStyle,
                    cropX: preferences.cropX, cropY: preferences.cropY, coverFilename: name))
            }
            let snapshot = ImportantDayWidgetSnapshot(version: 1, generation: UUID(), generatedAt: Date(), records: records)
            try store.publish(snapshot, covers: images)
            lastError = false; WidgetCenter.shared.reloadAllTimelines()
        } catch {
            lastError = true
            Self.log.error("Widget projection failed code=\((error as NSError).code, privacy: .public)")
        }
    }
    static func smallImage(at url: URL) -> Data? {
        guard FileManager.default.fileExists(atPath: url.path),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 640, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary),
              let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.8), data.count <= 700_000 else { return nil }
        return data
    }
}
