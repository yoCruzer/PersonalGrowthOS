import Foundation
import CryptoKit

public enum LabError: Error { case invalidWire, identityCollision, missingImage, staleEpoch, blocked, limit }
public func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func canonical<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
}
public struct Mutation: Codable, Equatable, Sendable {
    public var id: String
    public var object: String
    public var parents: [String]
    public var requires: [String]
    public var text: String
    public var deleted: Bool
    public var imageHash: String?
    public var imageBytes: Int?
    public var version: Int
    public init(id: String = UUID().uuidString.lowercased(), object: String, parents: [String] = [], requires: [String] = [], text: String, deleted: Bool = false, imageHash: String? = nil, imageBytes: Int? = nil, version: Int = 1) {
        self.id = id; self.object = object; self.parents = parents.sorted(); self.requires = requires.sorted()
        self.text = text; self.deleted = deleted; self.imageHash = imageHash; self.imageBytes = imageBytes; self.version = version
    }
    func validate() throws {
        guard version == 1, validID(id), validID(object), parents.allSatisfy(validID), requires.allSatisfy(validID), Set(parents).count == parents.count, Set(requires).count == requires.count,
              text.utf8.count <= 32_768, parents.count <= 64, requires.count <= 64,
              (imageHash == nil && imageBytes == nil) || (isHash(imageHash ?? "") && (1...8_388_608).contains(imageBytes ?? 0)),
              deleted || !text.isEmpty || imageHash != nil else { throw LabError.invalidWire }
    }
}
func validID(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 80 && value.unicodeScalars.allSatisfy { (48...57).contains($0.value) || (65...90).contains($0.value) || (97...122).contains($0.value) || $0 == "-" || $0 == "_" } }
func isHash(_ value: String) -> Bool { value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) } }

public struct Envelope: Codable, Equatable, Sendable {
    public var version = 1
    public var object: String
    public var mutations: [Mutation]
    public init(object: String, mutations: [Mutation]) { self.object = object; self.mutations = mutations.sorted { $0.id < $1.id } }
    public func encoded() throws -> Data {
        guard version == 1, validID(object), mutations.count <= 512, !mutations.isEmpty else { throw LabError.invalidWire }
        var ids = Set<String>()
        for m in mutations { try m.validate(); guard m.object == object, ids.insert(m.id).inserted else { throw LabError.identityCollision } }
        let bytes = try canonical(self)
        guard bytes.count <= 262_144 else { throw LabError.limit }
        return bytes
    }
    public static func decode(_ bytes: Data) throws -> Envelope {
        guard bytes.count <= 262_144 else { throw LabError.limit }
        let value = try JSONDecoder().decode(Self.self, from: bytes)
        // Strict canonical wire prevents alternate bytes with the same identity.
        guard try value.encoded() == bytes else { throw LabError.invalidWire }
        return value
    }
    public func merging(_ other: Envelope) throws -> Envelope {
        guard object == other.object else { throw LabError.identityCollision }
        var rows = Dictionary(uniqueKeysWithValues: mutations.map { ($0.id, $0) })
        for row in other.mutations {
            if let old = rows[row.id], old != row { throw LabError.identityCollision }
            rows[row.id] = row
        }
        let result = Envelope(object: object, mutations: Array(rows.values)); _ = try result.encoded(); return result
    }
}
public struct Projection: Equatable, Sendable {
    public var state: String
    public var candidates: [String]
    public var preview: Mutation?
    public var complete: Bool { state == "ready" || state == "deleted" || state == "absent" }
}
// Bounded, conservative experiment; not a reducer for the 39 production entities.
public final class Graph {
    private var ancestryCache: [String: Set<String>] = [:]
    private var invalidLineage: Set<String> = []
    private var headCache: [String: [Mutation]] = [:]
    private var invalidObjects: Set<String> = []
    private var readyCache: [String: Bool] = [:]
    private let imageAvailable: (Mutation) -> Bool
    let rows: [Mutation]
    let byID: [String: Mutation]
    public init(_ rows: [Mutation], imageAvailable: @escaping (Mutation) -> Bool = { _ in true }) throws {
        self.imageAvailable = imageAvailable
        guard rows.count <= 4096 else { throw LabError.limit }
        var values: [String: Mutation] = [:]
        for row in rows {
            if let old = values[row.id], old != row { throw LabError.identityCollision }
            values[row.id] = row
        }
        self.rows = Array(values.values); byID = values
    }
    func ancestry(_ id: String, _ visiting: Set<String> = []) -> Set<String>? {
        guard visiting.count < 512, !visiting.contains(id), let m = byID[id], m.version == 1 else { return nil }
        if invalidLineage.contains(id) { return nil }
        if let cached = ancestryCache[id] { return cached }
        var result: Set<String> = [id]
        for parent in m.parents {
            guard byID[parent]?.object == m.object, let inherited = ancestry(parent, visiting.union([id])) else { invalidLineage.insert(id); return nil }
            result.formUnion(inherited)
        }
        ancestryCache[id] = result
        return result
    }
    public func heads(_ object: String) -> [Mutation]? {
        if invalidObjects.contains(object) { return nil }
        if let cached = headCache[object] { return cached }
        let objects = rows.filter { $0.object == object }
        var superseded = Set<String>()
        for m in objects { guard let all = ancestry(m.id) else { invalidObjects.insert(object); return nil }; superseded.formUnion(all.subtracting([m.id])) }
        let result = objects.filter { !superseded.contains($0.id) }.sorted { $0.id < $1.id }
        headCache[object] = result; return result
    }
    func ready(_ m: Mutation, _ visiting: Set<String> = []) -> Bool {
        guard visiting.count < 512, !visiting.contains(m.object) else { return false }
        if m.deleted { return true }
        if let cached = readyCache[m.id] { return cached }
        guard imageAvailable(m) else { readyCache[m.id] = false; return false }
        let result = m.requires.allSatisfy {
            guard let current = heads($0), current.count == 1, !current[0].deleted else { return false }
            return ready(current[0], visiting.union([m.object]))
        }
        readyCache[m.id] = result; return result
    }
    public func project(_ object: String) -> Projection {
        guard let heads = heads(object) else { return Projection(state: "staged", candidates: rows.filter { $0.object == object }.map(\.id).sorted(), preview: nil) }
        let ids = heads.map(\.id)
        if heads.isEmpty { return Projection(state: "absent", candidates: [], preview: nil) }
        if heads.contains(where: \.deleted) { return Projection(state: heads.count == 1 ? "deleted" : "deleted_conflict", candidates: ids, preview: nil) }
        guard heads.allSatisfy({ ready($0) }) else { return Projection(state: "staged", candidates: ids, preview: nil) }
        if heads.count == 1 { return Projection(state: "ready", candidates: ids, preview: heads[0]) }
        var common = ancestry(heads[0].id) ?? []
        for head in heads.dropFirst() { common.formIntersection(ancestry(head.id) ?? []) }
        let maximal = common.filter { id in !common.contains { other in other != id && (ancestry(other)?.contains(id) ?? false) } }
        let base = maximal.count == 1 ? byID[maximal.first!] : nil
        let preview = base.flatMap { !$0.deleted && ready($0) ? $0 : nil }
        return Projection(state: "conflict", candidates: ids, preview: preview)
    }
}
