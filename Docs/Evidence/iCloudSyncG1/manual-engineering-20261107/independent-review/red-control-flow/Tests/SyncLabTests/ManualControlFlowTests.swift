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
}
