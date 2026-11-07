import XCTest
import Darwin
@testable import SyncLab
final class ManualIndependentTests: XCTestCase {
 func plan(_ id:String="probe-first") -> ManualProbePlan { ManualProbePlan(id:id,dataset:"synthetic-g1-review",runID:"probe-run-review",commands:[ProbeCommand(id:"probe-snapshot",action:.snapshot)]) }
 func result(_ p:ManualProbePlan) throws -> ProbeResult { ProbeResult(planID:p.id,id:p.commands[0].id,dataset:p.dataset,runID:p.runID,commandDigest:try digest(canonical(p.commands[0])),status:"PASS",events:[],halted:false,platform:"TEST_ONLY") }
 func testPlansCannotReuseEarlierSnapshotOrForeignResult() throws {
  let root=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
  let first=plan(),second=plan("probe-second"),a=try ProbeJournal(root:root,dataset:first.dataset,runID:first.runID,contextID:first.id),b=try ProbeJournal(root:root,dataset:second.dataset,runID:second.runID,contextID:second.id)
  XCTAssertNil(try a.claim(first.commands[0],bytes:canonical(first.commands[0])));try a.complete(result(first))
  XCTAssertNil(try b.claim(second.commands[0],bytes:canonical(second.commands[0])))
  XCTAssertThrowsError(try b.complete(result(first)))
  let wrong=ManualProbeReport(planID:second.id,dataset:second.dataset,runID:second.runID,planDigest:try digest(canonical(second)),results:[try result(first)],completedAllCommands:true)
  XCTAssertThrowsError(try wrong.validate(plan:second,bytes:canonical(second)))
  try b.complete(result(second));XCTAssertEqual(try b.claim(second.commands[0],bytes:canonical(second.commands[0]))?.planID,second.id)
 }
 func testExportIsCopyImmutableAndRejectsSymlinkFIFOAndDirectory() throws {
  let root=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  let target=root.appendingPathComponent("flat.json"),bytes=Data("PRIVATE ORIGINAL".utf8)
  try publishProbeExport(bytes,to:target);try publishProbeExport(bytes,to:target)
  XCTAssertThrowsError(try publishProbeExport(Data("ALTERED".utf8),to:target));XCTAssertEqual(try Data(contentsOf:target),bytes)
  let link=root.appendingPathComponent("link.json");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:target)
  XCTAssertThrowsError(try publishProbeExport(bytes,to:link))
  let fifo=root.appendingPathComponent("fifo.json");XCTAssertEqual(mkfifo(fifo.path,0o600),0);XCTAssertThrowsError(try publishProbeExport(bytes,to:fifo))
  let dir=root.appendingPathComponent("dir.json");try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);XCTAssertThrowsError(try publishProbeExport(bytes,to:dir))
 }
 func testPlanImportBoundsIdentityAndTerminalFailureOrder() throws {
  let p=plan();XCTAssertNoThrow(try ManualProbePlan.decode(canonical(p)))
  var many=p;many.commands=(0..<16).map{ProbeCommand(id:"probe-\($0)",action:.snapshot)};XCTAssertNoThrow(try many.validate());many.commands.append(ProbeCommand(id:"probe-extra",action:.snapshot));XCTAssertThrowsError(try many.validate())
  let root=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  let url=root.appendingPathComponent("SyncLab-Probe-Plan.json");try canonical(p).write(to:url);XCTAssertEqual(try ManualProbePlan.readImportedPlan(documents:root),try canonical(p))
  try FileManager.default.removeItem(at:url);XCTAssertEqual(mkfifo(url.path,0o600),0);XCTAssertThrowsError(try ManualProbePlan.readImportedPlan(documents:root))
  var two=p;two.commands.append(ProbeCommand(id:"probe-second",action:.snapshot))
  var failed=try result(p);failed.status="FAIL";failed.errorCode="LAB_blocked"
  let report=ManualProbeReport(planID:p.id,dataset:p.dataset,runID:p.runID,planDigest:try digest(canonical(two)),results:[failed],completedAllCommands:false,errorCode:"LAB_blocked")
  XCTAssertNoThrow(try report.validate(plan:two,bytes:canonical(two)))
  var invalid=report;invalid.results.append(failed);XCTAssertThrowsError(try invalid.validate(plan:two,bytes:canonical(two)))
 }
}
