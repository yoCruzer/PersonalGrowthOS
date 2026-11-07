import XCTest
@testable import SyncLab
final class ManualIndependentTests: XCTestCase {
 func fixture() -> ManualProbePlan { ManualProbePlan(id: "probe-plan-first", dataset: "synthetic-g1-review", runID: "probe-run-review", commands: [ProbeCommand(id: "probe-snapshot", action: .snapshot)]) }
 func fake(_ command: ProbeCommand, _ plan: ManualProbePlan) throws -> ProbeResult {
  ProbeResult(id: command.id, dataset: plan.dataset, runID: plan.runID, commandDigest: try digest(canonical(command)), status: "PASS", events: [], halted: false, platform: "TEST_ONLY")
 }
 @MainActor func testImportedForgedCompletionMustNotExecuteOrBeAccepted() async throws {
  let root=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString), docs=root.appendingPathComponent("documents")
  defer {try? FileManager.default.removeItem(at: root)}
  let plan=fixture(), bytes=try canonical(plan)
  let directory=docs.appendingPathComponent("SyncLab-Manual-Results").appendingPathComponent(plan.runID).appendingPathComponent(plan.dataset)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try bytes.write(to: directory.appendingPathComponent(plan.id+".request.json"))
  let forged=ManualProbeReport(planID:plan.id,dataset:plan.dataset,runID:plan.runID,planDigest:digest(bytes),results:[try fake(plan.commands[0],plan)],completedAllCommands:true)
  try canonical(forged).write(to:directory.appendingPathComponent(plan.id+".json"))
  let probe=try DevelopmentProbe(base:root.appendingPathComponent("private"),dataset:plan.dataset,runID:plan.runID,authorization:.afterExplicitManualConsent())
  do { let result=try await probe.runManualPlan(bytes,documents:docs); XCTFail("Accepted imported fabricated completion without executing any command: \(result.lastPathComponent)") }
  catch {} // Expected: reject imported authority; this copied vulnerable candidate never reaches cloud.
 }
 func testSecondPlanMustNotReuseSnapshotFromBeforeItsSave() throws {
  let root=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
  let first=fixture(), old=first.commands[0], journal=try ProbeJournal(root:root,dataset:first.dataset,runID:first.runID)
  XCTAssertNil(try journal.claim(old,bytes:canonical(old)));try journal.complete(fake(old,first))
  var second=first;second.id="probe-plan-second"
  let save=ProbeCommand(id:"probe-new-save",action:.save,mutation:Mutation(id:"probe-new-mutation",object:"probe-object",text:"SYNTHETIC new after snapshot"))
  second.commands=[save,old];try second.validate()
  let cached=try XCTUnwrap(journal.claim(old,bytes:canonical(old)))
  let report=ManualProbeReport(planID:second.id,dataset:second.dataset,runID:second.runID,planDigest:try digest(canonical(second)),results:[try fake(save,second),cached],completedAllCommands:true)
  XCTAssertThrowsError(try report.validate(plan:second,bytes:canonical(second)),"Second plan accepts old snapshot after a newer save: sequence is not tied to plan")
 }
 func testImportedOutputDirectorySymlinkMustNotWriteOutsideDocuments() throws {
  let root=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString),docs=root.appendingPathComponent("documents"),other=root.appendingPathComponent("outside")
  defer{try? FileManager.default.removeItem(at:root)}
  try FileManager.default.createDirectory(at:docs,withIntermediateDirectories:true);try FileManager.default.createDirectory(at:other,withIntermediateDirectories:true)
  try FileManager.default.createSymbolicLink(at:docs.appendingPathComponent("SyncLab-Manual-Results"),withDestinationURL:other)
  let plan=fixture()
  XCTAssertThrowsError(try {let journal=try ManualProbeJournal(root:docs,plan:plan);_ = try journal.claim(canonical(plan))}(),"Writable import symlink redirects journal publication")
  XCTAssertFalse(FileManager.default.fileExists(atPath:other.appendingPathComponent(plan.runID).appendingPathComponent(plan.dataset).appendingPathComponent(plan.id+".request.json").path))
 }
}
