import Foundation

struct ZIPImportLimits: Equatable {
    static let production = ZIPImportLimits(
        maximumArchiveBytes: 8 * 1_024 * 1_024 * 1_024,
        maximumExpandedBytes: 24 * 1_024 * 1_024 * 1_024,
        capacitySafetyReserve: 1 * 1_024 * 1_024 * 1_024,
        maximumFileCount: 100_000,
        maximumObjectCount: 500_000,
        maximumCompressionRatio: 100,
        maximumManifestBytes: 32 * 1_024 * 1_024,
        maximumDataBytes: 64 * 1_024 * 1_024
    )

    let maximumArchiveBytes: Int64
    let maximumExpandedBytes: Int64
    let capacitySafetyReserve: Int64
    let maximumFileCount: Int
    let maximumObjectCount: Int
    let maximumCompressionRatio: Int64
    let maximumManifestBytes: Int64
    let maximumDataBytes: Int64

    init(
        maximumArchiveBytes: Int64,
        maximumExpandedBytes: Int64,
        capacitySafetyReserve: Int64,
        maximumFileCount: Int,
        maximumObjectCount: Int,
        maximumCompressionRatio: Int64,
        maximumManifestBytes: Int64 = 32 * 1_024 * 1_024,
        maximumDataBytes: Int64 = 64 * 1_024 * 1_024
    ) {
        self.maximumArchiveBytes = maximumArchiveBytes
        self.maximumExpandedBytes = maximumExpandedBytes
        self.capacitySafetyReserve = capacitySafetyReserve
        self.maximumFileCount = maximumFileCount
        self.maximumObjectCount = maximumObjectCount
        self.maximumCompressionRatio = maximumCompressionRatio
        self.maximumManifestBytes = maximumManifestBytes
        self.maximumDataBytes = maximumDataBytes
    }
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
    fileprivate let localHeaderOffset: UInt64
    fileprivate let compressionMethod: UInt16
}

private enum ZIPConstants {
    static let localHeaderSignature: UInt32 = 0x04034b50
    static let centralHeaderSignature: UInt32 = 0x02014b50
    static let endSignature: UInt32 = 0x06054b50
    static let zip64EndSignature: UInt32 = 0x06064b50
    static let zip64LocatorSignature: UInt32 = 0x07064b50
    static let localHeaderSize = 30
    static let centralHeaderSize = 46
    static let maximumEOCDSearch = 65_557
    static let chunkSize = 1_048_576
}

enum ZIPArchiveWriter {
    static func write(sources: [ZIPSource], to destination: URL) throws {
        var seenPaths = Set<String>()
        let prepared = try sources.map { source -> PreparedSource in
            let path = try ZIPPathValidator.validate(source.path, seenPaths: &seenPaths)
            let attributes = try FileManager.default.attributesOfItem(atPath: source.fileURL.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            guard size >= 0 else { throw ZIPArchiveError.malformedArchive }
            return PreparedSource(
                path: path,
                pathData: Data(path.utf8),
                fileURL: source.fileURL,
                size: UInt64(size),
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
                try Task.checkCancellation()
                let offset = try output.offset()
                try output.write(contentsOf: localHeader(for: source))
                try copy(source.fileURL, to: output)
                records.append(CentralRecord(source: source, localHeaderOffset: offset))
            }
            let centralOffset = try output.offset()
            for record in records {
                try output.write(contentsOf: centralHeader(for: record))
            }
            let centralSize = try output.offset() - centralOffset
            try output.write(contentsOf: endRecords(
                count: UInt64(records.count),
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
        let size: UInt64
        let crc32: UInt32
    }

    private struct CentralRecord {
        let source: PreparedSource
        let localHeaderOffset: UInt64
    }

    private static func localHeader(for source: PreparedSource) -> Data {
        let usesZIP64 = source.size >= UInt64(UInt32.max)
        var extra = Data()
        if usesZIP64 {
            extra.appendLE(UInt16(0x0001))
            extra.appendLE(UInt16(16))
            extra.appendLE(source.size)
            extra.appendLE(source.size)
        }
        var data = Data()
        data.appendLE(ZIPConstants.localHeaderSignature)
        data.appendLE(UInt16(usesZIP64 ? 45 : 20))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(source.crc32)
        data.appendLE(usesZIP64 ? UInt32.max : UInt32(source.size))
        data.appendLE(usesZIP64 ? UInt32.max : UInt32(source.size))
        data.appendLE(UInt16(source.pathData.count))
        data.appendLE(UInt16(extra.count))
        data.append(source.pathData)
        data.append(extra)
        return data
    }

    private static func centralHeader(for record: CentralRecord) -> Data {
        let source = record.source
        let largeSize = source.size >= UInt64(UInt32.max)
        let largeOffset = record.localHeaderOffset >= UInt64(UInt32.max)
        var extraPayload = Data()
        if largeSize {
            extraPayload.appendLE(source.size)
            extraPayload.appendLE(source.size)
        }
        if largeOffset { extraPayload.appendLE(record.localHeaderOffset) }
        var extra = Data()
        if !extraPayload.isEmpty {
            extra.appendLE(UInt16(0x0001))
            extra.appendLE(UInt16(extraPayload.count))
            extra.append(extraPayload)
        }
        var data = Data()
        data.appendLE(ZIPConstants.centralHeaderSignature)
        data.appendLE(UInt16(0x032d))
        data.appendLE(UInt16(largeSize || largeOffset ? 45 : 20))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(source.crc32)
        data.appendLE(largeSize ? UInt32.max : UInt32(source.size))
        data.appendLE(largeSize ? UInt32.max : UInt32(source.size))
        data.appendLE(UInt16(source.pathData.count))
        data.appendLE(UInt16(extra.count))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt32(0o100644) << 16)
        data.appendLE(largeOffset ? UInt32.max : UInt32(record.localHeaderOffset))
        data.append(source.pathData)
        data.append(extra)
        return data
    }

    private static func endRecords(count: UInt64, centralSize: UInt64, centralOffset: UInt64) -> Data {
        var data = Data()
        let usesZIP64 = count >= UInt64(UInt16.max)
            || centralSize >= UInt64(UInt32.max)
            || centralOffset >= UInt64(UInt32.max)
        if usesZIP64 {
            let zip64Offset = centralOffset + centralSize
            data.appendLE(ZIPConstants.zip64EndSignature)
            data.appendLE(UInt64(44))
            data.appendLE(UInt16(45))
            data.appendLE(UInt16(45))
            data.appendLE(UInt32(0))
            data.appendLE(UInt32(0))
            data.appendLE(count)
            data.appendLE(count)
            data.appendLE(centralSize)
            data.appendLE(centralOffset)
            data.appendLE(ZIPConstants.zip64LocatorSignature)
            data.appendLE(UInt32(0))
            data.appendLE(zip64Offset)
            data.appendLE(UInt32(1))
        }
        data.appendLE(ZIPConstants.endSignature)
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(usesZIP64 ? UInt16.max : UInt16(count))
        data.appendLE(usesZIP64 ? UInt16.max : UInt16(count))
        data.appendLE(usesZIP64 ? UInt32.max : UInt32(centralSize))
        data.appendLE(usesZIP64 ? UInt32.max : UInt32(centralOffset))
        data.appendLE(UInt16(0))
        return data
    }

    private static func copy(_ source: URL, to output: FileHandle) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: ZIPConstants.chunkSize), !chunk.isEmpty {
            try Task.checkCancellation()
            try output.write(contentsOf: chunk)
        }
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
            try Task.checkCancellation()
            let destination = rootURL.appendingPathComponent(member.path).standardizedFileURL
            guard destination.path.hasPrefix(rootURL.standardizedFileURL.path + "/") else {
                throw ZIPArchiveError.unsafePath
            }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try input.seek(toOffset: member.localHeaderOffset)
            let header = try input.readExactly(ZIPConstants.localHeaderSize)
            guard try header.uint32(at: 0) == ZIPConstants.localHeaderSignature else {
                throw ZIPArchiveError.malformedArchive
            }
            let localFlags = try header.uint16(at: 6)
            let localMethod = try header.uint16(at: 8)
            let localCRC = try header.uint32(at: 14)
            let localCompressed32 = try header.uint32(at: 18)
            let localExpanded32 = try header.uint32(at: 22)
            let nameLength = Int(try header.uint16(at: 26))
            let extraLength = Int(try header.uint16(at: 28))
            let nameData = try input.readExactly(nameLength)
            let extraData = try input.readExactly(extraLength)
            let localZIP64 = try ZIP64Extra.parse(
                extraData,
                needsExpanded: localExpanded32 == UInt32.max,
                needsCompressed: localCompressed32 == UInt32.max,
                needsOffset: false
            )
            let localCompressed = localCompressed32 == UInt32.max
                ? localZIP64.compressed
                : UInt64(localCompressed32)
            let localExpanded = localExpanded32 == UInt32.max
                ? localZIP64.expanded
                : UInt64(localExpanded32)
            guard localFlags & 0x9 == 0,
                  localMethod == member.compressionMethod,
                  localCRC == member.crc32,
                  localCompressed == UInt64(member.compressedSize),
                  localExpanded == UInt64(member.uncompressedSize),
                  String(data: nameData, encoding: .utf8) == member.path else {
                throw ZIPArchiveError.malformedArchive
            }
            guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let output = try FileHandle(forWritingTo: destination)
            do {
                var remaining = member.compressedSize
                var crc = CRC32()
                while remaining > 0 {
                    try Task.checkCancellation()
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
        let diskCount16 = try tail.uint16(at: eocdOffset + 8)
        let count16 = try tail.uint16(at: eocdOffset + 10)
        let centralSize32 = try tail.uint32(at: eocdOffset + 12)
        let centralOffset32 = try tail.uint32(at: eocdOffset + 16)
        let commentLength = Int(try tail.uint16(at: eocdOffset + 20))
        guard disk == 0, centralDisk == 0, diskCount16 == count16,
              eocdOffset + 22 + commentLength == tail.count else {
            throw ZIPArchiveError.malformedArchive
        }
        let eocdAbsoluteOffset = UInt64(archiveSize - Int64(searchSize) + Int64(eocdOffset))
        let usesZIP64 = count16 == UInt16.max
            || centralSize32 == UInt32.max
            || centralOffset32 == UInt32.max
        let count: UInt64
        let centralSize: UInt64
        let centralOffset: UInt64
        if usesZIP64 {
            guard eocdAbsoluteOffset >= 20 else { throw ZIPArchiveError.malformedArchive }
            try input.seek(toOffset: eocdAbsoluteOffset - 20)
            let locator = try input.readExactly(20)
            guard try locator.uint32(at: 0) == ZIPConstants.zip64LocatorSignature,
                  try locator.uint32(at: 4) == 0,
                  try locator.uint32(at: 16) == 1 else {
                throw ZIPArchiveError.malformedArchive
            }
            let zip64Offset = try locator.uint64(at: 8)
            try input.seek(toOffset: zip64Offset)
            let zip64 = try input.readExactly(56)
            guard try zip64.uint32(at: 0) == ZIPConstants.zip64EndSignature,
                  try zip64.uint64(at: 4) >= 44,
                  try zip64.uint32(at: 16) == 0,
                  try zip64.uint32(at: 20) == 0,
                  try zip64.uint64(at: 24) == zip64.uint64(at: 32) else {
                throw ZIPArchiveError.malformedArchive
            }
            count = try zip64.uint64(at: 32)
            centralSize = try zip64.uint64(at: 40)
            centralOffset = try zip64.uint64(at: 48)
        } else {
            count = UInt64(count16)
            centralSize = UInt64(centralSize32)
            centralOffset = UInt64(centralOffset32)
        }
        guard count <= UInt64(limits.maximumFileCount) else { throw ZIPArchiveError.tooManyFiles }
        let (centralEnd, centralOverflow) = centralOffset.addingReportingOverflow(centralSize)
        guard !centralOverflow, centralEnd <= UInt64(archiveSize) else {
            throw ZIPArchiveError.malformedArchive
        }

        try input.seek(toOffset: centralOffset)
        var members: [ZIPMember] = []
        var seenPaths = Set<String>()
        var totalCompressed: Int64 = 0
        var totalExpanded: Int64 = 0
        for _ in 0..<Int(count) {
            try Task.checkCancellation()
            let header = try input.readExactly(ZIPConstants.centralHeaderSize)
            guard try header.uint32(at: 0) == ZIPConstants.centralHeaderSignature else {
                throw ZIPArchiveError.malformedArchive
            }
            let flags = try header.uint16(at: 8)
            guard flags & 0x1 == 0 else { throw ZIPArchiveError.encryptedMember }
            let method = try header.uint16(at: 10)
            let crc = try header.uint32(at: 16)
            let compressed32 = try header.uint32(at: 20)
            let expanded32 = try header.uint32(at: 24)
            let nameLength = Int(try header.uint16(at: 28))
            let extraLength = Int(try header.uint16(at: 30))
            let commentLength = Int(try header.uint16(at: 32))
            let externalAttributes = try header.uint32(at: 38)
            let localOffset32 = try header.uint32(at: 42)
            let nameData = try input.readExactly(nameLength)
            guard let rawPath = String(data: nameData, encoding: .utf8) else {
                throw ZIPArchiveError.unsafePath
            }
            let path = try ZIPPathValidator.validate(rawPath, seenPaths: &seenPaths)
            let unixMode = (externalAttributes >> 16) & 0xF000
            guard unixMode == 0 || unixMode == 0x8000 else {
                throw ZIPArchiveError.unsupportedFileType
            }
            let extraData = try input.readExactly(extraLength)
            try input.seek(toOffset: input.offset() + UInt64(commentLength))
            let zip64 = try ZIP64Extra.parse(
                extraData,
                needsExpanded: expanded32 == UInt32.max,
                needsCompressed: compressed32 == UInt32.max,
                needsOffset: localOffset32 == UInt32.max
            )
            let compressed = compressed32 == UInt32.max ? zip64.compressed : UInt64(compressed32)
            let expanded = expanded32 == UInt32.max ? zip64.expanded : UInt64(expanded32)
            let localOffset = localOffset32 == UInt32.max ? zip64.offset : UInt64(localOffset32)
            guard compressed <= UInt64(Int64.max), expanded <= UInt64(Int64.max) else {
                throw ZIPArchiveError.expandedSizeExceeded
            }

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
        let (requiredCapacity, capacityOverflow) = totalExpanded.multipliedReportingOverflow(by: 2)
        guard !capacityOverflow, requiredCapacity <= extractionCapacity else {
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

private struct ZIP64Extra {
    let expanded: UInt64
    let compressed: UInt64
    let offset: UInt64

    static func parse(
        _ extra: Data,
        needsExpanded: Bool,
        needsCompressed: Bool,
        needsOffset: Bool
    ) throws -> ZIP64Extra {
        guard needsExpanded || needsCompressed || needsOffset else {
            return ZIP64Extra(expanded: 0, compressed: 0, offset: 0)
        }
        var fieldOffset = 0
        while fieldOffset + 4 <= extra.count {
            let identifier = try extra.uint16(at: fieldOffset)
            let size = Int(try extra.uint16(at: fieldOffset + 2))
            let payloadOffset = fieldOffset + 4
            guard payloadOffset + size <= extra.count else { throw ZIPArchiveError.malformedArchive }
            if identifier == 0x0001 {
                var cursor = payloadOffset
                func next(_ required: Bool) throws -> UInt64 {
                    guard required else { return 0 }
                    guard cursor + 8 <= payloadOffset + size else {
                        throw ZIPArchiveError.malformedArchive
                    }
                    defer { cursor += 8 }
                    return try extra.uint64(at: cursor)
                }
                return ZIP64Extra(
                    expanded: try next(needsExpanded),
                    compressed: try next(needsCompressed),
                    offset: try next(needsOffset)
                )
            }
            fieldOffset = payloadOffset + size
        }
        throw ZIPArchiveError.malformedArchive
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
            try Task.checkCancellation()
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

    func uint64(at offset: Int) throws -> UInt64 {
        guard offset >= 0, offset + 8 <= count else { throw ZIPArchiveError.malformedArchive }
        return (0..<8).reduce(UInt64(0)) { result, index in
            result | UInt64(self[offset + index]) << UInt64(index * 8)
        }
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
        guard count >= 0 else { throw ZIPArchiveError.malformedArchive }
        if count == 0 { return Data() }
        guard let data = try read(upToCount: count), data.count == count else {
            throw ZIPArchiveError.malformedArchive
        }
        return data
    }
}
