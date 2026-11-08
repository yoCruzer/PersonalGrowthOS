import Foundation
import Darwin
import SyncFoundation

/// Immutable leases outside business originals. Every store path component is opened
/// relative to a directory descriptor without following symlinks.
struct SyncAssetStore {
    let root: URL
    func url(for descriptor: AssetDescriptor) throws -> URL {
        guard descriptor.sha256.count == 64,
              descriptor.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              descriptor.byteCount > 0, descriptor.byteCount <= SyncLimits.originalBytes else { throw SyncValidationError.invalidIdentity }
        return root.appendingPathComponent("Sync/Assets/" + descriptor.sha256)
    }
    func read(_ descriptor: AssetDescriptor) throws -> Data {
        _ = try url(for: descriptor)
        return try directory(create: false) { folder in
            try Self.readDescriptor(openat(folder, descriptor.sha256, O_RDONLY | O_NOFOLLOW | O_CLOEXEC), expected: descriptor)
        }
    }
    @discardableResult func retain(_ bytes: Data, as descriptor: AssetDescriptor) throws -> URL {
        guard AssetDescriptor(bytes: bytes) == descriptor else { throw SyncValidationError.corruptAsset }
        let destination = try url(for: descriptor)
        try directory(create: true) { folder in
            let existing = openat(folder, descriptor.sha256, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            if existing >= 0 { _ = try Self.readDescriptor(existing, expected: descriptor); return }
            guard errno == ENOENT else { throw SyncValidationError.corruptAsset }
            let temporary = ".pending-" + UUID().uuidString.lowercased()
            let fd = openat(folder, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
            guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            defer { try? handle.close(); unlinkat(folder, temporary, 0) }
            try handle.write(contentsOf: bytes); try handle.synchronize(); try handle.close()
            // linkat publishes atomically and never replaces an existing immutable lease.
            guard linkat(folder, temporary, folder, descriptor.sha256, 0) == 0 || errno == EEXIST else { throw CocoaError(.fileWriteUnknown) }
            _ = try Self.readDescriptor(openat(folder, descriptor.sha256, O_RDONLY | O_NOFOLLOW | O_CLOEXEC), expected: descriptor)
            _ = fsync(folder)
        }
        return destination
    }
    @discardableResult func retainOriginal(_ media: SyncOriginalDescriptor, mediaStore: MediaStore) throws -> URL {
        let descriptor = AssetDescriptor(sha256: media.sha256, byteCount: Int(media.byteCount))
        let destination = try url(for: descriptor)
        if FileManager.default.fileExists(atPath: destination.path) { _ = try read(descriptor); return destination }
        let path = try mediaStore.fileURL(for: mediaStore.originalRelativePath(id: media.id, contentType: media.contentType))
        let bytes = try Self.readDescriptor(open(path.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC), expected: descriptor)
        return try retain(bytes, as: descriptor)
    }
    private func directory<T>(create: Bool, _ operation: (Int32) throws -> T) throws -> T {
        let rootFD = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw SyncValidationError.missingAsset }
        defer { close(rootFD) }
        if create, mkdirat(rootFD, "Sync", mode_t(0o700)) != 0 && errno != EEXIST { throw CocoaError(.fileWriteUnknown) }
        let syncFD = openat(rootFD, "Sync", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard syncFD >= 0 else { throw SyncValidationError.missingAsset }
        defer { close(syncFD) }
        if create, mkdirat(syncFD, "Assets", mode_t(0o700)) != 0 && errno != EEXIST { throw CocoaError(.fileWriteUnknown) }
        let assetsFD = openat(syncFD, "Assets", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard assetsFD >= 0 else { throw SyncValidationError.missingAsset }
        defer { close(assetsFD) }
        return try operation(assetsFD)
    }
    private static func readDescriptor(_ fd: Int32, expected descriptor: AssetDescriptor) throws -> Data {
        guard fd >= 0 else { throw SyncValidationError.missingAsset }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var initial = stat()
        guard fstat(fd, &initial) == 0, initial.st_mode & S_IFMT == S_IFREG,
              initial.st_size == descriptor.byteCount, descriptor.byteCount > 0,
              descriptor.byteCount <= SyncLimits.originalBytes else { throw SyncValidationError.corruptAsset }
        var data = Data(); data.reserveCapacity(descriptor.byteCount)
        while data.count <= descriptor.byteCount {
            let bytes = try handle.read(upToCount: min(1_048_576, descriptor.byteCount - data.count + 1)) ?? Data()
            if bytes.isEmpty { break }; data.append(bytes)
        }
        var final = stat()
        guard fstat(fd, &final) == 0, final.st_size == initial.st_size,
              final.st_mtimespec.tv_sec == initial.st_mtimespec.tv_sec, final.st_mtimespec.tv_nsec == initial.st_mtimespec.tv_nsec,
              final.st_ctimespec.tv_sec == initial.st_ctimespec.tv_sec, final.st_ctimespec.tv_nsec == initial.st_ctimespec.tv_nsec,
              AssetDescriptor(bytes: data) == descriptor else { throw SyncValidationError.corruptAsset }
        return data
    }
}
