import Foundation
import CloudKit
import SyncFoundation
import Darwin

// Generates candidate expectations from real local SDK records, never server state.
func run() throws {
    guard CommandLine.arguments.count == 2 else {
        throw NSError(domain: "SyncSchema", code: 1, userInfo: [NSLocalizedDescriptionKey: "Usage: SyncSchema <new-output-directory>"])
    }
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    // Refuse an existing directory so evidence is never overwritten.
    guard mkdir(root.path, 0o700) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    let dataset = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let payload = Data("{\"synthetic\":true}".utf8), original = Data([0x50, 0x47, 0x4f, 0x53])
    let payloadURL = root.appendingPathComponent("synthetic-payload.bin")
    let originalURL = root.appendingPathComponent("synthetic-original.bin")
    try payload.write(to: payloadURL, options: .withoutOverwriting)
    try original.write(to: originalURL, options: .withoutOverwriting)
    let descriptor = AssetDescriptor(bytes: original)
    let manifest = try MutationManifest(dataset: dataset,
        mutation: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        object: SyncObject(kind: "SyntheticFixture", id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!),
        payload: AssetDescriptor(bytes: payload), originals: [OriginalReference(id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!, asset: descriptor)])
    let records = [try CloudRecordCodec.encode(manifest, payloadURL: payloadURL),
                   try CloudRecordCodec.encodeOriginal(descriptor, dataset: dataset, url: originalURL)]
    var types: [String: [String: String]] = [:]
    for record in records {
        var fields: [String: String] = [:]
        for key in record.allKeys() {
            switch record[key] {
            case is CKAsset: fields[key] = "ASSET"
            case is Data: fields[key] = "BYTES"
            case is String: fields[key] = "STRING"
            case is NSNumber: fields[key] = "INT64"
            default: throw SyncValidationError.invalidRecord
            }
        }
        types[record.recordType] = fields
    }
    guard types[CloudRecordCodec.mutationType] == CloudRecordCodec.mutationFields,
          types[CloudRecordCodec.originalType] == CloudRecordCodec.originalFields else { throw SyncValidationError.invalidRecord }
    let result: [String: Any] = [
        "status": "CANDIDATE_NOT_FROZEN", "wireVersion": 1, "database": "private",
        "zonePattern": "PGSyncV1-<dataset UUID lowercase>",
        "recordNamePatterns": ["mutation-<mutation UUID lowercase>", "original-<sha256 lowercase>"],
        "recordTypes": types, "customIndexes": [],
        "serverSchemaChecked": false, "networkOperations": 0,
        "limits": ["manifestBytes": SyncLimits.manifestBytes, "payloadBytes": SyncLimits.payloadBytes,
                   "originalBytes": SyncLimits.originalBytes, "parents": SyncLimits.parents,
                   "dependencies": SyncLimits.dependencies, "media": SyncLimits.media]
    ]
    var bytes = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    bytes.append(0x0A)
    try bytes.write(to: root.appendingPathComponent("schema.json"), options: .withoutOverwriting)
    try Data((syncDigest(bytes) + "\n").utf8).write(to: root.appendingPathComponent("schema.sha256"), options: .withoutOverwriting)
    print("Generated local candidate schema; P0/server/Production remain unverified.")
}
do { try run() }
catch { fputs("SyncSchema failed: \(error)\n", stderr); exit(1) }
