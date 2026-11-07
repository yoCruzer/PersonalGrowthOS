#if DEBUG
import XCTest
import ImageIO
@testable import SyncLab

final class RemainingBatchTests: XCTestCase {
    func plans() throws -> [ManualProbePlan] {
        try RemainingBatch.plans(dataset: "synthetic-g1-batch-test", runID: "probe-batch-test")
    }
    func testPlansBoundedAndDeterministicWithoutAuthorization() throws {
        let values = try plans()
        XCTAssertEqual(values.map { $0.commands.count }, [16, 10, 4])
        XCTAssertEqual(try canonical(values), try canonical(plans()))
        XCTAssertEqual(Set(values.flatMap { $0.commands.map(\.id) }).count, 30)
        for p in values { XCTAssertNoThrow(try ManualProbePlan.decode(canonical(p))) }
        let otherRun = try RemainingBatch.plans(dataset: "synthetic-g1-batch-test", runID: "probe-other")
        let otherDataset = try RemainingBatch.plans(dataset: "synthetic-g1-other", runID: "probe-batch-test")
        XCTAssertTrue(Set(values.map(\.id)).isDisjoint(with: otherRun.map(\.id)))
        XCTAssertTrue(Set(values.map(\.id)).isDisjoint(with: otherDataset.map(\.id)))
        XCTAssertFalse(DevelopmentAuthorization.fromEnvironment().isEnabled)
        XCTAssertThrowsError(try RemainingBatch.plans(dataset: "daily", runID: "probe-run"))
        XCTAssertThrowsError(try RemainingBatch.plans(dataset: "synthetic-g1-test", runID: "../bad"))
    }
    func testPreparationNeverOverwritesOriginalOrFollowsOutputSymlink() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try RemainingBatch.write(to: root, dataset: "synthetic-g1-test", runID: "probe-run")
        let first = try RemainingBatch.plans(dataset: "synthetic-g1-test", runID: "probe-run")[0]
        let file = root.appendingPathComponent(first.id + "/SyncLab-Probe-Plan.json")
        let original = try Data(contentsOf: file)
        XCTAssertThrowsError(try RemainingBatch.write(to: root, dataset: "synthetic-g1-test", runID: "probe-other"))
        XCTAssertEqual(try Data(contentsOf: file), original)
        let link = root.appendingPathExtension("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        XCTAssertThrowsError(try RemainingBatch.write(to: link, dataset: "synthetic-g1-test", runID: "probe-run"))
    }
    func testSecondImageIsDecodableDistinctAndStrictlyAllowlisted() throws {
        let png = DevelopmentProbe.secondPNG
        XCTAssertNotEqual(digest(png), digest(DevelopmentProbe.png))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 1); XCTAssertEqual(image.height, 1)
        XCTAssertEqual(DevelopmentProbe.fixture(hash: digest(png), count: png.count), png)
        XCTAssertNil(DevelopmentProbe.fixture(hash: digest(png), count: png.count + 1))
        XCTAssertNil(DevelopmentProbe.fixture(hash: String(repeating: "a", count: 64), count: png.count))
        var mutation = try XCTUnwrap(plans()[1].commands.compactMap(\.mutation).last)
        XCTAssertNoThrow(try ProbeCommand(id: "probe-image", action: .save, mutation: mutation).validate())
        mutation.imageBytes = png.count + 1
        XCTAssertThrowsError(try ProbeCommand(id: "probe-image", action: .save, mutation: mutation).validate())
    }
    @MainActor func testNativeStagingRepairAndFreshImagePendingWithoutCloud() throws {
        let store = try LabStore(base: .temporaryDirectory.appendingPathComponent(UUID().uuidString),
                                 binding: Binding(accountHash: digest(Data("SYNTHETIC-BATCH".utf8)), dataset: "synthetic-g1-batch-test"))
        let values = try plans()
        for mutation in values[0].commands.compactMap(\.mutation) { try store.save(mutation) }
        let before = try store.projections()
        XCTAssertEqual(before.count, 9)
        XCTAssertEqual(before["probe-batch-deleted"]?.state, "deleted")
        for name in ["deleted-child", "missing", "trans-mid", "trans-root", "dep-a", "dep-b", "head", "cause"] {
            XCTAssertEqual(before["probe-batch-" + name]?.state, "staged", name)
            XCTAssertNil(before["probe-batch-" + name]?.preview, name)
        }
        XCTAssertEqual(before["probe-batch-head"]?.candidates, ["probe-batch-head-new"])
        let initial = try store.envelopes().flatMap(\.mutations)
        for mutation in values[1].commands.compactMap(\.mutation) {
            try store.save(mutation, image: DevelopmentProbe.fixture(hash: mutation.imageHash, count: mutation.imageBytes))
        }
        let after = try store.projections()
        for name in ["missing", "trans-mid", "trans-root", "trans-leaf", "head", "head-dependency", "new-image"] {
            XCTAssertEqual(after["probe-batch-" + name]?.state, "ready", name)
        }
        for name in ["deleted-child", "dep-a", "dep-b", "cause"] { XCTAssertEqual(after["probe-batch-" + name]?.state, "staged", name) }
        XCTAssertEqual(after["probe-batch-head"]?.preview?.id, "probe-batch-head-new")
        let all = try store.envelopes().flatMap(\.mutations)
        XCTAssertEqual(all.count, 16)
        for old in initial { XCTAssertTrue(all.contains(old)) }
        let hash = digest(DevelopmentProbe.secondPNG)
        XCTAssertTrue(try store.pending().contains { $0.key == "image-" + hash })
        XCTAssertEqual(try store.image(hash, count: DevelopmentProbe.secondPNG.count), DevelopmentProbe.secondPNG)
    }
}
#endif
