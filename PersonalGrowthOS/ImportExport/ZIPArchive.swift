import Foundation

struct ZIPImportLimits: Equatable {
    static let production = ZIPImportLimits(
        maximumArchiveBytes: 8 * 1_024 * 1_024 * 1_024,
        maximumExpandedBytes: 24 * 1_024 * 1_024 * 1_024,
        capacitySafetyReserve: 1 * 1_024 * 1_024 * 1_024,
        maximumFileCount: 100_000,
        maximumObjectCount: 500_000,
        maximumCompressionRatio: 100
    )

    let maximumArchiveBytes: Int64
    let maximumExpandedBytes: Int64
    let capacitySafetyReserve: Int64
    let maximumFileCount: Int
    let maximumObjectCount: Int
    let maximumCompressionRatio: Int64
}

enum ZIPArchiveError: Error, Equatable {
    case archiveTooLarge
    case malformedArchive
    case unsupportedZIP64
    case unsupportedCompression
    case encryptedMember
    case tooManyFiles
    case expandedSizeExceeded
    case insufficientCapacity
    case compressionRatioExceeded
    case unsafePath
    case duplicatePath
    case unsupportedFileType
    case checksumMismatch
    case missingMember(String)
}

struct ZIPSource {
    let path: String
    let fileURL: URL
}

struct ZIPMember: Equatable {
    let path: String
    let compressedSize: Int64
    let uncompressedSize: Int64
    let crc32: UInt32
    fileprivate let localHeaderOffset: UInt32
    fileprivate let compressionMethod: UInt16
}

private enum ZIPConstants {
    static let localHeaderSignature: UInt32 = 0x04034b50
    static let centralHeaderSignature: UInt32 = 0x02014b50
    static let endSignature: UInt32 = 0x06054b50
    static let localHeaderSize = 30
    static let centralHeaderSize = 46
    static let maximumEOCDSearch = 65_557
    static let chunkSize = 1_048_576
}

enum ZIPArchiveWriter {
    static func write(sources: [ZIPSource], to destination: URL) throws {
        guard sources.count <= Int(UInt16.max) else { throw ZIPArchiveError.unsupportedZIP64 }
        var seenPaths = Set<String>()
        let prepared = try sources.map { source -> PreparedSource in
            let path = try ZIPPathValidator.validate(source.path, seenPaths: &seenPaths)
            let attributes = try FileManager.default.attributesOfItem(atPath: source.fileURL.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            guard size >= 0, size <= Int64(UInt32.max) else {
                throw ZIPArchiveError.unsupportedZIP64
            }
            return PreparedSource(
                path: path,
                pathData: Data(path.utf8),
                fileURL: source.fileURL,
                size: UInt32(size),
                crc32: try CRC32.checksum(fileAt: source.fileURL)
            )
        }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: destination)
        do {
            var records: [CentralRecord] = []
            for source in prepared {
                let offset = try checkedUInt32(output.offset())
                try output.write(contentsOf: localHeader(for: source))
                try copy(source.fileURL, to: output)
                records.append(CentralRecord(source: source, localHeaderOffset: offset))
            }
            let centralOffset = try checkedUInt32(output.offset())
            for record in records {
                try output.write(contentsOf: centralHeader(for: record))
            }
            let centralSize = try checkedUInt32(output.offset() - UInt64(centralOffset))
            try output.write(contentsOf: endRecord(
                count: UInt16(records.count),
                centralSize: centralSize,
                centralOffset: centralOffset
            ))
            try output.synchronize()
            try output.close()
        } catch {
            try? output.close()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private struct PreparedSource {
        let path: String
        let pathData: Data
        let fileURL: URL
        let size: UInt32
        let crc32: UInt32
    }

    private struct CentralRecord {
        let source: PreparedSource
        let localHeaderOffset: UInt32
    }

    private static func localHeader(for source: PreparedSource) -> Data {
        var data = Data()
        data.appendLE(ZIPConstants.localHeaderSignature)
        data.appendLE(UInt16(20))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(source.crc32)
        data.appendLE(source.size)
        data.appendLE(source.size)
        data.appendLE(UInt16(source.pathData.count))
        data.appendLE(UInt16(0))
        data.append(source.pathData)
        return data
    }

    private static func centralHeader(for record: CentralRecord) -> Data {
        let source = record.source
        var data = Data()
        data.appendLE(ZIPConstants.centralHeaderSignature)
        data.appendLE(UInt16(0x0314))
        data.appendLE(UInt16(20))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(source.crc32)
        data.appendLE(source.size)
        data.appendLE(source.size)
        data.appendLE(UInt16(source.pathData.count))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt32(0o100644) << 16)
        data.appendLE(record.localHeaderOffset)
        data.append(source.pathData)
        return data
    }

    private static func endRecord(count: UInt16, centralSize: UInt32, centralOffset: UInt32) -> Data {
        var data = Data()
        data.appendLE(ZIPConstants.endSignature)
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(count)
        data.appendLE(count)
        data.appendLE(centralSize)
        data.appendLE(centralOffset)
        data.appendLE(UInt16(0))
        return data
    }

    private static func copy(_ source: URL, to output: FileHandle) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: ZIPConstants.chunkSize), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
    }

    private static func checkedUInt32(_ value: UInt64) throws -> UInt32 {
        guard value <= UInt64(UInt32.max) else { throw ZIPArchiveError.unsupportedZIP64 }
        return UInt32(value)
    }
}

final class ZIPArchiveReader {
    let members: [ZIPMember]

    private let archiveURL: URL
    private let limits: ZIPImportLimits

    init(
        archiveURL: URL,
        limits: ZIPImportLimits = .production,
        availableCapacity: Int64
    ) throws {
        self.archiveURL = archiveURL
        self.limits = limits
        let attributes = try FileManager.default.attributesOfItem(atPath: archiveURL.path)
        let archiveSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard archiveSize <= limits.maximumArchiveBytes else { throw ZIPArchiveError.archiveTooLarge }
        members = try Self.readDirectory(
            archiveURL: archiveURL,
            archiveSize: archiveSize,
            limits: limits,
            availableCapacity: availableCapacity
        )
    }

    func extractAll(to rootURL: URL) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let input = try FileHandle(forReadingFrom: archiveURL)
        defer { try? input.close() }
        for member in members {
            let destination = rootURL.appendingPathComponent(member.path).standardizedFileURL
            guard destination.path.hasPrefix(rootURL.standardizedFileURL.path + "/") else {
                throw ZIPArchiveError.unsafePath
            }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try input.seek(toOffset: UInt64(member.localHeaderOffset))
            let header = try input.readExactly(ZIPConstants.localHeaderSize)
            guard try header.uint32(at: 0) == ZIPConstants.localHeaderSignature else {
                throw ZIPArchiveError.malformedArchive
            }
            let localFlags = try header.uint16(at: 6)
            let localMethod = try header.uint16(at: 8)
            let localCRC = try header.uint32(at: 14)
            let localCompressedSize = try header.uint32(at: 18)
            let localExpandedSize = try header.uint32(at: 22)
            let nameLength = Int(try header.uint16(at: 26))
            let extraLength = Int(try header.uint16(at: 28))
            let nameData = try input.readExactly(nameLength)
            guard localFlags & 0x9 == 0,
                  localMethod == member.compressionMethod,
                  localCRC == member.crc32,
                  Int64(localCompressedSize) == member.compressedSize,
                  Int64(localExpandedSize) == member.uncompressedSize,
                  String(data: nameData, encoding: .utf8) == member.path else {
                throw ZIPArchiveError.malformedArchive
            }
            try input.seek(toOffset: input.offset() + UInt64(extraLength))
            guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let output = try FileHandle(forWritingTo: destination)
            do {
                var remaining = member.compressedSize
                var crc = CRC32()
                while remaining > 0 {
                    let count = Int(min(Int64(ZIPConstants.chunkSize), remaining))
                    let chunk = try input.readExactly(count)
                    crc.update(chunk)
                    try output.write(contentsOf: chunk)
                    remaining -= Int64(chunk.count)
                }
                try output.close()
                guard crc.value == member.crc32 else { throw ZIPArchiveError.checksumMismatch }
            } catch {
                try? output.close()
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }
    }

    private static func readDirectory(
        archiveURL: URL,
        archiveSize: Int64,
        limits: ZIPImportLimits,
        availableCapacity: Int64
    ) throws -> [ZIPMember] {
        guard archiveSize >= 22 else { throw ZIPArchiveError.malformedArchive }
        let input = try FileHandle(forReadingFrom: archiveURL)
        defer { try? input.close() }
        let searchSize = Int(min(archiveSize, Int64(ZIPConstants.maximumEOCDSearch)))
        try input.seek(toOffset: UInt64(archiveSize - Int64(searchSize)))
        let tail = try input.readExactly(searchSize)
        guard let eocdOffset = tail.lastIndex(ofLittleEndian: ZIPConstants.endSignature),
              eocdOffset + 22 <= tail.count else {
            throw ZIPArchiveError.malformedArchive
        }
        let disk = try tail.uint16(at: eocdOffset + 4)
        let centralDisk = try tail.uint16(at: eocdOffset + 6)
        let diskCount = try tail.uint16(at: eocdOffset + 8)
        let count = try tail.uint16(at: eocdOffset + 10)
        let centralSize = try tail.uint32(at: eocdOffset + 12)
        let centralOffset = try tail.uint32(at: eocdOffset + 16)
        let commentLength = Int(try tail.uint16(at: eocdOffset + 20))
        guard disk == 0, centralDisk == 0, diskCount == count,
              eocdOffset + 22 + commentLength == tail.count else {
            throw ZIPArchiveError.malformedArchive
        }
        guard count != UInt16.max, centralSize != UInt32.max, centralOffset != UInt32.max else {
            throw ZIPArchiveError.unsupportedZIP64
        }
        guard Int(count) <= limits.maximumFileCount else { throw ZIPArchiveError.tooManyFiles }
        guard UInt64(centralOffset) + UInt64(centralSize) <= UInt64(archiveSize) else {
            throw ZIPArchiveError.malformedArchive
        }

        try input.seek(toOffset: UInt64(centralOffset))
        var members: [ZIPMember] = []
        var seenPaths = Set<String>()
        var totalCompressed: Int64 = 0
        var totalExpanded: Int64 = 0
        for _ in 0..<count {
            let header = try input.readExactly(ZIPConstants.centralHeaderSize)
            guard try header.uint32(at: 0) == ZIPConstants.centralHeaderSignature else {
                throw ZIPArchiveError.malformedArchive
            }
            let flags = try header.uint16(at: 8)
            guard flags & 0x1 == 0 else { throw ZIPArchiveError.encryptedMember }
            let method = try header.uint16(at: 10)
            let crc = try header.uint32(at: 16)
            let compressed = try header.uint32(at: 20)
            let expanded = try header.uint32(at: 24)
            let nameLength = Int(try header.uint16(at: 28))
            let extraLength = Int(try header.uint16(at: 30))
            let commentLength = Int(try header.uint16(at: 32))
            let externalAttributes = try header.uint32(at: 38)
            let localOffset = try header.uint32(at: 42)
            guard compressed != UInt32.max, expanded != UInt32.max, localOffset != UInt32.max else {
                throw ZIPArchiveError.unsupportedZIP64
            }
            let nameData = try input.readExactly(nameLength)
            guard let rawPath = String(data: nameData, encoding: .utf8) else {
                throw ZIPArchiveError.unsafePath
            }
            let path = try ZIPPathValidator.validate(rawPath, seenPaths: &seenPaths)
            let unixMode = (externalAttributes >> 16) & 0xF000
            guard unixMode == 0 || unixMode == 0x8000 else {
                throw ZIPArchiveError.unsupportedFileType
            }
            try input.seek(toOffset: input.offset() + UInt64(extraLength + commentLength))

            let compressedSize = Int64(compressed)
            let expandedSize = Int64(expanded)
            let ratio = expandedSize == 0 ? 1 : expandedSize / max(compressedSize, 1)
            guard ratio <= limits.maximumCompressionRatio else {
                throw ZIPArchiveError.compressionRatioExceeded
            }
            totalCompressed = try checkedAdd(totalCompressed, compressedSize)
            totalExpanded = try checkedAdd(totalExpanded, expandedSize)
            guard totalExpanded <= limits.maximumExpandedBytes else {
                throw ZIPArchiveError.expandedSizeExceeded
            }
            members.append(ZIPMember(
                path: path,
                compressedSize: compressedSize,
                uncompressedSize: expandedSize,
                crc32: crc,
                localHeaderOffset: localOffset,
                compressionMethod: method
            ))
        }
        let wholeRatio = totalExpanded == 0 ? 1 : totalExpanded / max(totalCompressed, 1)
        guard wholeRatio <= limits.maximumCompressionRatio else {
            throw ZIPArchiveError.compressionRatioExceeded
        }
        let extractionCapacity = availableCapacity > limits.capacitySafetyReserve
            ? availableCapacity - limits.capacitySafetyReserve
            : 0
        guard totalExpanded <= extractionCapacity else {
            throw ZIPArchiveError.insufficientCapacity
        }
        guard members.allSatisfy({ $0.compressionMethod == 0 && $0.compressedSize == $0.uncompressedSize }) else {
            throw ZIPArchiveError.unsupportedCompression
        }
        return members
    }

    private static func checkedAdd(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw ZIPArchiveError.expandedSizeExceeded }
        return result
    }
}

private enum ZIPPathValidator {
    static func validate(_ rawPath: String, seenPaths: inout Set<String>) throws -> String {
        guard !rawPath.isEmpty,
              rawPath.utf8.count <= 1_024,
              !rawPath.hasPrefix("/"),
              !rawPath.hasPrefix("\\"),
              !rawPath.contains("\\"),
              !rawPath.contains(":"),
              rawPath == rawPath.precomposedStringWithCanonicalMapping else {
            throw ZIPArchiveError.unsafePath
        }
        let components = rawPath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.count <= 32,
              components.allSatisfy({ $0.utf8.count <= 255 }),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ZIPArchiveError.unsafePath
        }
        let normalizedKey = rawPath.precomposedStringWithCanonicalMapping.lowercased()
        guard seenPaths.insert(normalizedKey).inserted else { throw ZIPArchiveError.duplicatePath }
        return rawPath
    }
}

struct CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 == 1 ? 0xedb88320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    private var state: UInt32 = 0xffffffff

    var value: UInt32 { state ^ 0xffffffff }

    mutating func update(_ data: Data) {
        for byte in data {
            let index = Int((state ^ UInt32(byte)) & 0xff)
            state = Self.table[index] ^ (state >> 8)
        }
    }

    static func checksum(fileAt url: URL) throws -> UInt32 {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var crc = CRC32()
        while let chunk = try input.read(upToCount: ZIPConstants.chunkSize), !chunk.isEmpty {
            crc.update(chunk)
        }
        return crc.value
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    func uint16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { throw ZIPArchiveError.malformedArchive }
        return UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func uint32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw ZIPArchiveError.malformedArchive }
        return UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }

    func lastIndex(ofLittleEndian value: UInt32) -> Int? {
        guard count >= 4 else { return nil }
        let bytes = [
            UInt8(value & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 24) & 0xff)
        ]
        for offset in stride(from: count - 4, through: 0, by: -1) {
            if self[offset] == bytes[0], self[offset + 1] == bytes[1],
               self[offset + 2] == bytes[2], self[offset + 3] == bytes[3] {
                return offset
            }
        }
        return nil
    }
}

private extension FileHandle {
    func readExactly(_ count: Int) throws -> Data {
        guard count >= 0, let data = try read(upToCount: count), data.count == count else {
            throw ZIPArchiveError.malformedArchive
        }
        return data
    }
}
