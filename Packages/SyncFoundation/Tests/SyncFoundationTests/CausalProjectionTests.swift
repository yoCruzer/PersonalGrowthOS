import XCTest
@testable import SyncFoundation

final class CausalProjectionTests: XCTestCase {
    let dataset = UUID(uuidString: "10000000-0000-0000-0000-000000000000")!
    func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
    func object(_ n: Int, kind: String = "Aggregate") throws -> SyncObject { try SyncObject(kind: kind, id: id(n)) }
    func mutation(_ n: Int, object o: Int = 1, parents: [Int] = [], dependencies: [Int] = [],
                  deleted: Bool = false, version: Int = 1, content: String = "synthetic") throws -> MutationManifest {
        try MutationManifest(dataset: dataset, mutation: id(n), object: object(o), parents: parents.map(id),
            dependencies: dependencies.map { try object($0) }, deleted: deleted, payloadVersion: version,
            payload: deleted ? nil : PayloadManifest(bytes: Data(content.utf8)))
    }
    func project(_ values: [MutationManifest], assets: Set<UUID>? = nil,
                 limits: CausalProjectionLimits = .init()) throws -> [CausalObjectProjection] {
        try CausalProjection.project(manifestBytes: values.map { try $0.encoded() }, dataset: dataset,
            supportedPayloadVersions: ["Aggregate": [1]],
            verifiedMutationAssets: assets ?? Set(values.map(\.mutation)), limits: limits)
    }
    func testLinearHistorySelectsHeadNotLexicalMaximumAndDeduplicates() throws {
        let old = try mutation(90), next = try mutation(10, parents: [90])
        let actual = try project([old, next, old])
        XCTAssertEqual(actual.count, 1); XCTAssertEqual(actual[0].heads, [id(10)])
        XCTAssertEqual(actual[0].selectedMutation, id(10)); XCTAssertEqual(actual[0].state, .ready)
        XCTAssertTrue(actual[0].complete); XCTAssertNil(actual[0].previewMutation)
    }
    func testPermutationAndDuplicateInputsProduceIdenticalConflict() throws {
        let a = try mutation(10), b = try mutation(20, parents: [10]), c = try mutation(30, parents: [10])
        let expected = try project([a,b,c])
        for permutation in [[a,c,b],[b,a,c],[b,c,a],[c,a,b],[c,b,a]] {
            XCTAssertEqual(try project(permutation), expected)
            XCTAssertEqual(try project(permutation + [b,a,c]), expected)
        }
        XCTAssertEqual(expected[0].heads, [id(20),id(30)])
        XCTAssertEqual(expected[0].state, .conflict); XCTAssertEqual(expected[0].previewMutation, id(10))
        XCTAssertNil(expected[0].selectedMutation); XCTAssertFalse(expected[0].complete)
    }
    func testSameMutationDifferentBytesRejectedRatherThanFirstWins() throws {
        let a = try mutation(10), b = try mutation(10, content: "different")
        for values in [[a,b], [b,a]] {
            XCTAssertThrowsError(try project(values)) { XCTAssertEqual($0 as? SyncValidationError, .identityCollision) }
        }
    }
    func testLateParentUnblocksWithoutChangingHead() throws {
        let head = try mutation(20, parents: [10])
        let before = try project([head])[0]
        XCTAssertEqual(before.heads, [id(20)]); XCTAssertEqual(before.state, .pending)
        XCTAssertEqual(before.pendingReasons, [.missingParent(mutation: id(20), parent: id(10))])
        let after = try project([head, mutation(10)])[0]
        XCTAssertEqual(after.selectedMutation, id(20)); XCTAssertEqual(after.state, .ready)
    }
    func testLateDependencyUnblocksChain() throws {
        let a = try mutation(10, dependencies: [2]), b = try mutation(20, object: 2, dependencies: [3])
        let before = try project([a,b])
        XCTAssertEqual(before.map(\.state), [.pending,.pending])
        XCTAssertEqual(before[0].pendingReasons, [.dependencyNotReady(try object(2))])
        let after = try project([mutation(30, object: 3), b, a])
        XCTAssertEqual(after.map(\.state), [.ready,.ready,.ready])
    }
    func testDeletedTargetHistoricalLiveVersionCannotSatisfyDependency() throws {
        let target = try mutation(10, object: 2), deleted = try mutation(20, object: 2, parents: [10], deleted: true)
        let dependent = try mutation(30, dependencies: [2])
        let result = try project([target,deleted,dependent])
        XCTAssertEqual(result.map(\.state), [.pending,.deleted]); XCTAssertNil(result[0].selectedMutation)
        XCTAssertEqual(result[1].selectedMutation, id(20))
    }
    func testMissingAncestorTargetCannotSatisfyDependency() throws {
        let result = try project([mutation(20, object: 2, parents: [10]), mutation(30, dependencies: [2])])
        XCTAssertEqual(result.map(\.state), [.pending,.pending])
        XCTAssertEqual(result[1].pendingReasons, [.missingParent(mutation: id(20), parent: id(10))])
    }
    func testTransitiveMissingDependencyDoesNotPublishParentOrChild() throws {
        let result = try project([mutation(10, dependencies: [2]), mutation(20, object: 2, dependencies: [3])])
        XCTAssertEqual(result.map(\.state), [.pending,.pending]); XCTAssertTrue(result.allSatisfy { !$0.complete })
    }
    func testCausalCycleTargetCannotSatisfyDependency() throws {
        let result = try project([mutation(10, object: 2, parents: [20]), mutation(20, object: 2, parents: [10]),
                                  mutation(30, dependencies: [2])])
        XCTAssertEqual(result.map(\.state), [.pending,.pending])
        XCTAssertEqual(result[1].pendingReasons, [.causalCycle]); XCTAssertTrue(result[1].heads.isEmpty)
    }
    func testCurrentBlockedHeadNeverFallsBackToHistoricalLiveRow() throws {
        let old = try mutation(10, object: 2), head = try mutation(20, object: 2, parents: [10], dependencies: [3])
        let result = try project([old,head,mutation(30, dependencies: [2])])
        XCTAssertEqual(result.map(\.state), [.pending,.pending]); XCTAssertEqual(result[1].heads, [id(20)])
        XCTAssertNil(result[1].selectedMutation); XCTAssertNil(result[1].previewMutation)
    }
    func testCrossObjectParentBlocksChildButDoesNotEraseOtherObjectsHead() throws {
        let result = try project([mutation(10, object: 2), mutation(20, parents: [10])])
        XCTAssertEqual(result.map(\.state), [.pending,.ready])
        XCTAssertEqual(result[0].pendingReasons, [.crossObjectParent(mutation: id(20), parent: id(10))])
        XCTAssertEqual(result[1].heads, [id(10)])
    }
    func testUnknownPayloadVersionRetainsAllHeadsAndBlocksHistoricalFallback() throws {
        let result = try project([mutation(10), mutation(20, parents: [10], version: 2), mutation(30, parents: [10])])[0]
        XCTAssertEqual(result.state, .pending); XCTAssertEqual(result.heads, [id(20),id(30)])
        XCTAssertEqual(result.pendingReasons, [.unsupportedPayload(mutation: id(20), version: 2)])
        XCTAssertNil(result.previewMutation)
    }
    func testDependencyCycleRemainsPendingAndDeletionReleasesRemovedDependency() throws {
        let a = try mutation(10, dependencies: [2]), b = try mutation(20, object: 2, dependencies: [1])
        let pending = try project([a,b]); XCTAssertTrue(pending.allSatisfy { $0.pendingReasons.contains(.dependencyCycle) })
        let deleted = try project([a,b,mutation(30, parents: [10], deleted: true)])
        XCTAssertEqual(deleted.map(\.state), [.deleted,.pending])
        XCTAssertEqual(deleted[0].selectedMutation, id(30))
    }
    func testDeleteEditConflictRetainsCandidatesWithoutLivePreview() throws {
        let result = try project([mutation(10), mutation(20, parents: [10], deleted: true), mutation(30, parents: [10])])[0]
        XCTAssertEqual(result.state, .conflict); XCTAssertEqual(result.heads, [id(20),id(30)])
        XCTAssertNil(result.previewMutation); XCTAssertNil(result.selectedMutation); XCTAssertFalse(result.complete)
    }
    func testMultipleNearestCommonAncestorsDoNotSelectAnArbitraryBaseline() throws {
        let values = try [mutation(10), mutation(20, parents: [10]), mutation(30, parents: [10]),
                          mutation(40, parents: [20,30]), mutation(50, parents: [20,30])]
        let result = try project(values)[0]
        XCTAssertEqual(result.heads, [id(40),id(50)]); XCTAssertEqual(result.state, .conflict)
        XCTAssertNil(result.previewMutation)
    }
    func testResolutionDominatesAllConflictHeadsAndUnrelatedRootsHaveNoPreview() throws {
        let branches = try [mutation(10), mutation(20)]
        XCTAssertNil(try project(branches)[0].previewMutation)
        let result = try project(branches + [mutation(30, parents: [10,20])])[0]
        XCTAssertEqual(result.selectedMutation, id(30)); XCTAssertEqual(result.state, .ready)
    }
    func testMissingAssetsAndPreviewDependencyClosureStayUnconfirmed() throws {
        let old = try mutation(10), head = try mutation(20, parents: [10])
        let result = try project([old,head], assets: [id(10)])[0]
        XCTAssertEqual(result.state, .pending); XCTAssertEqual(result.pendingReasons, [.unavailableAssets(mutation: id(20))])
        let conflict = try [mutation(10, dependencies: [2]), mutation(20, parents: [10]), mutation(30, parents: [10])]
        let preview = try project(conflict)[0]
        XCTAssertEqual(preview.state, .conflict); XCTAssertNil(preview.previewMutation)
        XCTAssertEqual(preview.pendingReasons, [.dependencyNotReady(try object(2))])
        XCTAssertEqual(try project(conflict + [mutation(40, object: 2)])[0].previewMutation, id(10))
    }
    func testDatasetAndUnknownKindAreNotSilentlyAccepted() throws {
        let foreign = try MutationManifest(dataset: id(999), mutation: id(10), object: object(1),
                                           payload: PayloadManifest(bytes: Data([1])))
        XCTAssertThrowsError(try project([foreign])) { XCTAssertEqual($0 as? SyncValidationError, .invalidIdentity) }
        let unknown = try MutationManifest(dataset: dataset, mutation: id(10), object: object(1, kind: "Future"),
                                           payload: PayloadManifest(bytes: Data([1])))
        XCTAssertEqual(try project([unknown])[0].pendingReasons, [.unsupportedPayload(mutation: id(10), version: 1)])
    }
    func testResourceLimitsRejectWholeResultIncludingDuplicateInput() throws {
        let value = try mutation(10)
        for limits in [CausalProjectionLimits(manifests: 1), CausalProjectionLimits(encodedBytes: 1),
                       CausalProjectionLimits(graphSteps: 0)] {
            XCTAssertThrowsError(try project([value,value], limits: limits)) {
                XCTAssertEqual($0 as? SyncValidationError, .limitExceeded)
            }
        }
    }
    func testLongChainUsesIterationAndSharedAncestryDoesNotExplode() throws {
        var chain: [MutationManifest] = []
        for n in 1...1_200 { chain.append(try mutation(n, parents: n == 1 ? [] : [n-1])) }
        XCTAssertEqual(try project(chain)[0].selectedMutation, id(1_200))
        var diamond = [try mutation(1)]
        for n in 1...60 {
            let previous = n == 1 ? [1] : [2*n-2,2*n-1]
            diamond.append(try mutation(2*n, parents: previous))
            diamond.append(try mutation(2*n+1, parents: previous))
        }
        let result = try project(diamond)[0]
        XCTAssertEqual(result.heads, [id(120),id(121)]); XCTAssertEqual(result.state, .conflict)
        XCTAssertNil(result.previewMutation)
    }
}
