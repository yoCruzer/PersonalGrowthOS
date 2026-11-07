import Foundation
import CloudKit
import CryptoKit
import Darwin
import SyncFoundation

/// Offline synthetic fixture replay. Input is read only; output must be a new directory.
func run() throws {
    let args = CommandLine.arguments
    guard args.count == 5, let count = Int(args[3]) else {
        throw NSError(domain: "SyncPayloadProbe", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "Usage: SyncPayloadProbe <synthetic-source-file> <expected-sha256> <expected-byte-count> <new-output-directory>"])
    }
    let source = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[4], isDirectory: true)
    guard mkdir(output.path, 0o700) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    let expected = AssetDescriptor(sha256: args[2], byteCount: count)
    let dataset = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    var records: [CKRecord] = [], maximumCallbackBytes = 0
    let payload = try PayloadManifest.prepare(fileURL: source, expected: expected) { index, descriptor, bytes in
        maximumCallbackBytes = max(maximumCallbackBytes, bytes.count)
        let url = output.appendingPathComponent(String(format: "chunk-%02d.bin", index))
        try bytes.write(to: url, options: .withoutOverwriting)
        records.append(try CloudRecordCodec.encodeChunk(descriptor, dataset: dataset, url: url))
    }
    let manifest = try MutationManifest(dataset: dataset,
        mutation: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        object: SyncObject(kind: "NetWorthSnapshot", id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!), payload: payload)
    let received = try CloudRecordCodec.decode(CloudRecordCodec.encode(manifest), dataset: dataset)
    var cursor = 0
    try received.verifyAssetsComplete(nextPayloadChunk: {
        guard cursor < records.count else { return nil }
        defer { cursor += 1 }
        let decoded = try CloudRecordCodec.decodeChunk(records[cursor], dataset: dataset)
        guard decoded.0 == payload.chunks[cursor] else { throw SyncValidationError.corruptAsset }
        return IndexedPayloadChunk(index: cursor, bytes: decoded.1)
    }, originalBytes: { _ in throw SyncValidationError.missingAsset })
    // A separate bounded final read proves the original fixture still matches its supplied oracle.
    var finalHash = SHA256(), finalCount = 0
    let file = try FileHandle(forReadingFrom: source)
    defer { try? file.close() }
    while try autoreleasepool(invoking: {
        guard let bytes = try file.read(upToCount: 65_536), !bytes.isEmpty else { return false }
        guard finalCount <= SyncLimits.payloadBytes - bytes.count else { throw SyncValidationError.limitExceeded }
        finalHash.update(data: bytes); finalCount += bytes.count
        return true
    }) {}
    let finalDigest = finalHash.finalize().map { String(format: "%02x", $0) }.joined()
    guard finalCount == expected.byteCount, finalDigest == expected.sha256 else { throw SyncValidationError.corruptAsset }
    let summary: [String: Any] = ["status": "OFFLINE_CODEC_PASS", "wireVersion": 2,
        "byteCount": count, "sha256": finalDigest, "sourceUnchanged": true,
        "chunkCount": records.count, "orderedIndices": Array(records.indices),
        "chunkHashes": payload.chunks.map(\.sha256), "chunkByteCounts": payload.chunks.map(\.byteCount),
        "maximumEmittedChunkBytes": maximumCallbackBytes, "manifestBytes": try manifest.encoded().count,
        "networkOperations": 0, "productionVerified": false,
        "memoryScope": "Streaming payload path: up to two chunk buffers internally; excludes caller-owned input/output retention and SDK overhead. Process RSS not asserted."]
    let bytes = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
    try bytes.write(to: output.appendingPathComponent("summary.json"), options: .withoutOverwriting)
    try manifest.encoded().write(to: output.appendingPathComponent("manifest.json"), options: .withoutOverwriting)
    print("Verified synthetic payload: \(count) bytes, \(records.count) ordered chunks; source unchanged.")
}
do { try run() }
catch { fputs("SyncPayloadProbe failed: \(error)\n", stderr); exit(1) }
