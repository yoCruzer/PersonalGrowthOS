import XCTest
@testable import SyncLab
final class ManualControlFlowTests: XCTestCase {
 @MainActor func testCancelledPlanMustNotReachCloudEntry() async throws {
  let root=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
  let plan=ManualProbePlan(id:"probe-cancel-plan",dataset:"synthetic-g1-cancel",runID:"probe-cancel-run",commands:[ProbeCommand(id:"probe-connect",action:.connect)])
  let probe=try DevelopmentProbe(base:root.appendingPathComponent("private"),dataset:plan.dataset,runID:plan.runID,authorization:.afterExplicitManualConsent())
  DevelopmentProbe.reviewConnectCount=0
  let task=Task { @MainActor in try await probe.runManualPlan(canonical(plan),documents:root.appendingPathComponent("documents")) }
  task.cancel()
  _ = try? await task.value
  XCTAssertEqual(DevelopmentProbe.reviewConnectCount,0,"Pre-cancelled plan reached connect despite cancellation")
 }
 @MainActor func testReentrantPlanMustNotReleaseActivePlanLock() async throws {
  let root=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString),base=root.appendingPathComponent("private"),docs=root.appendingPathComponent("documents")
  defer{try? FileManager.default.removeItem(at:root)}
  let plan=ManualProbePlan(id:"probe-reentry-plan",dataset:"synthetic-g1-reentry",runID:"probe-reentry-run",commands:[ProbeCommand(id:"probe-connect",action:.connect)])
  let probe=try DevelopmentProbe(base:base,dataset:plan.dataset,runID:plan.runID,authorization:.afterExplicitManualConsent())
  var resume:CheckedContinuation<Void,Never>?
  DevelopmentProbe.reviewConnectHook={await withCheckedContinuation{resume=$0}}
  let first=Task { @MainActor in try await probe.runManualPlan(canonical(plan),documents:docs) }
  while resume == nil {await Task.yield()}
  do {_ = try await probe.runManualPlan(canonical(plan),documents:docs);XCTFail("Reentry accepted")}catch{}
  XCTAssertThrowsError(try ProbeProcessLock(base:base,dataset:plan.dataset),"Rejected reentrant invocation released original live process lock")
  DevelopmentProbe.reviewConnectHook=nil;resume?.resume();_ = try? await first.value
 }
 @MainActor func testCancellationBetweenCommandsRetainsFirstAndSkipsNext() async throws {
  let root=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString),base=root.appendingPathComponent("private"),docs=root.appendingPathComponent("documents")
  defer{try? FileManager.default.removeItem(at:root);DevelopmentProbe.reviewPerformHook=nil}
  let plan=ManualProbePlan(id:"probe-midcancel-plan",dataset:"synthetic-g1-midcancel",runID:"probe-midcancel-run",commands:[ProbeCommand(id:"probe-first",action:.snapshot),ProbeCommand(id:"probe-second",action:.snapshot)])
  var count=0
  DevelopmentProbe.reviewPerformHook={ command in
   count += 1;withUnsafeCurrentTask{$0?.cancel()}
   return ProbeResult(id:command.id,dataset:plan.dataset,runID:plan.runID,commandDigest:try! digest(canonical(command)),status:"PASS",events:[],halted:false,platform:"TEST_ONLY_INJECTED")
  }
  let probe=try DevelopmentProbe(base:base,dataset:plan.dataset,runID:plan.runID,authorization:.afterExplicitManualConsent())
  let task=Task { @MainActor in try await probe.runManualPlan(canonical(plan),documents:docs) }
  let executed=try await task.value
  XCTAssertEqual(count,1);XCTAssertEqual(executed.report.results.count,1);XCTAssertEqual(executed.report.errorCode,"CANCELLED");XCTAssertFalse(executed.report.completedAllCommands)
  let commands=try ProbeJournal(root:base.appendingPathComponent("probe-journals"),dataset:plan.dataset,runID:plan.runID,contextID:plan.id)
  XCTAssertNotNil(try commands.claim(plan.commands[0],bytes:canonical(plan.commands[0])))
  XCTAssertFalse(FileManager.default.fileExists(atPath:commands.directory.appendingPathComponent("probe-second.request.json").path))
  XCTAssertNoThrow(try ProbeProcessLock(base:base,dataset:plan.dataset))
 }

}
