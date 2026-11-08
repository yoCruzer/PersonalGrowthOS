import Foundation
import Darwin

public enum FormalProbeError: Error { case invalidPlan, invalidPath, existingOutput, missingFile, fileChanged, limit, signatureUnavailable }

/// Probe-owned directories only; no recursive traversal or caller-selected business files.
public final class ProbeDirectory {
    public let url: URL
    private let descriptor: Int32
    public init(_ url: URL, create: Bool) throws {
        guard url.isFileURL, url.path.hasPrefix("/"), !url.pathComponents.contains(".."), !url.pathComponents.contains(".") else { throw FormalProbeError.invalidPath }
        let parts = Array(url.pathComponents.dropFirst())
        guard let leaf = parts.last, !leaf.isEmpty else { throw FormalProbeError.invalidPath }
        // Ancestors need search permission only, not directory listing access.
        // O_EVTONLY still requests read-data access under App Sandbox.
        var parent = open("/", O_SEARCH | O_DIRECTORY | O_NOFOLLOW)
        guard parent >= 0 else { throw FormalProbeError.invalidPath }
        defer { close(parent) }
        for part in parts.dropLast() {
            let next = openat(parent, part, O_SEARCH | O_DIRECTORY | O_NOFOLLOW)
            guard next >= 0 else { throw FormalProbeError.invalidPath }
            close(parent); parent = next
        }
        if create, mkdirat(parent, leaf, 0o700) != 0 { throw FormalProbeError.existingOutput }
        let fd = openat(parent, leaf, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw FormalProbeError.invalidPath }
        self.descriptor = fd; self.url = url
    }
    deinit { close(descriptor) }
    private func validateName(_ name: String) throws {
        guard !name.isEmpty, !name.hasPrefix("."), name.utf8.count < 128,
              name.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,95].contains($0) }) else { throw FormalProbeError.invalidPath }
    }
    public func read(_ name: String, maximum: Int = 65_536) throws -> Data {
        try validateName(name)
        let fd = openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw FormalProbeError.missingFile }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? file.close() }
        var state = stat()
        guard fstat(fd, &state) == 0, state.st_mode & S_IFMT == S_IFREG, state.st_size >= 0, state.st_size <= maximum else { throw FormalProbeError.invalidPath }
        let bytes = try file.read(upToCount: maximum + 1) ?? Data()
        guard bytes.count == state.st_size, bytes.count <= maximum else { throw FormalProbeError.fileChanged }
        return bytes
    }
    public func write(_ name: String, bytes: Data) throws {
        try validateName(name)
        let fd = openat(descriptor, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw FormalProbeError.existingOutput }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? file.close() }
        try file.write(contentsOf: bytes); try file.synchronize()
        guard fsync(descriptor) == 0 else { throw FormalProbeError.fileChanged }
    }
    public func requirePathBinding() throws {
        let current = try ProbeDirectory(url, create: false)
        var original = stat(), present = stat()
        guard fstat(descriptor, &original) == 0, fstat(current.descriptor, &present) == 0,
              original.st_dev == present.st_dev, original.st_ino == present.st_ino else { throw FormalProbeError.fileChanged }
    }
    /// SDK file URLs require an immutable private lease. Verify the directory binding
    /// immediately before/after SDK use; source reads and writes themselves stay fd-relative.
    public func assetURL(_ name: String) throws -> URL {
        try validateName(name); try requirePathBinding()
        var state = stat()
        guard fstatat(descriptor, name, &state, AT_SYMLINK_NOFOLLOW) == 0,
              state.st_mode & S_IFMT == S_IFREG else { throw FormalProbeError.invalidPath }
        return url.appendingPathComponent(name)
    }
    public func verifyNames(_ expected: Set<String>) throws {
        let duplicate = dup(descriptor)
        guard duplicate >= 0, let directory = fdopendir(duplicate) else {
            if duplicate >= 0 { close(duplicate) }; throw FormalProbeError.invalidPath
        }
        defer { closedir(directory) }
        rewinddir(directory)
        var names = Set<String>()
        errno = 0
        while let entry = readdir(directory) {
            var info = entry.pointee
            let name = withUnsafePointer(to: &info.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: 1_024) { String(cString: $0) }
            }
            if name != "." && name != ".." { names.insert(name) }
        }
        guard errno == 0 else { throw FormalProbeError.invalidPath }
        guard names == expected else { throw FormalProbeError.invalidPlan }
        for name in names { _ = try read(name) }
    }
}

func probeJSON<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
}
