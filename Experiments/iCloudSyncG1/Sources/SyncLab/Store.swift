import Foundation
import SwiftData

@Model final class LabRow {
    @Attribute(.unique) var key: String
    var payload: Data
    var pending: Bool
    var systemFields: Data?
    init(key: String, payload: Data, pending: Bool = false, systemFields: Data? = nil) {
        self.key = key; self.payload = payload; self.pending = pending; self.systemFields = systemFields
    }
}
public struct Binding: Codable, Equatable, Sendable {
    public static let container = "iCloud.com.yocruzer.PersonalGrowthOS.SyncLab"
    public let accountHash: String
    public let dataset: String
    public init(accountHash: String, dataset: String) throws {
        guard isHash(accountHash), validID(dataset) else { throw LabError.invalidWire }
        self.accountHash = accountHash; self.dataset = dataset
    }
    public var partition: String { digest(Data((Self.container + "|Development|" + accountHash + "|" + dataset).utf8)) }
}
public struct Pending: Sendable { public let key: String; public let payload: Data; public let systemFields: Data? }
public struct LabSnapshot: Codable { public var envelopes: [Envelope]; public var images: [String: Data] }

// MainActor serializes transaction, file installation and checkpoint publication.
// There is never an await between a fact mutation and its outbox save.
@MainActor public final class LabStore {
    let container: ModelContainer
    let context: ModelContext
    public let root: URL
    public let binding: Binding
    public private(set) var epoch = UUID()
    public private(set) var stopped = false
    public var beforeCommit: (() throws -> Void)?
    public var failBeforeCommit = false // explicit LOCAL_FAULT_INJECTION only
    public init(base: URL, binding: Binding) throws {
        self.binding = binding
        root = base.appendingPathComponent(binding.partition, isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("images"), withIntermediateDirectories: true)
        let config = ModelConfiguration(url: root.appendingPathComponent("facts.sqlite"), cloudKitDatabase: .none)
        container = try ModelContainer(for: LabRow.self, configurations: config)
        context = ModelContext(container); context.autosaveEnabled = false
        stopped = try row("restore-gate") != nil
    }
    public func fence() { epoch = UUID(); stopped = true }
    public func check(_ ticket: UUID) throws { guard ticket == epoch, !stopped else { throw LabError.staleEpoch } }
    func rows() throws -> [LabRow] { try context.fetch(FetchDescriptor<LabRow>()) }
    func row(_ key: String) throws -> LabRow? { try context.fetch(FetchDescriptor<LabRow>(predicate: #Predicate { $0.key == key })).first }
    func commit(_ work: () throws -> Void) throws {
        do { try work(); try beforeCommit?(); if failBeforeCommit { throw LabError.blocked }; try context.save() }
        catch { context.rollback(); throw error }
    }
    func put(_ key: String, _ payload: Data, pending: Bool, fields: Data? = nil) throws {
        if let value = try row(key) { value.payload = payload; value.pending = pending; value.systemFields = fields }
        else { context.insert(LabRow(key: key, payload: payload, pending: pending, systemFields: fields)) }
    }
    public func envelopes() throws -> [Envelope] {
        try rows().filter { $0.key.hasPrefix("object-") }.map { try Envelope.decode($0.payload) }.sorted { $0.object < $1.object }
    }
    public func pending() throws -> [Pending] {
        try rows().filter(\.pending).sorted { $0.key < $1.key }.map { Pending(key: $0.key, payload: $0.payload, systemFields: $0.systemFields) }
    }
    public func checkpoint() throws -> Data? { try row("checkpoint")?.payload }
    public func saveCheckpoint(_ data: Data, ticket: UUID) throws {
        try check(ticket); try commit { try put("checkpoint", data, pending: false) }
    }
    public func imageURL(_ hash: String) throws -> URL {
        guard isHash(hash) else { throw LabError.invalidWire }
        return root.appendingPathComponent("images").appendingPathComponent(hash)
    }
    public func image(_ hash: String, count: Int) throws -> Data {
        let url = try imageURL(hash)
        guard !(try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink ?? false) else { throw LabError.invalidWire }
        let data = try Data(contentsOf: url)
        guard data.count == count, digest(data) == hash else { throw LabError.missingImage }
        return data
    }
    func stage(_ data: Data, hash: String, count: Int) throws {
        guard count > 0, count <= 8_388_608, data.count == count, digest(data) == hash else { throw LabError.missingImage }
        let url = try imageURL(hash)
        if FileManager.default.fileExists(atPath: url.path) {
            guard !(try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink ?? false) else { throw LabError.invalidWire }
            let old = try Data(contentsOf: url)
            if old.count == count && digest(old) == hash { return }
            // Preserve the corrupt original before replacing it with a verified copy.
            try retainFile(old)
        }
        // .atomic publishes a full immutable original before the referencing DB commit.
        // Failed DB saves leave harmless retained orphans. G1 intentionally has NO GC.
        try data.write(to: url, options: .atomic)
        _ = try image(hash, count: count)
    }
    public func retainFile(_ data: Data) throws {
        let directory = root.appendingPathComponent("quarantine", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(digest(data))
        if !FileManager.default.fileExists(atPath: target.path) { try data.write(to: target, options: .atomic) }
    }
    public func retainInbound(_ bytes: Data, ticket: UUID) throws {
        try check(ticket)
        try commit { try put("inbox-" + digest(bytes), bytes, pending: false) }
    }
    public func save(_ mutation: Mutation, image data: Data? = nil) throws {
        try mutation.validate() // network fences must never disable local capture
        let all = try envelopes()
        for other in all where other.object != mutation.object {
            guard !other.mutations.contains(where: { $0.id == mutation.id }) else { throw LabError.identityCollision }
        }
        if let hash = mutation.imageHash, let count = mutation.imageBytes {
            if let data { try stage(data, hash: hash, count: count) }
            _ = try image(hash, count: count)
        }
        let new = Envelope(object: mutation.object, mutations: [mutation])
        let merged = try all.first(where: { $0.object == mutation.object })?.merging(new) ?? new
        let bytes = try merged.encoded()
        try commit {
            let key = "object-" + mutation.object
            try put(key, bytes, pending: true, fields: row(key)?.systemFields)
            if let hash = mutation.imageHash, let count = mutation.imageBytes {
                let key = "image-" + hash
                if try row(key) == nil { try put(key, canonical(count), pending: true) }
            }
        }
    }
    public func acknowledge(_ key: String, sent: Data, fields: Data, ticket: UUID) throws {
        try check(ticket)
        try commit {
            guard let value = try row(key) else { throw LabError.invalidWire }
            value.systemFields = fields
            // Engine removes its pending ID after save. Exact bytes guard the new edit.
            if value.payload == sent { value.pending = false }
        }
    }
    public func receiveEnvelope(_ bytes: Data, key: String, fields: Data, ticket: UUID) throws {
        try check(ticket)
        // Durable receipt precedes decoding/publication/checkpoint. Malformed evidence retained.
        try commit { try put("inbox-" + digest(Data(key.utf8) + bytes), bytes, pending: false) }
        let incoming = try Envelope.decode(bytes)
        guard key == "object-" + incoming.object else { throw LabError.invalidWire }
        let all = try envelopes()
        let foreignIDs = Set(all.filter { $0.object != incoming.object }.flatMap { $0.mutations.map(\.id) })
        guard !incoming.mutations.contains(where: { foreignIDs.contains($0.id) }) else { throw LabError.identityCollision }
        let merged = try all.first(where: { $0.object == incoming.object })?.merging(incoming) ?? incoming
        let combined = try merged.encoded()
        try commit { try put(key, combined, pending: combined != bytes, fields: fields) }
    }
    public func receiveImage(_ data: Data, hash: String, count: Int, fields: Data, ticket: UUID) throws {
        try check(ticket); try stage(data, hash: hash, count: count)
        try commit { try put("image-" + hash, canonical(count), pending: false, fields: fields) }
    }
    public func projections() throws -> [String: Projection] {
        let all = try envelopes(); let graph = try Graph(all.flatMap(\.mutations), imageAvailable: { m in
            guard let hash = m.imageHash, let count = m.imageBytes else { return true }
            return (try? self.image(hash, count: count)) != nil
        })
        var output: [String: Projection] = [:]
        for e in all {
            var p = graph.project(e.object)
            // Missing originals anywhere in retained history prevent a complete claim.
            if e.mutations.contains(where: { m in
                guard let hash = m.imageHash, let count = m.imageBytes else { return false }
                return (try? image(hash, count: count)) == nil
            }) { p.state = "missing_image"; p.preview = nil }
            output[e.object] = p
        }
        return output
    }
    public func exportSnapshot() throws -> Data {
        let all = try envelopes(); var images: [String: Data] = [:]
        guard all.count <= 128, all.reduce(0, { $0 + $1.mutations.count }) <= 4096 else { throw LabError.limit }
        var declared: [String: Int] = [:]
        for m in all.flatMap(\.mutations) { if let hash = m.imageHash, let count = m.imageBytes { declared[hash] = count } }
        guard declared.values.reduce(0, +) <= 23_000_000 else { throw LabError.limit }
        for m in all.flatMap(\.mutations) { if let hash = m.imageHash, let count = m.imageBytes { images[hash] = try image(hash, count: count) } }
        let data = try canonical(LabSnapshot(envelopes: all, images: images))
        guard data.count <= 32_000_000 else { throw LabError.limit }
        return data
    }
    // Import into a NEW isolated dataset only; never restores state, account, ACK or system fields.
    public func importSnapshot(_ data: Data) throws {
        guard try envelopes().isEmpty, try pending().isEmpty, try checkpoint() == nil else { throw LabError.blocked }
        guard data.count <= 32_000_000 else { throw LabError.limit }
        fence() // in-flight callbacks and sends invalid before parsing or file install
        let snapshot = try JSONDecoder().decode(LabSnapshot.self, from: data)
        guard snapshot.envelopes.count <= 128, Set(snapshot.envelopes.map(\.object)).count == snapshot.envelopes.count else { throw LabError.invalidWire }
        _ = try Graph(snapshot.envelopes.flatMap(\.mutations))
        for e in snapshot.envelopes {
            _ = try e.encoded()
            for m in e.mutations { if let hash = m.imageHash, let count = m.imageBytes {
                guard let bytes = snapshot.images[hash] else { throw LabError.missingImage }
                try stage(bytes, hash: hash, count: count)
            } }
        }
        try commit {
            try put("restore-gate", Data("EXPLICIT_MAPPING_REQUIRED".utf8), pending: false)
            for e in snapshot.envelopes {
                try put("object-" + e.object, e.encoded(), pending: true)
                for m in e.mutations { if let hash = m.imageHash, let count = m.imageBytes { try put("image-" + hash, canonical(count), pending: true) } }
            }
        }
        // Persistent gate survives cold start. This experiment exposes no automatic mapping/unlock.
        // Restored facts remain locally editable/exportable; cloud activation is blocked.
    }
}
