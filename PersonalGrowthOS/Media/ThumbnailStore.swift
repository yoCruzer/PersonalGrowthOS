import Foundation
import ImageIO
import UIKit

final class ThumbnailStore {
    private let rootURL: URL
    private let mediaStore: MediaStore
    private let fileManager: FileManager

    init(rootURL: URL, mediaStore: MediaStore, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.mediaStore = mediaStore
        self.fileManager = fileManager
    }

    func image(for metadata: ImageMetadata, maximumPixelSize: Int = 512) -> UIImage? {
        let cacheURL = rootURL.appendingPathComponent("\(metadata.id.uuidString.lowercased()).jpg")
        if let image = UIImage(contentsOfFile: cacheURL.path) {
            return image
        }
        guard let originalURL = try? mediaStore.fileURL(for: metadata.relativePath),
              let source = CGImageSourceCreateWithURL(originalURL as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = UIImage(cgImage: cgImage)
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try? data.write(to: cacheURL, options: .atomic)
        }
        return image
    }

    func removeThumbnail(for imageID: UUID) {
        let url = rootURL.appendingPathComponent("\(imageID.uuidString.lowercased()).jpg")
        try? fileManager.removeItem(at: url)
    }

    func reconcile(liveImageIDs: Set<UUID>) throws -> Int {
        guard fileManager.fileExists(atPath: rootURL.path),
              let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey]
              ) else { return 0 }
        var removedCount = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true,
                  url.pathExtension.lowercased() == "jpg",
                  let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  !liveImageIDs.contains(id) else { continue }
            try fileManager.removeItem(at: url)
            removedCount += 1
        }
        return removedCount
    }
}
