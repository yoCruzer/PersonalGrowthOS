import Foundation
import CryptoKit

public enum SyncValidationError: Error, Equatable {
    case invalidIdentity, invalidManifest, unsupportedVersion, limitExceeded
    case invalidRecord, missingAsset, corruptAsset, identityCollision, staleEpoch
}

public enum CloudEnvironment: String, Sendable { case development, production }

/// Local routing identity. Deliberately not Codable: never put account or generation in wire payloads.
public struct SyncBinding: Equatable, Sendable {
    public let container: String
    public let environment: CloudEnvironment
    public let accountHash: String
    public let dataset: UUID
    public let generation: UUID

    public init(container: String, environment: CloudEnvironment, accountHash: String,
                dataset: UUID, generation: UUID) throws {
        guard container.hasPrefix("iCloud."), container.utf8.count <= 255,
              container.utf8.allSatisfy({ asciiIdentifier($0) || $0 == 46 }), validHash(accountHash) else {
            throw SyncValidationError.invalidIdentity
        }
        self.container = container; self.environment = environment; self.accountHash = accountHash
        self.dataset = dataset; self.generation = generation
    }
}

/// Fence applies on the same actor as the eventual commit. Recheck after every suspension.
/// It neither cancels SDK operations nor persists identity; those are integration responsibilities.
@MainActor public final class SyncEpochFence {
    public struct Ticket: Equatable, Sendable {
        fileprivate let binding: SyncBinding
        fileprivate let nonce: UUID
    }
    public let binding: SyncBinding
    private var nonce = UUID()
    private var active = true
    public init(binding: SyncBinding) { self.binding = binding }
    public func ticket() throws -> Ticket {
        guard active else { throw SyncValidationError.staleEpoch }
        return Ticket(binding: binding, nonce: nonce)
    }
    public func check(_ ticket: Ticket) throws {
        guard active, ticket.binding == binding, ticket.nonce == nonce else { throw SyncValidationError.staleEpoch }
    }
    public func invalidate() { active = false; nonce = UUID() }
}

public enum SyncLimits {
    public static let manifestBytes = 65_536
    public static let payloadBytes = 16 * 1_024 * 1_024
    public static let originalBytes = 25 * 1_024 * 1_024
    public static let parents = 256
    public static let dependencies = 1_024
    public static let media = 1_024
}

public func syncDigest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
func validHash(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
}
func asciiIdentifier(_ byte: UInt8) -> Bool {
    (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 45 || byte == 95
}
func canonical<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
}
extension UUID { var wire: String { uuidString.lowercased() } }
