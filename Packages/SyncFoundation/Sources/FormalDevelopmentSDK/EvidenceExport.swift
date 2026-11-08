import Foundation
import Darwin
import FormalProbeCore
import SyncFoundation

private struct ExportedProbeFile: Encodable {
    let section: String
    let name: String
    let sha256: String
    let bytes: Data
}
private struct ProbeEvidenceExport: Encodable {
    let mode = "PRIVATE_PROBE_EVIDENCE_READ_ONLY"
    let run: UUID
    let files: [ExportedProbeFile]
    let unavailableSections: [String]
    let cloudOperations = 0
    let keychainOperations = 0
    let ledgerAuthentication = "NOT_PERFORMED_NO_KEYCHAIN_ACCESS"
    let p0Passed = false
}

/// Exports only this application's probe evidence. No arbitrary input/output path,
/// account operation, Keychain read, lock mutation, repair or retry is exposed.
public enum FormalDevelopmentEvidenceExport {
    public static func export(run: UUID) throws -> Data {
        let roots = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard roots.count == 1, let root = roots.first else { throw FormalProbeError.invalidPath }
        return try capture(root: root, run: run)
    }
    // Internal synthetic-files seam only; the CLI cannot select a root.
    static func capture(root: URL, run: UUID) throws -> Data {
        var files: [ExportedProbeFile] = [], unavailable: [String] = [], total = 0
        for (section, leaf) in [
            ("run", "com.yocruzer.PersonalGrowthOS.FormalSyncProbe.Run-" + run.uuidString.lowercased()),
            ("ledger", "com.yocruzer.PersonalGrowthOS.FormalSyncProbe.ExecutionGuard-v1")
        ] {
            let url = root.appendingPathComponent(leaf, isDirectory: true)
            do {
                let fd = try ExecutionLedgerFiles.directory(url)
                defer { close(fd) }
                try requireBinding(fd, url: url)
                let names = try namesAt(fd)
                var captured: [ExportedProbeFile] = []
                for name in names.sorted() where name != "guard.lock" {
                    let runNames: Set<String> = ["plan.json", "fatal-unknown.json", "deadline-expired.json", "prepared-report.json", "verified-report.json", "failed-report.json",
                        "lease-original.png", "lease-create.payload", "lease-edit.payload", "lease-create.manifest", "lease-edit.manifest", "lease-tombstone.manifest"]
                    let allowed = section == "ledger"
                        ? name.range(of: "^[0-9]{8}\\.json$", options: .regularExpression) != nil
                        : runNames.contains(name) || name.range(of: "^[0-9]{6}-(callback|returned|validated|failed-return)\\.json$", options: .regularExpression) != nil
                    guard allowed else {
                        throw FormalProbeError.invalidPath
                    }
                    let bytes = try readFile(fd, name: name)
                    total += bytes.count
                    guard total <= 8 * 1_024 * 1_024 else { throw FormalProbeError.limit }
                    guard try readFile(fd, name: name) == bytes else { throw FormalProbeError.fileChanged }
                    captured.append(ExportedProbeFile(section: section, name: name, sha256: syncDigest(bytes), bytes: bytes))
                }
                try requireBinding(fd, url: url)
                guard try namesAt(fd) == names else { throw FormalProbeError.fileChanged }
                files += captured
            } catch {
                // A partial section is never represented as a complete capture.
                unavailable.append(section)
            }
        }
        return try json(ProbeEvidenceExport(run: run, files: files, unavailableSections: unavailable))
    }
    private static func requireBinding(_ fd: Int32, url: URL) throws {
        let current = try ExecutionLedgerFiles.directory(url)
        defer { close(current) }
        var original = stat(), present = stat()
        guard fstat(fd, &original) == 0, fstat(current, &present) == 0,
              original.st_dev == present.st_dev, original.st_ino == present.st_ino,
              present.st_uid == getuid(), present.st_mode & 0o077 == 0 else { throw FormalProbeError.fileChanged }
    }
    private static func readFile(_ directory: Int32, name: String) throws -> Data {
        let fd = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw FormalProbeError.invalidPath }
        defer { close(fd) }
        var before = stat(), after = stat(), named = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_uid == getuid(), before.st_nlink == 1,
              before.st_size >= 0, before.st_size <= 65_536 else { throw FormalProbeError.invalidPath }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 { if errno == EINTR { continue }; throw FormalProbeError.fileChanged }
            guard data.count + count <= 65_536 else { throw FormalProbeError.limit }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard fstat(fd, &after) == 0, fstatat(directory, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              before.st_dev == named.st_dev, before.st_ino == named.st_ino,
              before.st_size == data.count, after.st_size == before.st_size,
              after.st_uid == getuid(), after.st_nlink == 1,
              named.st_mode & S_IFMT == S_IFREG, named.st_uid == getuid(), named.st_nlink == 1,
              named.st_size == after.st_size,
              named.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              named.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              named.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              named.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw FormalProbeError.fileChanged }
        return data
    }
    private static func namesAt(_ directory: Int32) throws -> Set<String> {
        let fd = dup(directory)
        guard fd >= 0 else { throw FormalProbeError.invalidPath }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else {
            close(fd); throw FormalProbeError.invalidPath
        }
        guard let stream = fdopendir(fd) else { close(fd); throw FormalProbeError.invalidPath }
        defer { closedir(stream) }
        rewinddir(stream)
        var names = Set<String>(); errno = 0
        while let item = readdir(stream) {
            var value = item.pointee
            let name = withUnsafePointer(to: &value.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: 1_024) { String(cString: $0) }
            }
            if name != "." && name != ".." { names.insert(name) }
            guard names.count <= 4_096 else { throw FormalProbeError.limit }
        }
        guard errno == 0 else { throw FormalProbeError.invalidPath }
        return names
    }
}
