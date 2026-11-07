import Foundation
import CloudKit
import CoreFoundation
import Darwin

/// Local SDK codec only. Never creates a CKContainer or performs a cloud operation.
public enum CloudRecordCodec {
    public static let mutationType = "PGMutationV2"
    public static let originalType = "PGOriginalV2"
    public static let mutationFields = ["wireVersion": "INT64", "manifest": "BYTES", "sha256": "STRING"]
    public static let chunkType = "PGPayloadChunkV2"
    public static let chunkFields = ["wireVersion": "INT64", "sha256": "STRING", "byteCount": "INT64", "chunk": "ASSET"]
    public static let originalFields = ["wireVersion": "INT64", "sha256": "STRING", "byteCount": "INT64", "original": "ASSET"]
    public static func zone(dataset: UUID) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "PGSyncV2-" + dataset.wire, ownerName: CKCurrentUserDefaultName)
    }
    public static func mutationID(_ mutation: UUID, dataset: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "mutation-" + mutation.wire, zoneID: zone(dataset: dataset))
    }
    public static func originalID(_ hash: String, dataset: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "original-" + hash, zoneID: zone(dataset: dataset))
    }

    /// A manifest record never embeds payload bytes or a growing history.
    public static func encode(_ manifest: MutationManifest) throws -> CKRecord {
        let bytes = try manifest.encoded()
        let record = CKRecord(recordType: mutationType, recordID: mutationID(manifest.mutation, dataset: manifest.dataset))
        record["wireVersion"] = 2 as CKRecordValue
        record["manifest"] = bytes as CKRecordValue
        record["sha256"] = syncDigest(bytes) as CKRecordValue
        return record
    }

    /// Receipt of this record alone proves neither payload completeness nor business validity.
    public static func decode(_ record: CKRecord, dataset: UUID) throws -> MutationManifest {
        guard record.recordType == mutationType, record.recordID.zoneID == zone(dataset: dataset),
              exactInteger(record["wireVersion"]) == 2, Set(record.allKeys()) == Set(mutationFields.keys),
              let bytes = record["manifest"] as? Data, bytes.count <= SyncLimits.manifestBytes,
              record["sha256"] as? String == syncDigest(bytes) else { throw SyncValidationError.invalidRecord }
        let manifest = try MutationManifest.decode(bytes)
        guard manifest.dataset == dataset, record.recordID == mutationID(manifest.mutation, dataset: dataset) else {
            throw SyncValidationError.invalidRecord
        }
        return manifest
    }
    public static func chunkID(_ hash: String, dataset: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "chunk-" + hash, zoneID: zone(dataset: dataset))
    }
    /// URL must be an immutable caller-owned staging lease until SDK completion.
    public static func encodeChunk(_ descriptor: AssetDescriptor, dataset: UUID, url: URL) throws -> CKRecord {
        try verifyAssetBytes(readAsset(url, maximum: SyncLimits.chunkBytes), descriptor: descriptor, maximum: SyncLimits.chunkBytes)
        let record = CKRecord(recordType: chunkType, recordID: chunkID(descriptor.sha256, dataset: dataset))
        record["wireVersion"] = 2 as CKRecordValue
        record["sha256"] = descriptor.sha256 as CKRecordValue
        record["byteCount"] = descriptor.byteCount as CKRecordValue
        record["chunk"] = CKAsset(fileURL: url)
        return record
    }
    public static func decodeChunk(_ record: CKRecord, dataset: UUID) throws -> (AssetDescriptor, Data) {
        guard record.recordType == chunkType, record.recordID.zoneID == zone(dataset: dataset),
              Set(record.allKeys()) == Set(chunkFields.keys), exactInteger(record["wireVersion"]) == 2,
              let hash = record["sha256"] as? String, let count = exactInteger(record["byteCount"]),
              record.recordID == chunkID(hash, dataset: dataset) else { throw SyncValidationError.invalidRecord }
        let descriptor = AssetDescriptor(sha256: hash, byteCount: count)
        try descriptor.validate(maximum: SyncLimits.chunkBytes)
        guard let asset = record["chunk"] as? CKAsset, let url = asset.fileURL else { throw SyncValidationError.missingAsset }
        let bytes = try readAsset(url, maximum: SyncLimits.chunkBytes)
        try verifyAssetBytes(bytes, descriptor: descriptor, maximum: SyncLimits.chunkBytes)
        return (descriptor, bytes)
    }

    public static func encodeOriginal(_ descriptor: AssetDescriptor, dataset: UUID, url: URL) throws -> CKRecord {
        try verifyAssetBytes(readAsset(url, maximum: SyncLimits.originalBytes), descriptor: descriptor, maximum: SyncLimits.originalBytes)
        let record = CKRecord(recordType: originalType, recordID: originalID(descriptor.sha256, dataset: dataset))
        record["wireVersion"] = 2 as CKRecordValue
        record["sha256"] = descriptor.sha256 as CKRecordValue
        record["byteCount"] = descriptor.byteCount as CKRecordValue
        record["original"] = CKAsset(fileURL: url)
        return record
    }
    public static func decodeOriginal(_ record: CKRecord, dataset: UUID) throws -> (AssetDescriptor, Data) {
        guard record.recordType == originalType, record.recordID.zoneID == zone(dataset: dataset),
              Set(record.allKeys()) == Set(originalFields.keys), exactInteger(record["wireVersion"]) == 2,
              let hash = record["sha256"] as? String, let count = exactInteger(record["byteCount"]),
              record.recordID == originalID(hash, dataset: dataset) else { throw SyncValidationError.invalidRecord }
        let descriptor = AssetDescriptor(sha256: hash, byteCount: count)
        try descriptor.validate(maximum: SyncLimits.originalBytes)
        guard let asset = record["original"] as? CKAsset, let url = asset.fileURL else { throw SyncValidationError.missingAsset }
        let bytes = try readAsset(url, maximum: SyncLimits.originalBytes)
        try verifyAssetBytes(bytes, descriptor: descriptor, maximum: SyncLimits.originalBytes)
        return (descriptor, bytes)
    }
}

private func exactInteger(_ value: CKRecordValue?) -> Int? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"].contains(String(cString: number.objCType)),
          let result = Int(number.stringValue) else { return nil }
    return result
}

/// Bounded read from one regular-file descriptor. Refuse symlinks and special files;
/// reject growth past the limit before allocating unbounded bytes.
private func readAsset(_ url: URL, maximum: Int) throws -> Data {
    let file = try openRegularAsset(url, maximum: maximum)
    defer { try? file.close() }
    var result = Data()
    while let chunk = try file.read(upToCount: min(65_536, maximum - result.count + 1)), !chunk.isEmpty {
        guard result.count + chunk.count <= maximum else { throw SyncValidationError.limitExceeded }
        result.append(chunk)
    }
    return result
}
