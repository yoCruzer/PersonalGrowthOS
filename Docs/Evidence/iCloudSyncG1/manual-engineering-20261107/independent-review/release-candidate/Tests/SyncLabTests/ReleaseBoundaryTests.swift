import XCTest
import Darwin
@testable import SyncLab
final class ReleaseBoundaryTests:XCTestCase {
 @MainActor func testReleaseCannotAuthorizeEvenWithEnvironment() async throws {
  let previous=getenv("SYNCLAB_ENABLE_DEVELOPMENT").map{String(cString:$0)}
  defer{if let previous{setenv("SYNCLAB_ENABLE_DEVELOPMENT",previous,1)}else{unsetenv("SYNCLAB_ENABLE_DEVELOPMENT")}}
  setenv("SYNCLAB_ENABLE_DEVELOPMENT","YES",1)
  XCTAssertFalse(DevelopmentAuthorization.fromEnvironment().isEnabled)
  let root=URL.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
  let store=try LabStore(base:root,binding:Binding(accountHash:String(repeating:"a",count:64),dataset:"synthetic-g1-release"))
  let driver=CloudDriver(store:store)
  do{try await driver.start();XCTFail("Release must fail before CloudKit")}catch let e as LabError{XCTAssertEqual(String(describing:e),"blocked")}
  XCTAssertTrue(driver.events.isEmpty)
 }
}
