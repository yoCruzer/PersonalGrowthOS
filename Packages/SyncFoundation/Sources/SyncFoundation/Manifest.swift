import Foundation

/// A domain name is a versioned codec key, not an arbitrary display label.
/// Domain decoders must allowlist supported kinds before publishing business facts.
public struct SyncObject: Codable, Hashable, Sendable {
    public let kind: String
    public let id: UUID
    public init(kind: String, id: UUID) throws {
        self.kind = kind; self.id = id; try validate()
    }
    func validate() throws {
        guard (1...64).contains(kind.utf8.count), kind.utf8.allSatisfy(asciiIdentifier) else {
            throw SyncValidationError.invalidIdentity
        }
    }
    var sortKey: String { kind + "/" + id.wire }
}

public struct AssetDescriptor: Codable, Hashable, Sendable {
    public let sha256: String
    public let byteCount: Int
    public init(bytes: Data) { sha256 = syncDigest(bytes); byteCount = bytes.count }
    public init(sha256: String, byteCount: Int) { self.sha256 = sha256; self.byteCount = byteCount }
    func validate(maximum: Int) throws {
        guard validHash(sha256), byteCount > 0 else { throw SyncValidationError.invalidManifest }
        guard byteCount <= maximum else { throw SyncValidationError.limitExceeded }
    }
}

public struct OriginalReference: Codable, Hashable, Sendable {
    public let id: UUID
    public let asset: AssetDescriptor
    public init(id: UUID, asset: AssetDescriptor) { self.id = id; self.asset = asset }
}

/// One immutable aggregate revision. Payload is opaque domain bytes; this layer never projects it.
/// Aggregate identity is the object itself. An aggregate can contain multiple domain entities in payload.
public struct MutationManifest: Codable, Equatable, Sendable {
    public let wireVersion: Int
    public let payloadVersion: Int
    public let dataset: UUID
    public let mutation: UUID
    public let object: SyncObject
    public let parents: [UUID]
    public let dependencies: [SyncObject]
    public let deleted: Bool
    public let payload: AssetDescriptor?
    public let originals: [OriginalReference]

    public init(dataset: UUID, mutation: UUID, object: SyncObject, parents: [UUID] = [],
                dependencies: [SyncObject] = [], deleted: Bool = false, payloadVersion: Int = 1,
                payload: AssetDescriptor? = nil, originals: [OriginalReference] = []) throws {
        wireVersion = 1; self.payloadVersion = payloadVersion; self.dataset = dataset
        self.mutation = mutation; self.object = object
        self.parents = parents.sorted { $0.wire < $1.wire }
        self.dependencies = dependencies.sorted { $0.sortKey < $1.sortKey }
        self.deleted = deleted; self.payload = payload
        self.originals = originals.sorted { $0.id.wire < $1.id.wire }
        try validate()
    }

    private func validate() throws {
        guard wireVersion == 1 else { throw SyncValidationError.unsupportedVersion }
        guard payloadVersion > 0 else { throw SyncValidationError.invalidManifest }
        try object.validate()
        guard parents.count <= SyncLimits.parents, dependencies.count <= SyncLimits.dependencies,
              originals.count <= SyncLimits.media else { throw SyncValidationError.limitExceeded }
        guard Set(parents).count == parents.count, !parents.contains(mutation),
              Set(dependencies).count == dependencies.count, !dependencies.contains(object),
              Set(originals.map(\.id)).count == originals.count,
              parents == parents.sorted(by: { $0.wire < $1.wire }),
              dependencies == dependencies.sorted(by: { $0.sortKey < $1.sortKey }),
              originals == originals.sorted(by: { $0.id.wire < $1.id.wire }) else {
            throw SyncValidationError.invalidManifest
        }
        for dependency in dependencies { try dependency.validate() }
        if deleted {
            // Deletion must not wait for dependencies being removed, nor carry active media.
            guard payload == nil, originals.isEmpty, dependencies.isEmpty else { throw SyncValidationError.invalidManifest }
        } else {
            guard let payload else { throw SyncValidationError.missingAsset }
            try payload.validate(maximum: SyncLimits.payloadBytes)
        }
        var byHash: [String: Int] = [:]
        for original in originals {
            try original.asset.validate(maximum: SyncLimits.originalBytes)
            if let prior = byHash[original.asset.sha256], prior != original.asset.byteCount {
                throw SyncValidationError.invalidManifest
            }
            byHash[original.asset.sha256] = original.asset.byteCount
        }
    }

    public func encoded() throws -> Data {
        try validate()
        let bytes = try canonical(self)
        guard bytes.count <= SyncLimits.manifestBytes else { throw SyncValidationError.limitExceeded }
        return bytes
    }
    public static func decode(_ bytes: Data) throws -> Self {
        guard bytes.count <= SyncLimits.manifestBytes else { throw SyncValidationError.limitExceeded }
        let value = try JSONDecoder().decode(Self.self, from: bytes)
        guard try value.encoded() == bytes else { throw SyncValidationError.invalidManifest }
        return value
    }

    /// Compare with a previously persisted manifest *before* installing a fetched revision.
    /// Caller must do this and the insert under its single-store transaction/uniqueness constraint.
    public func verifyReplay(of existing: Data) throws {
        let previous = try Self.decode(existing)
        guard dataset == previous.dataset, mutation == previous.mutation,
              try encoded() == existing else { throw SyncValidationError.identityCollision }
    }

    /// Checks only asset closure. Causal/domain validity and publication remain separate gates.
    /// Full export needs every original, independently of manifest receipt.
    public func verifyAssetsComplete(payload bytes: Data?, originalBytes: (OriginalReference) throws -> Data) throws {
        try validate()
        if let descriptor = payload {
            guard let bytes else { throw SyncValidationError.missingAsset }
            try verify(bytes, descriptor: descriptor, maximum: SyncLimits.payloadBytes)
        } else if bytes != nil { throw SyncValidationError.invalidManifest }
        for original in originals {
            try verify(originalBytes(original), descriptor: original.asset, maximum: SyncLimits.originalBytes)
        }
    }
}

func verify(_ bytes: Data, descriptor: AssetDescriptor, maximum: Int) throws {
    try descriptor.validate(maximum: maximum)
    guard bytes.count == descriptor.byteCount, syncDigest(bytes) == descriptor.sha256 else {
        throw SyncValidationError.corruptAsset
    }
}
