#if DEBUG
import XCTest
@testable import SyncLab
final class BatchRepeatedRunTests:XCTestCase {
 func testNewRunCanExportWithoutCollidingWithPreservedPreviousRun() throws {
  let root=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
  let a=try RemainingBatch.plans(dataset:"synthetic-g1-first",runID:"probe-first")[1]
  let b=try RemainingBatch.plans(dataset:"synthetic-g1-second",runID:"probe-second")[1]
  func publish(_ plan:ManualProbePlan)throws {
   let bytes=try canonical(plan),journal=try ManualProbeJournal(root:root.appendingPathComponent("private"),plan:plan)
   XCTAssertNil(try journal.claim(bytes))
   let report=ManualProbeReport(planID:plan.id,dataset:plan.dataset,runID:plan.runID,planDigest:digest(bytes),results:[],completedAllCommands:false,errorCode:"CANCELLED")
   try journal.complete(report)
   let output=root.appendingPathComponent("documents").appendingPathComponent("SyncLab-Manual-"+plan.id+".json")
   try publishProbeExport(Data(contentsOf:journal.resultURL),to:output)
  }
  try publish(a)
  XCTAssertNoThrow(try publish(b),"A new run/dataset must preserve previous export while making new result available")
 }
}
#endif
