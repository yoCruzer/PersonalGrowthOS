import Foundation
import Darwin

/// Held root + lock descriptors. No recursive cleanup or repair is provided.
final class ExecutionLedgerFiles {
    let url: URL
    private let rootFD: Int32
    private let lockFD: Int32
    let device: UInt64
    let inode: UInt64
    let lockDevice: UInt64
    let lockInode: UInt64
    static func directory(_ url: URL, create: Bool = false) throws -> Int32 {
        let parts = url.pathComponents
        guard url.isFileURL, parts.first == "/", parts.count > 1, !parts.contains(".."), !parts.contains(".") else { throw LedgerFailure.pathChanged }
        var fd = Darwin.open("/", O_SEARCH | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw LedgerFailure.io }
        do {
            for (index, part) in parts.dropFirst().enumerated() {
                if create && index == parts.count - 2 {
                    guard mkdirat(fd, part, 0o700) == 0 else { throw LedgerFailure.io }
                    let syncFD = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                    guard syncFD >= 0 else { throw LedgerFailure.io }
                    let synced = fsync(syncFD); close(syncFD)
                    guard synced == 0 else { throw LedgerFailure.io }
                }
                let next = openat(fd, part, (index == parts.count - 2 ? O_RDONLY : O_SEARCH) | O_DIRECTORY | O_NOFOLLOW)
                guard next >= 0 else { throw LedgerFailure.pathChanged }
                close(fd); fd = next
            }
            return fd
        } catch { close(fd); throw error }
    }
    init(url: URL, enroll: Bool) throws {
        self.url = url
        let fd = try Self.directory(url, create: enroll)
        var root = stat()
        guard fstat(fd, &root) == 0, root.st_uid == getuid(), root.st_mode & 0o077 == 0 else { close(fd); throw LedgerFailure.permission }
        let lock = openat(fd, "guard.lock", O_RDWR | O_NOFOLLOW | O_NONBLOCK | (enroll ? O_CREAT | O_EXCL : 0), 0o600)
        guard lock >= 0 else { close(fd); throw LedgerFailure.corrupt }
        var info = stat()
        guard fstat(lock, &info) == 0, Self.regular(info), flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            close(lock); close(fd); throw LedgerFailure.busy
        }
        guard !enroll || fsync(lock) == 0 && fsync(fd) == 0 else { close(lock); close(fd); throw LedgerFailure.io }
        rootFD = fd; lockFD = lock; device = UInt64(UInt32(bitPattern: root.st_dev)); inode = root.st_ino
        lockDevice = UInt64(UInt32(bitPattern: info.st_dev)); lockInode = info.st_ino
        try verifyBinding()
    }
    deinit { flock(lockFD, LOCK_UN); close(lockFD); close(rootFD) }
    private static func regular(_ s: stat) -> Bool {
        s.st_mode & S_IFMT == S_IFREG && s.st_uid == getuid() && s.st_mode & 0o077 == 0 && s.st_nlink == 1
    }
    func verifyBinding() throws {
        let current = try Self.directory(url); defer { close(current) }
        var root = stat(), old = stat(), path = stat()
        guard fstat(current, &root) == 0, UInt64(UInt32(bitPattern: root.st_dev)) == device, root.st_ino == inode,
              root.st_uid == getuid(), root.st_mode & 0o077 == 0,
              fstat(lockFD, &old) == 0, fstatat(rootFD, "guard.lock", &path, AT_SYMLINK_NOFOLLOW) == 0,
              Self.regular(old), Self.regular(path), old.st_dev == path.st_dev, old.st_ino == path.st_ino else { throw LedgerFailure.pathChanged }
    }
    func names() throws -> Set<String> {
        try verifyBinding()
        let copy = dup(rootFD)
        guard copy >= 0 else { throw LedgerFailure.io }
        guard let stream = fdopendir(copy) else { close(copy); throw LedgerFailure.io }
        defer { closedir(stream) }; rewinddir(stream)
        var result = Set<String>(); errno = 0
        while let next = readdir(stream) {
            var value = next.pointee
            let name = withUnsafePointer(to: &value.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: 1_024) { String(cString: $0) } }
            if name != "." && name != ".." { result.insert(name) }
            guard result.count <= 2_049 else { throw LedgerFailure.capacity }
        }
        guard errno == 0 else { throw LedgerFailure.io }; try verifyBinding(); return result
    }
    static func recordName(_ sequence: Int) -> String { String(format: "%08d.json", sequence) }
    func read(_ sequence: Int) throws -> Data {
        try verifyBinding()
        let fd = openat(rootFD, Self.recordName(sequence), O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw LedgerFailure.corrupt }
        defer { close(fd) }; var before = stat(), after = stat()
        guard fstat(fd, &before) == 0, Self.regular(before), before.st_size > 0, before.st_size <= 16_384 else { throw LedgerFailure.corrupt }
        var bytes = Data(count: Int(before.st_size) + 1)
        let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        guard count == before.st_size, fstat(fd, &after) == 0, before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec, before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec, before.st_size == after.st_size else { throw LedgerFailure.corrupt }
        bytes.count = count; try verifyBinding(); return bytes
    }
    func write(_ sequence: Int, bytes: Data) throws {
        try verifyBinding(); guard bytes.count <= 16_384 else { throw LedgerFailure.capacity }
        let fd = openat(rootFD, Self.recordName(sequence), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw LedgerFailure.corrupt }; defer { close(fd) }
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                guard count > 0 else { throw LedgerFailure.io }; offset += count
            }
        }
        guard fsync(fd) == 0, fsync(rootFD) == 0 else { throw LedgerFailure.io }; try verifyBinding()
    }
}
