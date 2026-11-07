import XCTest
import Foundation
@testable import SyncLab
final class ProbeReviewTests: XCTestCase {
 func testIndependentJournalIdentityAndCrashBoundary() throws {
  let root=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let c=ProbeCommand(id:"probe-review",action:.snapshot)
  let bytes=try canonical(c)
  let j=try ProbeJournal(root:root,dataset:"synthetic-g1-review",runID:"probe-run")
  XCTAssertNil(try j.claim(c,bytes:bytes))
  XCTAssertThrowsError(try j.claim(c,bytes:bytes))
  var r=ProbeResult(id:c.id,dataset:"synthetic-g1-review",runID:"probe-other",commandDigest:digest(bytes),status:"PASS",events:[],halted:false,platform:"SYNTHETIC_TEST")
  XCTAssertThrowsError(try j.complete(r))
  r.runID="probe-run";try j.complete(r)
  let original=try Data(contentsOf:j.directory.appendingPathComponent(c.id+".json"))
  XCTAssertEqual(try j.claim(c,bytes:bytes)?.runID,"probe-run")
  XCTAssertThrowsError(try j.claim(c,bytes:bytes+Data(" ".utf8)))
  r.status="FAIL";XCTAssertThrowsError(try j.complete(r))
  XCTAssertEqual(try Data(contentsOf:j.directory.appendingPathComponent(c.id+".json")),original)
  let other=try ProbeJournal(root:root,dataset:"synthetic-g1-other",runID:"probe-run")
  XCTAssertNil(try other.claim(c,bytes:bytes))
 }
 func testIndependentCrossProcessLockAndNoFollow() throws {
  let base=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  var held:ProbeProcessLock?=try ProbeProcessLock(base:base,dataset:"synthetic-g1-review")
  XCTAssertNotNil(held)
  let path=base.appendingPathComponent("probe-locks/synthetic-g1-review.lock").path
  func attempt() throws -> Int32 {
   let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/python3")
   p.arguments=["-c","import os,sys,fcntl\nf=os.open(sys.argv[1],os.O_RDWR)\ntry:\n fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)\nexcept BlockingIOError:\n sys.exit(2)\n",path]
   try p.run();p.waitUntilExit();return p.terminationStatus
  }
  XCTAssertEqual(try attempt(),2)
  held=nil;XCTAssertEqual(try attempt(),0)
  let link=base.appendingPathComponent("probe-locks/synthetic-g1-link.lock")
  try FileManager.default.createSymbolicLink(at:link,withDestinationURL:URL(fileURLWithPath:path))
  XCTAssertThrowsError(try ProbeProcessLock(base:base,dataset:"synthetic-g1-link"))
 }
 @MainActor func testIndependentOptInAndLoopbackRejections() async throws {
  XCTAssertNotEqual(ProcessInfo.processInfo.environment["SYNCLAB_ENABLE_DEVELOPMENT"],"YES")
  let base=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let p=try DevelopmentProbe(base:base,dataset:"synthetic-g1-review",runID:"probe-run")
  let result=await p.perform(ProbeCommand(id:"probe-connect",action:.connect))
  XCTAssertEqual(result.status,"FAIL");XCTAssertNil(result.accountFingerprint)
  XCTAssertFalse(FileManager.default.fileExists(atPath:base.path))
  for value in ["file:///tmp/data","http://127.0.0.1:23456/#secret","http://127.0.0.1:23456/../next","http://[::1]:23456","http://127.0.0.1.evil:23456"] { XCTAssertThrowsError(try DevelopmentProbe.loopbackURL(value)) }
 }
}
