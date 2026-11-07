import Foundation
import CloudKit
import CoreFoundation
import Darwin

/// Local SDK codec only. Never creates a CKContainer or performs a cloud operation.
public enum CloudRecordCodec {
    public static let mutationType = "PGMutationV1"
    public static let originalType = "PGOriginalV1"
    public static let mutationFields = ["wireVersion": "INT64", "manifest": "BYTES", "sha256": "STRING", "payload": "ASSET"]
    public static let originalFields = ["wireVersion": "INT64", "sha256": "STRING", "byteCount": "INT64", "original": "ASSET"]
    public static func zone(dataset: UUID) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "PGSyncV1-" + dataset.wire, ownerName: CKCurrentUserDefaultName)
    }
    public static func mutationID(_ mutation: UUID, dataset: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "mutation-" + mutation.wire, zoneID: zone(dataset: dataset))
    }
    public static func originalID(_ hash: String, dataset: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "original-" + hash, zoneID: zone(dataset: dataset))
    }

    /// URLs must belong to caller-owned immutable staging leases until SDK completion.
    /// Validation does not make an externally mutable file immutable.
    public static func encode(_ manifest: MutationManifest, payloadURL: URL?) throws -> CKRecord {
        let bytes = try manifest.encoded()
        let record = CKRecord(recordType: mutationType, recordID: mutationID(manifest.mutation, dataset: manifest.dataset))
        record["wireVersion"] = 1 as CKRecordValue
        record["manifest"] = bytes as CKRecordValue
        record["sha256"] = syncDigest(bytes) as CKRecordValue
        if let descriptor = manifest.payload {
            guard let payloadURL else { throw SyncValidationError.missingAsset }
            try verify(readAsset(payloadURL, maximum: SyncLimits.payloadBytes), descriptor: descriptor, maximum: SyncLimits.payloadBytes)
            record["payload"] = CKAsset(fileURL: payloadURL)
        } else if payloadURL != nil { throw SyncValidationError.invalidManifest }
        return record
    }

    /// Bytes returned are owned Data; caller retains them durably before any engine checkpoint.
    /// Successful decoding is not permission to publish before causal/domain/media validation.
    public static func decode(_ record: CKRecord, dataset: UUID) throws -> (MutationManifest, Data?) {
        guard record.recordType == mutationType, record.recordID.zoneID == zone(dataset: dataset),
              exactInteger(record["wireVersion"]) == 1,
              let bytes = record["manifest"] as? Data, bytes.count <= SyncLimits.manifestBytes,
              record["sha256"] as? String == syncDigest(bytes) else { throw SyncValidationError.invalidRecord }
        let manifest = try MutationManifest.decode(bytes)
        guard manifest.dataset == dataset, record.recordID == mutationID(manifest.mutation, dataset: dataset),
              Set(record.allKeys()) == Set(manifest.deleted ? ["wireVersion", "manifest", "sha256"] : Array(mutationFields.keys)) else {
            throw SyncValidationError.invalidRecord
        }
        if let descriptor = manifest.payload {
            guard let asset = record["payload"] as? CKAsset, let url = asset.fileURL else { throw SyncValidationError.missingAsset }
            let payload = try readAsset(url, maximum: SyncLimits.payloadBytes)
            try verify(payload, descriptor: descriptor, maximum: SyncLimits.payloadBytes)
            return (manifest, payload)
        }
        return (manifest, nil)
    }

    public static func encodeOriginal(_ descriptor: AssetDescriptor, dataset: UUID, url: URL) throws -> CKRecord {
        try verify(readAsset(url, maximum: SyncLimits.originalBytes), descriptor: descriptor, maximum: SyncLimits.originalBytes)
        let record = CKRecord(recordType: originalType, recordID: originalID(descriptor.sha256, dataset: dataset))
        record["wireVersion"] = 1 as CKRecordValue
        record["sha256"] = descriptor.sha256 as CKRecordValue
        record["byteCount"] = descriptor.byteCount as CKRecordValue
        record["original"] = CKAsset(fileURL: url)
        return record
    }
    public static func decodeOriginal(_ record: CKRecord, dataset: UUID) throws -> (AssetDescriptor, Data) {
        guard record.recordType == originalType, record.recordID.zoneID == zone(dataset: dataset),
              Set(record.allKeys()) == Set(originalFields.keys), exactInteger(record["wireVersion"]) == 1,
              let hash = record["sha256"] as? String, let count = exactInteger(record["byteCount"]),
              record.recordID == originalID(hash, dataset: dataset) else { throw SyncValidationError.invalidRecord }
        let descriptor = AssetDescriptor(sha256: hash, byteCount: count)
        try descriptor.validate(maximum: SyncLimits.originalBytes)
        guard let asset = record["original"] as? CKAsset, let url = asset.fileURL else { throw SyncValidationError.missingAsset }
        let bytes = try readAsset(url, maximum: SyncLimits.originalBytes)
        try verify(bytes, descriptor: descriptor, maximum: SyncLimits.originalBytes)
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
    guard url.isFileURL else { throw SyncValidationError.missingAsset }
    let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    guard descriptor >= 0 else { throw SyncValidationError.missingAsset }
    let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? file.close() }
    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
          metadata.st_size > 0 else { throw SyncValidationError.missingAsset }
    guard metadata.st_size <= maximum else { throw SyncValidationError.limitExceeded }
    var result = Data()
    while let chunk = try file.read(upToCount: min(65_536, maximum - result.count + 1)), !chunk.isEmpty {
        guard result.count + chunk.count <= maximum else { throw SyncValidationError.limitExceeded }
        result.append(chunk)
    }
    return result
}
