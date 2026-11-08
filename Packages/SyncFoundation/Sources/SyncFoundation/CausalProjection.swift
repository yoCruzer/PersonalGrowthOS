import Foundation

/// Bounds the entire invocation, including duplicate input and graph traversal work.
/// Exhaustion throws; no partially publishable projection is returned.
public struct CausalProjectionLimits: Sendable {
    public let manifests: Int
    public let encodedBytes: Int
    public let graphSteps: Int
    public init(manifests: Int = 10_000, encodedBytes: Int = 32 * 1_024 * 1_024,
                graphSteps: Int = 2_000_000) {
        self.manifests = manifests; self.encodedBytes = encodedBytes; self.graphSteps = graphSteps
    }
}

public enum CausalPendingReason: Equatable, Sendable {
    case missingParent(mutation: UUID, parent: UUID)
    case crossObjectParent(mutation: UUID, parent: UUID)
    case causalCycle
    case unsupportedPayload(mutation: UUID, version: Int)
    case unavailableAssets(mutation: UUID)
    case dependencyNotReady(SyncObject)
    case dependencyCycle
}

public struct CausalObjectProjection: Equatable, Sendable {
    public enum State: String, Sendable { case ready, deleted, conflict, pending }
    public let object: SyncObject
    /// All observed causal heads, including unpublishable and deleted candidates.
    public let heads: [UUID]
    public let state: State
    /// Only a unique, publishable current head. Never a fallback to an ancestor.
    public let selectedMutation: UUID?
    /// A unique nearest common ancestor, for an explicitly incomplete conflict preview only.
    public let previewMutation: UUID?
    public let pendingReasons: [CausalPendingReason]
    public var complete: Bool { state == .ready || state == .deleted }
}

/// Pure, dataset-local projection. No persistence, SDK, wall-clock or arrival-order input.
/// Domain relationships forming legal cycles must be encoded inside one aggregate; cycles
/// between aggregates remain pending. A ready result does not validate domain payload semantics.
public enum CausalProjection {
    /// `verifiedMutationAssets` must contain only mutations whose payload AND originals the caller
    /// has verified against this exact immutable manifest. It is not proof supplied by a peer.
    /// Supported kind/version pairs are explicit: unrecognized kinds also remain pending.
    public static func project(manifestBytes: [Data], dataset: UUID,
                               supportedPayloadVersions: [String: Set<Int>],
                               verifiedMutationAssets: Set<UUID>,
                               limits: CausalProjectionLimits = .init()) throws -> [CausalObjectProjection] {
        guard limits.manifests >= 0, limits.encodedBytes >= 0, limits.graphSteps >= 0,
              manifestBytes.count <= limits.manifests else { throw SyncValidationError.limitExceeded }
        var byteBudget = limits.encodedBytes
        var work = limits.graphSteps
        func step(_ count: Int = 1) throws {
            guard count <= work else { throw SyncValidationError.limitExceeded }
            work -= count
        }
        var bytesByID: [UUID: Data] = [:]
        var mutations: [UUID: MutationManifest] = [:]
        for bytes in manifestBytes {
            guard bytes.count <= byteBudget else { throw SyncValidationError.limitExceeded }
            byteBudget -= bytes.count
            let value = try MutationManifest.decode(bytes)
            guard value.dataset == dataset else { throw SyncValidationError.invalidIdentity }
            if let previous = bytesByID[value.mutation], previous != bytes {
                throw SyncValidationError.identityCollision
            }
            bytesByID[value.mutation] = bytes; mutations[value.mutation] = value
        }
        let grouped = Dictionary(grouping: mutations.values, by: \.object)
        let objects = grouped.keys.sorted { $0.sortKey < $1.sortKey }
        var heads: [SyncObject: [UUID]] = [:]
        var reasons: [SyncObject: [CausalPendingReason]] = [:]
        var uniqueLive: [SyncObject: MutationManifest] = [:]
        var deleted: Set<SyncObject> = []

        // Validate complete observed object histories before checking current dependencies.
        for object in objects {
            let history = grouped[object]!.sorted { $0.mutation.wire < $1.mutation.wire }
            var referenced: Set<UUID> = []
            var remaining: [UUID: Int] = [:]
            var children: [UUID: [UUID]] = [:]
            var issues: [CausalPendingReason] = []
            for value in history {
                try step()
                if !(supportedPayloadVersions[object.kind]?.contains(value.payloadVersion) ?? false) {
                    issues.append(.unsupportedPayload(mutation: value.mutation, version: value.payloadVersion))
                }
                remaining[value.mutation] = 0
                for parent in value.parents {
                    try step()
                    guard let predecessor = mutations[parent] else {
                        issues.append(.missingParent(mutation: value.mutation, parent: parent)); continue
                    }
                    guard predecessor.object == object else {
                        issues.append(.crossObjectParent(mutation: value.mutation, parent: parent)); continue
                    }
                    referenced.insert(parent)
                    remaining[value.mutation, default: 0] += 1
                    children[parent, default: []].append(value.mutation)
                }
            }
            var queue = history.map(\.mutation).filter { remaining[$0] == 0 }
            var cursor = 0
            while cursor < queue.count {
                let id = queue[cursor]; cursor += 1
                for child in children[id, default: []] {
                    try step(); remaining[child]! -= 1
                    if remaining[child] == 0 { queue.append(child) }
                }
            }
            if queue.count != history.count { issues.append(.causalCycle) }
            let current = history.map(\.mutation).filter { !referenced.contains($0) }
            heads[object] = current; reasons[object] = issues
            guard issues.isEmpty, current.count == 1, let head = mutations[current[0]] else { continue }
            if head.deleted { deleted.insert(object) }
            else if verifiedMutationAssets.contains(head.mutation) { uniqueLive[object] = head }
            else { reasons[object, default: []].append(.unavailableAssets(mutation: head.mutation)) }
        }

        // Reverse edges let each ready dependency release its dependents exactly once.
        // Deleted/conflicted/pending targets never satisfy a live relationship.
        var remainingDependencies: [SyncObject: Int] = [:]
        var dependents: [SyncObject: [SyncObject]] = [:]
        var ready: Set<SyncObject> = []
        var queue: [SyncObject] = []
        for object in objects {
            guard let value = uniqueLive[object] else { continue }
            remainingDependencies[object] = value.dependencies.count
            for dependency in value.dependencies {
                try step(); dependents[dependency, default: []].append(object)
            }
            if value.dependencies.isEmpty { queue.append(object); ready.insert(object) }
        }
        var cursor = 0
        while cursor < queue.count {
            let object = queue[cursor]; cursor += 1
            for dependent in dependents[object, default: []] {
                try step(); remainingDependencies[dependent]! -= 1
                if remainingDependencies[dependent] == 0 { ready.insert(dependent); queue.append(dependent) }
            }
        }
        for object in objects {
            guard let value = uniqueLive[object], !ready.contains(object) else { continue }
            for dependency in value.dependencies where !ready.contains(dependency) {
                reasons[object, default: []].append(.dependencyNotReady(dependency))
            }
            // Iterative, bounded reachability distinguishes a cycle from a merely missing target.
            var seen: Set<SyncObject> = []
            var stack = value.dependencies
            while let next = stack.popLast() {
                try step()
                if next == object { reasons[object, default: []].append(.dependencyCycle); break }
                guard seen.insert(next).inserted, let linked = uniqueLive[next] else { continue }
                try step(linked.dependencies.count); stack.append(contentsOf: linked.dependencies)
            }
        }

        func ancestors(of id: UUID) throws -> Set<UUID> {
            var seen: Set<UUID> = []
            var stack = [id]
            while let next = stack.popLast() {
                try step()
                guard seen.insert(next).inserted else { continue }
                let parents = mutations[next]!.parents
                try step(parents.count); stack.append(contentsOf: parents)
            }
            return seen
        }
        var result: [CausalObjectProjection] = []
        for object in objects {
            let current = heads[object]!
            var issues = reasons[object, default: []]
            var preview: UUID?
            let state: CausalObjectProjection.State
            if ready.contains(object) { state = .ready }
            else if deleted.contains(object) { state = .deleted }
            else if current.count > 1 && issues.isEmpty {
                state = .conflict
                // A concurrent tombstone prevents any normal live preview.
                if current.allSatisfy({ !mutations[$0]!.deleted }) {
                    var common = try ancestors(of: current[0])
                    for head in current.dropFirst() { common.formIntersection(try ancestors(of: head)) }
                    var nearest = common
                    for candidate in common.sorted(by: { $0.wire < $1.wire }) {
                        var prior = try ancestors(of: candidate); prior.remove(candidate)
                        nearest.subtract(prior)
                    }
                    if nearest.count == 1, let id = nearest.first, let baseline = mutations[id], !baseline.deleted {
                        if !verifiedMutationAssets.contains(id) { issues.append(.unavailableAssets(mutation: id)) }
                        for dependency in baseline.dependencies where !ready.contains(dependency) {
                            issues.append(.dependencyNotReady(dependency))
                        }
                        if issues.isEmpty { preview = id }
                    }
                }
            } else { state = .pending }
            result.append(CausalObjectProjection(object: object, heads: current, state: state,
                selectedMutation: state == .ready || state == .deleted ? current.first : nil,
                previewMutation: preview, pendingReasons: issues))
        }
        return result
    }
}
