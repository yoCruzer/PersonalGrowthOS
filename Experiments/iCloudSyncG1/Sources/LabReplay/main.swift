import Foundation
import CloudKit
import SyncLab
import Darwin

@main struct Replay {
    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        #if DEBUG
        if args.count == 4, args[1] == "offline-fault" {
            try await OfflineFaultReplay.run(mode: args[2], base: URL(fileURLWithPath: args[3], isDirectory: true))
            return
        }
        if args.count == 5, args[1] == "prepare-faults" {
            try FaultBatch.write(to: URL(fileURLWithPath: args[2], isDirectory: true), dataset: args[3], runID: args[4])
            print("Prepared ordered synthetic fault plans; no app launch or cloud operations.")
            return
        }
        if args.count == 5, args[1] == "prepare-batch" {
            try RemainingBatch.write(to: URL(fileURLWithPath: args[2], isDirectory: true), dataset: args[3], runID: args[4])
            print("Prepared three ordered synthetic plans; no app launch or cloud operations.")
            return
        }
        #endif
        guard args.count == 3 else { fatalError("Usage: LabReplay MODE NEW_SYNTHETIC_ROOT") }
        let base = URL(fileURLWithPath: args[2], isDirectory: true)
        let binding = try Binding(accountHash: digest(Data("SYNTHETIC-PROCESS-A".utf8)), dataset: "replay")
        let store = try LabStore(base: base, binding: binding)
        let a = Mutation(id: "a", object: "entry", text: "SYNTHETIC-A")
        let b = Mutation(id: "b", object: "entry", parents: ["a"], text: "SYNTHETIC-B")
        switch args[1] {
        case "seed-crash":
            guard try store.envelopes().isEmpty else { throw LabError.blocked }
            try store.save(a)
            store.beforeCommit = { _exit(73) }
            try store.save(b)
            fatalError("Fault exit was not reached")
        case "verify-crash":
            guard try store.envelopes().first?.mutations == [a], try store.pending().count == 1 else { throw LabError.invalidWire }
            print("PASS independent process: uncommitted B absent; A and outbox intact")
        case "receive-exit":
            try store.saveCheckpoint(Data("PRE-FETCH-CHECKPOINT".utf8), ticket: store.epoch)
            try store.receiveEnvelope(Envelope(object: "entry", mutations: [a,b]).encoded(), key: "object-entry", fields: Data(), ticket: store.epoch)
            _exit(74) // terminate before the next state event
        case "verify-receive":
            guard try store.envelopes().first?.mutations == [a,b], try store.checkpoint() == Data("PRE-FETCH-CHECKPOINT".utf8) else { throw LabError.invalidWire }
            print("PASS independent process: fetched content durable before checkpoint; replay idempotent")
            try store.receiveEnvelope(Envelope(object: "entry", mutations: [a,b]).encoded(), key: "object-entry", fields: Data(), ticket: store.epoch)
            guard try store.envelopes().first?.mutations.count == 2 else { throw LabError.identityCollision }
        case "schema":
            let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
            try store.save(Mutation(id: "image-op", object: "image-entry", requires: ["entry"], text: "SYNTHETIC-SCHEMA", imageHash: digest(png), imageBytes: png.count), image: png)
            var types: [String: [String: String]] = [:]
            for item in try store.pending() {
                let record = try Wire.record(item, dataset: "replay", imageURL: store.imageURL)
                var fields: [String: String] = [:]
                for key in record.allKeys() {
                    switch record[key] {
                    case is CKAsset: fields[key] = "ASSET"
                    case is Data: fields[key] = "BYTES"
                    case is NSNumber: fields[key] = "INT64"
                    case is String: fields[key] = "STRING"
                    default: throw LabError.invalidWire
                    }
                }
                _ = try Wire.payload(record, dataset: "replay")
                types[record.recordType] = fields
            }
            let data = try JSONSerialization.data(withJSONObject: ["types": types, "customIndexes": [], "status": "CANDIDATE_NOT_FROZEN", "coverage": "actual local codec; no server schema inspected", "container": Binding.container], options: [.prettyPrinted,.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        default: throw LabError.invalidWire
        }
    }
}
