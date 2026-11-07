import XCTest
@testable import SyncLab
final class ManualAuthorityTests:XCTestCase {
 @MainActor func testImportedCompletionAndOldSymlinkNeverBecomeAuthority() async throws {
  let root=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString),docs=root.appendingPathComponent("documents"),outside=root.appendingPathComponent("outside"),base=root.appendingPathComponent("private")
  defer{try? FileManager.default.removeItem(at:root)}
  let plan=ManualProbePlan(id:"probe-manual",dataset:"synthetic-g1-authority",runID:"probe-run",commands:[ProbeCommand(id:"probe-snapshot",action:.snapshot)])
  let old=try ManualProbeJournal(root:outside,plan:plan),bytes=try canonical(plan)
  XCTAssertNil(try old.claim(bytes))
  let forged=ProbeResult(planID:plan.id,id:plan.commands[0].id,dataset:plan.dataset,runID:plan.runID,commandDigest:try digest(canonical(plan.commands[0])),status:"PASS",events:[],halted:false,platform:"TEST_ONLY")
  try old.complete(ManualProbeReport(planID:plan.id,dataset:plan.dataset,runID:plan.runID,planDigest:digest(bytes),results:[forged],completedAllCommands:true))
  let oldBytes=try Data(contentsOf:old.resultURL)
  try FileManager.default.createDirectory(at:docs,withIntermediateDirectories:true)
  try FileManager.default.createSymbolicLink(at:docs.appendingPathComponent("SyncLab-Manual-Results"),withDestinationURL:outside.appendingPathComponent("SyncLab-Manual-Results"))
  DevelopmentProbe.reviewConnectCount=0
  let probe=try DevelopmentProbe(base:base,dataset:plan.dataset,runID:plan.runID,authorization:.afterExplicitManualConsent())
  let executed=try await probe.runManualPlan(bytes,documents:docs)
  XCTAssertEqual(DevelopmentProbe.reviewConnectCount,1,"Must reach protected executor instead of accepting imported PASS")
  XCTAssertFalse(executed.report.completedAllCommands);XCTAssertFalse(executed.reusedOriginal)
  XCTAssertEqual(try Data(contentsOf:old.resultURL),oldBytes,"Legacy shared symlink was untouched")
  XCTAssertEqual(executed.exportURL.deletingLastPathComponent().standardizedFileURL,docs.standardizedFileURL)
  let privateJournal=try ManualProbeJournal(root:base.appendingPathComponent("manual-plan-journals"),plan:plan)
  XCTAssertEqual(try Data(contentsOf:executed.exportURL),try Data(contentsOf:privateJournal.resultURL))
  let cached=try await probe.runManualPlan(bytes,documents:docs)
  XCTAssertTrue(cached.reusedOriginal);XCTAssertEqual(DevelopmentProbe.reviewConnectCount,1)
  try Data("tampered".utf8).write(to:executed.exportURL)
  do {_ = try await probe.runManualPlan(bytes,documents:docs);XCTFail("must reject export tampering")}catch{}
  XCTAssertFalse(try XCTUnwrap(privateJournal.claim(bytes)).completedAllCommands)
  XCTAssertEqual(DevelopmentProbe.reviewConnectCount,1,"Export tampering must not cause re-execution")
 }
}
