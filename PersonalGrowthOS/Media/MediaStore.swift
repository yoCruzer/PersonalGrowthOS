import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct MediaSource {
    let url: URL
    let originalFilename: String
    let contentType: String
}

struct StoredMediaFile: Equatable {
    let id: UUID
    let relativePath: String
    let byteCount: Int64
    let checksum: String
    let pixelWidth: Int
    let pixelHeight: Int
}

struct TrashedMediaFile: Equatable {
    let originalRelativePath: String
    let trashRelativePath: String
}

struct MediaIntegrityReport: Equatable {
    var removedStagingFileCount = 0
    var missingOriginalPaths: [String] = []
    var recoveryFilePaths: [String] = []
    var removedThumbnailCount = 0

    var requiresAttention: Bool {
        !missingOriginalPaths.isEmpty || !recoveryFilePaths.isEmpty
    }
}

enum MediaStoreError: Error, Equatable {
    case sourceMissing
    case unsupportedContentType(String)
    case originalTooLarge(maximumBytes: Int64)
    case invalidRelativePath
    case destinationAlreadyExists
    case insufficientCapacity(requiredBytes: Int64, availableBytes: Int64)
    case invalidImage
    case contentTypeMismatch
    case imageTooLarge(maximumPixels: Int)
    case originalMissing
}

final class MediaStore {
    static let maximumOriginalByteCount: Int64 = 25 * 1_024 * 1_024
    static let maximumPixelCount = 80_000_000
    static let capacitySafetyReserve: Int64 = 100 * 1_024 * 1_024

    let rootURL: URL
    private let fileManager: FileManager
    private let availableCapacity: () throws -> Int64
    private let beforeStoreCopy: ((Int) throws -> Void)?
    private let beforeTrashRestore: (() throws -> Void)?
    private var storeCopyCount = 0

    init(
        rootURL: URL,
        fileManager: FileManager = .default,
        availableCapacity: (() throws -> Int64)? = nil,
        beforeStoreCopy: ((Int) throws -> Void)? = nil,
        beforeTrashRestore: (() throws -> Void)? = nil
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
        self.beforeStoreCopy = beforeStoreCopy
        self.beforeTrashRestore = beforeTrashRestore
        self.availableCapacity = availableCapacity ?? {
            let values = try rootURL.deletingLastPathComponent().resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])
            return values.volumeAvailableCapacityForImportantUsage
                ?? Int64(values.volumeAvailableCapacity ?? 0)
        }
    }

    func storeOriginal(_ source: MediaSource, id: UUID = UUID()) throws -> StoredMediaFile {
        guard fileManager.fileExists(atPath: source.url.path) else {
            throw MediaStoreError.sourceMissing
        }

        let attributes = try fileManager.attributesOfItem(atPath: source.url.path)
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard byteCount <= Self.maximumOriginalByteCount else {
            throw MediaStoreError.originalTooLarge(maximumBytes: Self.maximumOriginalByteCount)
        }
        let requiredCapacity = byteCount * 2 + Self.capacitySafetyReserve
        let capacity = try availableCapacity()
        guard capacity >= requiredCapacity else {
            throw MediaStoreError.insufficientCapacity(
                requiredBytes: requiredCapacity,
                availableBytes: capacity
            )
        }

        let fileExtension = try validatedExtension(for: source.contentType)
        let idString = id.uuidString.lowercased()
        let relativePath = "Media/Originals/\(idString.prefix(2))/\(idString).\(fileExtension)"
        let finalURL = rootURL.appendingPathComponent(relativePath)
        let stagingDirectory = rootURL.appendingPathComponent("Staging", isDirectory: true)
        let stagingURL = stagingDirectory.appendingPathComponent("\(idString).\(fileExtension)")

        guard !fileManager.fileExists(atPath: finalURL.path) else {
            throw MediaStoreError.destinationAlreadyExists
        }

        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: finalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            if fileManager.fileExists(atPath: stagingURL.path) {
                try fileManager.removeItem(at: stagingURL)
            }
            storeCopyCount += 1
            try beforeStoreCopy?(storeCopyCount)
            try fileManager.copyItem(at: source.url, to: stagingURL)
            let data = try Data(contentsOf: stagingURL, options: .mappedIfSafe)
            let dimensions = try validatedDimensions(at: stagingURL, declaredContentType: source.contentType)
            let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            try fileManager.moveItem(at: stagingURL, to: finalURL)
            return StoredMediaFile(
                id: id,
                relativePath: relativePath,
                byteCount: byteCount,
                checksum: checksum,
                pixelWidth: dimensions.width,
                pixelHeight: dimensions.height
            )
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    func ensureCapacity(for sources: [MediaSource]) throws {
        guard !sources.isEmpty else { return }
        let totalBytes = try sources.reduce(Int64(0)) { partial, source in
            guard fileManager.fileExists(atPath: source.url.path) else {
                throw MediaStoreError.sourceMissing
            }
            let attributes = try fileManager.attributesOfItem(atPath: source.url.path)
            return partial + ((attributes[.size] as? NSNumber)?.int64Value ?? 0)
        }
        let requiredCapacity = totalBytes * 2 + Self.capacitySafetyReserve
        let capacity = try availableCapacity()
        guard capacity >= requiredCapacity else {
            throw MediaStoreError.insufficientCapacity(
                requiredBytes: requiredCapacity,
                availableBytes: capacity
            )
        }
    }

    func fileURL(for relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/"), !relativePath.split(separator: "/").contains("..") else {
            throw MediaStoreError.invalidRelativePath
        }
        let candidate = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(rootURL.path + "/") else {
            throw MediaStoreError.invalidRelativePath
        }
        return candidate
    }

    func removeOriginal(at relativePath: String) throws {
        let url = try fileURL(for: relativePath)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func moveToTrash(_ relativePath: String) throws -> TrashedMediaFile {
        let originalURL = try fileURL(for: relativePath)
        guard fileManager.fileExists(atPath: originalURL.path) else {
            throw MediaStoreError.originalMissing
        }
        let trashRelativePath = "Trash/\(relativePath)"
        let trashURL = try fileURL(for: trashRelativePath)
        try fileManager.createDirectory(at: trashURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: originalURL, to: trashURL)
        return TrashedMediaFile(
            originalRelativePath: relativePath,
            trashRelativePath: trashRelativePath
        )
    }

    func restoreFromTrash(_ trashedFile: TrashedMediaFile) throws {
        let trashURL = try fileURL(for: trashedFile.trashRelativePath)
        let originalURL = try fileURL(for: trashedFile.originalRelativePath)
        guard !fileManager.fileExists(atPath: originalURL.path) else {
            throw MediaStoreError.destinationAlreadyExists
        }
        try beforeTrashRestore?()
        try fileManager.createDirectory(at: originalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: trashURL, to: originalURL)
    }

    func purgeTrash(_ trashedFile: TrashedMediaFile) throws {
        let url = try fileURL(for: trashedFile.trashRelativePath)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func recoverInterruptedTrash(referencedOriginalPaths: Set<String>) throws {
        let trashRoot = rootURL.appendingPathComponent("Trash", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: trashRoot,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return }

        for case let trashURL as URL in enumerator {
            let values = try trashURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let prefix = trashRoot.standardizedFileURL.path + "/"
            guard trashURL.standardizedFileURL.path.hasPrefix(prefix) else { continue }
            let originalRelativePath = String(trashURL.standardizedFileURL.path.dropFirst(prefix.count))
            let record = TrashedMediaFile(
                originalRelativePath: originalRelativePath,
                trashRelativePath: "Trash/\(originalRelativePath)"
            )
            if referencedOriginalPaths.contains(originalRelativePath) {
                let originalURL = try fileURL(for: originalRelativePath)
                if fileManager.fileExists(atPath: originalURL.path) {
                    try purgeTrash(record)
                } else {
                    try restoreFromTrash(record)
                }
            } else {
                try purgeTrash(record)
            }
        }
    }

    func reconcile(referencedOriginalPaths: Set<String>) throws -> MediaIntegrityReport {
        var report = MediaIntegrityReport()
        let stagingRoot = rootURL.appendingPathComponent("Staging", isDirectory: true)
        if fileManager.fileExists(atPath: stagingRoot.path) {
            report.removedStagingFileCount = try regularFiles(at: stagingRoot).count
            try fileManager.removeItem(at: stagingRoot)
        }

        let originalsRoot = rootURL.appendingPathComponent("Media/Originals", isDirectory: true)
        for originalURL in try regularFiles(at: originalsRoot) {
            let relativePath = try relativePath(for: originalURL)
            guard !referencedOriginalPaths.contains(relativePath) else { continue }
            let recoveryRelativePath = try moveOrphanToRecovery(originalURL, originalRelativePath: relativePath)
            report.recoveryFilePaths.append(recoveryRelativePath)
        }

        report.missingOriginalPaths = try referencedOriginalPaths
            .filter { !fileManager.fileExists(atPath: try fileURL(for: $0).path) }
            .sorted()

        let recoveryRoot = rootURL.appendingPathComponent("Recovery/Orphaned", isDirectory: true)
        let existingRecoveryPaths = try regularFiles(at: recoveryRoot).map { try relativePath(for: $0) }
        report.recoveryFilePaths = Array(Set(report.recoveryFilePaths + existingRecoveryPaths)).sorted()
        return report
    }

    func originalsByteCount() throws -> Int64 {
        let originalsURL = rootURL.appendingPathComponent("Media/Originals", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: originalsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ) else { return 0 }

        return try (enumerator.allObjects as? [URL] ?? []).reduce(Int64(0)) { total, url in
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            return values.isRegularFile == true ? total + Int64(values.fileSize ?? 0) : total
        }
    }

    private func validatedExtension(for contentType: String) throws -> String {
        switch contentType.lowercased() {
        case "image/jpeg", "image/jpg":
            return "jpg"
        case "image/png":
            return "png"
        case "image/heic", "image/heif":
            return "heic"
        default:
            throw MediaStoreError.unsupportedContentType(contentType)
        }
    }

    private func regularFiles(at directory: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path),
              let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey]
              ) else { return [] }
        return try (enumerator.allObjects as? [URL] ?? []).filter {
            try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        }
    }

    private func relativePath(for url: URL) throws -> String {
        let rootPrefix = rootURL.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPrefix) else { throw MediaStoreError.invalidRelativePath }
        return String(path.dropFirst(rootPrefix.count))
    }

    private func moveOrphanToRecovery(
        _ originalURL: URL,
        originalRelativePath: String
    ) throws -> String {
        var recoveryRelativePath = "Recovery/Orphaned/\(originalRelativePath)"
        var recoveryURL = try fileURL(for: recoveryRelativePath)
        if fileManager.fileExists(atPath: recoveryURL.path) {
            let stem = recoveryURL.deletingPathExtension().lastPathComponent
            let suffix = recoveryURL.pathExtension
            let uniqueName = suffix.isEmpty
                ? "\(stem)-\(UUID().uuidString.lowercased())"
                : "\(stem)-\(UUID().uuidString.lowercased()).\(suffix)"
            recoveryURL = recoveryURL.deletingLastPathComponent().appendingPathComponent(uniqueName)
            recoveryRelativePath = try relativePath(for: recoveryURL)
        }
        try fileManager.createDirectory(
            at: recoveryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: originalURL, to: recoveryURL)
        return recoveryRelativePath
    }

    private func validatedDimensions(
        at url: URL,
        declaredContentType: String
    ) throws -> (width: Int, height: Int) {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(imageSource) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0 else {
            throw MediaStoreError.invalidImage
        }
        if let detectedIdentifier = CGImageSourceGetType(imageSource) as String?,
           let detectedType = UTType(detectedIdentifier),
           let declaredType = UTType(mimeType: declaredContentType),
           !detectedType.conforms(to: declaredType),
           !declaredType.conforms(to: detectedType) {
            throw MediaStoreError.contentTypeMismatch
        }
        guard width <= Self.maximumPixelCount / height else {
            throw MediaStoreError.imageTooLarge(maximumPixels: Self.maximumPixelCount)
        }
        return (width, height)
    }
}
