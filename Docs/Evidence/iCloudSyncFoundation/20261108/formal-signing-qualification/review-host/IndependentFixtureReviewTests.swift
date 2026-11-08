import XCTest
import Foundation
import FormalDevelopmentSDK

final class IndependentFixtureReviewTests: XCTestCase {
    func testFixedFixtureReportsClosedGatesWithoutPrivatePaths() throws {
        let bytes=try FormalDevelopmentLockedHost.inspectFixture()
        let report=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any])
        XCTAssertEqual(Set(report.keys),Set(["mode","status","failure","planSHA256","container","environment","run","dataset","networkOperations","networkAuthorized","p0Passed","missingFactory"]))
        XCTAssertEqual(report["mode"] as? String,"OFFLINE_ONLY");XCTAssertEqual(report["status"] as? String,"NOT_READY")
        XCTAssertEqual(report["failure"] as? String,"EXTERNAL_GATE_NOT_COMPLETE");XCTAssertEqual(report["networkOperations"] as? Int,0)
        XCTAssertEqual(report["networkAuthorized"] as? Bool,false);XCTAssertEqual(report["p0Passed"] as? Bool,false)
        XCTAssertEqual(report["container"] as? String,"iCloud.com.yocruzer.PersonalGrowthOS");XCTAssertEqual(report["environment"] as? String,"Development")
        let text=try XCTUnwrap(String(data:bytes,encoding:.utf8));XCTAssertFalse(text.contains("/private/"));XCTAssertFalse(text.contains("/Users/"))
    }
    func testTwoInvocationsCreateDistinctSyntheticIdentities() throws {
        let a=try XCTUnwrap(JSONSerialization.jsonObject(with:FormalDevelopmentLockedHost.inspectFixture()) as? [String:Any])
        let b=try XCTUnwrap(JSONSerialization.jsonObject(with:FormalDevelopmentLockedHost.inspectFixture()) as? [String:Any])
        for key in ["run","dataset","planSHA256"] {XCTAssertNotEqual(a[key] as? String,b[key] as? String)}
        XCTAssertEqual(a["container"] as? String,b["container"] as? String);XCTAssertEqual(a["environment"] as? String,b["environment"] as? String)
    }
}
