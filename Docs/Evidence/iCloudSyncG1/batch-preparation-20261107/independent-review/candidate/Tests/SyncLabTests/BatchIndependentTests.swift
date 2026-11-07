#if DEBUG
import XCTest
import Darwin
import CloudKit
@testable import SyncLab
final class BatchIndependentTests:XCTestCase {
 @MainActor func testEachPublicationBoundaryAndSecondAssetWire() throws {
  let root=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
  let plans=try RemainingBatch.plans(dataset:"synthetic-g1-independent",runID:"probe-independent")
  XCTAssertEqual(plans[0].commands.map(\.action),[.connect]+Array(repeating:.save,count:12)+[.sync,.sync,.snapshot])
  XCTAssertEqual(plans[1].commands.map(\.action),[.connect,.sync,.snapshot]+Array(repeating:.save,count:4)+[.sync,.sync,.snapshot])
  XCTAssertEqual(plans[2].commands.map(\.action),[.connect,.sync,.sync,.snapshot])
  let store=try LabStore(base:root,binding:Binding(accountHash:String(repeating:"c",count:64),dataset:"synthetic-g1-independent"))
  for command in plans[0].commands {
   guard let m=command.mutation else {continue};try store.save(m)
   if m.id=="probe-batch-head-old" {XCTAssertEqual(try store.projections()[m.object]?.state,"ready");XCTAssertEqual(try store.projections()[m.object]?.preview?.id,m.id)}
   if m.id=="probe-batch-head-new" {XCTAssertEqual(try store.projections()[m.object]?.state,"staged");XCTAssertNil(try store.projections()[m.object]?.preview);XCTAssertEqual(try store.projections()[m.object]?.candidates,[m.id])}
  }
  let seed=try store.exportSnapshot();let before=try store.projections()
  XCTAssertEqual(before["probe-batch-deleted"]?.state,"deleted")
  for name in ["deleted-child","missing","trans-mid","trans-root","dep-a","dep-b","head","cause"] {XCTAssertEqual(before["probe-batch-"+name]?.state,"staged");XCTAssertNil(before["probe-batch-"+name]?.preview)}
  XCTAssertEqual(try store.envelopes().flatMap(\.mutations).count,12)
  XCTAssertTrue(try JSONDecoder().decode(LabSnapshot.self,from:seed).images.isEmpty)
  // Independent second client reconstruction through actual codecs, no engine/cloud.
  let remote=try LabStore(base:root.appendingPathComponent("second"),binding:Binding(accountHash:String(repeating:"c",count:64),dataset:"synthetic-g1-independent"))
  for e in try store.envelopes(){try remote.receiveEnvelope(e.encoded(),key:"object-"+e.object,fields:Data(),ticket:remote.epoch)}
  XCTAssertEqual(try remote.exportSnapshot(),seed);XCTAssertTrue(try remote.pending().isEmpty)
  for c in plans[1].commands {guard let m=c.mutation else{continue};try remote.save(m,image:DevelopmentProbe.fixture(hash:m.imageHash,count:m.imageBytes))}
  let pending=try remote.pending();let hash=digest(DevelopmentProbe.secondPNG)
  XCTAssertEqual(Set(pending.map(\.key)),Set(["object-probe-batch-missing","object-probe-batch-trans-leaf","object-probe-batch-head-dependency","object-probe-batch-new-image","image-"+hash]))
  let imagePending=try XCTUnwrap(pending.first{$0.key=="image-"+hash})
  let record=try Wire.record(imagePending,dataset:"synthetic-g1-independent",imageURL:remote.imageURL)
  let ckAsset=try XCTUnwrap(record["original"] as? CKAsset)
  XCTAssertEqual(try Data(contentsOf:try XCTUnwrap(ckAsset.fileURL)),DevelopmentProbe.secondPNG)
  XCTAssertNotEqual(try Data(contentsOf:try XCTUnwrap(ckAsset.fileURL)),DevelopmentProbe.png)
  let repaired=try remote.projections();for name in ["missing","trans-mid","trans-root","trans-leaf","head","head-dependency","new-image"]{XCTAssertEqual(repaired["probe-batch-"+name]?.state,"ready")}
  for name in ["deleted-child","dep-a","dep-b","cause"]{XCTAssertEqual(repaired["probe-batch-"+name]?.state,"staged");XCTAssertNil(repaired["probe-batch-"+name]?.preview)}
 }
 func testOutputPermissionsAndFailBeforeCreatingInvalidDestination() throws {
  let root=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
  let invalid=root.appendingPathComponent("invalid");XCTAssertThrowsError(try RemainingBatch.write(to:invalid,dataset:"daily",runID:"probe-run"));XCTAssertFalse(FileManager.default.fileExists(atPath:invalid.path))
  let output=root.appendingPathComponent("out"),previous=umask(0);defer{umask(previous)}
  try RemainingBatch.write(to:output,dataset:"synthetic-g1-review",runID:"probe-run")
  let attrs=try FileManager.default.attributesOfItem(atPath:output.path);XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue,0o700)
  XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:output.path).count,3)
  XCTAssertThrowsError(try RemainingBatch.write(to:output,dataset:"synthetic-g1-review",runID:"probe-another"))
  let file=root.appendingPathComponent("file");try Data("KEEP".utf8).write(to:file);XCTAssertThrowsError(try RemainingBatch.write(to:file,dataset:"synthetic-g1-review",runID:"probe-run"));XCTAssertEqual(try Data(contentsOf:file),Data("KEEP".utf8))
  let link=root.appendingPathComponent("dangling");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:root.appendingPathComponent("absent"));XCTAssertThrowsError(try RemainingBatch.write(to:link,dataset:"synthetic-g1-review",runID:"probe-run"));XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("absent").path))
 }
}
#endif
