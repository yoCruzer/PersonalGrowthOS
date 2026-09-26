import Foundation
import Darwin
import CryptoKit
import OSLog

// Shared by the app and extension; contains no database or application-only API.
enum CaptureLog {
    static let logger = Logger(subsystem: "com.yocruzer.PersonalGrowthOS", category: "ExternalCapture")
    static func event(_ status: String, id: UUID? = nil) {
        logger.info("\(status, privacy: .public) id=\(id?.uuidString ?? "none", privacy: .public)")
    }
}

enum CaptureError: String, Error {
    case groupUnavailable, emptyContent, invalidURL, unsupportedSchema, invalidPayload
    case attachmentInvalid, tooLarge, unsupportedProvider, providerTimedOut, multipleSources
}

enum CaptureMode: String, Codable { case metadataOnly, selectedContent }

struct CaptureSource: Codable, Equatable {
    var url: String
    var canonicalURL: String?
    var title: String?
    var siteName: String?
    var capturedAt: Date
    var captureMode: CaptureMode

    // Only external, optional enrichment is normalized. Stored payloads/backups remain strict.
    mutating func normalizeMetadata() {
        title = Self.metadataText(title, byteLimit: 32_768)
        siteName = Self.metadataText(siteName, byteLimit: 4_096)
        if Self.webURL(canonicalURL) == nil { canonicalURL = nil }
    }

    static func metadataText(_ value: String?, byteLimit: Int) -> String? {
        guard let value else { return nil }
        var result = ""
        var used = 0
        for character in value {
            let count = String(character).utf8.count
            guard count <= byteLimit - used else { break }
            result.append(character)
            used += count
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : result
    }

    static func webURL(_ value: String?) -> URL? {
        guard let value, value.utf8.count <= 16_384, let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }

    func validate() throws {
        guard Self.webURL(url) != nil,
              canonicalURL == nil || Self.webURL(canonicalURL) != nil,
              url.utf8.count <= 16_384, (canonicalURL?.utf8.count ?? 0) <= 16_384,
              (title?.utf8.count ?? 0) <= 32_768, (siteName?.utf8.count ?? 0) <= 4_096,
              capturedAt.timeIntervalSince1970.isFinite else { throw CaptureError.invalidURL }
    }
}

struct CaptureAttachment: Codable, Equatable {
    let id: UUID
    let filename: String
    let contentType: String
    let byteCount: Int64
    let checksum: String
}

struct ShareImportPayload: Codable, Equatable {
    var schemaVersion = 1
    var id = UUID()
    var createdAt = Date()
    var text = ""
    var source: CaptureSource?
    var images: [CaptureAttachment] = []

    func validate() throws {
        guard schemaVersion == 1 else { throw CaptureError.unsupportedSchema }
        guard createdAt.timeIntervalSince1970.isFinite, text.utf8.count <= 1_048_576,
              images.count <= 9, Set(images.map(\.id)).count == images.count,
              Set(images.map(\.filename)).count == images.count else { throw CaptureError.invalidPayload }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || source != nil || !images.isEmpty else {
            throw CaptureError.emptyContent
        }
        try source?.validate()
        for image in images {
            guard image.filename == image.id.uuidString.lowercased(),
                  ["image/jpeg", "image/png", "image/heic", "image/heif"].contains(image.contentType),
                  image.byteCount > 0, image.byteCount <= 25 * 1_024 * 1_024,
                  image.checksum.count == 64 else { throw CaptureError.attachmentInvalid }
        }
    }
}

struct ShareInbox {
    static let groupIdentifier = "group.com.yocruzer.PersonalGrowthOS"
    let root: URL
    private let fm = FileManager.default

    static func shared() throws -> ShareInbox {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            throw CaptureError.groupUnavailable
        }
        return ShareInbox(root: url.appendingPathComponent("ExternalCapture", isDirectory: true))
    }

    // Only a fully written directory is published. Incomplete staging is never consumed.
    func publish(_ payload: ShareImportPayload, files: [UUID: URL]) throws {
        try payload.validate()
        _ = try CaptureStagingSession.reclaimAbandoned(root: root)
        let session = try CaptureStagingSession(root: root)
        let staging = session.directory
        let pending = root.appendingPathComponent("Pending", isDirectory: true)
        defer { try? session.remove() }
        try fm.createDirectory(at: pending, withIntermediateDirectories: true)
        for image in payload.images {
            try Task.checkCancellation()
            guard let file = files[image.id] else { throw CaptureError.attachmentInvalid }
            let target = staging.appendingPathComponent(image.filename)
            try fm.copyItem(at: file, to: target)
            try verify(image, at: target)
        }
        let data = try JSONEncoder().encode(payload)
        guard data.count <= 2_097_152 else { throw CaptureError.tooLarge }
        CaptureLog.event("payload.serialized bytes=\(data.count)", id: payload.id)
        try data.write(to: staging.appendingPathComponent("payload.json"), options: .atomic)
        try Task.checkCancellation()
        try fm.moveItem(at: staging, to: pending.appendingPathComponent(payload.id.uuidString.lowercased()))
        CaptureLog.event("inbox.published", id: payload.id)
    }

    func pending() throws -> [URL] {
        let pending = root.appendingPathComponent("Pending", isDirectory: true)
        guard fm.fileExists(atPath: pending.path) else { return [] }
        return try fm.contentsOfDirectory(at: pending, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func read(_ directory: URL) throws -> ShareImportPayload {
        try regular(directory, directory: true)
        let file = directory.appendingPathComponent("payload.json")
        try regular(file)
        guard try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 <= 2_097_152 else { throw CaptureError.tooLarge }
        let payload = try JSONDecoder().decode(ShareImportPayload.self, from: Data(contentsOf: file))
        try payload.validate()
        guard directory.lastPathComponent == payload.id.uuidString.lowercased() else { throw CaptureError.invalidPayload }
        for image in payload.images { try verify(image, at: directory.appendingPathComponent(image.filename)) }
        return payload
    }

    func remove(_ directory: URL) throws {
        if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
    }

    func verify(_ image: CaptureAttachment, at url: URL) throws {
        try regular(url)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size == image.byteCount, size <= 25 * 1_024 * 1_024,
              try Self.checksum(url) == image.checksum else { throw CaptureError.attachmentInvalid }
    }

    static func checksum(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func regular(_ url: URL, directory: Bool = false) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
        guard values.isSymbolicLink != true, directory ? values.isDirectory == true : values.isRegularFile == true else {
            throw CaptureError.invalidPayload
        }
    }
}

// Kernel-held leases survive neither process death nor a crash. Age alone never proves
// a staging directory is abandoned. Unmarked legacy directories are retained.
final class CaptureFileLease {
    private let descriptor: Int32

    init?(url: URL, nonblocking: Bool = false) throws {
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        if flock(descriptor, LOCK_EX | (nonblocking ? LOCK_NB : 0)) != 0 {
            let code = errno
            close(descriptor)
            if nonblocking && code == EWOULDBLOCK { return nil }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        self.descriptor = descriptor
    }

    deinit { close(descriptor) }
}

final class CaptureStagingSession {
    let directory: URL
    private let lease: CaptureFileLease

    init(root: URL) throws {
        let staging = root.appendingPathComponent("Staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let registry = try CaptureFileLease(url: staging.appendingPathComponent(".registry"))
        defer { withExtendedLifetime(registry) {} }
        directory = staging.appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            guard let lease = try CaptureFileLease(url: directory.appendingPathComponent(".lease")) else {
                throw CaptureError.invalidPayload
            }
            self.lease = lease
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func remove() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        withExtendedLifetime(lease) {}
    }

    static func reclaimAbandoned(root: URL) throws -> Int {
        let staging = root.appendingPathComponent("Staging", isDirectory: true)
        guard FileManager.default.fileExists(atPath: staging.path) else { return 0 }
        let registry = try CaptureFileLease(url: staging.appendingPathComponent(".registry"))
        defer { withExtendedLifetime(registry) {} }
        var count = 0
        for directory in try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey]) {
            guard UUID(uuidString: directory.lastPathComponent) != nil else { continue }
            do {
                let attributes = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                guard attributes.isDirectory == true, attributes.isSymbolicLink != true else { continue }
                let marker = directory.appendingPathComponent(".lease")
                guard FileManager.default.fileExists(atPath: marker.path),
                      let lease = try CaptureFileLease(url: marker, nonblocking: true) else { continue }
                defer { withExtendedLifetime(lease) {} }
                try FileManager.default.removeItem(at: directory)
                count += 1
            } catch { CaptureLog.event("staging.cleanupRetained") }
        }
        return count
    }
}
