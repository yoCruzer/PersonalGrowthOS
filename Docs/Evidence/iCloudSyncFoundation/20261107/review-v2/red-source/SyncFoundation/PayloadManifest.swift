import Foundation
import CryptoKit
import Darwin

/// Ordered fixed-size chunks bind an aggregate without placing the whole payload in a record.
/// Repeated content is legal at distinct positions; chunk record identity is its byte hash.
public struct PayloadManifest: Codable, Equatable, Sendable {
    public let total: AssetDescriptor
    public let chunks: [AssetDescriptor]

    public init(total: AssetDescriptor, chunks: [AssetDescriptor]) throws {
        self.total = total; self.chunks = chunks; try validate()
    }
    public init(bytes: Data) throws {
        guard !bytes.isEmpty, bytes.count <= SyncLimits.payloadBytes else { throw SyncValidationError.limitExceeded }
        var descriptors: [AssetDescriptor] = []
        for offset in stride(from: 0, to: bytes.count, by: SyncLimits.chunkBytes) {
            descriptors.append(AssetDescriptor(bytes: bytes.subdata(in: offset..<min(offset + SyncLimits.chunkBytes, bytes.count))))
        }
        try self.init(total: AssetDescriptor(bytes: bytes), chunks: descriptors)
    }
    func validate() throws {
        try total.validate(maximum: SyncLimits.payloadBytes)
        guard !chunks.isEmpty, chunks.count <= SyncLimits.payloadChunks,
              chunks.count == (total.byteCount + SyncLimits.chunkBytes - 1) / SyncLimits.chunkBytes else {
            throw SyncValidationError.invalidManifest
        }
        var count = 0
        for (index, chunk) in chunks.enumerated() {
            try chunk.validate(maximum: SyncLimits.chunkBytes)
            guard chunk.byteCount == min(SyncLimits.chunkBytes, total.byteCount - count) else {
                throw SyncValidationError.invalidManifest
            }
            count += chunk.byteCount
            if index < chunks.count - 1, chunk.byteCount != SyncLimits.chunkBytes { throw SyncValidationError.invalidManifest }
        }
        guard count == total.byteCount else { throw SyncValidationError.invalidManifest }
    }

    /// Streaming verification holds at most one caller-provided chunk (4 MiB) internally.
    /// Do not publish partial output: full aggregate validity exists only after this returns.
    public func verifyChunks(next: () throws -> IndexedPayloadChunk?) throws {
        try validate()
        var hasher = SHA256(), count = 0
        for (index, descriptor) in chunks.enumerated() {
            guard let chunk = try next() else { throw SyncValidationError.missingAsset }
            guard chunk.index == index else { throw SyncValidationError.invalidManifest }
            try verifyAssetBytes(chunk.bytes, descriptor: descriptor, maximum: SyncLimits.chunkBytes)
            hasher.update(data: chunk.bytes); count += chunk.bytes.count
        }
        guard try next() == nil else { throw SyncValidationError.invalidManifest }
        guard count == total.byteCount, hexDigest(hasher.finalize()) == total.sha256 else { throw SyncValidationError.corruptAsset }
    }
    public func verify(bytes: Data) throws {
        var index = 0
        try verifyChunks {
            guard index * SyncLimits.chunkBytes < bytes.count else { return nil }
            let start = index * SyncLimits.chunkBytes
            defer { index += 1 }
            return IndexedPayloadChunk(index: index, bytes: bytes.subdata(in: start..<min(start + SyncLimits.chunkBytes, bytes.count)))
        }
    }

    /// Emits chunks into caller-owned staging. A failed preparation never returns a manifest.
    /// Caller retains source and owns cleanup/lease policy for any partially emitted chunks.
    public static func prepare(fileURL: URL, emit: (Int, AssetDescriptor, Data) throws -> Void) throws -> Self {
        let file = try openRegularAsset(fileURL, maximum: SyncLimits.payloadBytes)
        defer { try? file.close() }
        var hasher = SHA256(), count = 0, descriptors: [AssetDescriptor] = []
        while let bytes = try readChunk(file), !bytes.isEmpty {
            guard count <= SyncLimits.payloadBytes - bytes.count else { throw SyncValidationError.limitExceeded }
            let descriptor = AssetDescriptor(bytes: bytes)
            try emit(descriptors.count, descriptor, bytes)
            descriptors.append(descriptor); count += bytes.count; hasher.update(data: bytes)
        }
        return try Self(total: AssetDescriptor(sha256: hexDigest(hasher.finalize()), byteCount: count), chunks: descriptors)
    }
}

public struct IndexedPayloadChunk: Sendable {
    public let index: Int
    public let bytes: Data
    public init(index: Int, bytes: Data) { self.index = index; self.bytes = bytes }
}

private func hexDigest(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }
private func readChunk(_ file: FileHandle) throws -> Data? {
    var bytes = Data()
    while bytes.count < SyncLimits.chunkBytes {
        guard let fragment = try file.read(upToCount: SyncLimits.chunkBytes - bytes.count), !fragment.isEmpty else { break }
        bytes.append(fragment)
    }
    return bytes.isEmpty ? nil : bytes
}

func openRegularAsset(_ url: URL, maximum: Int) throws -> FileHandle {
    guard url.isFileURL else { throw SyncValidationError.missingAsset }
    let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    guard descriptor >= 0 else { throw SyncValidationError.missingAsset }
    let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG, metadata.st_size > 0 else {
        try? file.close(); throw SyncValidationError.missingAsset
    }
    guard metadata.st_size <= maximum else { try? file.close(); throw SyncValidationError.limitExceeded }
    return file
}
