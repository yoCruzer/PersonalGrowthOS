import CryptoKit
import Foundation

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
}

enum MediaStoreError: Error, Equatable {
    case sourceMissing
    case unsupportedContentType(String)
    case originalTooLarge(maximumBytes: Int64)
    case invalidRelativePath
    case destinationAlreadyExists
}

final class MediaStore {
    static let maximumOriginalByteCount: Int64 = 25 * 1_024 * 1_024

    let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
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
            try fileManager.copyItem(at: source.url, to: stagingURL)
            let data = try Data(contentsOf: stagingURL, options: .mappedIfSafe)
            let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            try fileManager.moveItem(at: stagingURL, to: finalURL)
            return StoredMediaFile(
                id: id,
                relativePath: relativePath,
                byteCount: byteCount,
                checksum: checksum
            )
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
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
}
