import Foundation
import CloudKit
import FormalProbeCore
import SyncFoundation

enum BatchFailure: String, Error { case busy, consumed, staleEpoch, cancelled, existingZone, wrongZone, unexpectedResults, partialFailure, bytesMismatch, bindingChanged, externalGateNotComplete }

/// In-memory single-use binding, not Apple identity or Owner authorization. Persistence,
/// cross-process exclusion and real authority issuance are intentionally not implemented.
@MainActor final class BatchTicket {
    let planSHA256: String
    let plan: FormalProbePlan
    let epoch: UUID
    private(set) var used = false
    private(set) var valid = true
    init(fixture: ProbeFixture, epoch: UUID) throws {
        plan = fixture.plan; planSHA256 = try fixture.plan.digest; self.epoch = epoch
    }
    func invalidate() { valid = false }
    func consume() throws { guard !used else { throw BatchFailure.consumed }; used = true }
}

struct Outcome: Codable {
    let recordName: String
    let status: String
    let errorDomain: String?
    let errorCode: Int?
    let partialErrors: [String: Int]?
    let unknownPartialErrorCodes: [Int]?
}
struct StepEvidence: Codable {
    let sequence: Int
    let stage: String
    let event: String
    let planSHA256: String
    let outcomes: [Outcome]
    let failure: String?
}
struct BatchReport: Encodable {
    let mode = "INJECTED_TRANSPORT_ONLY"
    let realAuthorityVerified = false
    let p0Passed = false
    let zoneCreationAtomic = false
    let planSHA256: String
    let run: UUID
    let dataset: UUID
    let status: String
    let stage: String
    let failure: String?
    let completed: [String]
}
func json<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value)
}
func code(_ error: Error) -> String {
    if let failure = error as? BatchFailure { return failure.rawValue }
    if error is CancellationError { return BatchFailure.cancelled.rawValue }
    if let cloud = error as? CKError { return "CK_\(cloud.errorCode)" }
    if error is FormalProbeError { return "PLAN_OR_LEASE_REJECTED" }
    if error is SyncValidationError { return "CODEC_REJECTED" }
    return "IO_OR_VALIDATION_FAILED"
}
func outcome(_ name: String, _ result: Result<CKRecord, Error>, id: CKRecord.ID? = nil, allowed: Set<CKRecord.ID> = []) -> Outcome {
    let safeName = name == "operation" && id == nil || id.map({ allowed.contains($0) }) == true ? name : "UNEXPECTED_RECORD_ID"
    switch result {
    case .success: return Outcome(recordName: safeName, status: "RETURNED_SUCCESS_UNVERIFIED", errorDomain: nil, errorCode: nil, partialErrors: nil, unknownPartialErrorCodes: nil)
    case .failure(let error):
        let ns = error as NSError
        var partial: [String: Int] = [:], unknownCodes: [Int] = []
        // Preserve numeric CloudKit partial error detail without localized strings,
        // account identifiers, server record payloads or filesystem paths.
        if let values = ns.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error] {
            for (id, failure) in values { if allowed.contains(id) { partial[id.recordName] = (failure as NSError).code }
                else { unknownCodes.append((failure as NSError).code) } }
        }
        return Outcome(recordName: safeName, status: "RETURNED_FAILURE", errorDomain: ns.domain == CKErrorDomain ? CKErrorDomain : "OTHER", errorCode: ns.code, partialErrors: partial.isEmpty ? nil : partial, unknownPartialErrorCodes: unknownCodes.isEmpty ? nil : unknownCodes.sorted())
    }
}

@MainActor final class BatchRunner {
    private var busy = false
    private(set) var epoch: UUID
    init(epoch: UUID) { self.epoch = epoch }
    func invalidateEpoch() { epoch = UUID() }

    /// Only callable inside this module / @testable tests. No actual account/environment
    /// authority exists. Every suspension is fenced before another operation or success.
    func run(planURL: URL, ticket: BatchTicket, output: URL, transport: BatchTransport) async throws -> BatchReport {
        guard !busy else { throw BatchFailure.busy }
        try ticket.consume(); busy = true; defer { busy = false }
        let destination = try ProbeDirectory(output, create: true)
        var sequence = 0, completed: [String] = [], stage = "load"
        var fixture: ProbeFixture?
        func emit(_ event: String, outcomes: [Outcome] = [], failure: String? = nil) throws {
            let evidence = StepEvidence(sequence: sequence, stage: stage, event: event, planSHA256: ticket.planSHA256, outcomes: outcomes, failure: failure)
            try destination.write(String(format: "%03d-%@.json", sequence, event), bytes: json(evidence)); sequence += 1
        }
        func check() throws {
            guard ticket.valid, ticket.epoch == epoch else { throw BatchFailure.staleEpoch }
            try Task.checkCancellation()
            let current = try ProbeFixture.load(from: planURL, expectedSHA256: ticket.planSHA256)
            guard current.plan == ticket.plan else { throw BatchFailure.bindingChanged }
            try destination.requirePathBinding()
            if let fixture {
                for (name, bytes) in fixture.files { guard try destination.read("lease-" + name) == bytes else { throw BatchFailure.bytesMismatch } }
            }
        }
        func report(_ error: Error?) -> BatchReport {
            BatchReport(planSHA256: ticket.planSHA256, run: ticket.plan.run, dataset: ticket.plan.dataset,
                status: error == nil ? "INJECTED_TRANSPORT_VERIFIED" : "FAILED", stage: stage, failure: error.map(code), completed: completed)
        }
        do {
            try FormalProbeReplay.verifySchemaPin()
            try check()
            let loaded = try ProbeFixture.load(from: planURL, expectedSHA256: ticket.planSHA256)
            let allowed = Set(loaded.plan.records.map { CKRecord.ID(recordName: $0.recordName, zoneID: CloudRecordCodec.zone(dataset: loaded.plan.dataset)) })
            for (name, bytes) in loaded.files { try destination.write("lease-" + name, bytes: bytes) }
            fixture = loaded
            let zone = CloudRecordCodec.zone(dataset: loaded.plan.dataset)
            var records: [CKRecord] = []
            for item in loaded.plan.records {
                let bytes = loaded.files[item.file]!, url = try destination.assetURL("lease-" + item.file)
                if item.recordType == CloudRecordCodec.originalType {
                    records.append(try CloudRecordCodec.encodeOriginal(AssetDescriptor(bytes: bytes), dataset: loaded.plan.dataset, url: url))
                } else if item.recordType == CloudRecordCodec.chunkType {
                    records.append(try CloudRecordCodec.encodeChunk(AssetDescriptor(bytes: bytes), dataset: loaded.plan.dataset, url: url))
                } else { records.append(try CloudRecordCodec.encode(MutationManifest.decode(bytes))) }
            }
            func validate(_ results: [CKRecord.ID: Result<CKRecord, Error>], expected: [CKRecord]) throws {
                guard Set(results.keys) == Set(expected.map(\.recordID)) else { throw BatchFailure.unexpectedResults }
                for expectedRecord in expected {
                    guard case .success(let record) = results[expectedRecord.recordID]! else { throw BatchFailure.partialFailure }
                    guard record.recordID == expectedRecord.recordID, record.recordType == expectedRecord.recordType,
                          let item = loaded.plan.records.first(where: { $0.recordName == record.recordID.recordName }) else { throw BatchFailure.unexpectedResults }
                    let bytes: Data
                    if record.recordType == CloudRecordCodec.originalType { bytes = try CloudRecordCodec.decodeOriginal(record, dataset: loaded.plan.dataset).1 }
                    else if record.recordType == CloudRecordCodec.chunkType { bytes = try CloudRecordCodec.decodeChunk(record, dataset: loaded.plan.dataset).1 }
                    else { bytes = try CloudRecordCodec.decode(record, dataset: loaded.plan.dataset).encoded() }
                    guard bytes == loaded.files[item.file] else { throw BatchFailure.bytesMismatch }
                }
            }
            stage = "zone-probe"; try check(); try emit("intent")
            let exists = try await transport.zoneExists(zone)
            try emit(exists ? "observed-existing" : "observed-absent"); try check()
            guard !exists else { throw BatchFailure.existingZone }; completed.append(stage)
            // Observation + save is NOT atomic create-if-absent. No cross-process claim.
            stage = "zone-save"; try check(); try emit("intent")
            let savedZone = try await transport.createZone(zone)
            try emit(savedZone == zone ? "returned-matching-zone" : "returned-wrong-zone"); try check()
            guard savedZone == zone else { throw BatchFailure.wrongZone }; completed.append(stage)
            for (label, batch) in [("assets-save", records.filter { $0.recordType != CloudRecordCodec.mutationType }),
                                   ("mutations-save", records.filter { $0.recordType == CloudRecordCodec.mutationType })] {
                stage = label; try check(); try emit("intent")
                let result = try await transport.save(batch)
                try emit("returned", outcomes: result.keys.sorted { $0.recordName < $1.recordName }.map { outcome($0.recordName, result[$0]!, id: $0, allowed: allowed) })
                try check(); try validate(result, expected: batch); completed.append(stage)
            }
            stage = "exact-fetch"; try check(); try emit("intent")
            let result = try await transport.fetch(records.map(\.recordID))
            try emit("returned", outcomes: result.keys.sorted { $0.recordName < $1.recordName }.map { outcome($0.recordName, result[$0]!, id: $0, allowed: allowed) })
            try check(); try validate(result, expected: records); completed.append(stage)
            stage = "final-bindings"; try check(); try emit("verified")
            let success = report(nil); try destination.write("report.json", bytes: json(success)); return success
        } catch {
            try emit("failed", outcomes: [outcome("operation", .failure(error), allowed: Set(ticket.plan.records.map { CKRecord.ID(recordName: $0.recordName, zoneID: CloudRecordCodec.zone(dataset: ticket.plan.dataset)) }))], failure: code(error))
            try destination.write("report.json", bytes: json(report(error)))
            throw error
        }
    }
}
