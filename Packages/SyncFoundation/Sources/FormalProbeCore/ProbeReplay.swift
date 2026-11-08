import Foundation
import CloudKit
import SyncFoundation

public struct ProbeCommandResult: Codable, Equatable, Sendable {
    public let index: Int
    public let command: String
    public let status: String
    public let recordType: String
    public let recordName: String
    public let sourceSHA256: String
}
public struct ProbeReport: Codable, Sendable {
    public let formatVersion: Int
    public let mode: String
    public let planSHA256: String
    public let run: UUID?
    public let dataset: UUID?
    public let networkOperations: Int
    public let serverSchemaChecked: Bool
    public let p0Passed: Bool
    public let status: String
    public let failureCode: String?
    public let failureStage: String?
    public let failureIndex: Int?
    public let commands: [ProbeCommandResult]
}
public enum FormalProbeReplay {
    /// Only fixed synthetic fixture files accepted. No transport/network or business database.
    @discardableResult public static func run(planURL: URL, expectedSHA256: String, output: URL) throws -> ProbeReport {
        let destination = try ProbeDirectory(output, create: true)
        var results: [ProbeCommandResult] = [], fixture: ProbeFixture?
        var stage = "schema", active: (Int, ProbeRecord)?
        do {
            try verifySchemaPin()
            stage = "plan-load"
            let loaded = try ProbeFixture.load(from: planURL, expectedSHA256: expectedSHA256)
            fixture = loaded
            let source = try ProbeDirectory(planURL, create: false)
            var readbackChunks: [String: Data] = [:], readbackOriginals: [String: Data] = [:]
            for (index, item) in loaded.plan.records.enumerated() {
                stage = "command"; active = (index, item)
                let bytes = try source.read(item.file)
                guard bytes == loaded.files[item.file], syncDigest(bytes) == item.sha256 else { throw FormalProbeError.fileChanged }
                let lease = "lease-" + item.file
                try destination.write(lease, bytes: bytes)
                let url = try destination.assetURL(lease)
                let record: CKRecord
                if item.recordType == CloudRecordCodec.originalType {
                    record = try CloudRecordCodec.encodeOriginal(AssetDescriptor(bytes: bytes), dataset: loaded.plan.dataset, url: url)
                    let received = try CloudRecordCodec.decodeOriginal(record, dataset: loaded.plan.dataset)
                    guard received.1 == bytes, received.1 == ProbeFixture.png else { throw FormalProbeError.fileChanged }
                    readbackOriginals[received.0.sha256] = received.1
                } else if item.recordType == CloudRecordCodec.chunkType {
                    record = try CloudRecordCodec.encodeChunk(AssetDescriptor(bytes: bytes), dataset: loaded.plan.dataset, url: url)
                    let received = try CloudRecordCodec.decodeChunk(record, dataset: loaded.plan.dataset)
                    guard received.1 == bytes else { throw FormalProbeError.fileChanged }
                    readbackChunks[received.0.sha256] = received.1
                } else {
                    let manifest = try MutationManifest.decode(bytes)
                    record = try CloudRecordCodec.encode(manifest)
                    let received = try CloudRecordCodec.decode(record, dataset: loaded.plan.dataset)
                    guard received == manifest, try received.encoded() == bytes else { throw FormalProbeError.fileChanged }
                    var cursor = 0
                    try received.verifyAssetsComplete(nextPayloadChunk: {
                        guard let payload = received.payload, cursor < payload.chunks.count else { return nil }
                        let chunk = payload.chunks[cursor]
                        guard let data = readbackChunks[chunk.sha256] else { throw FormalProbeError.missingFile }
                        defer { cursor += 1 }
                        return IndexedPayloadChunk(index: cursor, bytes: data)
                    }, originalBytes: { original in
                        guard let data = readbackOriginals[original.asset.sha256] else { throw FormalProbeError.missingFile }
                        return data
                    })
                }
                guard record.recordType == item.recordType, record.recordID.recordName == item.recordName,
                      record.recordID.zoneID == CloudRecordCodec.zone(dataset: loaded.plan.dataset) else { throw FormalProbeError.invalidPlan }
                try destination.requirePathBinding()
                results.append(ProbeCommandResult(index: index, command: item.command, status: "OFFLINE_PASS",
                    recordType: record.recordType, recordName: record.recordID.recordName, sourceSHA256: item.sha256))
            }
            // Recheck all source bytes at the boundary; a modified plan cannot masquerade as this run.
            stage = "final-reread"; active = nil
            _ = try ProbeFixture.load(from: planURL, expectedSHA256: expectedSHA256)
            let report = report(fixture: fixture, hash: expectedSHA256, commands: results, failure: nil, stage: nil, index: nil)
            try destination.write("report.json", bytes: probeJSON(report)); return report
        } catch {
            if let (index, item) = active {
                results.append(ProbeCommandResult(index: index, command: item.command, status: "OFFLINE_FAIL", recordType: item.recordType,
                    recordName: item.recordName, sourceSHA256: item.sha256))
            }
            let failure = report(fixture: fixture, hash: expectedSHA256, commands: results, failure: failureCode(error), stage: stage, index: active?.0)
            try destination.write("report.json", bytes: probeJSON(failure))
            throw error
        }
    }
    private static func report(fixture: ProbeFixture?, hash: String, commands: [ProbeCommandResult], failure: String?, stage: String?, index: Int?) -> ProbeReport {
        ProbeReport(formatVersion: 1, mode: "OFFLINE_ONLY", planSHA256: hash, run: fixture?.plan.run, dataset: fixture?.plan.dataset,
            networkOperations: 0, serverSchemaChecked: false, p0Passed: false,
            status: failure == nil ? "OFFLINE_PASS" : "OFFLINE_FAIL", failureCode: failure, failureStage: stage, failureIndex: index, commands: commands)
    }
    private static func failureCode(_ error: Error) -> String {
        switch error {
        case FormalProbeError.invalidPlan: "PLAN_REJECTED"
        case FormalProbeError.invalidPath: "PATH_REJECTED"
        case FormalProbeError.existingOutput: "OUTPUT_EXISTS"
        case FormalProbeError.missingFile: "FILE_MISSING"
        case FormalProbeError.fileChanged: "FILE_CHANGED"
        case FormalProbeError.limit: "LIMIT"
        case is SyncValidationError: "CODEC_REJECTED"
        case is DecodingError: "PLAN_DECODING_REJECTED"
        default: "IO_OR_VALIDATION_FAILED"
        }
    }
    public static func verifySchemaPin() throws {
        let result: [String: Any] = [
            "status": "CANDIDATE_NOT_FROZEN", "wireVersion": 2, "database": "private",
            "zonePattern": "PGSyncV2-<dataset UUID lowercase>",
            "recordNamePatterns": ["mutation-<mutation UUID lowercase>", "original-<sha256 lowercase>", "chunk-<sha256 lowercase>"],
            "recordTypes": [CloudRecordCodec.mutationType: CloudRecordCodec.mutationFields,
                            CloudRecordCodec.originalType: CloudRecordCodec.originalFields, CloudRecordCodec.chunkType: CloudRecordCodec.chunkFields],
            "customIndexes": [], "serverSchemaChecked": false, "networkOperations": 0,
            "limits": ["manifestBytes": SyncLimits.manifestBytes, "payloadBytes": SyncLimits.payloadBytes,
                       "originalBytes": SyncLimits.originalBytes, "chunkBytes": SyncLimits.chunkBytes,
                       "payloadChunks": SyncLimits.payloadChunks, "parents": SyncLimits.parents,
                       "dependencies": SyncLimits.dependencies, "media": SyncLimits.media]
        ]
        var bytes = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]); bytes.append(0x0A)
        guard syncDigest(bytes) == FormalProbeIdentity.schemaSHA256 else { throw FormalProbeError.invalidPlan }
    }
}
