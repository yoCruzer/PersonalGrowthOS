import Foundation
import CloudKit
import SyncFoundation

public enum FormalProbeIdentity {
    public static let container = "iCloud.com.yocruzer.PersonalGrowthOS"
    public static let environment = "Development"
    public static let team = "83SKX2PM7B"
    // Proposed isolated client only: no claim that this identifier/profile exists.
    public static let candidateBundle = "com.yocruzer.PersonalGrowthOS.FormalSyncProbe"
    public static let schemaSHA256 = "6fcf5478c3307685f8a45154b44eeeaec6a907c33412a2c388a6cb8831f04003"
}
public struct ProbeRecord: Codable, Equatable, Sendable {
    public let command: String
    public let recordType: String
    public let recordName: String
    public let file: String
    public let sha256: String
    public let byteCount: Int
}
public struct FormalProbePlan: Codable, Equatable, Sendable {
    public let version: Int
    public let run: UUID
    public let dataset: UUID
    public let container: String
    public let environment: String
    public let team: String
    public let candidateBundle: String
    public let candidateRegistration: String
    public let schemaSHA256: String
    public let records: [ProbeRecord]
    public func encoded() throws -> Data { try probeJSON(self) }
    public var digest: String { get throws { syncDigest(try encoded()) } }
}

public struct ProbeFixture {
    public let plan: FormalProbePlan
    public let files: [String: Data]
    public let manifests: [MutationManifest]
    public static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgSPj/HwAEIgJfhz+lZwAAAABJRU5ErkJggg==")!

    public static func make(run: UUID, dataset: UUID) throws -> Self {
        func identity(_ label: String) -> UUID {
            let hash = syncDigest(Data((run.uuidString + ":" + label).utf8))
            let chars = Array(hash.prefix(32))
            let value = String(chars[0..<8]) + "-" + String(chars[8..<12]) + "-" + String(chars[12..<16]) + "-" + String(chars[16..<20]) + "-" + String(chars[20..<32])
            return UUID(uuidString: value)!
        }
        let object = try SyncObject(kind: "SyntheticFormalProbeText", id: identity("object"))
        let original = OriginalReference(id: identity("original"), asset: AssetDescriptor(bytes: png))
        let createPayload = Data("{\"synthetic\":true,\"text\":\"Formal Development create 原始文字\"}".utf8)
        let editPayload = Data("{\"synthetic\":true,\"text\":\"Formal Development edit 后续修改\"}".utf8)
        let create = try MutationManifest(dataset: dataset, mutation: identity("create"), object: object,
            payload: PayloadManifest(bytes: createPayload), originals: [original])
        let edit = try MutationManifest(dataset: dataset, mutation: identity("edit"), object: object, parents: [create.mutation],
            payload: PayloadManifest(bytes: editPayload), originals: [original])
        let tombstone = try MutationManifest(dataset: dataset, mutation: identity("tombstone"), object: object, parents: [edit.mutation], deleted: true)
        let files = ["original.png": png, "create.payload": createPayload, "edit.payload": editPayload,
            "create.manifest": try create.encoded(), "edit.manifest": try edit.encoded(), "tombstone.manifest": try tombstone.encoded()]
        func record(_ command: String, _ type: String, _ name: String, _ file: String) -> ProbeRecord {
            ProbeRecord(command: command, recordType: type, recordName: name, file: file,
                sha256: syncDigest(files[file]!), byteCount: files[file]!.count)
        }
        let records = [
            record("original", CloudRecordCodec.originalType, CloudRecordCodec.originalID(original.asset.sha256, dataset: dataset).recordName, "original.png"),
            record("create-chunk", CloudRecordCodec.chunkType, CloudRecordCodec.chunkID(syncDigest(createPayload), dataset: dataset).recordName, "create.payload"),
            record("create", CloudRecordCodec.mutationType, CloudRecordCodec.mutationID(create.mutation, dataset: dataset).recordName, "create.manifest"),
            record("edit-chunk", CloudRecordCodec.chunkType, CloudRecordCodec.chunkID(syncDigest(editPayload), dataset: dataset).recordName, "edit.payload"),
            record("edit", CloudRecordCodec.mutationType, CloudRecordCodec.mutationID(edit.mutation, dataset: dataset).recordName, "edit.manifest"),
            record("tombstone", CloudRecordCodec.mutationType, CloudRecordCodec.mutationID(tombstone.mutation, dataset: dataset).recordName, "tombstone.manifest")]
        let plan = FormalProbePlan(version: 1, run: run, dataset: dataset, container: FormalProbeIdentity.container,
            environment: FormalProbeIdentity.environment, team: FormalProbeIdentity.team, candidateBundle: FormalProbeIdentity.candidateBundle,
            candidateRegistration: "PROPOSED_NOT_REGISTERED_OR_VERIFIED", schemaSHA256: FormalProbeIdentity.schemaSHA256, records: records)
        return Self(plan: plan, files: files, manifests: [create, edit, tombstone])
    }
    public static func prepare(at output: URL) throws -> FormalProbePlan {
        try FormalProbeReplay.verifySchemaPin()
        let fixture = try make(run: UUID(), dataset: UUID())
        let directory = try ProbeDirectory(output, create: true)
        for name in fixture.files.keys.sorted() { try directory.write(name, bytes: fixture.files[name]!) }
        try directory.write("plan.json", bytes: fixture.plan.encoded())
        try directory.write("plan.sha256", bytes: Data((try fixture.plan.digest + "\n").utf8))
        return fixture.plan
    }
    public static func load(from url: URL, expectedSHA256: String) throws -> Self {
        let directory = try ProbeDirectory(url, create: false)
        let bytes = try directory.read("plan.json")
        guard syncDigest(bytes) == expectedSHA256,
              try directory.read("plan.sha256") == Data((expectedSHA256 + "\n").utf8) else { throw FormalProbeError.invalidPlan }
        let plan = try JSONDecoder().decode(FormalProbePlan.self, from: bytes)
        guard try plan.encoded() == bytes else { throw FormalProbeError.invalidPlan }
        let fixture = try make(run: plan.run, dataset: plan.dataset)
        guard fixture.plan == plan else { throw FormalProbeError.invalidPlan }
        try directory.verifyNames(Set(fixture.files.keys).union(["plan.json", "plan.sha256"]))
        for (name, expected) in fixture.files { guard try directory.read(name) == expected else { throw FormalProbeError.fileChanged } }
        return fixture
    }
}
